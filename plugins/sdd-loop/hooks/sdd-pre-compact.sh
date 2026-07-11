#!/usr/bin/env bash
# SDD loop · PreCompact (main session)
# ------------------------------------
# The harness is about to compact the MAIN session. This is the DETERMINISTIC handoff
# trigger the methodology needs — it replaces the impossible "agent measures ~40% context"
# self-assessment. Remind the session to flush its volatile position to durable files NOW,
# before context is lost; after compaction the SessionStart hook re-injects PROGRESS.
#
# Note: robust recovery comes primarily from RECORD-after-every-issue keeping PROGRESS.md
# current + the SessionStart re-prime. This flush reminder is a best-effort belt-and-braces.
#
# Silent no-op outside an SDD project. PreCompact does not fire for subagents (main only).
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$ROOT/.sdd/profile.md" ] || exit 0

printf '%s\n' "[SDD loop — PreCompact handoff]"
printf '%s\n' "Context is about to compact. BEFORE it does:"
printf '%s\n' "  - Ensure docs/PROGRESS.md reflects the current 'doing' issue, the next action, and open questions."
printf '%s\n' "  - If mid-issue, record the exact resume point (branch, red/green state) under PROGRESS 'Open questions'."
printf '%s\n' "  - If a subagent is mid-flight, note which issue it holds so it can be re-dispatched."
printf '%s\n' "After compaction the SessionStart hook re-injects PROGRESS; continue the loop from there."

exit 0
