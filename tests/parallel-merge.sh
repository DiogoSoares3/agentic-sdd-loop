#!/usr/bin/env bash
# PARALLEL / MERGE-RESOLVER mechanics — deterministic proof (real git + real pytest, NO model).
# ------------------------------------------------------------------------------------------------
# Faixa A proves the hooks; this proves the *scenario* the sdd-merge-resolver is asked to survive is
# sound and that the regression gate actually gates. It builds a real `calc` repo where two parallel
# issues collide on a shared registry line, lands one, and drives the second through a rebase conflict.
#
# It asserts, with plain git + pytest (no Haiku):
#   1. the two ready-to-land branches REALLY conflict on rebase onto the moving develop;
#   2. the CORRECT resolution (keep both intents) makes the FULL suite green;
#   3. a WEAKENING resolution (drop the landed issue's behaviour) is CAUGHT by the full suite — the
#      regression gate has teeth, so "never weaken a landed test/behaviour" is enforceable;
#   4. the landed issue's test file is left byte-identical by a correct resolution;
#   5. the +hook landed-test WARNING fires when the resolver would edit a landed test.
#
# Requires: git, python3 + pytest, jq (for the hook check). Runs entirely in a mktemp dir.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # re-running pytest across git rebases: never let a stale .pyc mask a break
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WARN="$REPO/plugins/sdd-loop/hooks/sdd-warn-landed-test-edit.sh"
BASE="$(mktemp -d)"; PASS=0; FAIL=0
G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'
ok(){ if eval "$2"; then printf "${G}PASS${N} %s\n" "$1"; PASS=$((PASS+1)); else printf "${R}FAIL${N} %s\n" "$1"; FAIL=$((FAIL+1)); fi; }

py(){ ( cd "$1" && PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1 ); }   # $1 repo -> exit 0 if green

# Build a repo stopped at "issue/2 rebasing onto a develop that already landed issue/1" -> conflict pending.
# Echoes the repo dir. Both issues edit the SAME registry line, so the rebase MUST conflict.
mk_conflict(){
  local d="$1"; mkdir -p "$d/src/calc" "$d/tests" "$d/.sdd"
  git -C "$d" init -q -b develop; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf 'integrity: prose+git +hook\nContinuation mode: auto\n' > "$d/.sdd/profile.md"
  # base seam: an empty operation registry + a public apply() that dispatches through it.
  printf 'OPERATIONS = {}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$d/src/calc/__init__.py"
  git -C "$d" add -A; git -C "$d" commit -qm 'base: calc registry seam' >/dev/null
  local base; base="$(git -C "$d" rev-parse HEAD)"

  # issue/1-add: register add + its behaviour test. Land it onto develop.
  git -C "$d" checkout -q -b issue/1-add "$base"; mkdir -p "$d/tests"
  printf 'OPERATIONS = {"add": lambda a, b: a + b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$d/src/calc/__init__.py"
  printf 'from calc import apply\n\ndef test_add():\n    assert apply("add", 2, 3) == 5\n' > "$d/tests/test_add.py"
  git -C "$d" add -A; git -C "$d" commit -qm 'issue/1: add' >/dev/null
  git -C "$d" checkout -q develop; git -C "$d" merge -q --no-ff -m 'land issue/1-add' issue/1-add

  # issue/2-subtract: branched from the SAME base (never saw issue/1) -> edits the same registry line.
  git -C "$d" checkout -q -b issue/2-subtract "$base"; mkdir -p "$d/tests"
  printf 'OPERATIONS = {"subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$d/src/calc/__init__.py"
  printf 'from calc import apply\n\ndef test_subtract():\n    assert apply("subtract", 5, 3) == 2\n' > "$d/tests/test_subtract.py"
  git -C "$d" add -A; git -C "$d" commit -qm 'issue/2: subtract' >/dev/null

  # The orchestrator's serial land queue now rebases issue/2 onto the moving develop -> CONFLICT.
  git -C "$d" checkout -q issue/2-subtract
  git -C "$d" rebase develop >/dev/null 2>&1   # expected to STOP on a conflict (non-zero)
  echo "$d"
}

