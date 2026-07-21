#!/usr/bin/env bash
# Faixa B · flow — TEST-FIRST fixture. The one guard whose blocking direction the live suite never exercised.
# `guard` covers the BRANCH hook (wrong branch); this covers `sdd-enforce-test-first.sh` (right branch, no
# test committed yet), which is the hook that makes "BDD outer test before implementation" mechanical.
#
# The repo is left in the exact state the guard exists for: ON the issue branch, cursor `Doing: FR-1`,
# integrity `+hook`, and NOTHING test-shaped committed on the branch vs `develop`. `tests/` ships with a
# .gitkeep only — the guard diffs the branch against the integration branch, so a pre-existing suite would
# not satisfy it, but an empty dir keeps pytest's own behaviour unambiguous.
#
# Pure setup: no model, no network.
#
# Usage:  bash fixture-testfirst.sh [WORKDIR]   (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/testfirst-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

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
`src/calc/__init__.py` — `OPERATIONS` registry + `apply(op, a, b)` dispatch. Behaviour tests call `apply`.
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
`OPERATIONS` + `apply()` in `src/calc/__init__.py`.

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

## Depends on
None — first phase.

## DoD gate (this phase)
- [ ] `apply("add", 2, 3)` returns `5` → `FR-1`
EOF

cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Addition

## Issue FR-1 — add two numbers through the registry
Status: doing

### What to build
Register `add` in `OPERATIONS` so `apply("add", a, b)` returns the sum.

### Acceptance criteria
```gherkin
Scenario: a user adds two numbers through the calculator
  Given the calc package as installed
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

write_cursor "$PROJ/docs/PROGRESS.md" 1 FR-1 none none \
  "FR-1: branch created and checked out, nothing committed on it yet."

printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
: > "$PROJ/tests/.gitkeep"

git_init "$PROJ"
git -C "$PROJ" checkout -q -b issue/FR-1-add     # on the branch, and it carries NO commits vs develop

write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG"

# The seam AS COMMITTED at the branch base. Turn 1 must leave it untouched: no implementation may be
# committed before a test is.
git -C "$PROJ" show HEAD:src/calc/__init__.py | sha256sum | awk '{print $1}' > "$WORK/seam.sha256"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
