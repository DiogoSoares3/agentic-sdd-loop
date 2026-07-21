#!/usr/bin/env bash
# Faixa B · flow — LAND fixture. A VALIDATED `calc` project with phase 1 ALREADY CUT, so the run starts
# straight at BUILD and the scenario isolates the land path: `Concurrency: serial`, `auto-merge`, provider
# `none`. Two issues, one per setting of the TDD flag:
#   FR-1  apply() dispatch + unknown-op error path   -> Inner loop (TDD): required  (must leave a checkpoint)
#   FR-2  a VERSION constant                         -> Inner loop (TDD): skipped
# Pure setup: no model, no network.
#
# Usage:  bash fixture-land.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/land-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
### Functional (FR-n)
- `FR-1` — `apply(op, a, b)` dispatches through the registry; an unknown op raises `UnknownOperation`.
- `FR-2` — the package exports `VERSION`, the string "1.0.0".
## Definition of done
- [ ] `python3 -m pytest -q` green → `FR-1`, `FR-2`
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seams
`src/calc/__init__.py` — the package's public surface. Behaviour tests import from `calc` and assert results.
`OPERATIONS` is the op→fn registry; `apply(op, a, b)` dispatches through it.
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
`public surface → apply() dispatch → pytest`.

## Issue granularity
One demoable behaviour; ~300 LOC anchor.

## Seams
The `calc` public surface in `src/calc/__init__.py`.

## Fakes / fixtures
None — pure functions.

## Definition of Done
`python3 -m pytest -q` green.

## Phase-cutting rule
Dependency order, must-first.

## Phase roadmap (derived; validated once, before the first PLAN)
- Phase 1 — Dispatch surface: `FR-1`, `FR-2` · DoD: pytest green for both requirements

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
# Phase 1 — Dispatch surface

## Realizes (requirement IDs)
`FR-1`, `FR-2`

## Seam(s) touched
The `calc` public surface (`src/calc/__init__.py`).

## Depends on
None — first phase.

## DoD gate (this phase)
- [ ] `apply` dispatches known ops and raises `UnknownOperation` for anything else → `FR-1`
- [ ] `VERSION` is importable from `calc` and equals "1.0.0" → `FR-2`
EOF

cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Dispatch surface

## Issue FR-1 — dispatch a known op, reject an unknown one
Status: todo

### What to build
`apply(op, a, b)` resolves `op` through the registry and returns its result; an op that is not registered
raises `UnknownOperation`. Register `add` as the first operation so the path is demoable end to end.

### Acceptance criteria
```gherkin
Scenario: an unknown operation is rejected at the dispatch seam
  Given the calc registry with "add" registered
  When apply is called with an operation name that is not registered
  Then UnknownOperation is raised and no result is returned
```

### Inner loop (TDD)
`required`

### Blocked by
None — can start immediately

### Touches
`src/calc/__init__.py` (registry + dispatch)

## Issue FR-2 — export the package VERSION
Status: todo

### What to build
The `calc` package exports a `VERSION` constant equal to the string "1.0.0".

### Acceptance criteria
```gherkin
Scenario: the package reports its version
  Given the calc package
  When VERSION is read from it
  Then it equals "1.0.0"
```

### Inner loop (TDD)
`skipped — a fixed constant with no unit-decomposable logic; the scenario covers it end to end`

### Blocked by
- FR-1

### Touches
`src/calc/__init__.py` (module constant)
EOF

write_cursor "$PROJ/docs/PROGRESS.md" 1 none FR-1 none \
  "Phase 1 cut: FR-1 (TDD required), FR-2 (TDD skipped). Backlog approved, nothing built yet."

printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"

git_init "$PROJ"
write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
