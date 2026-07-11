#!/usr/bin/env bash
# SDD loop · SessionStart (resume|compact)
# ----------------------------------------
# The ONE load-bearing compaction-survival mechanism. It deterministically RE-INJECTS the durable
# loop state AND the derived next action so a resumed/just-compacted main session re-enters the loop
# correctly instead of freelancing. State is PLACED in context by code, not requested from the model.
#
# It reads the fixed SDD-CURSOR block in docs/PROGRESS.md (four keys the loop keeps current) — not the
# freeform backlog — so the parse is robust. From {Phase, Doing, Next, Stop-reason} + the profile's
# Continuation mode it emits: the cursor, the recommended next action, and whether to ASK the user first.
#
# PreCompact is NOT used (it cannot inject context); recovery = this hook + RECORD-after-every-issue.
# Silent no-op outside an SDD project. SessionStart fires for the MAIN session only (never subagents).
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE="$ROOT/.sdd/profile.md"
[ -f "$PROFILE" ] || exit 0

PROGRESS="$ROOT/docs/PROGRESS.md"

# --- Extract the SDD-CURSOR block + its four fields (robust: fixed markers, fixed keys). ---
cur_field() { printf '%s\n' "$CURSOR" | grep -iE "^- $1:" | head -n1 | sed -E "s/^- $1:[[:space:]]*//I"; }
CURSOR=""; PHASE=""; DOING=""; NEXT=""; STOP=""
if [ -f "$PROGRESS" ]; then
  CURSOR="$(awk '/<!-- SDD-CURSOR/{f=1;next} /<!-- \/SDD-CURSOR/{f=0} f' "$PROGRESS" 2>/dev/null || true)"
  PHASE="$(cur_field Phase)"; DOING="$(cur_field Doing)"; NEXT="$(cur_field Next)"; STOP="$(cur_field Stop-reason)"
fi
: "${PHASE:=unknown}" "${DOING:=unknown}" "${NEXT:=unknown}" "${STOP:=unknown}"

# --- Continuation mode from the profile (default ask). ---
MODE=ask
grep -qiE 'continuation( mode)?:.*auto' "$PROFILE" && MODE=auto

# --- Derive the recommended next action from the stop reason. ---
case "$(printf '%s' "$STOP" | tr '[:upper:]' '[:lower:]')" in
  none|compacted|unknown)
    low_next="$(printf '%s' "$NEXT" | tr '[:upper:]' '[:lower:]')"
    if [ "$PHASE" = none ] || [ "$PHASE" = unknown ] || [ -z "$PHASE" ]; then
      ACTION="No phase planned yet: spawn sdd-phase-opener to PLAN the first phase (once the spec gate — validated PRD.md + ARCHITECTURE.md — is green)."
    elif [ "$DOING" != none ] && [ "$DOING" != unknown ] && [ -n "$DOING" ]; then
      ACTION="Resume BUILD of issue $DOING: attach to its existing issue/<id> branch and continue from actual git/test state (do not demand a fresh RED)."
    elif [ "${low_next#none}" != "$low_next" ]; then
      ACTION="Phase appears drained (Next=$NEXT): spawn sdd-phase-opener to PLAN the next phase, or STOP if every requirement ID + DoD item is done (project complete)."
    else
      ACTION="SELECT and dispatch the Next todo ($NEXT) via a fresh sdd-issue-worker off the freshly-pulled integration branch."
    fi ;;
  clean-boundary)
    ACTION="Boundary: the phase is drained. Spawn sdd-phase-opener to PLAN the next phase — or STOP if every requirement ID + DoD item is done (project complete)." ;;
  awaiting-review)
    ACTION="Reconcile any merged PRs to done first. If issues still sit in-review blocking dependents, surface the open PRs and wait — a human merge re-opens grabbable work." ;;
  blocked|needs-decision|needs-revalidation)
    ACTION="Do NOT dispatch a build. This is a human-touch stop: read Open questions in PROGRESS, then resolve via /grill-me (needs-decision/needs-revalidation → ADR/PRD/ARCH amendment) before continuing." ;;
  *)
    ACTION="Re-derive position from PROGRESS + backlog + git, then continue per /sdd." ;;
esac

# --- ask/auto directive. ---
if [ "$MODE" = auto ]; then
  DIRECTIVE="Continuation mode = auto (unattended): proceed with the action above WITHOUT asking. Only a blocked / needs-decision / needs-revalidation stop needs a human."
else
  DIRECTIVE="Continuation mode = ask (default): PRESENT the cursor + the recommended action to the user and ASK whether to continue the SDD loop from here. Wait for confirmation before dispatching. (A blocked / needs-decision / needs-revalidation stop always needs a human regardless.)"
fi

CONTEXT="$(
  printf '%s\n' "[SDD loop — re-prime gate]"
  printf '%s\n' "You are continuing an SDD build loop. Do NOT write code before restating position and the next action per /sdd."
  printf '%s\n' ""
  printf '%s\n' "Resume cursor (from docs/PROGRESS.md):"
  printf '%s\n' "  Phase: $PHASE | Doing: $DOING | Next: $NEXT | Stop-reason: $STOP"
  printf '%s\n' "Recommended next action: $ACTION"
  printf '%s\n' "$DIRECTIVE"
  printf '%s\n' ""
  printf '%s\n' "Before acting: re-read .sdd/profile.md, docs/PROGRESS.md, the current phase PRD + backlog;"
  printf '%s\n' "reconcile any landed issues to done; consult docs/adrs/ before any architectural decision"
  printf '%s\n' "(uncovered -> escalate as needs-decision); dispatch through sdd-phase-opener / sdd-issue-worker."
  if [ -f "$PROGRESS" ]; then
    printf '%s\n' "--- docs/PROGRESS.md (full durable state) ---"
    cat "$PROGRESS"
  fi
)"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  printf '%s\n' "$CONTEXT"
fi

exit 0
