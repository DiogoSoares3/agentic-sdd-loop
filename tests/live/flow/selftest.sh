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
REPO="$(cd "$HERE/../../.." && pwd)"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
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

# ---------- red: a HONEST green — test-only commit, really red first, delivered surface works ----------
W="$(mktemp -d)"; bash "$HERE/fixture-red.sh" "$W" >/dev/null
P="$W/red-proj"
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker FR-1" "spawn sdd-merge-resolver FR-1" > "$out"
  cd "'"$P"'"
  git checkout -q -b issue/FR-1-add
  printf "from calc import apply\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  git add -A && git commit -qm "FR-1: behaviour test (RED)"
  printf "def _add(a, b):\n    return a + b\n\n\nOPERATIONS = {\"add\": _add}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: register add in the shipped registry"
  git checkout -q develop && git merge -q --no-ff -m "land FR-1" issue/FR-1-add'
export SIM_build
SKIP_MODEL=1 bash "$HERE/red-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "red-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/RED assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_build

# ---------- negative control: the HOLLOW GREEN this scenario exists for must FAIL ----------
# Verbatim shape of the defect a live run produced: the registration lives in the test, so the suite is
# green, the two-commit rule is satisfied, and the shipped package still raises KeyError.
W="$(mktemp -d)"; bash "$HERE/fixture-red.sh" "$W" >/dev/null
P="$W/red-proj"
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker FR-1" "spawn sdd-merge-resolver FR-1" > "$out"
  cd "'"$P"'"
  git checkout -q -b issue/FR-1-add
  printf "from calc import apply, OPERATIONS\n\n\ndef add(a, b):\n    return a + b\n\n\nOPERATIONS[\"add\"] = add\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  git add -A && git commit -qm "FR-1: behaviour test"
  git checkout -q develop && git merge -q --no-ff -m "land FR-1" issue/FR-1-add'
export SIM_build
SKIP_MODEL=1 bash "$HERE/red-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "red-chain REJECTS a hollow green (negative control)";
else report 1 "red-chain REJECTS a hollow green (negative control)"; sed -n '/RED assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_build

# ---------- tdd: the checkpoint gate blocks the shortcut and the worker recovers ----------
W="$(mktemp -d)"; bash "$HERE/fixture-tdd.sh" "$W" >/dev/null
P="$W/tdd-proj"
# The SubagentStop log is written by a real hook in a live run; here the sim stands in for it, in the marker
# format the hook emits (one STOP line per stop, carrying the verdict when there is one) and with the
# verifier's real block wording, so the chain's greps are tested against the text it will actually meet.
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker FR-1" "spawn sdd-merge-resolver FR-1" > "$out"
  printf "STOP %s\n" "{\"decision\":\"block\",\"reason\":\"sdd-issue-worker reports success on issue FR-1, whose '"'"'Inner loop (TDD)'"'"' flag is REQUIRED, but docs/PROGRESS.md carries no inner-loop checkpoint for it.\"}" >> "'"$W"'/subagentstop.txt"
  printf "STOP \n" >> "'"$W"'/subagentstop.txt"
  cd "'"$P"'"
  git checkout -q -b issue/FR-1-format
  printf "from calc import format_result\n\n\ndef test_accounting_style():\n    assert format_result(4) == \"4\"\n    assert format_result(4.5) == \"4.50\"\n    assert format_result(-4) == \"(4)\"\n" > tests/test_format.py
  git add -A && git commit -qm "FR-1: behaviour test (RED)"
  printf "def format_result(value):\n    if value < 0:\n        return \"(\" + format_result(-value) + \")\"\n    if float(value).is_integer():\n        return str(int(value))\n    return \"%%.2f\" %% value\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: implementation"
  printf -- "- FR-1: unit \"integers render plain\" green; next: two-decimal rule\n- FR-1: unit \"negatives render in parentheses\" green; next: done\n" >> docs/PROGRESS.md
  git add -A && git commit -qm "record inner-loop checkpoints"
  git checkout -q develop && git merge -q --no-ff -m "land FR-1" issue/FR-1-format'
export SIM_build
SKIP_MODEL=1 bash "$HERE/tdd-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "tdd-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/TDD assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_build

