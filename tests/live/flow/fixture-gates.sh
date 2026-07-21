#!/usr/bin/env bash
# Faixa B · flow — GATES fixture. A clean, VALIDATED `calc` project whose profile still has
# `Phase roadmap: PENDING` and `Backlog review: confirm`, so BOTH approval gates are live and nothing has
# been planned or built yet. Pure setup: no model, no network.
#
# Usage:  bash fixture-gates.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
#   env: PLUGIN_HOOKS  hooks dir the settings.json points at.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/gates-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

# Three requirements that cut naturally into TWO phases — so a roadmap is a real statement, not a formality.
cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)

## Problem
Callers need a small arithmetic service they can extend without touching the dispatch code.

## Scope & prioritization (MoSCoW)
| Priority | Capability | Requirements |
|---|---|---|
| **Must** | apply arithmetic operations through one entry point | FR-1, FR-2 |
| **Should** | inspect what has been applied | FR-3 |

## Requirements
### Functional (FR-n)
- `FR-1` — `apply("add", a, b)` returns the integer sum, resolved through the operation registry.
- `FR-2` — `apply("subtract", a, b)` returns the integer difference, through the same registry.
- `FR-3` — `history()` returns the list of operation names applied so far, most recent last.

## Definition of done
- [ ] `python3 -m pytest -q` green for every requirement → `FR-1`, `FR-2`, `FR-3`
- [ ] every operation resolves through the single registry seam → `FR-1`, `FR-2`
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)

## Seams
`src/calc/__init__.py` exposes `OPERATIONS` (an op→fn registry) and `apply(op, a, b)` that dispatches
through it. Behaviour tests call the public surface (`apply`, `history`) and assert results.

## Dependency order
FR-1 and FR-2 register operations and are independent of each other. FR-3 (`history`) observes what
`apply` did, so it depends on `apply` existing and lands after them.
EOF

cat > "$PROJ/.sdd/profile.md" <<'EOF'
# SDD Project Profile — calc

## Régua
Solo maintainer — simple > flexible.

## Sources of truth
| Product truth | `docs/PRD.md` | validated with stakeholders |
| Technical truth | `docs/ARCHITECTURE.md` | validated with engineers |

## Spec gate
PRD.md validated with stakeholders AND ARCHITECTURE.md validated with engineers. Both are validated — OPEN.

## Vertical slice
`register/extend the public surface → apply() dispatch → pytest`.

## Issue granularity
One demoable behaviour; ~300 LOC anchor.

## Seams
The `calc` public surface: `OPERATIONS` + `apply()` + `history()` in `src/calc/__init__.py`.

## Fakes / fixtures
None — pure functions.

## Definition of Done
`python3 -m pytest -q` green.

## Phase-cutting rule
Dependency order, must-first. One registry-behaviour group per phase.

## Phase roadmap (derived; validated once, before the first PLAN)
PENDING — derived and validated at the spec gate.

## Test command(s)
- Slice command: `python3 -m pytest -q`
- Full-suite / regression command: `python3 -m pytest -q`

## Loop
- Continuation mode: `auto`
- Backlog review: `confirm`
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

write_cursor "$PROJ/docs/PROGRESS.md" none none none none
printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"

git_init "$PROJ"
write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
