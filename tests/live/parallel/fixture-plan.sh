#!/usr/bin/env bash
# Faixa B (plan) fixture — a CLEAN, VALIDATED `calc` project configured for `Concurrency: parallel`,
# with NO pre-seeded issue branches and NO backlog yet. It exists so the PLAN step can be tested in the
# state PLAN actually runs in (a fresh repo), separately from the seeded merge-conflict fixture. The point
# is to check that the cut backlog carries the `Touches` parallel-safety hint (the /to-issues change).
# Pure setup: no model, no network. Registers all FOUR hooks + a SessionStart-source probe.
#
# Usage:  bash fixture-plan.sh [WORKDIR]     (prints WORK=… / PROJ=… / SETTINGS=… on the last lines)
#   env: PLUGIN_HOOKS  hooks dir the settings.json points at.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/plan-proj"; HOOKLOG="$WORK/hooklog.txt"
rm -rf "$PROJ"; mkdir -p "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
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
it. Behaviour tests call `apply(...)`. Both operations register into the SAME `OPERATIONS` literal.
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
PRD.md + ARCHITECTURE.md validated. OPEN — go straight to PLAN.
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

cat > "$PROJ/docs/PROGRESS.md" <<'EOF'
# PROGRESS — calc

<!-- SDD-CURSOR  machine-read resume cursor; the loop keeps these four keys current at every RECORD -->
- Phase: none
- Doing: none
- Next: none
- Stop-reason: none
<!-- /SDD-CURSOR -->

## Worklog
- (empty)
EOF

printf 'OPERATIONS = {}\n\ndef apply(op, a, b):\n    return OPERATIONS[op](a, b)\n' > "$PROJ/src/calc/__init__.py"

git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name "sdd test"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "chore: validated baselines + registry seam"
git -C "$PROJ" branch develop; git -C "$PROJ" checkout -q develop

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
          { "type": "command", "command": "bash '$PLUGIN_HOOKS/sdd-warn-landed-test-edit.sh'" }
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
