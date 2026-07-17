#!/usr/bin/env bash
# FAIXA A — deterministic end-to-end of all three SDD hooks + path-awareness.
# Feeds each hook REAL JSON against REAL git repos / profiles and asserts allow/block/inject.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$REPO/plugins/sdd-loop/hooks"
ENF="$H/sdd-enforce-test-first.sh"; SS="$H/sdd-session-start.sh"; WARN="$H/sdd-warn-landed-test-edit.sh"
SCRATCH="$(cd "$(dirname "$0")" && pwd)"
BASE="$(mktemp -d)"; PASS=0; FAIL=0
G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'
chk(){ if eval "$2"; then printf "${G}PASS${N} %s\n" "$1"; PASS=$((PASS+1)); else printf "${R}FAIL${N} %s\n" "$1"; FAIL=$((FAIL+1)); fi; }

mkrepo(){ # $1 dir ; profile with +hook, develop base, issue branch
  local d="$1"; mkdir -p "$d/.sdd"; git -C "$d" init -q -b develop
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf '# profile\nintegrity: prose+git +hook\ncontinuation mode: auto\n' > "$d/.sdd/profile.md"
  echo seed > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm seed
}
enf(){ # $1 project-dir  $2 file_path  -> echoes exit code (0 allow / 2 block)
  # Feed via here-string, not a pipe: a fail-open hook may exit BEFORE reading stdin, which would
  # SIGPIPE a piped writer and (under pipefail) surface as 141 instead of the hook's real exit code.
  local json; json="$(jq -nc --arg f "$2" '{tool_input:{file_path:$f}}')"
  CLAUDE_PROJECT_DIR="$1" bash "$ENF" >/dev/null 2>&1 <<<"$json"; echo $?
}

echo "===== GROUP 1 — PreToolUse: test-first (+hook) ====="
d="$BASE/g1a"; mkdir -p "$d/.sdd"                       # no git, +hook -> fail-open allow? needs profile
printf 'integrity: prose+git +hook\n' > "$d/.sdd/profile.md"
chk "no git repo -> allow (fail-open)"            '[ "$(enf "'"$d"'" "'"$d"'/src/x.py")" = 0 ]'
d="$BASE/g1b"; mkdir -p "$d/.sdd"; printf 'integrity: prose+git\n' > "$d/.sdd/profile.md"
chk "+hook NOT enabled -> allow"                  '[ "$(enf "'"$d"'" "'"$d"'/src/x.py")" = 0 ]'
d="$BASE/g1c"; mkrepo "$d"; git -C "$d" checkout -q -b issue/1-x
chk "issue branch, impl, NO test committed -> BLOCK" '[ "$(enf "'"$d"'" "'"$d"'/src/x.py")" = 2 ]'
chk "issue branch, editing a TEST file -> allow"     '[ "$(enf "'"$d"'" "'"$d"'/tests/test_x.py")" = 0 ]'
chk "issue branch, editing a .md doc -> allow"       '[ "$(enf "'"$d"'" "'"$d"'/docs/NOTES.md")" = 0 ]'
chk "issue branch, editing PROGRESS -> allow"        '[ "$(enf "'"$d"'" "'"$d"'/docs/PROGRESS.md")" = 0 ]'
mkdir -p "$d/tests"; echo 'def test_x(): assert 1' > "$d/tests/test_x.py"; git -C "$d" add -A; git -C "$d" commit -qm 'test'
chk "issue branch, impl AFTER test committed -> allow" '[ "$(enf "'"$d"'" "'"$d"'/src/x.py")" = 0 ]'
git -C "$d" checkout -q develop
chk "NOT on issue branch -> allow"                   '[ "$(enf "'"$d"'" "'"$d"'/src/x.py")" = 0 ]'
# repo-relative classification: ancestor dir named 'test' must NOT disable the guard
anc="$BASE/testing-zone/proj"; mkdir -p "$anc"; mkrepo "$anc"; git -C "$anc" checkout -q -b issue/2-y
chk "ancestor dir named 'test' still BLOCKS impl"    '[ "$(enf "'"$anc"'" "'"$anc"'/src/y.py")" = 2 ]'

