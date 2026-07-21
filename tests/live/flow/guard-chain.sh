#!/usr/bin/env bash
# Faixa B · flow — GUARD chain. Two turns, with a positive control, proving the issue-branch guard is wired
# and discriminating (a guard that denies everything is as broken as one that denies nothing):
#   turn 1  edit the seam WHILE ON develop, issue in flight  -> DENIED, file byte-identical
#   turn 2  same edit after checking out issue/FR-1-subtract -> ALLOWED, file changed
#
# Out of scope by design: writes through Bash bypass every PreToolUse guard (see the README note). The turns
# below therefore ask explicitly for the Edit/Write tools — the tools the hook is registered for.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash guard-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: guard-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/guard-proj"; SETTINGS="$WORK/settings.json"
SEAM="$PROJ/src/calc/__init__.py"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
SID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

turn() { # $1 out-file  $2 prompt  $3 session-mode  $4 sim-key
  run_turn "$1" "SIM_$4" "$3" "$SID" "$2"
}

T1='Register the "subtract" operation in the OPERATIONS registry in src/calc/__init__.py so that apply("subtract", 5, 3) returns 2. Use the Edit or Write tool to change that file — do not use Bash, git, or any shell command to write it, and do not switch branches. Just make the edit where you are.'
T2='Now run: git checkout issue/FR-1-subtract. Then make exactly the same change — register "subtract" in the OPERATIONS registry in src/calc/__init__.py — using the Edit or Write tool.'

dev_seam(){ git -C "$PROJ" show develop:src/calc/__init__.py 2>/dev/null | sha256sum | awk '{print $1}'; }

turn "$WORK/stream-g1.jsonl" "$T1" --session-id g1
dev_after1="$(dev_seam)"; branch1="$(git -C "$PROJ" rev-parse --abbrev-ref HEAD)"

turn "$WORK/stream-g2.jsonl" "$T2" --resume g2
dev_after2="$(dev_seam)"; branch2="$(git -C "$PROJ" rev-parse --abbrev-ref HEAD)"
before="$(cat "$WORK/seam.sha256")"

echo
echo "===== GUARD assertions ====="
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- turn 1: asked to implement on develop with an issue in flight ---"
chk "the guard's denial reached the transcript"            'grep -qi "branch integrity\|issue/\* branch\|integration/protected" "$WORK/stream-g1.jsonl"'
chk "develop's committed seam is byte-identical"           '[ "$dev_after1" = "$before" ]'
chk "no new commit landed on develop"                      '[ "$(git -C "$PROJ" rev-list --count develop)" = 1 ]'

echo "--- turn 2: the work belongs on the issue branch, and gets there ---"
chk "ended on the issue branch"                            '[ "$branch2" = issue/FR-1-subtract ]'
chk "the edit went through there"                          'grep -q "subtract" "$SEAM"'
chk "develop STILL untouched after both turns"             '[ "$dev_after2" = "$before" ]'

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- working tree seam ---"; cat "$SEAM"
  echo "--- develop seam ---"; git -C "$PROJ" show develop:src/calc/__init__.py
  echo "--- branch: $branch1 -> $branch2 ---"
fi
[ "$bad" -eq 0 ]
