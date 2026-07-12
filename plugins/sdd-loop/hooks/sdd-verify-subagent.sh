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
# Covers BOTH bounded agents:
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

# Only our two bounded agents (accept bare or plugin-scoped name, e.g. sdd-loop:sdd-issue-worker).
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

# ---- sdd-issue-worker: claims green -> the issue/* branch must carry a committed test. ----
WT="${CWD:-$ROOT}"
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || exit 0      # no git -> allow
BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
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
