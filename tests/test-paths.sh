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
echo "== session-start: ABSOLUTE durable-state path =="
d="$BASE/abs"; mkdir -p "$d/.sdd"; ABS="$BASE/abs-external-state.md"
printf '## Paths\n- **Durable state:** `%s`\n' "$ABS" > "$d/.sdd/profile.md"
cursor 7 none E7-1 none > "$ABS"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "reads an absolute durable-state path (Phase 7 / Next E7-1)" 'printf "%s" "$OUT" | grep -q "Phase: 7 | Doing: none | Next: E7-1"'

echo "== session-start: partial Paths (Phases dir set, Durable state absent) -> docs/ fallback =="
d="$BASE/partial"; mkdir -p "$d/.sdd" "$d/docs"
printf '## Paths\n- **Phases dir:** `epics/`\n' > "$d/.sdd/profile.md"   # no Durable state line
cursor 2 P2-1 P2-2 none > "$d/docs/PROGRESS.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "missing Durable-state line -> falls back to docs/PROGRESS.md (Phase 2 / Doing P2-1)" 'printf "%s" "$OUT" | grep -q "Phase: 2 | Doing: P2-1"'

echo "== session-start: non-bold / oddly-spaced Paths line still parsed =="
d="$BASE/fmt"; mkdir -p "$d/.sdd" "$d/place"
printf '## Paths\n-   Durable state :   `place/st.md`\n' > "$d/.sdd/profile.md"
cursor 4 none E4-9 none > "$d/place/st.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "parses a non-bold, extra-spaced Durable-state line (Next E4-9)" 'printf "%s" "$OUT" | grep -q "Phase: 4 | Doing: none | Next: E4-9"'

echo "== verify-subagent: DEFAULT phases dir (docs/phases) fallback =="
d="$BASE/vdef-ok"; mkdir -p "$d/.sdd" "$d/docs/phases/phase-1"; printf 'integrity: prose+git\n' > "$d/.sdd/profile.md"  # no Paths section
printf -- '- FR-1: x\n' > "$d/docs/phases/phase-1/backlog.md"
O="$(runVS 'phase 1 opened · 1 issue' "$d")"; ok "no Paths section, backlog under docs/phases -> ALLOW" '! isblock "$O"'
d="$BASE/vdef-none"; mkdir -p "$d/.sdd" "$d/docs/phases"; printf 'integrity: prose+git\n' > "$d/.sdd/profile.md"
O="$(runVS 'phase 1 opened · 3 issues' "$d")"; ok "no Paths section, NO backlog under docs/phases -> BLOCK" 'isblock "$O"'

echo "== END-TO-END: a fully-relocated project (spec/ tree) through BOTH hooks =="
d="$BASE/e2e"; mkdir -p "$d/.sdd" "$d/spec/phases/phase-1" "$d/spec/adrs"
cat > "$d/.sdd/profile.md" <<'PROF'
## Loop
- Continuation mode: auto
## Paths
- **Phases dir:** `spec/phases/`
- **Durable state:** `spec/state.md`
- **Baselines:** `spec/PRD.md` · `spec/ARCHITECTURE.md` · `spec/adrs/`
PROF
cursor 5 none E5-1 none > "$d/spec/state.md"
printf -- '- E5-1: relocated slice\n' > "$d/spec/phases/phase-1/backlog.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "session-start reads spec/state.md (Phase 5 / Next E5-1)" 'printf "%s" "$OUT" | grep -q "Phase: 5 | Doing: none | Next: E5-1"'
ok "session-start echoes the relocated durable-state path"    'printf "%s" "$OUT" | grep -q "spec/state.md"'
ok "session-start recommends dispatch (not re-plan)"          'printf "%s" "$OUT" | grep -qi "SELECT and dispatch the Next"'
O="$(runVS 'phase 1 opened · 1 issue' "$d")"; ok "verify reads spec/phases backlog -> ALLOW" '! isblock "$O"'
rm -rf "$d/spec/phases/phase-1"; mkdir -p "$d/spec/phases"
O="$(runVS 'phase 1 opened · 1 issue' "$d")"; ok "verify: relocated phases now empty -> BLOCK" 'isblock "$O"'

echo
echo "== THE SHIPPED TEMPLATE must work with its own hooks =="
# Every other case here hand-writes a minimal profile, so the artifact `/sdd-init` actually scaffolds was
# never fed to the hooks that read it. It did not work: the Paths section is introduced by an explanatory
# blockquote that NAMES "Durable state" and "Phases dir", and a first-match grep picked THAT line — the
# re-prime resolved its state file to `SessionStart` and reported the cursor as unknown, silently disabling
# the one load-bearing compaction-survival mechanism for every scaffolded project.
d="$BASE/shipped"; mkdir -p "$d/.sdd" "$d/docs/phases/phase-1"
cp "$REPO/plugins/sdd-loop/templates/profile.template.md" "$d/.sdd/profile.md"
cursor 6 none E6-2 none > "$d/docs/PROGRESS.md"
printf -- '- E6-2: slice\n' > "$d/docs/phases/phase-1/backlog.md"
OUT="$(CLAUDE_PROJECT_DIR="$d" bash "$SS" </dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
ok "shipped template: re-prime finds docs/PROGRESS.md (Phase 6 / Next E6-2)" \
   'printf "%s" "$OUT" | grep -q "Phase: 6 | Doing: none | Next: E6-2"'
ok "shipped template: re-prime does NOT resolve state to a prose word" \
   '! printf "%s" "$OUT" | grep -qi "from SessionStart"'
# The template documents `ask` as the default; prose elsewhere in it mentions the unattended mode. Reading
# that mention as the setting would silently run a supervised project unattended.
ok "shipped template: continuation mode reads as the documented default (ask)" \
   'printf "%s" "$OUT" | grep -qi "Continuation mode = ask"'
O="$(runVS 'phase 1 opened · 1 issue' "$d")"
ok "shipped template: verify reads the real phases dir -> ALLOW" '! isblock "$O"'
rm -rf "$d/docs/phases/phase-1"; mkdir -p "$d/docs/phases"
O="$(runVS 'phase 1 opened · 1 issue' "$d")"
ok "shipped template: verify still BLOCKS an empty phases dir" 'isblock "$O"'
# The guard hook parses the same section for the branch names.
GRD="$HDIR/sdd-guard-issue-branch.sh"
cursor 6 E6-2 E6-3 none > "$d/docs/PROGRESS.md"
git -C "$d" init -q -b develop 2>/dev/null
git -C "$d" config user.email t@t; git -C "$d" config user.name t
echo seed > "$d/README.md"; git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
RC="$(jq -nc --arg f "$d/src/x.py" '{tool_input:{file_path:$f}}' | CLAUDE_PROJECT_DIR="$d" bash "$GRD" >/dev/null 2>&1; echo $?)"
ok "shipped template: guard reads the real integration branch -> BLOCK on develop" '[ "$RC" = 2 ]'

echo
printf "== %d passed, %d failed ==\n" "$PASS" "$FAIL"
rm -rf "$BASE"; [ "$FAIL" -eq 0 ]
