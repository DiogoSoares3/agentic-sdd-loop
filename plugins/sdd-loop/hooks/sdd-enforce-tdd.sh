#!/usr/bin/env bash
# SDD loop · PreToolUse(Edit|Write) — TEST-FIRST enforcement
# ---------------------------------------------------------
# Structural teeth for the BDD/TDD discipline, active ONLY when the project opted into
# `integrity: ... +hook` in .sdd/profile.md. Every issue must commit its behaviour test
# (BDD outer — ALWAYS required, even for TDD-`skipped` issues) BEFORE any implementation
# edit. Editing a test file is always allowed.
#
# Design: FAIL-OPEN. On any uncertainty (no jq, no git, no base branch, not on an issue
# branch, cannot classify the file) it ALLOWS the edit, so the guard can never brick the
# loop. It only DENIES the clearly-unsafe case. Fires in the main session AND inside
# subagents (PreToolUse is a tool-execution hook, applied globally).
#
# Tunables (env):
#   SDD_TEST_PATTERN       regex marking a path as a test  (default below)
#   SDD_INTEGRATION_BRANCH integration branch to diff against (default: develop)
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE="$ROOT/.sdd/profile.md"

[ -f "$PROFILE" ] || exit 0                       # not an SDD project -> allow
grep -qiE '\+hook' "$PROFILE" || exit 0           # +hook not enabled     -> allow
command -v jq >/dev/null 2>&1 || exit 0           # cannot parse input    -> allow (fail-open)

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -n "$FILE" ] || exit 0

TESTPAT="${SDD_TEST_PATTERN:-(test|tests|spec|specs|_test\.|\.test\.|\.spec\.|/tests?/)}"
INT_BRANCH="${SDD_INTEGRATION_BRANCH:-develop}"

# Editing a test file IS test-first-compliant.
printf '%s' "$FILE" | grep -qiE "$TESTPAT" && exit 0

# Only guard while on an issue branch.
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
case "$BRANCH" in
  issue/*) : ;;
  *) exit 0 ;;
esac

# Establish the branch base; if we cannot, fail open.
BASE="$(git -C "$ROOT" merge-base HEAD "$INT_BRANCH" 2>/dev/null || echo)"
[ -n "$BASE" ] || exit 0

# A test already committed on this branch? implementation is allowed.
if git -C "$ROOT" diff --name-only "$BASE"..HEAD 2>/dev/null | grep -qiE "$TESTPAT"; then
  exit 0
fi

# +hook on, on an issue branch, editing a non-test file, no test committed yet -> block.
cat >&2 <<'MSG'
[SDD integrity +hook] Test-first violation. Commit this issue's FAILING behaviour test (BDD outer —
prove RED) before editing implementation. Editing a test file is always allowed. This guard is active
because .sdd/profile.md sets integrity `+hook`, you are on an issue/* branch, and no test has been
committed on it yet. Write the scenario's test, commit it alone, then implement.
MSG
exit 2
