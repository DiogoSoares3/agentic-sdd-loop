#!/usr/bin/env bash
# Faixa B · flow — SELFTEST. Runs every chain with SKIP_MODEL=1, substituting a scripted mutation for each
# `claude` turn: the state a CORRECT run would have produced. No model, no network, seconds to run.
#
# It does not test the loop — it tests the TESTS. A live suite whose assertions have never been shown to
# pass is a liability: a typo'd grep, a subshell that swallows a `break`, a path that never existed all read
# as "the model misbehaved". Every chain must go GREEN here before a single Haiku token is spent, and after
# any edit to the chains.
#
#   bash tests/live/flow/selftest.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'
report(){ if [ "$1" -eq 0 ]; then printf "${G}SELFTEST PASS${N} %s\n" "$2"; PASS=$((PASS+1));
          else printf "${R}SELFTEST FAIL${N} %s (rc=%s)\n" "$2" "$1"; FAIL=$((FAIL+1)); fi; }

# ---------- gates: three turns, each mutating the repo the way a correct run would ----------
W="$(mktemp -d)"; bash "$HERE/fixture-gates.sh" "$W" >/dev/null
P="$W/gates-proj"

# turn 1 — roadmap derived and PRESENTED only: nothing on disk changes.
SIM_t1='printf "%s\n" "{\"text\":\"Phase 1 — registry ops (FR-1, FR-2). Phase 2 — history (FR-3). Approve?\"}" > "$out"'

# turn 2 — roadmap written into the profile, phase 1 cut. Still nothing built.
SIM_t2='
  perl -0pi -e "s/^PENDING.*\$/- Phase 1 — Registry ops: \`FR-1\`, \`FR-2\` · DoD: pytest green\n- Phase 2 — History: \`FR-3\` · DoD: history() reports applied ops/m" "'"$P"'/.sdd/profile.md"
  mkdir -p "'"$P"'/docs/phases/phase-1"
  cat > "'"$P"'/docs/phases/phase-1/backlog.md" <<BL
## Issue FR-1 — add through the registry
### Acceptance criteria
\`\`\`gherkin
Scenario: add resolves through the registry
  Given the calc registry
  When apply is called with "add", 2 and 3
  Then the result is 5
\`\`\`
### Inner loop (TDD)
\`required\`
BL
  : > "$out"'

# turn 3 — the whole phase built and landed through the worker + lander split.
SIM_t3='
  printf "%s\n" "spawning sdd-issue-worker" "spawning sdd-merge-resolver" > "$out"
  cd "'"$P"'"
  printf "from calc import apply\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  printf "from calc import apply\n\n\ndef test_subtract():\n    assert apply(\"subtract\", 5, 3) == 2\n" > tests/test_subtract.py
  printf "OPERATIONS = {\"add\": lambda a, b: a + b, \"subtract\": lambda a, b: a - b}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  git add -A && git commit -qm "phase 1: add + subtract"'
export SIM_t1 SIM_t2 SIM_t3
SKIP_MODEL=1 bash "$HERE/gates-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "gates-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/GATES assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_t1 SIM_t2 SIM_t3

# ---------- land: one turn producing the full worker+lander end state ----------
W="$(mktemp -d)"; bash "$HERE/fixture-land.sh" "$W" >/dev/null
P="$W/land-proj"
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker FR-1" "spawn sdd-merge-resolver FR-1 -> ready-to-land" \
                "spawn sdd-issue-worker FR-2" "spawn sdd-merge-resolver FR-2" > "$out"
  cd "'"$P"'"
  git checkout -q -b issue/FR-1-dispatch
  printf "from calc import apply, UnknownOperation\nimport pytest\n\n\ndef test_unknown_op():\n    with pytest.raises(UnknownOperation):\n        apply(\"nope\", 1, 2)\n" > tests/test_dispatch.py
  git add -A && git commit -qm "FR-1: behaviour test (RED)"
  printf "class UnknownOperation(Exception):\n    pass\n\n\nOPERATIONS = {\"add\": lambda a, b: a + b}\n\n\ndef apply(op, a, b):\n    if op not in OPERATIONS:\n        raise UnknownOperation(op)\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: implementation"
  git checkout -q develop && git merge -q --no-ff -m "land FR-1" issue/FR-1-dispatch
  git checkout -q -b issue/FR-2-version
  printf "from calc import VERSION\n\n\ndef test_version():\n    assert VERSION == \"1.0.0\"\n" > tests/test_version.py
  git add -A && git commit -qm "FR-2: behaviour test (RED)"
  printf "%s\n" "VERSION = \"1.0.0\"" >> src/calc/__init__.py
  git add -A && git commit -qm "FR-2: implementation"
  git checkout -q develop && git merge -q --no-ff -m "land FR-2" issue/FR-2-version
  python3 - <<PYEOF
import re, pathlib
p = pathlib.Path("docs/PROGRESS.md"); t = p.read_text()
t = t.replace("- Doing: none", "- Doing: none")
t += "\n- FR-1: unit \"dispatch rejects unknown op\" green; next: register add\n"
p.write_text(t)
PYEOF
  git add -A && git commit -qm "record"'
export SIM_build
SKIP_MODEL=1 bash "$HERE/land-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "land-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/LAND assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_build

# ---------- guard: turn 1 denied (no change), turn 2 allowed on the issue branch ----------
W="$(mktemp -d)"; bash "$HERE/fixture-guard.sh" "$W" >/dev/null
P="$W/guard-proj"
SIM_g1='printf "%s\n" "{\"text\":\"[SDD branch integrity] denied: you are on develop, not an issue/* branch\"}" > "$out"
  cd "'"$P"'" && git checkout -q issue/FR-1-subtract'
SIM_g2='
  cd "'"$P"'" && git checkout -q issue/FR-1-subtract
  printf "OPERATIONS = {\"subtract\": lambda a, b: a - b}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  : > "$out"'
export SIM_g1 SIM_g2
SKIP_MODEL=1 bash "$HERE/guard-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "guard-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/GUARD assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_g1 SIM_g2

# ---------- negative control: a WRONG end state must FAIL, or the assertions prove nothing ----------
W="$(mktemp -d)"; bash "$HERE/fixture-land.sh" "$W" >/dev/null
P="$W/land-proj"
# The pre-change behaviour: the worker builds AND lands by itself — no lander, and no test-first split.
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker" > "$out"
  cd "'"$P"'"
  printf "class UnknownOperation(Exception):\n    pass\n\n\nOPERATIONS = {}\nVERSION = \"1.0.0\"\n\n\ndef apply(op, a, b):\n    raise UnknownOperation(op)\n" > src/calc/__init__.py
  printf "from calc import VERSION\n\n\ndef test_version():\n    assert VERSION == \"1.0.0\"\n" > tests/test_version.py
  git add -A && git commit -qm "everything at once, straight on develop"'
export SIM_build
SKIP_MODEL=1 bash "$HERE/land-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "land-chain REJECTS a worker-lands-it-itself run (negative control)";
else report 1 "land-chain REJECTS a worker-lands-it-itself run (negative control)"; sed -n '/LAND assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_build

echo
printf "== selftest: %d passed, %d failed ==\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
