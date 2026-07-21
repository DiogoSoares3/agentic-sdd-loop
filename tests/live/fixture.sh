#!/usr/bin/env bash
# Faixa B fixture — builds a disposable, VALIDATED `calc` SDD project + a settings.json that
# registers the plugin's five hooks (plus a probe that logs every SessionStart source).
# Pure setup: no model, no network. Isolation is the caller's job (Docker / sandbox-exec).
#
# Usage:  bash fixture.sh [WORKDIR]
#   WORKDIR        where to build (default: a fresh mktemp dir). Printed as WORK=… on the last line.
#   PLUGIN_HOOKS   (env) hooks dir the settings.json points at. Default: this repo's hooks.
#                  In Docker set PLUGIN_HOOKS=/plugin/hooks (the read-only-mounted plugin).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${1:-$(mktemp -d)}"
PLUGIN_HOOKS="${PLUGIN_HOOKS:-$REPO/plugins/sdd-loop/hooks}"
PROJ="$WORK/ac-proj"; HOOKLOG="$WORK/hooklog.txt"

rm -rf "$PROJ"; mkdir -p "$PROJ/docs/adrs" "$PROJ/src/calc" "$PROJ/tests" "$PROJ/.sdd"
: > "$HOOKLOG"

cat > "$PROJ/docs/PRD.md" <<'EOF'
# PRD — calc (VALIDATED)
## Requirements
- **FR-1 (Must)** — `add(a,b)` returns the integer sum. Branching-logic slice → TDD required.
- **FR-2 (Must)** — a `VERSION` constant exported as the string "1.0.0". Fixed string → TDD skipped.
## Definition of Done
- `python3 -m pytest -q` green.
EOF

cat > "$PROJ/docs/ARCHITECTURE.md" <<'EOF'
# ARCHITECTURE — calc (VALIDATED)
## Seam
The public module surface `src/calc/__init__.py`. Behaviour tests import from `calc` and assert results.
## Dependency order
FR-1 before FR-2 (both independent; FR-1 first by MoSCoW/id order).
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
`public function → pytest`.
## Issue granularity
One demoable behaviour; ~300 LOC anchor.
## Seams
The `calc` package public surface (`src/calc/__init__.py`).
## Fakes / fixtures
None — pure functions.
## Definition of Done
`python3 -m pytest -q` green.
## Phase-cutting rule
Dependency order, must-first. Phase 1 = FR-1 + FR-2.
## Test command(s)
`python3 -m pytest -q`
## Loop
- Continuation mode: `auto`
- Backlog review: `auto`
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

git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name "sdd test"
git -C "$PROJ" add -A; git -C "$PROJ" commit -qm "chore: validated baselines + profile"
git -C "$PROJ" branch develop; git -C "$PROJ" checkout -q develop

# settings.json — registers the plugin's 4 hooks headlessly + a SessionStart source probe.
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

# macOS seatbelt profile (used only by run-macos-sandbox.sh): deny writes to the real repo, allow the rest.
cat > "$WORK/sandbox.sb" <<EOF
(version 1)
(allow default)
(deny file-write* (subpath "$REPO"))
EOF

echo "PROJ=$PROJ"
echo "SETTINGS=$WORK/settings.json"
echo "HOOKLOG=$HOOKLOG"
echo "WORK=$WORK"
