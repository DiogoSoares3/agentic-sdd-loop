#!/usr/bin/env bash
# Faixa B — the load-bearing live test: PLAN → /compact → CONTINUE in one persisted session.
# Forces a REAL main-session compaction with /compact and asserts the SessionStart(compact) re-prime
# lets the orchestrator resume the BUILD from the cursor WITHOUT re-planning or rewriting baselines.
#
# This is a PURE harness — it runs `claude` directly and does NOT isolate itself. Run it through one of:
#   • run-in-docker.sh      (cross-platform; the real repo is mounted read-only)
#   • run-macos-sandbox.sh  (macOS seatbelt; validated in dev)
# …never against a repo you care about without isolation — a headless model writing files is the point.
#
# Usage:  bash compact-chain.sh WORKDIR
#   env: PLUGIN_DIR (default: this repo's plugin) · MODEL (default: claude-haiku-4-5-20251001)
#   Requires: a claude CLI logged in (CLAUDE_CODE_OAUTH_TOKEN / setup-token / API key) + network.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${1:?usage: compact-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/ac-proj"; SETTINGS="$WORK/settings.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/hooklog.txt"; : > "$WORK/stderr.txt"; : > "$WORK/run-meta.txt"

run() { # $1 label  $2 stream-out  $3.. claude args (prompt last)
  local label="$1" out="$2"; shift 2
  echo ">>> $label" >> "$WORK/hooklog.txt"
  ( cd "$PROJ" && claude --print --verbose --output-format stream-json \
      --dangerously-skip-permissions \
      --plugin-dir "$PLUGIN_DIR" --settings "$SETTINGS" --model "$MODEL" \
      "$@" > "$out" 2>>"$WORK/stderr.txt" )
  echo "   [$label exit=$?]" >> "$WORK/run-meta.txt"
}

PLAN='Invoke the /sdd skill. Prime from .sdd/profile.md + docs/PROGRESS.md + the baselines. Then PLAN phase 1 ONLY: dispatch the sdd-phase-opener subagent to cut the phase (docs/phases/phase-1/prd.md + backlog.md; each issue a Gherkin Scenario + an Inner loop (TDD) flag) realizing FR-1 (TDD required) and FR-2 (VERSION constant, TDD skipped). Update the SDD-CURSOR block (Phase: 1, Doing: none, Next: <first issue id>, Stop-reason: none). Then STOP and report the cursor. DO NOT build any issue yet.'
CONT='Continue the SDD build loop from where it left off. Do NOT re-plan and do NOT rewrite the profile or baselines. For each todo issue in docs/phases/phase-1/backlog.md, dispatch a fresh sdd-issue-worker one at a time: BDD outer test first (prove RED, commit test alone), run /tdd inner loop only when the flag is required, make green (python3 -m pytest -q), land onto develop (auto-merge). Keep the SDD-CURSOR current. Continuation mode is auto — do not ask.'

run "step1-plan(startup)"    "$WORK/stream-s1.jsonl" --session-id "$SID" "$PLAN"
run "step2-compact(resume)"  "$WORK/stream-s2.jsonl" --resume "$SID" "/compact"
run "step3-continue(resume)" "$WORK/stream-s3.jsonl" --resume "$SID" "$CONT"

echo "===== hooklog (expect: startup … resume, compact … resume) ====="; cat "$WORK/hooklog.txt"
echo "===== assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }
chk "SessionStart fired with source=compact"      'grep -q "source=compact" "$WORK/hooklog.txt"'
chk "step3 dispatched sdd-issue-worker (built)"    'grep -q "sdd-issue-worker" "$WORK/stream-s3.jsonl"'
chk "baselines/profile untouched after planning"   '[ -z "$(git -C "$PROJ" log --oneline -- docs/PRD.md docs/ARCHITECTURE.md .sdd/profile.md | grep -v "validated baselines")" ]'
chk "pytest green on develop"                       '( cd "$PROJ" && git checkout -q develop 2>/dev/null; python3 -m pytest -q >/dev/null 2>&1 )'
echo "===== $ok passed, $bad failed ====="
[ "$bad" -eq 0 ]
