#!/usr/bin/env bash
# Faixa B (multi) fixture — a `calc` project configured for `Concurrency: parallel`, PRE-SEEDED with a
# THREE-item land queue: issue/1-add, issue/2-subtract, issue/3-multiply are all `ready-to-land`,
# independent (no blockers between them), and each edits the SAME OPERATIONS registry line — so as the
# orchestrator drains the queue serially, every land after the first hits a rebase conflict. develop stays
# at base (nothing landed yet). Exercises the lander over a real multi-item queue. Registers all five hooks.
#
# Usage:  bash fixture-multi.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/pc-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
- **FR-1 (Must)** — `apply("add", a, b)` = integer sum, via the operation registry.
- **FR-2 (Must)** — `apply("subtract", a, b)` = integer difference, via the same registry.
- **FR-3 (Must)** — `apply("multiply", a, b)` = integer product, via the same registry.
## Definition of Done
- `python3 -m pytest -q` green (WHOLE suite — all three operations).
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seam
`src/calc/__init__.py` exposes `OPERATIONS` (op→fn registry) + `apply(op,a,b)` dispatch. All operations
register into the SAME `OPERATIONS` literal — three slices built in parallel collide on that line and are
reconciled at land time (keep all entries).
EOF

cat > "$PROJ/.sdd/profile.md" <<'EOF'
# SDD Project Profile — calc
## Régua
Solo maintainer — simple > flexible.
## Sources of truth
| Product truth | `docs/PRD.md` | validated |
| Technical truth | `docs/ARCHITECTURE.md` | validated |
## Spec gate
Validated. OPEN.
## Vertical slice
`register an op → apply() dispatch → pytest`.
## Issue granularity
One demoable behaviour.
## Seams
`OPERATIONS` + `apply()` in `src/calc/__init__.py`.
## Fakes / fixtures
None — pure functions.
## Definition of Done
`python3 -m pytest -q` green.
## Phase-cutting rule
Dependency order, must-first.
## Test command(s)
- Slice command: `python3 -m pytest -q`
- Full-suite / regression command: `python3 -m pytest -q`
## Loop
- Continuation mode: `auto`
- Backlog review: `auto`
- Concurrency: `parallel`
- Integrity enforcement: `prose+git +hook`
## Git strategy
- Protected branch: `main`.
- Integration branch: `develop`.
- Issue branch naming: `issue/<id>-<slug>`.
- PR provider: `none`.
- Merge policy: `auto-merge`.
## Paths
- Phases dir: `docs/phases/`.
- Baselines: `docs/PRD.md` · `docs/ARCHITECTURE.md` · `docs/adrs/`.
- Durable state: `docs/PROGRESS.md`.
EOF

cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — three independent ops (all ready-to-land)

## Issue issue-1-add
Status: ready-to-land
Blocked by: None — can start immediately
Touches: src/calc/__init__.py (OPERATIONS registry)

## Issue issue-2-subtract
Status: ready-to-land
Blocked by: None — can start immediately
Touches: src/calc/__init__.py (OPERATIONS registry)

## Issue issue-3-multiply
Status: ready-to-land
Blocked by: None — can start immediately
Touches: src/calc/__init__.py (OPERATIONS registry)
EOF

cat > "$PROJ/docs/PROGRESS.md" <<'EOF'
# PROGRESS — calc

<!-- SDD-CURSOR -->
- Phase: 1
- Doing: none
- Next: drain the land queue (3 issues ready-to-land, all conflicting)
- Stop-reason: none
<!-- /SDD-CURSOR -->

## Worklog
- issue-1-add, issue-2-subtract, issue-3-multiply: built green in parallel, all ready-to-land.
- Each edits the shared OPERATIONS line; the land queue must rebase+resolve serially.
EOF

# ---- git: base seam; three independent ready-to-land branches; develop at base ----
git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name "sdd test"
printf 'OPERATIONS = {}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "chore: validated baselines + registry seam"
git -C "$PROJ" branch develop; git -C "$PROJ" checkout -q develop
BASE="$(git -C "$PROJ" rev-parse HEAD)"

mkbr(){ # $1 branch  $2 fragment  $3 testfile  $4 testbody
  git -C "$PROJ" checkout -q -b "$1" "$BASE"; mkdir -p "$PROJ/tests"
  printf 'OPERATIONS = {%s}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' "$2" > "$PROJ/src/calc/__init__.py"
  printf '%s' "$4" > "$PROJ/tests/$3"
  git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "$1"
}
mkbr issue/1-add      '"add": lambda a, b: a + b'      test_add.py      'from calc import apply
def test_add():
    assert apply("add", 2, 3) == 5
'
mkbr issue/2-subtract '"subtract": lambda a, b: a - b' test_subtract.py 'from calc import apply
def test_subtract():
    assert apply("subtract", 5, 3) == 2
'
mkbr issue/3-multiply '"multiply": lambda a, b: a * b' test_multiply.py 'from calc import apply
def test_multiply():
    assert apply("multiply", 4, 3) == 12
'
git -C "$PROJ" checkout -q develop   # queue awaits draining; develop is base

cat > "$WORK/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-session-start.sh'" },
          { "type": "command", "command": "jq -r '\"SESSIONSTART source=\" + (.source // \"?\")' >> '$HOOKLOG'" }
        ] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-enforce-test-first.sh'" },
          { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-warn-landed-test-edit.sh'" },
          { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-guard-issue-branch.sh'" }
        ] }
    ],
    "SubagentStop": [
      { "matcher": "*",
        "hooks": [ { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-verify-subagent.sh'" } ] }
    ]
  }
}
EOF

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