# ---------- negative control: the shortcut going unblocked must FAIL ----------
W="$(mktemp -d)"; bash "$HERE/fixture-tdd.sh" "$W" >/dev/null
P="$W/tdd-proj"
SIM_build='
  printf "%s\n" "spawn sdd-issue-worker FR-1" > "$out"
  printf "STOP \n" >> "'"$W"'/subagentstop.txt"
  cd "'"$P"'"
  git checkout -q -b issue/FR-1-format
  printf "from calc import format_result\n\n\ndef test_accounting_style():\n    assert format_result(4) == \"4\"\n" > tests/test_format.py
  printf "def format_result(value):\n    return str(int(value))\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: test and implementation, no inner loop"
  git checkout -q develop && git merge -q --no-ff -m "land FR-1" issue/FR-1-format'
export SIM_build
SKIP_MODEL=1 bash "$HERE/tdd-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "tdd-chain REJECTS an unblocked shortcut (negative control)";
else report 1 "tdd-chain REJECTS an unblocked shortcut (negative control)"; sed -n '/TDD assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_build

# ---------- testfirst: turn 1 denied (nothing committed), turn 2 in the right order ----------
W="$(mktemp -d)"; bash "$HERE/fixture-testfirst.sh" "$W" >/dev/null
P="$W/testfirst-proj"
SIM_tf1='printf "%s\n" "{\"text\":\"[SDD integrity +hook] Test-first violation. Commit this issue'"'"'s FAILING behaviour test (BDD outer - prove RED) before editing implementation.\"}" > "$out"'
SIM_tf2='
  cd "'"$P"'" && git checkout -q issue/FR-1-add
  printf "from calc import apply\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  git add -A && git commit -qm "FR-1: behaviour test (RED)"
  printf "def _add(a, b):\n    return a + b\n\n\nOPERATIONS = {\"add\": _add}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: implementation"
  : > "$out"'
export SIM_tf1 SIM_tf2
SKIP_MODEL=1 bash "$HERE/testfirst-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "testfirst-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/TEST-FIRST assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_tf1 SIM_tf2

# ---------- negative control: implementation landing before any test must FAIL ----------
W="$(mktemp -d)"; bash "$HERE/fixture-testfirst.sh" "$W" >/dev/null
P="$W/testfirst-proj"
SIM_tf1='
  cd "'"$P"'"
  printf "def _add(a, b):\n    return a + b\n\n\nOPERATIONS = {\"add\": _add}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n" > src/calc/__init__.py
  git add -A && git commit -qm "FR-1: implementation first, tests later"
  : > "$out"'
SIM_tf2=':'
export SIM_tf1 SIM_tf2
SKIP_MODEL=1 bash "$HERE/testfirst-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "testfirst-chain REJECTS implementation-before-test (negative control)";
else report 1 "testfirst-chain REJECTS implementation-before-test (negative control)"; sed -n '/TEST-FIRST assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_tf1 SIM_tf2

# ---------- bdd: each posture reads its own sibling and writes its own artefact ----------
# The readlog is written by a real PreToolUse(Read) hook live; here the sims stand in for it, appending the
# sibling path a correctly-routing /bdd would open, and producing the artefact each posture yields.
W="$(mktemp -d)"; bash "$HERE/fixture-bdd.sh" "$W" >/dev/null
P="$W/bdd-proj"; RL="$W/readlog.txt"
BDD="$PLUGIN_DIR/skills/bdd"
SIM_author='
  printf "%s\n%s\n" "'"$BDD"'/SKILL.md" "'"$BDD"'/authoring.md" >> "'"$RL"'"
  cat >> "'"$P"'/docs/phases/phase-1/backlog.md" <<BL

