#!/usr/bin/env bash
# Faixa B · flow — TDD fixture. Aimed at the BAD path of the inner-loop checkpoint: a worker that does the
# BDD outer test and jumps straight to the implementation on an issue flagged `Inner loop (TDD): required`.
#
# That flag was, until recently, decorative — nothing in the system read it, so a `required` issue that only
# ever wrote the outer test passed every guard. The SubagentStop verifier now demands a durable checkpoint
# (`<id>: unit "<name>" green`) in the durable-state file. Its BLOCKING direction has never run against a
# real model: `tests/subagentstop.sh` proves the hook blocks fabricated JSON, not that a blocked worker can
# ACT on the block. A gate nobody can get past is as broken as no gate.
#
# The issue is deliberately unit-decomposable (three named rules behind one behaviour) so `required` is
# obviously right and the recovery has something real to do.
#
# `write_settings` gets a 4th argument here: a log-only duplicate of the verifier, because a `decision:
# block` is fed back to the SUBAGENT and never appears in the main transcript.
# Pure setup: no model, no network.
#
# Usage:  bash fixture-tdd.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$HERE/common.sh"

WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/tdd-proj"; HOOKLOG="$WORK/hooklog.txt"; SUBLOG="$WORK/subagentstop.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/phases/phase-1" "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"; : > "$SUBLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
### Functional (FR-n)
- `FR-1` — the calculator formats a result for display: integers plain, non-integers to two decimals,
  and anything negative wrapped in parentheses (accounting style).
## Definition of done
- [ ] `python3 -m pytest -q` green → `FR-1`
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seams
`src/calc/__init__.py` — the public surface. `format_result(value)` is the display seam; behaviour tests
call it directly. Its three formatting rules are independently unit-testable.
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
`format_result() → pytest`.

## Issue granularity
One demoable behaviour; ~300 LOC anchor.

## Seams
`format_result()` in `src/calc/__init__.py`.

## Fakes / fixtures
None — pure functions.

## Definition of Done
`python3 -m pytest -q` green.

## Phase-cutting rule
Dependency order, must-first.

## Phase roadmap (derived; validated once, before the first PLAN)
- Phase 1 — Display formatting: `FR-1` · DoD: pytest green

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
# Phase 1 — Display formatting

## Realizes (requirement IDs)
`FR-1`

## Seam(s) touched
`format_result()` in `src/calc/__init__.py`.

## Depends on
None — first phase.

## DoD gate (this phase)
- [ ] `format_result` renders integers, decimals and negatives per the accounting rules → `FR-1`
EOF

# NB: a SECOND entry (FR-2) exists so the verifier's id resolution has to discriminate. The branch will be
# `issue/FR-1-<slug>`, and a parser that cut the id at the first dash would land on `FR`, match nothing, and
# fail open — the production bug this suite found once already.
cat > "$PROJ/docs/phases/phase-1/backlog.md" <<'EOF'
# Phase 1 backlog — Display formatting

## Issue FR-1 — format a result for display
Status: todo

### What to build
`format_result(value)` renders a number the way the UI shows it, by three rules:
1. an integer value renders with no decimal point — `4` → `"4"`
2. a non-integer renders to exactly two decimals — `4.5` → `"4.50"`
3. a negative value is wrapped in parentheses instead of signed — `-4` → `"(4)"`, `-4.5` → `"(4.50)"`

### Acceptance criteria
```gherkin
Scenario: results are rendered in accounting style
  Given the calculator has produced a result
  When the result is formatted for display
  Then integers render plain, non-integers render to two decimals, and negatives render in parentheses
```

### Inner loop (TDD)
`required` — three independent rules behind one behaviour; drive each one out with its own unit test

### Blocked by
None — can start immediately

### Touches
`src/calc/__init__.py` (`format_result`)

## Issue FR-2 — expose the formatter from the package root
Status: todo

### What to build
Re-export `format_result` so callers can `from calc import format_result`.

### Acceptance criteria
```gherkin
Scenario: the formatter is importable from the package root
  Given the calc package
  When format_result is imported from it
  Then the import succeeds
```

### Inner loop (TDD)
`skipped — a re-export with no logic`

### Blocked by
- FR-1

### Touches
`src/calc/__init__.py`
EOF

write_cursor "$PROJ/docs/PROGRESS.md" 1 none FR-1 none \
  "Phase 1 cut: FR-1 (TDD required), FR-2 (TDD skipped). Backlog approved, nothing built yet."

printf 'def format_result(value):\n    raise NotImplementedError\n' > "$PROJ/src/calc/__init__.py"

git_init "$PROJ"
write_settings "$WORK" "$PLUGIN_HOOKS" "$HOOKLOG" "$SUBLOG"

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "SUBLOG=$SUBLOG"
echo "WORK=$WORK"
