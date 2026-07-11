#!/usr/bin/env bash
# SDD loop · SessionStart (resume|compact)
# ----------------------------------------
# Deterministically RE-INJECT the durable loop state so a resumed or just-compacted main
# session re-enters the loop instead of freelancing. This is the structural fix for
# "the agent loses the loop after compaction": the state is placed IN the context by code,
# not requested from the model.
#
# Silent no-op outside an SDD project (no .sdd/profile.md), so it is harmless everywhere else.
# Only fires for the MAIN session (SessionStart does not fire for subagents).
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$ROOT/.sdd/profile.md" ] || exit 0

PROGRESS="$ROOT/docs/PROGRESS.md"

printf '%s\n' "[SDD loop — re-prime gate]"
printf '%s\n' "You are continuing an SDD build loop. BEFORE anything else:"
printf '%s\n' "  1. Re-read .sdd/profile.md, docs/PROGRESS.md, the current phase PRD, and its backlog."
printf '%s\n' "  2. Restate position: which phase, which issue is 'doing', and the next grabbable 'todo'."
printf '%s\n' "  3. Do NOT write code until you have restated position and the next action per /sdd."
printf '%s\n' "  4. Consult docs/adrs/ before any architectural decision; if uncovered -> escalate (needs-decision)."
printf '%s\n' "  5. Dispatch work through the sdd-phase-opener / sdd-issue-worker subagents; do not improvise a build."

if [ -f "$PROGRESS" ]; then
  printf '%s\n' "--- docs/PROGRESS.md (durable state) ---"
  cat "$PROGRESS"
fi

exit 0