## Issue FR-2 — subtract two numbers through the registry
### Acceptance criteria
\`\`\`gherkin
Scenario: a user subtracts two numbers through the calculator
  Given the calc package with subtract registered
  When apply is called with "subtract", 5 and 3
  Then the result is 2
\`\`\`
BL
  : > "$out"'
SIM_realize='
  printf "%s\n%s\n" "'"$BDD"'/SKILL.md" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  cd "'"$P"'" && git checkout -q issue/FR-1-add
  printf "from calc import apply\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  : > "$out"'
export SIM_author SIM_realize
SKIP_MODEL=1 bash "$HERE/bdd-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "bdd-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/BDD ROUTING assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_author SIM_realize

# ---------- negative control: the WRONG sibling on each turn must FAIL ----------
# The failure the split exists to prevent: /bdd loads the authoring rules while realizing (and vice versa),
# so the realizer is told to WRITE the scenario it must treat as immutable. The routing assertions must
# reject it.
W="$(mktemp -d)"; bash "$HERE/fixture-bdd.sh" "$W" >/dev/null
P="$W/bdd-proj"; RL="$W/readlog.txt"; BDD="$PLUGIN_DIR/skills/bdd"
SIM_author='
  printf "%s\n%s\n" "'"$BDD"'/SKILL.md" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  printf "\n## Issue FR-2 — subtract\n### Acceptance criteria\n\`\`\`gherkin\nScenario: subtract\n  Given x\n  When y\n  Then z\n\`\`\`\n" >> "'"$P"'/docs/phases/phase-1/backlog.md"
  : > "$out"'
SIM_realize='
  printf "%s\n%s\n" "'"$BDD"'/SKILL.md" "'"$BDD"'/authoring.md" >> "'"$RL"'"
  cd "'"$P"'" && git checkout -q issue/FR-1-add
  printf "from calc import apply\n\n\ndef test_add():\n    assert apply(\"add\", 2, 3) == 5\n" > tests/test_add.py
  : > "$out"'
export SIM_author SIM_realize
SKIP_MODEL=1 bash "$HERE/bdd-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "bdd-chain REJECTS reading the wrong sibling (negative control)";
else report 1 "bdd-chain REJECTS reading the wrong sibling (negative control)"; sed -n '/BDD ROUTING assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_author SIM_realize

# ---------- worker: a dispatched sdd-issue-worker invokes the right skills per dispatch variation ----------
# The skilllog is written by a real PreToolUse(Skill) hook live; here the sims stand in for it, appending the
# skill names a correct worker would invoke under each dispatch (and the `sdd-issue-worker` marker the chain
# greps from the stream to confirm the main agent dispatched at all).
W="$(mktemp -d)"; bash "$HERE/fixture-worker.sh" "$W" >/dev/null
SL="$W/skilllog.txt"; RL="$W/readlog.txt"; BDD="$PLUGIN_DIR/skills/bdd"
SIM_A='
  printf "sdd-loop:bdd\nsdd-loop:tdd\n" >> "'"$SL"'"
  printf "%s\n" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  printf "sdd-issue-worker\n" > "$out"'
SIM_B='printf "sdd-issue-worker\n" > "$out"'   # paths-only: no skill invoked — the contrast baseline
SIM_C='
  printf "sdd-loop:bdd\n" >> "'"$SL"'"
  printf "%s\n" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  printf "sdd-issue-worker\n" > "$out"'
export SIM_A SIM_B SIM_C
SKIP_MODEL=1 PLUGIN_DIR="$PLUGIN_DIR" bash "$HERE/worker-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
report "$rc" "worker-chain assertions can pass"
[ "$rc" -eq 0 ] || sed -n '/WORKER-DISPATCH assertions/,$p' "$W/out.txt"
rm -rf "$W"; unset SIM_A SIM_B SIM_C

# ---------- negative control: a SKIPPED issue whose worker invokes /tdd anyway must FAIL ----------
# The gate C proves: the `Inner loop (TDD)` flag still governs the inner loop. If a skipped-flag worker fires
# /tdd, the chain must reject it — otherwise the conditional assertion is worthless.
W="$(mktemp -d)"; bash "$HERE/fixture-worker.sh" "$W" >/dev/null
SL="$W/skilllog.txt"; RL="$W/readlog.txt"; BDD="$PLUGIN_DIR/skills/bdd"
SIM_A='
  printf "sdd-loop:bdd\nsdd-loop:tdd\n" >> "'"$SL"'"
  printf "%s\n" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  printf "sdd-issue-worker\n" > "$out"'
SIM_B='printf "sdd-issue-worker\n" > "$out"'
SIM_C='
  printf "sdd-loop:bdd\nsdd-loop:tdd\n" >> "'"$SL"'"
  printf "%s\n" "'"$BDD"'/realizing.md" >> "'"$RL"'"
  printf "sdd-issue-worker\n" > "$out"'
export SIM_A SIM_B SIM_C
SKIP_MODEL=1 PLUGIN_DIR="$PLUGIN_DIR" bash "$HERE/worker-chain.sh" "$W" >"$W/out.txt" 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then report 0 "worker-chain REJECTS a skipped-flag worker that invokes /tdd (negative control)";
else report 1 "worker-chain REJECTS a skipped-flag worker that invokes /tdd (negative control)"; sed -n '/WORKER-DISPATCH assertions/,$p' "$W/out.txt"; fi
rm -rf "$W"; unset SIM_A SIM_B SIM_C

echo
printf "== selftest: %d passed, %d failed ==\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
