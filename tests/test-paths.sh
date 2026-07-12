#!/usr/bin/env bash
# Prove the hooks read relocated paths from the profile (Durable state / Phases dir), with docs/ fallback.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HDIR="$REPO/plugins/sdd-loop/hooks"
SS="$HDIR/sdd-session-start.sh"; VS="$HDIR/sdd-verify-subagent.sh"
BASE="$(mktemp -d)"; PASS=0; FAIL=0
G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'
ok(){ if eval "$2"; then printf "${G}PASS${N} %s\n" "$1"; PASS=$((PASS+1)); else printf "${R}FAIL${N} %s\n" "$1"; FAIL=$((FAIL+1)); fi; }

cursor(){ printf '<!-- SDD-CURSOR -->\n- Phase: %s\n- Doing: %s\n- Next: %s\n- Stop-reason: %s\n<!-- /SDD-CURSOR -->\n' "$1" "$2" "$3" "$4"; }

echo "== session-start: RELOCATED durable state (state/cursor.md) =="
d="$BASE/reloc"; mkdir -p "$d/.sdd" "$d/state"
printf '## Loop\n- Continuation mode: auto\n## Paths\n- **Phases dir:** `epics/`\n- **Durable state:** `state/cursor.md`\n' > "$d/.sdd/profile.md"
cursor 3 none E3-1 none > "$d/state/cursor.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "reads relocated cursor (Phase 3 / Next E3-1)" 'printf "%s" "$OUT" | grep -q "Phase: 3 | Doing: none | Next: E3-1"'
ok "does NOT emit \"No phase planned\"" '! printf "%s" "$OUT" | grep -qi "No phase planned yet"'
ok "recommends dispatching Next (not re-plan)" 'printf "%s" "$OUT" | grep -qi "SELECT and dispatch the Next"'

echo "== session-start: DEFAULT fallback (docs/PROGRESS.md, no Paths section) =="
d="$BASE/def"; mkdir -p "$d/.sdd" "$d/docs"
printf 'integrity: prose+git +hook\n' > "$d/.sdd/profile.md"
cursor 1 P1-2 P1-3 none > "$d/docs/PROGRESS.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "fallback finds docs/PROGRESS.md (Doing P1-2 -> Resume BUILD)" 'printf "%s" "$OUT" | grep -q "Phase: 1 | Doing: P1-2" && printf "%s" "$OUT" | grep -qi "Resume BUILD of issue P1-2"'

echo
echo "== verify-subagent: RELOCATED phases dir (epics/) =="
mk_op(){ # $1 dir  $2 backlog-content(empty=>none)
  mkdir -p "$1/.sdd"; printf '## Paths\n- **Phases dir:** `epics/`\n' > "$1/.sdd/profile.md"; }
runVS(){ jq -nc --arg a sdd-loop:sdd-phase-opener --arg m "$1" '{agent_type:$a,cwd:"",last_assistant_message:$m}' \
        | CLAUDE_PROJECT_DIR="$2" bash "$VS" 2>/dev/null; }
isblock(){ printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; }

d="$BASE/op-ok"; mk_op "$d"; mkdir -p "$d/epics/phase-1"; printf -- '- E1: x\n' > "$d/epics/phase-1/backlog.md"
O="$(runVS 'phase 1 opened · 1 issue' "$d")"; ok "opened + non-empty backlog under epics/ -> ALLOW" '! isblock "$O"'

d="$BASE/op-none"; mk_op "$d"; mkdir -p "$d/epics"
O="$(runVS 'phase 1 opened · 3 issues' "$d")"; ok "opened but NO backlog under epics/ -> BLOCK" 'isblock "$O"'

d="$BASE/op-empty"; mk_op "$d"; mkdir -p "$d/epics/phase-1"; : > "$d/epics/phase-1/backlog.md"
O="$(runVS 'phase 1 opened' "$d")"; ok "opened but EMPTY backlog under epics/ -> BLOCK" 'isblock "$O"'

echo
printf "== %d passed, %d failed ==\n" "$PASS" "$FAIL"
rm -rf "$BASE"; [ "$FAIL" -eq 0 ]
