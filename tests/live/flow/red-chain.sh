#!/usr/bin/env bash
# Faixa B · flow — RED chain. One turn. Everything else in this suite asks "did the loop follow the
# procedure?"; this one asks the question no gate in the plugin currently answers: "is the green REAL?"
#
# Three independent readings of the same run, none of them trusting the transcript:
#   1. history  — a test-only commit precedes the implementation (the two-commit rule left a trace)
#   2. RED      — those tests, replayed against the source as it was BEFORE them, actually FAIL
#   3. delivered— an out-of-project probe exercises the behaviour on a checkout with NO tests present
#
# (2) and (3) both fail on a hollow green, from opposite directions: a test that arranges what it asserts
# goes green against the old source (so there was never a red), and leaves the shipped module empty (so the
# probe raises). (1) alone passes it happily — which is exactly how the defect got through a live run.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash red-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: red-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/red-proj"; SETTINGS="$WORK/settings.json"; ST="$WORK/stream-red.jsonl"
PROBE="$WORK/probe_fr1.py"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

BUILD='Invoke the /sdd skill and continue the build loop. Phase 1 is already cut and its backlog is approved — do NOT re-plan and do NOT rewrite the profile or the baselines. Build issue FR-1 from docs/phases/phase-1/backlog.md following the dispatcher exactly: create and check out its issue/<id>-<slug> branch yourself, spawn a fresh sdd-issue-worker on it, and dispatch the lander once it returns. Continuation mode is auto — do not ask me anything.'

run_turn "$ST" SIM_build --session-id "$SID" "$BUILD"

cd "$PROJ"; git checkout -q develop 2>/dev/null
TESTFILES="$(git ls-tree -r --name-only develop 2>/dev/null | grep -iE '(^|/)tests?/' || true)"

echo
echo "===== RED assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- the suite is green (necessary, and by itself worth nothing) ---"
chk "pytest green on develop"                        'PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1'
chk "at least one behaviour test is committed"       '[ -n "$TESTFILES" ]'

echo "--- 1. the two-commit rule left a trace ---"
chk "a test-only commit exists on develop"           'has_test_only_commit "$PROJ" develop'

echo "--- 2. that test was really RED before the implementation ---"
chk "replaying the test against the pre-impl source FAILS" \
    'proves_red "$PROJ" develop "PYTHONPATH=src python3 -m pytest -q"'

echo "--- 3. the DELIVERED system works, with no test in the loop ---"
chk "the out-of-project probe passes on a tests-free checkout" \
    'probe_delivered "$PROJ" develop "$PROBE"'
chk "the shipped module registers add itself"        'git show develop:src/calc/__init__.py | grep -q "add"'

echo "--- the named anti-pattern: the test must not arrange what it asserts ---"
chk "no committed test writes into OPERATIONS" \
    '! (for f in $TESTFILES; do git show "develop:$f"; done) 2>/dev/null | grep -qE "OPERATIONS[[:space:]]*(\[|\.|=)"'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- develop history ---"; git log develop --oneline | head -20
  echo "--- shipped module ---"; git show develop:src/calc/__init__.py
  for f in $TESTFILES; do echo "--- $f ---"; git show "develop:$f"; done
fi
[ "$bad" -eq 0 ]
