#!/usr/bin/env bash
# Faixa B · flow — WORKER-DISPATCH fixture. Validates the fix that put the skill-invocation directive on the
# DISPATCH surface (the Task prompt), not only the sdd-issue-worker's system prompt: an empirically-confirmed
# gap where the worker leaned on paths-only packs and skipped `/bdd` + `/tdd`. So this scenario stands up a
# real two-level run — a Haiku MAIN agent that DISPATCHES a Haiku sdd-issue-worker via the Task tool — and a
# PreToolUse(Skill) probe records which skills the worker actually invokes.
#
# A validated `calc` project with TWO already-authored issues so the chain can vary the dispatch:
#   FR-1  Inner loop (TDD) = required  → worker should invoke BOTH /bdd and /tdd
#   FR-2  Inner loop (TDD) = skipped   → worker should invoke /bdd only (the flag gates /tdd)
# Both issue branches are pre-created (the orchestrator owns branch creation; here the chain checks the right
# one out before each context, and the subagent inherits that cwd/branch).
# Pure setup: no model, no network.
#
# Usage:  bash fixture-worker.sh [WORKDIR]     (prints PROJ=… / SETTINGS=… / …LOG lines last)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/worker-proj"; HOOKLOG="$WORK/hooklog.txt"; READLOG="$WORK/readlog.txt"; SKILLLOG="$WORK/skilllog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"; : > "$READLOG"; : > "$SKILLLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
### Functional (FR-n)
- `FR-1` — `apply("add", a, b)` returns the sum of the two operands.
- `FR-2` — `apply("subtract", a, b)` returns the difference of the two operands.
## Definition of done
- [ ] `python3 -m pytest -q` green → `FR-1`, `FR-2`
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
- Phase 1 — Arithmetic: `FR-1`, `FR-2` · DoD: pytest green
  - Excludes: anything beyond add/subtract (out of this phase)

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
# Phase 1 — Arithmetic

## Realizes (requirement IDs)
`FR-1`, `FR-2`

## Seam(s) touched
`OPERATIONS` + `apply()` in `src/calc/__init__.py`.

## DoD gate (this phase)
- [ ] `apply("add", 2, 3)` returns `5` → `FR-1`
- [ ] `apply("subtract", 5, 3)` returns `2` → `FR-2`
EOF

cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Arithmetic

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
`required`

### Blocked by
None — can start immediately

### Touches
`src/calc/__init__.py`

## Issue FR-2 — subtract two numbers through the registry
Status: todo

### What to build
Register `subtract` in `OPERATIONS` so `apply("subtract", a, b)` returns the difference.

### Acceptance criteria
```gherkin
Scenario: a user subtracts two numbers through the calculator
  Given the calc package as installed, with subtract registered in the shipped registry
  When apply is called with "subtract", 5 and 3
  Then the result is 2
```

### Inner loop (TDD)
`skipped — one arithmetic behaviour; the scenario covers it end to end`

### Blocked by
None — can start immediately

### Touches
`src/calc/__init__.py`
EOF

write_cursor "$PROJ/docs/PROGRESS.md" 1 none FR-1 none \
  "Phase 1 cut: FR-1 + FR-2 authored, nothing built."

printf 'OPERATIONS = {}\n\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"

git_init "$PROJ"
# The orchestrator owns branch creation; pre-make both issue branches so the chain can check the right one
# out per context and the dispatched worker inherits it (subagents share the cwd/branch).
git -C "$PROJ" checkout -q -b issue/FR-1-add
git -C "$PROJ" checkout -q develop
git -C "$PROJ" checkout -q -b issue/FR-2-sub
git -C "$PROJ" checkout -q develop

write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG" "" "$READLOG" "$SKILLLOG"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "READLOG=$READLOG"
echo "SKILLLOG=$SKILLLOG"
echo "WORK=$WORK"
