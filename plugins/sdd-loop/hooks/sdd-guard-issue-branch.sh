#!/usr/bin/env bash
# SDD loop · PreToolUse(Edit|Write) — the loop NEVER edits code on the integration/protected branch
# --------------------------------------------------------------------------------------------------
# Makes "one issue = one issue/* branch" mechanical instead of trusted. Every other integrity guard
# (test-first, landed-test warning, SubagentStop verify) checks `git branch == issue/*` and FAILS OPEN
# when it isn't — so a worker that never attached to its branch would silently switch the whole +hook
# layer off AND commit straight to the integration branch. This hook closes that hole from the front:
# while an issue is in flight, an implementation/test edit is only allowed on an issue/* branch.
#
# "In flight" is read from the SDD-CURSOR `Doing:` field in the durable-state file — a deterministic
# file signal, not a guess. That is what keeps this hook OFF the human's back: with `Doing: none` (the
# loop idle, or no loop at all) a user editing their own repo on `develop` is never touched. It bites
# only in the exact window where the loop claims to be building an issue.
#
# Unlike the test-first guard this is NOT gated on `integrity: +hook`: "the loop never commits to a
# protected branch" is an architectural invariant of the design, not a configurable strictness level.
#
# Design: FAIL-OPEN. No profile / no jq / no git / no cursor / unreadable branch names -> ALLOW.
# Docs, specs and loop state are ALWAYS allowed (the orchestrator legitimately updates PROGRESS.md and
# the backlog on the integration branch while an issue is doing).
#
# Tunables (env):
#   SDD_INTEGRATION_BRANCH  overrides the profile's integration branch (default: develop)
#   SDD_PROTECTED_BRANCH    overrides the profile's protected branch   (default: main)
#   SDD_ALLOW_PATTERN       regex of never-implementation paths (docs/spec/state)
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE="$ROOT/.sdd/profile.md"

[ -f "$PROFILE" ] || exit 0                       # not an SDD project -> allow
command -v jq >/dev/null 2>&1 || exit 0           # cannot parse input -> allow (fail-open)

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -n "$FILE" ] || exit 0

# Classify by the path RELATIVE to the repo root (same reasoning as the other guards).
REL="${FILE#"$ROOT"/}"

# Docs / spec / loop-state / config are not implementation — always allowed, on any branch. This is what
# lets the ORCHESTRATOR keep PROGRESS.md, the backlog and ADRs current on the integration branch.
ALLOWPAT="${SDD_ALLOW_PATTERN:-(\.md$|\.mdx$|\.rst$|\.txt$|/docs/|/\.sdd/|/adrs?/|(^|/)PROGRESS\.|(^|/)backlog\.)}"
printf '%s' "$REL" | grep -qiE "$ALLOWPAT" && exit 0

# Ask git about the WORKING TREE the call runs in: under `Concurrency: parallel` each worker lives in its own
# `git worktree` with its own HEAD, so the project root's branch is the wrong question. Profile and durable
# state still come from the project root. Falls back to ROOT when the payload carries no cwd.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
WT="${CWD:-$ROOT}"

git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || exit 0
BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
[ -n "$BRANCH" ] || exit 0

# First backtick-quoted token after the named profile LABEL (same parser as the other hooks): the key must
# be followed by a colon, so prose that merely mentions "integration branch" cannot win the match.
prof_tok() { { grep -ivE "^[[:space:]]*>" "$PROFILE" 2>/dev/null | grep -iE "(^|[[:space:]*])$1[[:space:]]*\**[[:space:]]*:" | head -n1 | sed -E "s/^.*$1[[:space:]]*\**[[:space:]]*://I" | grep -oE '`[^`]+`' | head -n1 | tr -d '`'; } || true; }
INT="${SDD_INTEGRATION_BRANCH:-$(prof_tok 'Integration branch')}"; : "${INT:=develop}"
PROT="${SDD_PROTECTED_BRANCH:-$(prof_tok 'Protected branch')}";    : "${PROT:=main}"

# Only the integration / protected branches are guarded. An issue/* branch (or any other) is fine.
case "$BRANCH" in
  "$INT"|"$PROT") : ;;
  *) exit 0 ;;
esac

# Is an issue actually in flight? Read the SDD-CURSOR `Doing:` field from the durable-state file.
PROGRESS_REL="$(prof_tok 'Durable state')"; : "${PROGRESS_REL:=docs/PROGRESS.md}"
case "$PROGRESS_REL" in /*) PROGRESS="$PROGRESS_REL";; *) PROGRESS="$ROOT/$PROGRESS_REL";; esac
[ -f "$PROGRESS" ] || exit 0                      # no durable state -> cannot tell -> allow

CURSOR="$(awk '/<!--[[:space:]]*SDD-CURSOR/{f=1;next} /<!--[[:space:]]*\/SDD-CURSOR/{f=0} f' "$PROGRESS" 2>/dev/null || true)"
DOING="$( { printf '%s\n' "$CURSOR" \
    | grep -iE '^[[:space:]]*[-*][[:space:]]*\**[[:space:]]*Doing[[:space:]]*\**[[:space:]]*:' \
    | head -n1 \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]*\**[[:space:]]*Doing[[:space:]]*\**[[:space:]]*://I; s/^[[:space:]*]+//; s/[[:space:]*]+$//'
  } || true )"

case "$(printf '%s' "$DOING" | tr '[:upper:]' '[:lower:]')" in
  ''|none|none*|unknown|n/a|-) exit 0 ;;          # loop idle (or unreadable) -> allow, never bother a human
esac

cat >&2 <<MSG
[SDD branch integrity] Issue "$DOING" is in flight, but you are on \`$BRANCH\` — the integration/protected
branch. The loop never builds there: one issue = one \`issue/*\` branch, and every integrity guard
(test-first, landed-test warning, SubagentStop verify) keys on that branch, so editing here would run
UNGUARDED and land unreviewed work straight on \`$BRANCH\`.

Orchestrator: create/check out the issue branch BEFORE dispatching the worker.
Worker: you only ATTACH to the branch you were handed — never branch yourself; if you are not on one,
return \`blocked\`.

Docs, specs and loop state (PROGRESS.md, the backlog, ADRs) are always allowed here — only code and tests
are blocked. If the loop is not actually building, set the cursor's \`Doing:\` back to \`none\`.
MSG
exit 2
