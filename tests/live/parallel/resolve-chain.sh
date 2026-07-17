#!/usr/bin/env bash
# Faixa B (resolve) — live test of the land-queue conflict path: the orchestrator dispatches the
# sdd-merge-resolver, which resolves via /resolving-merge-conflicts, keeps BOTH ops, runs the FULL
# regression suite, and lands — never weakening the landed test. Runs on the SEEDED fixture-parallel repo
# (issue/1-add landed, issue/2-subtract ready-to-land and conflicting).
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh / run-macos-sandbox.sh.
#   Usage:  bash resolve-chain.sh WORKDIR
#   env: PLUGIN_DIR (default: this repo's plugin) · MODEL (default: claude-haiku-4-5-20251001)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="${1:?usage: resolve-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/pc-proj"; SETTINGS="$WORK/settings.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"

RESOLVE='Invoke the /sdd skill. Concurrency is parallel. Land-queue state: issue/1-add is already LANDED on develop; issue/2-subtract is ready-to-land, but rebasing it onto the current develop tip CONFLICTS on the shared OPERATIONS registry line in src/calc/__init__.py. Drain the serial land queue: dispatch the sdd-merge-resolver subagent for issue/2-subtract. It must invoke the /resolving-merge-conflicts skill to rebase onto develop and resolve by KEEPING BOTH operations (add AND subtract) — NEVER weaken or delete the landed add test — then run the FULL regression suite (python3 -m pytest -q) and land issue/2 onto develop (auto-merge). Continuation mode is auto — do not ask.'

( cd "$PROJ" && claude --print --verbose --output-format stream-json \
    --dangerously-skip-permissions --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS" --model "$MODEL" \
    --session-id "$SID" "$RESOLVE" > "$WORK/stream-resolve.jsonl" 2>>"$WORK/stderr.txt" )

cd "$PROJ"; git checkout -q develop 2>/dev/null

echo "===== RESOLVE / merge-resolver assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }
chk "orchestrator dispatched sdd-merge-resolver"          'grep -q "sdd-merge-resolver" "$WORK/stream-resolve.jsonl"'
chk "resolver invoked /resolving-merge-conflicts"         'grep -q "resolving-merge-conflicts" "$WORK/stream-resolve.jsonl"'
chk "develop keeps BOTH ops (add + subtract) after merge" 'grep -q "\"add\"" src/calc/__init__.py && grep -q "\"subtract\"" src/calc/__init__.py'
chk "full regression suite green on develop (2 passed)"   'PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "2 passed"'
chk "the LANDED add test was not weakened"                'grep -q "apply(\"add\", 2, 3) == 5" tests/test_add.py'
echo "===== $ok passed, $bad failed ====="
[ "$bad" -eq 0 ]
