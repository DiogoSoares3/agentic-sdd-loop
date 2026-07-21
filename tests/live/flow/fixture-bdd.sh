#!/usr/bin/env bash
# Faixa B · flow — BDD ROUTING fixture. Validates the split done in `skills/bdd/`: a small SKILL.md that
# routes to one of two on-demand siblings — `authoring.md` (PLAN: write the Scenario) or `realizing.md`
# (BUILD: turn it into the failing outer test) — where each mode has the OPPOSITE posture toward the
# scenario. The claim under test is the routing table's: "Load ONLY the one that matches the task at hand"
# — reading the other mode's file would put instructions in context the agent must not act on.
#
# So this scenario does not exercise the loop; it exercises the /bdd skill's own dispatch, at the skill's
# altitude, by invoking it directly in each posture and watching (via a PreToolUse(Read) probe) which
# sibling it opens. A validated `calc` project with ONE backlog issue whose Scenario is already authored, so
# turn 2 has something to realize.
# Pure setup: no model, no network.
#
# Usage:  bash fixture-bdd.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/bdd-proj"; HOOKLOG="$WORK/hooklog.txt"; READLOG="$WORK/readlog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"; : > "$READLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
### Functional (FR-n)
- `FR-1` — `apply("add", a, b)` returns the sum of the two operands.
## Definition of done
- [ ] `python3 -m pytest -q` green → `FR-1`
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seams
`src/calc/__init__.py` — the package's public surface. `OPERATIONS` is the op→fn registry; `apply(op, a, b)`
dispatches through it. Behaviour tests import from `calc` and call `apply`; the test mechanism is `pytest`.
EOF

cat > "$PROJ/.sdd/profile.md" <<'EOF'
# SDD Project Profile — calc

## Régua
Solo maintainer — simple > flexible.

## Sources of truth
| Product truth | `docs/PRD.md` | validated with stakeholders |
| Technical truth | `docs/ARCHITECTURE.md` | validated with engineers |

## Spec gate
Both baselines validated — OPEN.

## Vertical slice
`registered op → apply() dispatch → pytest`.

## Issue granularity
One demoable behaviour; ~300 LOC anchor.

## Seams
`OPERATIONS` + `apply()` in `src/calc/__init__.py`. Test mechanism: `pytest`.

## Fakes / fixtures
None — pure functions.

## Definition of Done
`python3 -m pytest -q` green.

## Phase-cutting rule
Dependency order, must-first.

## Phase roadmap (derived; validated once, before the first PLAN)
- Phase 1 — Addition: `FR-1` · DoD: pytest green

## Test command(s)
- Slice command: `python3 -m pytest -q`
- Full-suite / regression command: `python3 -m pytest -q`

## Loop
- Continuation mode: `auto`
- Backlog review: `auto`
- Concurrency: `serial`
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

cat > "$PROJ/docs/phases/phase-1/prd.md" <<'EOF'
# Phase 1 — Addition

## Realizes (requirement IDs)
`FR-1`

## Seam(s) touched
`OPERATIONS` + `apply()` in `src/calc/__init__.py`.

## DoD gate (this phase)
- [ ] `apply("add", 2, 3)` returns `5` → `FR-1`
EOF

# The scenario for FR-1 is ALREADY authored — turn 2 realizes it, turn 1 authors a DIFFERENT one (FR-2).
cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Addition

## Issue FR-1 — add two numbers through the registry
Status: todo

### What to build
Register `add` in `OPERATIONS` so `apply("add", a, b)` returns the sum.

### Acceptance criteria
```gherkin
Scenario: a user adds two numbers through the calculator
  Given the calc package as installed, with add registered in the shipped registry
  When apply is called with "add", 2 and 3
  Then the result is 5
```

### Inner loop (TDD)
`skipped — one arithmetic behaviour; the scenario covers it end to end`

### Blocked by
None — can start immediately

### Touches
`src/calc/__init__.py`
EOF

write_cursor "$PROJ/docs/PROGRESS.md" 1 none FR-1 none \
  "Phase 1 cut: FR-1 authored, nothing built. Also considering FR-2 (subtract)."

printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"

git_init "$PROJ"
# Turn 2 realizes on an issue branch (that is where the build agent works); create it here so the guard is
# satisfied and the run stays about /bdd routing, not branch mechanics.
git -C "$PROJ" checkout -q -b issue/FR-1-add
git -C "$PROJ" checkout -q develop

write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG" "" "$READLOG"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "READLOG=$READLOG"
echo "WORK=$WORK"
