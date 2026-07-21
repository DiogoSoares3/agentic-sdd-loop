#!/usr/bin/env bash
# Faixa B · flow — LAND chain. One turn, phase already cut, `Concurrency: serial`. Proves the land path is
# the SAME in serial as in parallel: the worker builds on the branch it was handed, returns ready-to-land
# without merging, and a bounded lander does the rebase + full suite + merge. Also proves the TDD flag is
# honoured on BOTH settings (FR-1 required leaves an inner-loop checkpoint; FR-2 skipped needs none).
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash land-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: land-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/land-proj"; SETTINGS="$WORK/settings.json"; ST="$WORK/stream-land.jsonl"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

BUILD='Invoke the /sdd skill and continue the build loop. Phase 1 is already cut and its backlog is approved — do NOT re-plan and do NOT rewrite the profile or the baselines. Work through docs/phases/phase-1/backlog.md in dependency order, following the dispatcher exactly: for each issue you create and check out its issue/<id>-<slug> branch yourself before spawning a fresh sdd-issue-worker on it, and once that worker returns you dispatch the lander to take the branch to done. Continuation mode is auto and the backlog is approved — do not ask me anything.'

run_turn "$ST" SIM_build --session-id "$SID" "$BUILD"

cd "$PROJ"; git checkout -q develop 2>/dev/null
# NB: `grep -c` exits 1 on zero matches, so a `|| echo 0` fallback would append a SECOND zero.
workers="$(grep -c 'sdd-issue-worker' "$ST" 2>/dev/null; true)"
landers="$(grep -c 'sdd-merge-resolver' "$ST" 2>/dev/null; true)"

echo
echo "===== LAND assertions (worker mentions: $workers · lander mentions: $landers) ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- the split: worker builds, lander lands — in SERIAL ---"
chk "dispatched sdd-issue-worker"                    'grep -q "sdd-issue-worker" "$ST"'
chk "dispatched sdd-merge-resolver in SERIAL mode"   'grep -q "sdd-merge-resolver" "$ST"'
chk "the backlog reached ready-to-land at some point" 'grep -qi "ready-to-land" "$ST" docs/PROGRESS.md docs/phases/phase-1/backlog.md'

echo "--- the work actually landed ---"
chk "pytest green on develop"                        'PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1'
chk "FR-1 landed (UnknownOperation on the seam)"     'grep -qi "UnknownOperation" src/calc/__init__.py'
chk "FR-2 landed (VERSION constant)"                 'grep -q "VERSION" src/calc/__init__.py'
chk "both behaviours are covered by tests"           'PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "[2-9][0-9]* passed"'

echo "--- test-first is visible in the history ---"
chk "a test-only commit exists on develop"           'has_test_only_commit "$PROJ" develop'

echo "--- the TDD flag is honoured on both settings ---"
chk "FR-1 (required) left an inner-loop checkpoint"  'grep -qiE "FR-1.*unit .*green|unit .*green.*FR-1" docs/PROGRESS.md'
chk "the loop finished cleanly (Doing: none)"        'grep -iA3 "SDD-CURSOR" docs/PROGRESS.md | grep -qi "Doing: *none"'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- develop history ---"; git log develop --oneline | head -20
  echo "--- PROGRESS ---"; head -40 docs/PROGRESS.md
fi
[ "$bad" -eq 0 ]
