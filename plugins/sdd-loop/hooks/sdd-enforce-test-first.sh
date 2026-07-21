#!/usr/bin/env bash
# SDD loop · PreToolUse(Edit|Write) — TEST-FIRST (BDD-first) enforcement
# ---------------------------------------------------------------------
# NB: this guards the BDD outer test, NOT the inner TDD loop. It has nothing to do with an
# issue's `Inner loop (TDD)` flag — the behaviour (BDD) test is ALWAYS required, even for
# TDD-`skipped` issues, so the rule is universal: on an issue/* branch, no implementation edit
# before a test is committed. Active ONLY when the project opted into `integrity: ... +hook`
# in .sdd/profile.md. Editing a test file (or docs/spec/state) is always allowed.
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

# Git questions are asked of the WORKING TREE the tool call runs in, not the project root: under
# `Concurrency: parallel` each worker lives in its own `git worktree`, which has its own HEAD. Reading the
# root's branch there would judge the wrong branch entirely. The profile is still read from the project root
# (it is not per-worktree). Falls back to ROOT when the payload carries no cwd.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
WT="${CWD:-$ROOT}"

# Classify by the path RELATIVE to the repo root, never the absolute path — otherwise an ancestor
# directory named like "…test…" / "…spec…" / "…docs…" (e.g. a repo under ~/dev/testing/) would match
# the patterns below for EVERY file and silently disable the guard. Strip the ROOT prefix; a path that
# is already relative is left as-is.
REL="${FILE#"$ROOT"/}"

TESTPAT="${SDD_TEST_PATTERN:-(test|tests|spec|specs|_test\.|\.test\.|\.spec\.|/tests?/)}"
INT_BRANCH="${SDD_INTEGRATION_BRANCH:-develop}"

# Editing a test file IS test-first-compliant.
printf '%s' "$REL" | grep -qiE "$TESTPAT" && exit 0

# Docs / spec / loop-state / config are NOT implementation — always allowed (never gated by test-first).
# This is what lets the worker record a needs-decision to PROGRESS.md, update the backlog, or write an ADR
# on the issue branch before any test exists. The BDD outer test still gates real code.
ALLOWPAT="${SDD_ALLOW_PATTERN:-(\.md$|\.mdx$|\.rst$|\.txt$|/docs/|/\.sdd/|/adrs?/|(^|/)PROGRESS\.|(^|/)backlog\.)}"
printf '%s' "$REL" | grep -qiE "$ALLOWPAT" && exit 0

# Only guard while on an issue branch.
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || exit 0
BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
case "$BRANCH" in
  issue/*) : ;;
  *) exit 0 ;;
esac

# Establish the branch base; if we cannot, fail open.
BASE="$(git -C "$WT" merge-base HEAD "$INT_BRANCH" 2>/dev/null || echo)"
[ -n "$BASE" ] || exit 0

# A test already committed on this branch? implementation is allowed.
if git -C "$WT" diff --name-only "$BASE"..HEAD 2>/dev/null | grep -qiE "$TESTPAT"; then
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
