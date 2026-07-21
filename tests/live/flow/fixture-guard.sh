#!/usr/bin/env bash
# Faixa B · flow — GUARD fixture. An issue is IN FLIGHT (cursor `Doing: FR-1`, its branch created) but the
# repo is left checked out on `develop` — the exact state the issue-branch guard exists for. The chain then
# asks for an implementation edit right there (must be DENIED) and again from the issue branch (must PASS).
# Pure setup: no model, no network.
#
# Usage:  bash fixture-guard.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/guard-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
### Functional (FR-n)
- `FR-1` — `apply("subtract", a, b)` returns the integer difference, through the operation registry.
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
`register an op → apply() dispatch → pytest`.

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
- Phase 1 — Registry ops: `FR-1` · DoD: pytest green

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

cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Registry ops

## Issue FR-1 — subtract through the registry
Status: doing

### Acceptance criteria
```gherkin
Scenario: subtract resolves through the registry
  Given the calc registry
  When apply is called with "subtract", 5 and 3
  Then the result is 2
```

### Inner loop (TDD)
`required`

### Blocked by
None — can start immediately
EOF

write_cursor "$PROJ/docs/PROGRESS.md" 1 FR-1 none none \
  "FR-1 (subtract): branch created, build in flight."

# A test already exists and is committed, so the TEST-FIRST guard is satisfied — this scenario must isolate
# the BRANCH guard, not trip over a different one.
printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"
printf 'from calc import apply\n\n\ndef test_subtract():\n    assert apply("subtract", 5, 3) == 2\n' > "$PROJ/tests/test_subtract.py"

git_init "$PROJ"
git -C "$PROJ" checkout -q -b issue/FR-1-subtract
git -C "$PROJ" checkout -q develop        # issue in flight, but the WRONG branch is checked out

write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG"

# Baseline of the seam AS COMMITTED ON develop. The invariant under test is that nothing unguarded reaches
# the integration branch — not that the working tree never moves, since a correctly-guarded agent is told to
# recover by checking out its issue branch (which legitimately changes the working tree).
git -C "$PROJ" show develop:src/calc/__init__.py | sha256sum | awk '{print $1}' > "$WORK/seam.sha256"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
