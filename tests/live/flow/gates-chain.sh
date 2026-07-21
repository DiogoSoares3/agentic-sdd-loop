#!/usr/bin/env bash
# Faixa B · flow — GATES chain. Three turns on one persisted session, with the "user" answering between
# them, proving the two approval gates fire IN ORDER and neither is skipped:
#   turn 1  /sdd                  -> derive + present the phase roadmap, STOP (nothing written, nothing cut)
#   turn 2  "roadmap approved"    -> write it, cut phase 1, present scope+backlog, STOP (nothing built)
#   turn 3  "backlog approved"    -> build the WHOLE phase through, without asking again
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash gates-chain.sh WORKDIR
#   env: PLUGIN_DIR (default: this repo's plugin) · MODEL (default: claude-haiku-4-5-20251001)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: gates-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/gates-proj"; SETTINGS="$WORK/settings.json"
PROFILE="$PROJ/.sdd/profile.md"; BL="$PROJ/docs/phases/phase-1/backlog.md"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

turn() { # $1 sim-key (t1|t2|t3)  $2 out-file  $3 prompt  $4 session mode
  echo ">>> $1" >> "$WORK/hooklog.txt"
  run_turn "$2" "SIM_$1" "$4" "$SID" "$3"
}

T1='Invoke the /sdd skill and run the loop from here. Follow its procedure exactly, including every point where it is supposed to stop and ask me something.'
T2='The roadmap is correct — approved. Continue.'
T3='The phase 1 backlog is approved — build it.'

turn t1 "$WORK/stream-t1.jsonl" "$T1" --session-id
issue_branches_1="$(git -C "$PROJ" branch --list 'issue/*' | wc -l)"
profile_after_1="$(cat "$PROFILE")"
phases_after_1="$([ -d "$PROJ/docs/phases" ] && echo yes || echo no)"

turn t2 "$WORK/stream-t2.jsonl" "$T2" --resume
issue_branches_2="$(git -C "$PROJ" branch --list 'issue/*' | wc -l)"
profile_after_2="$(cat "$PROFILE")"
tests_after_2="$(ls -1 "$PROJ/tests" 2>/dev/null | wc -l | tr -d '[:space:]')"

turn t3 "$WORK/stream-t3.jsonl" "$T3" --resume
cd "$PROJ"; git checkout -q develop 2>/dev/null

echo
echo "===== GATES assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- turn 1: roadmap presented, NOTHING committed to yet ---"
chk "t1 kept the roadmap slot PENDING (asked before writing)" \
    'printf "%s" "$profile_after_1" | grep -qi "PENDING"'
chk "t1 did not cut a phase"                       '[ "$phases_after_1" = no ]'
chk "t1 created no issue branch"                   '[ "$issue_branches_1" -eq 0 ]'
chk "t1 presented BOTH phases in the transcript"   'grep -qi "phase 2\|fase 2" "$WORK/stream-t1.jsonl"'

echo "--- turn 2: roadmap recorded, phase cut, still not built ---"
# Punctuation-agnostic on purpose: the roadmap is prose the model formats, so assert it NAMES the phases and
# anchors them to requirement IDs — not that it picked an em dash over a colon.
chk "t2 wrote the roadmap into the profile"        'printf "%s" "$profile_after_2" | sed -n "/## Phase roadmap/,/^## Test/p" | grep -qiE "phase *1.*FR-1"'
chk "t2 roadmap covers the second phase too"       'printf "%s" "$profile_after_2" | sed -n "/## Phase roadmap/,/^## Test/p" | grep -qiE "phase *2.*FR-3"'
chk "t2 cleared the PENDING marker"                '! printf "%s" "$profile_after_2" | grep -qi "^PENDING"'
chk "t2 cut a non-empty phase-1 backlog"           'test -s "$BL"'
chk "t2 backlog carries a Gherkin Scenario"        'grep -qi "Scenario:" "$BL"'
chk "t2 backlog carries an Inner loop (TDD) flag"  'grep -qi "Inner loop" "$BL"'
chk "t2 built NOTHING (no issue branch yet)"       '[ "$issue_branches_2" -eq 0 ]'
chk "t2 wrote no test file yet"                    '[ "$tests_after_2" -eq 0 ]'

echo "--- turn 3: one approval covered the whole phase ---"
chk "t3 dispatched sdd-issue-worker"               'grep -q "sdd-issue-worker" "$WORK/stream-t3.jsonl"'
chk "t3 dispatched the lander (sdd-merge-resolver)" 'grep -q "sdd-merge-resolver" "$WORK/stream-t3.jsonl"'
chk "pytest green on develop"                      'PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1'
# The load-bearing one. A suite can go green while the SYSTEM does not work — e.g. a behaviour test that
# realizes its own `Given` by mutating the registry it is supposed to be observing, leaving production code
# that raises KeyError. Exercise the delivered surface with no test file in sight.
chk "the delivered system works with no test in the loop" \
    'PYTHONPATH=src python3 -c "from calc import apply; assert apply(\"add\", 2, 3) == 5; assert apply(\"subtract\", 5, 3) == 2"'
chk "no issue left mid-flight (cursor Doing: none)" 'grep -iA3 "SDD-CURSOR" docs/PROGRESS.md | grep -qi "Doing: *none"'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- profile roadmap slot after turn 2 ---"; sed -n '/Phase roadmap/,/^## /p' "$PROFILE" | head -20
  echo "--- backlog head ---"; head -30 "$BL" 2>/dev/null
fi
[ "$bad" -eq 0 ]
