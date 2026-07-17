#!/usr/bin/env bash
# PR/CI proxy — deterministic (real git + pytest, NO GitHub, NO model). Reproduces the plugin's
# provider/CI semantics without touching any real account: a **bare repo as the remote** (the PR/push
# surface) + a **merge gate that runs the FULL regression suite** before landing on a protected/integration
# branch. This is the isolatable stand-in for `provider: gh` + required checks.
#
# It asserts the behaviour the plugin documents for the regression gate at a merge to a non-feature branch:
#   1. a feature branch is published to the remote (the push/PR surface is real);
#   2. a GREEN feature passes CI and lands on develop;
#   3. a REGRESSING feature is REJECTED by CI — the protected branch stays byte-for-byte pristine;
#   4. develop → main promotion is gated the same way.
#
# Requires: git, python3 + pytest. Runs entirely in a mktemp dir.
set -uo pipefail
# Never write .pyc: this harness re-runs pytest on the SAME repo across git merges, and a stale cached
# bytecode from an earlier (green) run can mask a later break — a test-harness artifact, not the plugin.
export PYTHONDONTWRITEBYTECODE=1
BASE="$(mktemp -d)"; PASS=0; FAIL=0
G='\033[0;32m'; R='\033[0;31m'; NC='\033[0m'
ok(){ if eval "$2"; then printf "${G}PASS${NC} %s\n" "$1"; PASS=$((PASS+1)); else printf "${R}FAIL${NC} %s\n" "$1"; FAIL=$((FAIL+1)); fi; }
suite(){ ( cd "$1" && PYTHONPATH=src python3 -m pytest -q >/dev/null 2>&1 ); }

# --- a bare "remote" + a working clone with a landed baseline (add) on main + develop ---
BARE="$BASE/origin.git"; git init -q --bare -b main "$BARE"
W="$BASE/work"; git clone -q "$BARE" "$W" 2>/dev/null
git -C "$W" config user.email t@t; git -C "$W" config user.name t
mkdir -p "$W/src/calc" "$W/tests"
printf 'OPERATIONS = {"add": lambda a, b: a + b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$W/src/calc/__init__.py"
printf 'from calc import apply\n\ndef test_add():\n    assert apply("add", 2, 3) == 5\n' > "$W/tests/test_add.py"
git -C "$W" add -A; git -C "$W" commit -qm "baseline: add"
git -C "$W" push -q origin main
git -C "$W" branch develop; git -C "$W" push -q origin develop

# The CI gate: run the FULL suite on the would-be merge result; land+publish iff green, else reject (target
# left pristine). This is exactly "CI runs the regression suite at merge, gate the merge".
ci_merge(){ # $1 feature-ref  $2 target-branch  -> 0 landed / 1 rejected-by-CI / 3 conflict
  git -C "$W" checkout -q "$2"
  git -C "$W" merge --no-commit --no-ff "$1" >/dev/null 2>&1 || { git -C "$W" merge --abort 2>/dev/null; return 3; }
  if suite "$W"; then
    git -C "$W" commit -q --no-edit; git -C "$W" push -q origin "$2"; return 0
  else
    git -C "$W" merge --abort 2>/dev/null; git -C "$W" checkout -q -- .; return 1
  fi
}

echo "===== PR/CI proxy — bare remote + regression gate at merge ====="

# 1. GREEN feature (subtract) -> pushed -> CI green -> lands on develop
git -C "$W" checkout -q develop; git -C "$W" checkout -q -b feat/subtract
printf 'OPERATIONS = {"add": lambda a, b: a + b, "subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$W/src/calc/__init__.py"
printf 'from calc import apply\n\ndef test_subtract():\n    assert apply("subtract", 5, 3) == 2\n' > "$W/tests/test_subtract.py"
git -C "$W" add -A; git -C "$W" commit -qm "feat: subtract"
git -C "$W" push -q origin feat/subtract
ok "feature branch is published to the remote (PR/push surface is real)" \
   'git -C "'"$W"'" ls-remote --heads origin feat/subtract | grep -q feat/subtract'
ci_merge feat/subtract develop; rc=$?
ok "GREEN feature passes CI and LANDS on develop" \
   '[ "$rc" = 0 ] && git -C "'"$W"'" show develop:src/calc/__init__.py | grep -q subtract'
ok "regression suite green on develop after land (2 passed)" \
   '( cd "'"$W"'" && git checkout -q develop; PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "2 passed" )'

# 2. REGRESSING feature (breaks add) -> CI red -> REJECTED -> protected develop pristine
git -C "$W" checkout -q develop; git -C "$W" checkout -q -b feat/bad
printf 'OPERATIONS = {"add": lambda a, b: a - b, "subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$W/src/calc/__init__.py"
git -C "$W" add -A; git -C "$W" commit -qm "feat: (accidentally breaks add)"
git -C "$W" push -q origin feat/bad
DEV_SHA="$(git -C "$W" rev-parse origin/develop)"
ci_merge feat/bad develop; rc=$?
ok "REGRESSING feature is REJECTED by CI (gate returns non-zero)" '[ "$rc" = 1 ]'
ok "protected develop stays PRISTINE after a red merge (remote SHA unchanged)" \
   '[ "$(git -C "'"$W"'" rev-parse origin/develop)" = "'"$DEV_SHA"'" ]'
ok "develop suite still green — the regression never landed (2 passed)" \
   '( cd "'"$W"'" && git checkout -q develop; PYTHONPATH=src python3 -m pytest -q 2>/dev/null | grep -qE "2 passed" )'

# 3. develop -> main promotion is gated the same way (green -> main advances)
ci_merge develop main; rc=$?
ok "develop → main promotion passes CI and advances the protected branch" \
   '[ "$rc" = 0 ] && git -C "'"$W"'" show main:src/calc/__init__.py | grep -q subtract'

echo
printf "===== %d passed, %d failed =====\n" "$PASS" "$FAIL"
rm -rf "$BASE"; [ "$FAIL" -eq 0 ]