echo
echo "===== GROUP 1b — PreToolUse: WARN on editing a LANDED test (non-blocking) ====="
warn(){ # $1 project-dir  $2 file_path  -> echoes the systemMessage (empty if none)
  local json; json="$(jq -nc --arg f "$2" '{tool_input:{file_path:$f}}')"
  CLAUDE_PROJECT_DIR="$1" bash "$WARN" 2>/dev/null <<<"$json" | jq -r '.systemMessage // empty' 2>/dev/null
}
d="$BASE/w1"; mkrepo "$d"                                  # +hook, develop base
mkdir -p "$d/tests"; echo 'def test_a(): assert 1' > "$d/tests/test_landed.py"
git -C "$d" add -A; git -C "$d" commit -qm 'landed test'   # test now lives on develop
git -C "$d" checkout -q -b issue/9-z
chk "LANDED test edited on issue branch -> WARN"      '[ -n "$(warn "'"$d"'" "'"$d"'/tests/test_landed.py")" ]'
echo 'def test_n(): assert 1' > "$d/tests/test_new.py"     # new test, not on develop
chk "NEW (unlanded) test -> silent"                  '[ -z "$(warn "'"$d"'" "'"$d"'/tests/test_new.py")" ]'
chk "impl file (not a test) -> silent"               '[ -z "$(warn "'"$d"'" "'"$d"'/src/x.py")" ]'
git -C "$d" checkout -q develop
chk "landed test edited NOT on issue branch -> silent" '[ -z "$(warn "'"$d"'" "'"$d"'/tests/test_landed.py")" ]'
d="$BASE/w2"; mkdir -p "$d/.sdd"; git -C "$d" init -q -b develop
git -C "$d" config user.email t@t; git -C "$d" config user.name t
printf 'integrity: prose+git\n' > "$d/.sdd/profile.md"     # +hook OFF
mkdir -p "$d/tests"; echo x > "$d/tests/test_l.py"; git -C "$d" add -A; git -C "$d" commit -qm seed
git -C "$d" checkout -q -b issue/1-a
chk "+hook OFF -> silent even for a landed test"     '[ -z "$(warn "'"$d"'" "'"$d"'/tests/test_l.py")" ]'

echo
echo "===== GROUP 2 — SessionStart: re-prime injection ====="
cursor(){ printf '<!-- SDD-CURSOR -->\n- Phase: %s\n- Doing: %s\n- Next: %s\n- Stop-reason: %s\n<!-- /SDD-CURSOR -->\n' "$1" "$2" "$3" "$4"; }
mkproj(){ local d="$1" mode="$2"; mkdir -p "$d/.sdd" "$d/docs"; printf 'continuation mode: %s\n' "$mode" > "$d/.sdd/profile.md"; }
ctx(){ CLAUDE_PROJECT_DIR="$1" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }

d="$BASE/g2a"; mkproj "$d" auto; cursor none none none none > "$d/docs/PROGRESS.md"
chk "Phase=none -> 'No phase planned yet'"        'ctx "'"$d"'" | grep -q "No phase planned yet"'
chk "auto mode -> proceed WITHOUT asking"         'ctx "'"$d"'" | grep -qi "WITHOUT asking"'
d="$BASE/g2b"; mkproj "$d" ask; cursor 2 P2-3 P2-4 none > "$d/docs/PROGRESS.md"
chk "Doing set -> 'Resume BUILD of issue P2-3'"   'ctx "'"$d"'" | grep -q "Resume BUILD of issue P2-3"'
chk "ask mode -> PRESENT + ASK the user"          'ctx "'"$d"'" | grep -qi "ASK whether to continue"'
d="$BASE/g2c"; mkproj "$d" auto; cursor 1 none "none (phase-1 complete)" none > "$d/docs/PROGRESS.md"
chk "Next drained -> 'Phase appears drained'"     'ctx "'"$d"'" | grep -q "Phase appears drained"'
d="$BASE/g2d"; mkproj "$d" auto; cursor 1 none P1-2 none > "$d/docs/PROGRESS.md"
chk "grabbable Next -> 'SELECT and dispatch'"     'ctx "'"$d"'" | grep -q "SELECT and dispatch the Next"'
d="$BASE/g2e"; mkproj "$d" auto; cursor 1 P1-2 P1-3 needs-decision > "$d/docs/PROGRESS.md"
chk "stop=needs-decision -> human-touch stop"     'ctx "'"$d"'" | grep -qi "human-touch stop"'
chk "emits valid JSON w/ additionalContext"       'CLAUDE_PROJECT_DIR="'"$d"'" bash "'"$SS"'" </dev/null | jq -e ".hookSpecificOutput.additionalContext" >/dev/null'
d="$BASE/g2f"; mkdir -p "$d"                       # no profile -> silent no-op (no output)
chk "no .sdd/profile.md -> silent no-op"          '[ -z "$(CLAUDE_PROJECT_DIR="'"$d"'" bash "'"$SS"'" </dev/null)" ]'

echo
printf "===== GROUP 1+2 subtotal: %d passed, %d failed =====\n" "$PASS" "$FAIL"
rm -rf "$BASE"

echo
echo "===== GROUP 3 — SubagentStop verify matrix ====="; bash "$SCRATCH/subagentstop.sh"; s3=$?
echo
echo "===== GROUP 4 — Path-awareness (relocated + fallback) ====="; bash "$SCRATCH/test-paths.sh"; s4=$?

echo
if [ "$FAIL" -eq 0 ] && [ "$s3" -eq 0 ] && [ "$s4" -eq 0 ]; then
  echo "FAIXA A: ALL GREEN ✅ (Group1+2 $PASS/$((PASS)) · Group3 SubagentStop · Group4 Paths)"
else
  echo "FAIXA A: FAILURES PRESENT ❌  (g1+2 fails=$FAIL, g3=$s3, g4=$s4)"; exit 1
fi
