#!/usr/bin/env bash
# Faixa B (plan) — live test that PLAN cuts a backlog carrying the `Touches` parallel-safety hint.
# Runs on the CLEAN fixture-plan repo (no seeded branches), the state PLAN actually runs in.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh (Linux) /
# run-macos-sandbox.sh (macOS).  Usage:  bash plan-chain.sh WORKDIR
#   env: PLUGIN_DIR (default: this repo's plugin) · MODEL (default: claude-haiku-4-5-20251001)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="${1:?usage: plan-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/plan-proj"; SETTINGS="$WORK/settings.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"

PLAN='Invoke the /sdd skill and prime from .sdd/profile.md + docs/PROGRESS.md + the baselines. PLAN phase 1 ONLY: dispatch the sdd-phase-opener subagent to cut docs/phases/phase-1/prd.md + backlog.md for FR-1 (apply("add",...)) and FR-2 (apply("subtract",...)). Concurrency is parallel, so EACH backlog issue MUST carry: a Gherkin Scenario (via /bdd), an Inner loop (TDD) flag, AND a "Touches" hint naming the files/seam it changes. Write the files on develop and STOP. DO NOT build or land anything, and DO NOT switch branches or stash.'

( cd "$PROJ" && claude --print --verbose --output-format stream-json \
    --dangerously-skip-permissions --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS" --model "$MODEL" \
    --session-id "$SID" "$PLAN" > "$WORK/stream-plan.jsonl" 2>>"$WORK/stderr.txt" )

cd "$PROJ"; git checkout -q develop 2>/dev/null
BL="$PROJ/docs/phases/phase-1/backlog.md"

echo "===== PLAN / Touches assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }
chk "a phase-1 backlog.md was written"                'test -s "$BL"'
chk "backlog issues carry a Gherkin Scenario"         'grep -qi "Scenario:" "$BL"'
chk "backlog issues carry an Inner loop (TDD) flag"   'grep -qi "Inner loop" "$BL"'
chk "backlog carries the Touches parallel-safety hint" 'grep -qi "touches" "$BL"'
echo "===== $ok passed, $bad failed ====="
[ "$bad" -eq 0 ]