echo "===== PARALLEL / MERGE-RESOLVER mechanics (deterministic) ====="

# --- 1. the conflict is real ---
A="$(mk_conflict "$BASE/happy")"
ok "two parallel branches REALLY conflict on rebase onto develop" \
   'git -C "'"$A"'" status --porcelain 2>/dev/null | grep -q "^UU " || grep -q "<<<<<<<" "'"$A"'/src/calc/__init__.py"'

# --- 5. warn hook fires on editing the LANDED test during resolution (branch pre-rebase) ---
Wd="$(mktemp -d)"; W="$(mk_conflict "$Wd/w")"; git -C "$W" rebase --abort >/dev/null 2>&1
git -C "$W" checkout -q issue/2-subtract
warnmsg="$(printf '{"tool_input":{"file_path":"tests/test_add.py"}}' | CLAUDE_PROJECT_DIR="$W" bash "$WARN" 2>/dev/null | jq -r '.systemMessage // empty' 2>/dev/null)"
ok "warn hook fires when resolver would edit a LANDED test" '[ -n "$warnmsg" ]'

# --- 2. CORRECT resolution (keep BOTH intents) -> full suite green ---
printf 'OPERATIONS = {"add": lambda a, b: a + b, "subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$A/src/calc/__init__.py"
git -C "$A" add -A; GIT_EDITOR=true git -C "$A" rebase --continue >/dev/null 2>&1
ok "correct resolution: FULL suite green (both behaviours pass)" 'py "'"$A"'"'
ok "the resolved suite really runs BOTH behaviours (2 passed)" \
   '( cd "'"$A"'" && PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "2 passed" )'
ok "resolution re-lands cleanly (no rebase in progress)" '! git -C "'"$A"'" status | grep -qi "rebase in progress"'

# --- 4. the landed issue's test is left byte-identical by the correct resolution ---
ok "landed test (test_add.py) untouched by the resolution" \
   'git -C "'"$A"'" diff --quiet develop -- tests/test_add.py'

# --- 3. WEAKENING resolution (drop the landed behaviour) -> full suite CATCHES it ---
Bd="$(mk_conflict "$BASE/weaken")"
printf 'OPERATIONS = {"subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$Bd/src/calc/__init__.py"
git -C "$Bd" add -A; GIT_EDITOR=true git -C "$Bd" rebase --continue >/dev/null 2>&1
ok "weakening resolution (drops add) is CAUGHT by the full suite (regression gate has teeth)" '! py "'"$Bd"'"'

echo
echo "===== MULTI-ITEM LAND QUEUE — ordering (dependency → backlog) drains all green ====="
ADD='"add": lambda a, b: a + b'
SUB='"subtract": lambda a, b: a - b'
DBL='"double": lambda a, b: apply("add", a, a)'   # DEPENDS on "add" being registered

# Build a repo with base develop + THREE ready-to-land branches, each editing the shared OPERATIONS line
# (so they conflict pairwise) and each carrying its own behaviour test. Echoes the dir. develop stays at base.
build_multi(){
  local d="$1"; mkdir -p "$d/src/calc" "$d/tests" "$d/.sdd"
  git -C "$d" init -q -b develop; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf 'integrity: prose+git +hook\nConcurrency: parallel\n' > "$d/.sdd/profile.md"
  printf 'OPERATIONS = {}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$d/src/calc/__init__.py"
  git -C "$d" add -A; git -C "$d" commit -qm base >/dev/null
  local b; b="$(git -C "$d" rev-parse HEAD)"
  _mkbr(){ # $1 dir $2 branch $3 fragment $4 testfile $5 testbody
    git -C "$1" checkout -q -b "$2" "$b"; mkdir -p "$1/tests"
    printf 'OPERATIONS = {%s}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' "$3" > "$1/src/calc/__init__.py"
    printf '%s' "$5" > "$1/tests/$4"; git -C "$1" add -A; git -C "$1" commit -qm "$2" >/dev/null; }
  _mkbr "$d" issue/1-add      "$ADD" test_add.py      'from calc import apply
def test_add():
    assert apply("add", 2, 3) == 5
'
  _mkbr "$d" issue/2-subtract "$SUB" test_subtract.py 'from calc import apply
def test_subtract():
    assert apply("subtract", 5, 3) == 2
'
  _mkbr "$d" issue/3-double   "$DBL" test_double.py   'from calc import apply
def test_double():
    assert apply("double", 5, 0) == 10
'
  git -C "$d" checkout -q develop
}

