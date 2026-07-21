#!/usr/bin/env bash
# Faixa B (parallel) fixture — a disposable, VALIDATED `calc` SDD project configured for
# `Concurrency: parallel`, PRE-SEEDED with a real merge-conflict the live model must resolve:
#   • issue/1-add is already LANDED on develop (add behaviour + its test).
#   • issue/2-subtract is a ready-to-land branch that edits the SAME registry line, so rebasing it
#     onto the moving develop conflicts — exactly the case the sdd-merge-resolver exists for.
# Pure setup: no model, no network. Isolation is the caller's job (Docker). Registers all FIVE hooks
# (incl. the landed-test warning) + a SessionStart-source probe.
#
# Usage:  bash fixture-parallel.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
#   env: PLUGIN_HOOKS  hooks dir the settings.json points at (Docker: /plugin/hooks).
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
- **FR-1 (Must)** — `apply("add", a, b)` returns the integer sum, via the operation registry.
- **FR-2 (Must)** — `apply("subtract", a, b)` returns the integer difference, via the same registry.
## Definition of Done
- `python3 -m pytest -q` green (the WHOLE suite — both operations).
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seam
`src/calc/__init__.py` exposes `OPERATIONS` (an op→fn registry) and `apply(op,a,b)` that dispatches through
it. Behaviour tests call `apply(...)`. Both operations register into the SAME `OPERATIONS` literal — so two
slices built in parallel collide on that line and must be reconciled at land time (keep both entries).
## Dependency order
FR-1 then FR-2 (independent behaviours; both edit the shared registry line).
EOF

cat > "$PROJ/.sdd/profile.md" <<'EOF'
# SDD Project Profile — calc
## Régua
Solo maintainer — simple > flexible.
## Sources of truth
| Product truth | `docs/PRD.md` | validated |
| Technical truth | `docs/ARCHITECTURE.md` | validated |
## Spec gate
PRD.md + ARCHITECTURE.md validated. OPEN — go straight to PLAN/BUILD.
## Vertical slice
`register an op → apply() dispatch → pytest`.
## Issue granularity
One demoable behaviour; ~300 LOC anchor.
## Seams
The `calc` registry: `OPERATIONS` + `apply()` in `src/calc/__init__.py`.
## Fakes / fixtures
None — pure functions.
## Definition of Done
`python3 -m pytest -q` green.
## Phase-cutting rule
Dependency order, must-first. Phase 1 = FR-1 + FR-2.
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

# Empty phase-1 backlog placeholder (step 1 of the chain fills it via to-issues, exercising the Touches hint).
printf '# Phase 1 backlog — to be cut by sdd-phase-opener / to-issues\n' > "$PROJ/docs/phases/phase-1/backlog.md"

cat > "$PROJ/docs/PROGRESS.md" <<'EOF'
# PROGRESS — calc

<!-- SDD-CURSOR  machine-read resume cursor; the loop keeps these four keys current at every RECORD -->
- Phase: 1
- Doing: issue-2 (ready-to-land, conflicts with develop)
- Next: land the ready-to-land queue (issue-2 needs conflict resolution)
- Stop-reason: none
<!-- /SDD-CURSOR -->

## Worklog
- issue-1 (add): landed on develop.
- issue-2 (subtract): built green on its branch, ready-to-land — rebase conflicts on the registry line.
EOF

# ---- git: base seam, issue/1 LANDED, issue/2 ready-to-land (conflict pending on rebase) ----
git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name "sdd test"
printf 'OPERATIONS = {}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "chore: validated baselines + registry seam"
git -C "$PROJ" branch develop; git -C "$PROJ" checkout -q develop
BASE="$(git -C "$PROJ" rev-parse HEAD)"

# issue/1-add — landed on develop
git -C "$PROJ" checkout -q -b issue/1-add "$BASE"; mkdir -p "$PROJ/tests"
printf 'OPERATIONS = {"add": lambda a, b: a + b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
printf 'from calc import apply\n\ndef test_add():\n    assert apply("add", 2, 3) == 5\n' > "$PROJ/tests/test_add.py"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "issue/1: add op"
git -C "$PROJ" checkout -q develop; git -C "$PROJ" merge -q --no-ff -m "land issue/1-add" issue/1-add

# issue/2-subtract — ready-to-land, branched from BASE (never saw issue/1) -> will conflict on rebase
git -C "$PROJ" checkout -q -b issue/2-subtract "$BASE"; mkdir -p "$PROJ/tests"
printf 'OPERATIONS = {"subtract": lambda a, b: a - b}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
printf 'from calc import apply\n\ndef test_subtract():\n    assert apply("subtract", 5, 3) == 2\n' > "$PROJ/tests/test_subtract.py"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "issue/2: subtract op (ready-to-land)"
git -C "$PROJ" checkout -q develop   # leave the run on develop; issue/2 branch awaits the land queue

# settings.json — all FIVE hooks + a SessionStart source probe.
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
