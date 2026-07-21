#!/usr/bin/env bash
# Faixa B · flow — BDD ROUTING chain. Two turns, one session, invoking the /bdd skill DIRECTLY in each of
# its two postures — no phase-opener, no issue-worker, because the thing under test is the skill's own
# dispatch, not the loop. A PreToolUse(Read) probe records which sibling each turn opens.
#
#   turn 1  AUTHOR a new scenario (PLAN posture)   -> must read authoring.md, must NOT read realizing.md
#   turn 2  REALIZE FR-1's scenario (BUILD posture) -> must read realizing.md, must NOT read authoring.md
#
# The negative half of each pair is the real assertion: the split exists so the realizer never carries the
# authoring rules (which tell it to WRITE the scenario it must instead treat as immutable), and vice versa.
# Reading the right file alone could be luck; reading the right one AND not the wrong one is the routing.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash bdd-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: bdd-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/bdd-proj"; SETTINGS="$WORK/settings.json"; READLOG="$WORK/readlog.txt"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

AUTHOR='Invoke the /bdd skill to AUTHOR the acceptance criteria for a NEW backlog issue we are planning:
FR-2 — apply("subtract", a, b) returns the difference of the two operands, through the same OPERATIONS
registry. We are at PLAN: write the single Gherkin Scenario for FR-2 and append it to
docs/phases/phase-1/backlog.md. Do not write any test or implementation — this is planning only.'

REALIZE='Now invoke the /bdd skill to REALIZE the ALREADY-AUTHORED scenario of issue FR-1 (in
docs/phases/phase-1/backlog.md) as the failing outer behaviour test, at the seam ARCHITECTURE.md names.
We are at BUILD, on branch issue/FR-1-add. Do NOT rewrite or weaken the scenario — realize it as-is. Write
the test file and stop before implementing.'

# --- turn 1: authoring ---
git -C "$PROJ" checkout -q develop 2>/dev/null
run_turn "$WORK/stream-b1.jsonl" SIM_author --session-id "$SID" "$AUTHOR"
cp -f "$READLOG" "$WORK/readlog.after1.txt"

# --- turn 2: realizing (reset the probe so each turn's reads are attributed to that turn) ---
: > "$READLOG"
git -C "$PROJ" checkout -q issue/FR-1-add 2>/dev/null
run_turn "$WORK/stream-b2.jsonl" SIM_realize --resume "$SID" "$REALIZE"
cp -f "$READLOG" "$WORK/readlog.after2.txt"

R1="$WORK/readlog.after1.txt"; R2="$WORK/readlog.after2.txt"
reads_auth1="$(grep -c 'skills/bdd/authoring\.md'  "$R1" 2>/dev/null; true)"
reads_real1="$(grep -c 'skills/bdd/realizing\.md'  "$R1" 2>/dev/null; true)"
reads_auth2="$(grep -c 'skills/bdd/authoring\.md'  "$R2" 2>/dev/null; true)"
reads_real2="$(grep -c 'skills/bdd/realizing\.md'  "$R2" 2>/dev/null; true)"

echo
echo "===== BDD ROUTING assertions ====="
echo "  turn 1 (author):  authoring=$reads_auth1 realizing=$reads_real1"
echo "  turn 2 (realize): authoring=$reads_auth2 realizing=$reads_real2"
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- the skill was actually consulted (SKILL.md loaded on both turns) ---"
chk "turn 1 opened the bdd skill"                    'grep -q "skills/bdd/" "$R1"'
chk "turn 2 opened the bdd skill"                    'grep -q "skills/bdd/" "$R2"'

echo "--- turn 1 routed to AUTHORING, and only authoring ---"
chk "authoring.md was read"                          '[ "${reads_auth1:-0}" -gt 0 ]'
chk "realizing.md was NOT read"                      '[ "${reads_real1:-0}" -eq 0 ]'

echo "--- turn 2 routed to REALIZING, and only realizing ---"
chk "realizing.md was read"                          '[ "${reads_real2:-0}" -gt 0 ]'
chk "authoring.md was NOT read"                      '[ "${reads_auth2:-0}" -eq 0 ]'

echo "--- and each posture produced the right artefact (corroborating the routing) ---"
chk "turn 1 appended an FR-2 scenario to the backlog" \
    'grep -qi "FR-2" "$PROJ/docs/phases/phase-1/backlog.md" && grep -c "Scenario:" "$PROJ/docs/phases/phase-1/backlog.md" | grep -qE "[2-9]"'
chk "turn 2 wrote a test that calls the apply seam"  'ls "$PROJ"/tests/*.py >/dev/null 2>&1 && grep -rqi "apply" "$PROJ"/tests'
chk "turn 2 did NOT implement (OPERATIONS still empty on the branch)" \
    'git -C "$PROJ" show issue/FR-1-add:src/calc/__init__.py 2>/dev/null | grep -q "OPERATIONS = {}" || grep -q "OPERATIONS = {}" "$PROJ/src/calc/__init__.py"'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- readlog turn 1 (bdd only) ---"; grep 'skills/bdd/' "$R1" || echo "(none)"
  echo "--- readlog turn 2 (bdd only) ---"; grep 'skills/bdd/' "$R2" || echo "(none)"
  echo "--- backlog tail ---"; tail -20 "$PROJ/docs/phases/phase-1/backlog.md"
fi
[ "$bad" -eq 0 ]
