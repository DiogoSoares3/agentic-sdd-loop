#!/usr/bin/env bash
# Faixa B (multi) — live test of the lander over a REAL multi-item land queue. Three independent issues are
# `ready-to-land` and all edit the shared OPERATIONS line, so draining them serially forces a cascade of
# rebase conflicts. Verifies the subagent behaves correctly given the ready-to-land queue state: the
# orchestrator dispatches sdd-merge-resolver per item, each resolves via /resolving-merge-conflicts, and all
# three land green with no landed test weakened.
#
# PURE harness — runs `claude` directly. Drive via run-bwrap-multi.sh (Linux) / a seatbelt wrapper (macOS).
#   Usage:  bash multi-chain.sh WORKDIR
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="${1:?usage: multi-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/pc-proj"; SETTINGS="$WORK/settings.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"

DRAIN='Invoke the /sdd skill. Concurrency is parallel. The land queue (issues whose backlog status is `ready-to-land`, in docs/phases/phase-1/backlog.md) has THREE independent items: issue-1-add, issue-2-subtract, issue-3-multiply. All are green on their own `issue/*` branch and ALL edit the same OPERATIONS registry line in src/calc/__init__.py, so each land after the first will conflict on that line. develop is at base (nothing landed yet). Drain the SERIAL land queue in backlog order: for EACH item, dispatch a fresh sdd-merge-resolver subagent that rebases that branch onto the CURRENT develop tip, resolves any conflict via the /resolving-merge-conflicts skill by KEEPING ALL operations landed so far plus its own, NEVER weakening a landed test, runs the FULL regression suite (python3 -m pytest -q), and merges to develop. One lander at a time. Continuation mode is auto — do not ask.'

( cd "$PROJ" && claude --print --verbose --output-format stream-json \
    --dangerously-skip-permissions --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS" --model "$MODEL" \
    --session-id "$SID" "$DRAIN" > "$WORK/stream-multi.jsonl" 2>>"$WORK/stderr.txt" )

cd "$PROJ"; git checkout -q develop 2>/dev/null
ST="$WORK/stream-multi.jsonl"
landers="$(grep -oc 'subagent_type":"sdd-loop:sdd-merge-resolver' "$ST" 2>/dev/null || echo 0)"

echo "===== MULTI-ITEM QUEUE assertions (lander dispatch count in stream: $landers) ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }
chk "orchestrator dispatched sdd-merge-resolver (the lander)"   'grep -q "sdd-merge-resolver" "$ST"'
chk "lander invoked /resolving-merge-conflicts (cascade conflicts)" 'grep -q "resolving-merge-conflicts" "$ST"'
chk "develop carries ALL THREE ops (add + subtract + multiply)" 'grep -q "\"add\"" src/calc/__init__.py && grep -q "\"subtract\"" src/calc/__init__.py && grep -q "\"multiply\"" src/calc/__init__.py'
chk "full regression suite green on develop (3 passed)"         'PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "3 passed"'
chk "no landed test weakened (all three assertions intact)"     'grep -q "apply(\"add\", 2, 3) == 5" tests/test_add.py && grep -q "apply(\"subtract\", 5, 3) == 2" tests/test_subtract.py && grep -q "apply(\"multiply\", 4, 3) == 12" tests/test_multiply.py'
echo "===== $ok passed, $bad failed ====="
[ "$bad" -eq 0 ]
