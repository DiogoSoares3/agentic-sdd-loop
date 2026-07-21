#!/usr/bin/env bash
# Faixa B · flow — TEST-FIRST chain. Two turns, with the positive control that makes the first one mean
# something (a guard that denies everything is as broken as one that denies nothing):
#   turn 1  implement on the issue branch with NO test committed  -> DENIED, the seam stays byte-identical
#   turn 2  do it properly: failing test committed alone, then implement -> ALLOWED, two-commit trace
#
# This is the `+hook` layer of `prose+git +hook` doing the thing prose alone only asks for. Faixa A already
# proves the hook's exit code against synthetic payloads; what is unproven is whether a real agent, told
# plainly to skip the test, is actually stopped — and whether the denial is legible enough that it recovers
# into the right shape instead of working around it.
#
# Out of scope by design: writes through Bash bypass every PreToolUse guard (see the README note). Turn 1
# therefore asks explicitly for Edit/Write — the tools the hook is registered for.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash testfirst-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: testfirst-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/testfirst-proj"; SETTINGS="$WORK/settings.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

T1='You are on branch issue/FR-1-add. Register "add" in the OPERATIONS registry in src/calc/__init__.py so that apply("add", 2, 3) returns 5. Use the Edit or Write tool for that file — do not use Bash, git, or any shell command to write it. Skip the test for now; we will add tests at the end of the phase, once the implementation is settled.'
T2='Understood — do it the way the project requires instead. Write the failing behaviour test for the scenario in docs/phases/phase-1/backlog.md first, commit that test on its own, and only then implement the registration in src/calc/__init__.py and commit it. Use the Edit or Write tool for the file contents.'

branch_seam(){ git -C "$PROJ" show "issue/FR-1-add:src/calc/__init__.py" 2>/dev/null | sha256sum | awk '{print $1}'; }
commits_on_branch(){ git -C "$PROJ" rev-list --count develop..issue/FR-1-add 2>/dev/null || echo 0; }

before="$(cat "$WORK/seam.sha256")"

run_turn "$WORK/stream-tf1.jsonl" SIM_tf1 --session-id "$SID" "$T1"
# Snapshot NOW, not at the end: turn 2 legitimately adds an implementation commit, so anything about turn 1
# that is read after both turns is answering the wrong question.
seam1="$(branch_seam)"; commits1="$(commits_on_branch)"
impl1="$(git -C "$PROJ" log develop..issue/FR-1-add --name-only --format= 2>/dev/null | grep -c 'src/'; true)"

run_turn "$WORK/stream-tf2.jsonl" SIM_tf2 --resume "$SID" "$T2"
seam2="$(branch_seam)"

cd "$PROJ"
echo
echo "===== TEST-FIRST assertions (commits on the branch after turn 1: $commits1) ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- turn 1: implementation asked for with no test committed ---"
chk "the guard's denial reached the transcript" \
    'grep -qi "test-first violation\|prove RED\|failing behaviour test" "$WORK/stream-tf1.jsonl"'
chk "the committed seam is byte-identical"            '[ "$seam1" = "$before" ]'
chk "no implementation commit landed on the branch"   '[ "${impl1:-0}" -eq 0 ]'

echo "--- turn 2: done in the right order, the guard lets it through ---"
chk "the seam changed on the branch"                  '[ "$seam2" != "$before" ]'
chk "add is registered in the shipped module"         'git show issue/FR-1-add:src/calc/__init__.py | grep -q "add"'
chk "a test-only commit exists on the branch"         'has_test_only_commit "$PROJ" issue/FR-1-add'
chk "the test-only commit came BEFORE the implementation" \
    '[ -n "$(git rev-list develop..issue/FR-1-add --reverse 2>/dev/null | head -n1)" ] &&
     ! git show --name-only --format= "$(git rev-list develop..issue/FR-1-add --reverse | head -n1)" | grep -q "src/"'
chk "pytest green on the branch"                      'git checkout -q issue/FR-1-add && PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1'

echo "--- and nothing leaked onto the integration branch ---"
chk "develop still carries no implementation"         'git show develop:src/calc/__init__.py | grep -q "OPERATIONS = {}"'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- branch history ---"; git log develop..issue/FR-1-add --oneline --name-only | head -30
  echo "--- branch seam ---"; git show issue/FR-1-add:src/calc/__init__.py
fi
[ "$bad" -eq 0 ]
