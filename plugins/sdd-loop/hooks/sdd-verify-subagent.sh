#!/usr/bin/env bash
# SDD loop · SubagentStop — verify a bounded worker's exit is self-consistent
# --------------------------------------------------------------------------
# The mechanical backstop for silent subagent compaction. A subagent gets NO lifecycle
# hooks (no SessionStart/PreCompact), so if it overflows mid-work it compacts silently and
# may "lose its place" — then return claiming success. This hook re-reads the DURABLE truth
# (git + files) at SubagentStop and, if a worker that CLAIMS success left inconsistent state,
# BLOCKS the stop (`decision: block`) so the worker keeps going and fixes it.
#
# It also turns "did the worker actually do BDD/TDD?" from trust into a check: the BDD outer
# test must be committed on the issue branch (always required, even for TDD-`skipped` issues).
#
# Covers the two bounded agents it verifies (sdd-merge-resolver is intentionally not verified -> fail-open):
#   - sdd-issue-worker : claims green  -> its issue/* branch must carry a committed test.
#   - sdd-phase-opener : claims opened -> a non-empty backlog.md must exist under docs/phases/.
#
# Design: FAIL-OPEN. On ANY uncertainty (no jq/git/base branch, nonstandard paths, a legit
# blocked/needs-decision return, or a stop we can't classify) it ALLOWS the stop, so the guard
# can never brick the loop. It only BLOCKS the clearly-inconsistent "claims success but the
# durable state disagrees" case — a condition the worker can resolve by continuing.
#
# Tunables (env):
#   SDD_TEST_PATTERN       regex marking a path as a test  (default below)
#   SDD_INTEGRATION_BRANCH integration branch to diff against (default: develop)
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE="$ROOT/.sdd/profile.md"

[ -f "$PROFILE" ] || exit 0                      # not an SDD project -> allow
command -v jq >/dev/null 2>&1 || exit 0          # cannot parse/emit  -> fail-open allow

INPUT="$(cat)"
AGENT="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty')"
CWD="$(printf '%s'   "$INPUT" | jq -r '.cwd // empty')"
MSG="$(printf '%s'   "$INPUT" | jq -r '.last_assistant_message // empty')"

# Only the two bounded agents it verifies (accept bare or plugin-scoped name, e.g. sdd-loop:sdd-issue-worker).
case "$AGENT" in
  *sdd-issue-worker|*sdd-phase-opener) : ;;
  *) exit 0 ;;
esac

# A legit non-green stop (escalation / blocked / revalidation) must ALWAYS be allowed.
LMSG="$(printf '%s' "$MSG" | tr '[:upper:]' '[:lower:]')"
case "$LMSG" in
  *needs-decision*|*needs-revalidation*|*blocked*) exit 0 ;;
esac

block() {  # $1 = reason shown in the subagent's transcript
  jq -n --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

# ---- sdd-phase-opener: claims a phase opened -> a non-empty backlog must exist. ----
case "$AGENT" in
  *sdd-phase-opener)
    # Phases dir is read from the profile's Paths section (first backtick-quoted token on the
    # "Phases dir" line), so a project can relocate it out of docs/. Falls back to the default.
    prof_path() { { grep -iE "$1" "$PROFILE" 2>/dev/null | head -n1 | grep -oE '`[^`]+`' | head -n1 | tr -d '`'; } || true; }
    PHASES_REL="$(prof_path 'Phases dir')"; : "${PHASES_REL:=docs/phases}"; PHASES_REL="${PHASES_REL%/}"
    case "$PHASES_REL" in /*) PH_DIR="$PHASES_REL";; *) PH_DIR="$ROOT/$PHASES_REL";; esac
    [ -d "$PH_DIR" ] || exit 0                   # nonstandard/absent path -> fail-open
    NEWEST="$(ls -t "$PH_DIR"/*/backlog.md 2>/dev/null | head -n1 || true)"
    if [ -z "$NEWEST" ] || [ ! -s "$NEWEST" ]; then
      block "sdd-phase-opener returned but no non-empty backlog.md exists under $PHASES_REL/. Finish writing $PHASES_REL/phase-N/prd.md + backlog.md (issues each with a Gherkin Scenario and an Inner loop (TDD) flag) before stopping; if a decision is missing, return needs-decision instead."
    fi
    exit 0
    ;;
esac

prof_path() { { grep -iE "$1" "$PROFILE" 2>/dev/null | head -n1 | grep -oE '`[^`]+`' | head -n1 | tr -d '`'; } || true; }

# ---- sdd-issue-worker ----
WT="${CWD:-$ROOT}"
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || exit 0      # no git -> allow
BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"

