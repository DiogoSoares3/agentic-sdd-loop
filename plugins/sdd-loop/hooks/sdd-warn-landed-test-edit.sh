#!/usr/bin/env bash
# SDD loop · PreToolUse(Edit|Write) — WARN on editing a LANDED test (regression integrity)
# ---------------------------------------------------------------------------------------
# Advisory-only sibling of sdd-enforce-test-first.sh. It NEVER blocks (always exits 0). When a worker on an
# issue/* branch edits a test file that ALREADY EXISTS on the integration branch (a test an earlier, landed
# issue depends on), it emits a non-blocking warning: a regression failure is fixed in the CODE, not by
# weakening a test older behaviour relies on. This is the "they always want to touch the tests" guard, kept
# soft on purpose — a shared fixture/helper legitimately evolves, so a hard block would be wrong.
#
# Design: FAIL-OPEN + FAIL-SILENT. Any uncertainty (no jq/git, not an SDD project, +hook off, not on an
# issue branch, cannot classify the file, cannot confirm the test is landed) -> exit 0 with NO message.
# Opt-in with the same `integrity: +hook` switch as the test-first guard, so the two travel together.
#
# Tunables (env): SDD_TEST_PATTERN (regex marking a path as a test) · SDD_INTEGRATION_BRANCH (default develop)
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE="$ROOT/.sdd/profile.md"

[ -f "$PROFILE" ] || exit 0                       # not an SDD project     -> silent
grep -qiE '\+hook' "$PROFILE" || exit 0           # +hook not enabled       -> silent
command -v jq >/dev/null 2>&1 || exit 0           # cannot build a message   -> silent

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -n "$FILE" ] || exit 0

# Classify by the path RELATIVE to the repo root (same reasoning as the test-first guard: an ancestor dir
# named like "…test…" must not make every file look like a test).
REL="${FILE#"$ROOT"/}"

TESTPAT="${SDD_TEST_PATTERN:-(test|tests|spec|specs|_test\.|\.test\.|\.spec\.|/tests?/)}"
INT_BRANCH="${SDD_INTEGRATION_BRANCH:-develop}"

# Only test files are of interest here.
printf '%s' "$REL" | grep -qiE "$TESTPAT" || exit 0

# Only warn while on an issue branch.
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
case "$BRANCH" in
  issue/*) : ;;
  *) exit 0 ;;
esac

# Is this test already LANDED (present on the integration branch)? If we cannot confirm it exists there
# (a new test this issue is creating, or the branch is unavailable) -> silent, no warning.
landed=0
for ref in "$INT_BRANCH" "origin/$INT_BRANCH"; do
  if git -C "$ROOT" cat-file -e "$ref:$REL" 2>/dev/null; then landed=1; break; fi
done
[ "$landed" = 1 ] || exit 0

MSG="$(printf '%s' "[SDD regression integrity] You are editing \`$REL\`, a test that already exists on \`$INT_BRANCH\` (a LANDED test earlier issues depend on). A regression failure is fixed in the CODE, not by weakening a test older behaviour relies on — if the behaviour genuinely changed, that is a needs-revalidation baseline amendment, not a test edit. WARNING, not a block: it can be a false positive (a shared fixture/helper that legitimately evolves). Verify with \`git diff $INT_BRANCH...HEAD -- $REL\` and the regression run's logs before proceeding.")"

jq -nc --arg m "$MSG" '{systemMessage:$m}'
exit 0