M="$BASE/multi"; build_multi "$M"

# The backlog records the queue in order + the dependency, using the real /to-issues fields.
BLM="$M/backlog.md"
cat > "$BLM" <<'BK'
## Issue issue-1-add
Blocked by: None — can start immediately
Touches: src/calc/__init__.py (OPERATIONS registry)
## Issue issue-2-subtract
Blocked by: None — can start immediately
Touches: src/calc/__init__.py (OPERATIONS registry)
## Issue issue-3-double
Blocked by: issue-1-add
Touches: src/calc/__init__.py (OPERATIONS registry)
BK
ok "queue order is file-derivable (issue HEADINGS in backlog order 1,2,3)" \
   '[ "$(grep "^## Issue" "'"$BLM"'" | grep -oE "issue-[123]" | tr -d "\n")" = "issue-1issue-2issue-3" ]'
ok "dependency is file-derivable (issue-3 Blocked by issue-1)" \
   'awk "/issue-3-double/{f=1} f&&/Blocked by/{print;exit}" "'"$BLM"'" | grep -q "issue-1-add"'

# Serial drain in dependency→backlog order (1,2,3): each rebases onto the MOVING develop tip, resolving the
# shared-line conflict by keeping the running union of ops (this is what the lander does per queue item).
ACC=""
land_one(){ # $1 branch  $2 fragment
  git -C "$M" checkout -q "$1"
  if ! git -C "$M" rebase develop >/dev/null 2>&1; then
    printf 'OPERATIONS = {%s}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' "$ACC${ACC:+, }$2" > "$M/src/calc/__init__.py"
    git -C "$M" add -A; GIT_EDITOR=true git -C "$M" rebase --continue >/dev/null 2>&1
  fi
  git -C "$M" checkout -q develop && git -C "$M" merge -q --ff-only "$1"
  ACC="$ACC${ACC:+, }$2"
}
land_one issue/1-add "$ADD"
land_one issue/2-subtract "$SUB"
ok "serial drain rebases onto the MOVING tip (add+subtract both on develop after 2 lands)" \
   'git -C "'"$M"'" show develop:src/calc/__init__.py | grep -q "\"add\"" && git -C "'"$M"'" show develop:src/calc/__init__.py | grep -q "\"subtract\""'
land_one issue/3-double "$DBL"
ok "all 3 land green in dependency+backlog order (full suite 3 passed)" \
   '( cd "'"$M"'" && PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "3 passed" )'

# NEGATIVE: landing the DEPENDENT (issue/3-double) before its blocker (issue/1-add) -> red (add unregistered).
Nd="$BASE/multi-bad"; build_multi "$Nd"
git -C "$Nd" checkout -q issue/3-double; git -C "$Nd" rebase develop >/dev/null 2>&1
git -C "$Nd" checkout -q develop && git -C "$Nd" merge -q --ff-only issue/3-double
ok "dependency ordering is load-bearing: dependent-before-blocker -> full suite RED" '! py "'"$Nd"'"'

echo
printf "===== %d passed, %d failed =====\n" "$PASS" "$FAIL"
rm -rf "$BASE" "$Wd"
[ "$FAIL" -eq 0 ]