# ---- Inner-TDD checkpoint: `Inner loop (TDD): required` must leave a durable trace. ----
# The ONLY deterministic evidence that the inner loop actually ran. The worker is instructed to append
# `<issue-id>: unit "<name>" green; next: …` to the durable-state file after each unit goes green (it is
# also its own mid-issue resume point). Nothing else in the system reads the TDD flag, so without this a
# `required` issue that only ever wrote the outer BDD test passes every guard silently.
#
# Runs BEFORE the branch check on purpose: under serial auto-merge the worker merges and ends up back on
# the integration branch, so keying this on `issue/*` would make it dead code in the default config.
# Fail-open at every step: no id, no backlog, no flag line, an unparseable entry -> allow.
PROGRESS_REL="$(prof_path 'Durable state')"; : "${PROGRESS_REL:=docs/PROGRESS.md}"
case "$PROGRESS_REL" in /*) PROGRESS="$PROGRESS_REL";; *) PROGRESS="$ROOT/$PROGRESS_REL";; esac

# Which issue was this? The branch names it directly. When the worker has already merged and left the
# branch (serial auto-merge ends on the integration branch), fall back to the cursor's `Doing:` field —
# and if that is `none` too, we genuinely cannot tell which issue this was: fail open.
ISSUE_ID=""
case "$BRANCH" in
  issue/*) ISSUE_ID="${BRANCH#issue/}" ;;                        # e.g. FR-1-add — trimmed to the id below
  *) CURSOR="$(awk '/<!--[[:space:]]*SDD-CURSOR/{f=1;next} /<!--[[:space:]]*\/SDD-CURSOR/{f=0} f' "$PROGRESS" 2>/dev/null || true)"
     ISSUE_ID="$( { printf '%s\n' "$CURSOR" \
         | grep -iE '^[[:space:]]*[-*][[:space:]]*\**[[:space:]]*Doing[[:space:]]*\**[[:space:]]*:' \
         | head -n1 \
         | sed -E 's/^[[:space:]]*[-*][[:space:]]*\**[[:space:]]*Doing[[:space:]]*\**[[:space:]]*://I; s/^[[:space:]*]+//; s/[[:space:]*]+$//'
       } || true )"
     case "$(printf '%s' "$ISSUE_ID" | tr '[:upper:]' '[:lower:]')" in
       ''|none|none*|unknown|n/a|-) ISSUE_ID="" ;;
     esac ;;
esac

if [ -n "$ISSUE_ID" ]; then
  PHASES_REL="$(prof_path 'Phases dir')"; : "${PHASES_REL:=docs/phases}"; PHASES_REL="${PHASES_REL%/}"
  case "$PHASES_REL" in /*) PH_DIR="$PHASES_REL";; *) PH_DIR="$ROOT/$PHASES_REL";; esac
  BACKLOGS="$(cat "$PH_DIR"/*/backlog.md 2>/dev/null || true)"

  # The branch carries `<id>-<slug>` and ids routinely contain dashes (FR-1, P1-3, E2-7), so the id cannot
  # be cut at the first dash. Try progressively shorter dash-delimited prefixes — FR-1-add, FR-1, FR — and
  # keep the first that actually names a backlog entry. A bare cursor id (no slug) matches on the first try.
  ENTRY=""; CAND="$ISSUE_ID"
  while [ -n "$CAND" ]; do
    ENTRY="$(printf '%s\n' "$BACKLOGS" \
              | awk -v id="$CAND" 'tolower($0) ~ ("^#+ .*(^|[^a-z0-9])" tolower(id) "([^a-z0-9]|$)") {f=1;print;next} /^#+ /{f=0} f' \
              || true)"
    [ -n "$ENTRY" ] && { ISSUE_ID="$CAND"; break; }
    case "$CAND" in *-*) CAND="${CAND%-*}" ;; *) CAND="" ;; esac
  done
  FLAG="$(printf '%s' "$ENTRY" | grep -iE 'inner loop' | head -n1 || true)"
  # Only `required` is checked. `skipped`, an absent flag, or no entry at all -> nothing to prove -> allow.
  if printf '%s' "$FLAG" | grep -qiE 'required' && ! printf '%s' "$FLAG" | grep -qiE 'skipped'; then
    if ! grep -qiE "$ISSUE_ID.*unit.*green" "$PROGRESS" 2>/dev/null; then
      block "sdd-issue-worker reports success on issue $ISSUE_ID, whose 'Inner loop (TDD)' flag is REQUIRED, but $PROGRESS_REL carries no inner-loop checkpoint for it. Run the inner TDD loop (unit test -> minimal code -> unit green, one behaviour at a time) and append a line per green unit — '$ISSUE_ID: unit \"<name>\" green; next: <what>' — which is also your only durable resume point if you compact mid-issue. If the flag is wrong for this slice, return needs-decision; never flip it yourself."
    fi
  fi
fi

# ---- claims green -> the issue/* branch must carry a committed test. ----
case "$BRANCH" in
  issue/*) : ;;
  *) exit 0 ;;                                                  # already landed/discarded -> allow
esac

INT_BRANCH="${SDD_INTEGRATION_BRANCH:-develop}"
BASE="$(git -C "$WT" merge-base HEAD "$INT_BRANCH" 2>/dev/null || echo)"
[ -n "$BASE" ] || exit 0                                        # no base -> fail-open

FILES="$(git -C "$WT" diff --name-only "$BASE"..HEAD 2>/dev/null || echo)"
[ -n "$FILES" ] || block "sdd-issue-worker reports success but its issue/* branch has no commits vs $INT_BRANCH. Build the issue test-first, or return blocked/needs-decision — do not stop green with an empty branch."

TESTPAT="${SDD_TEST_PATTERN:-(test|tests|spec|specs|_test\.|\.test\.|\.spec\.|/tests?/)}"
if ! printf '%s' "$FILES" | grep -qiE "$TESTPAT"; then
  block "sdd-issue-worker reports success but no test file is committed on its issue/* branch. The BDD outer behaviour test is ALWAYS required (even when Inner loop (TDD) is skipped). Commit the failing behaviour test (prove RED), make it green, then stop."
fi

exit 0
