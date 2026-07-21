#!/usr/bin/env bash
# Deterministic exercise of sdd-verify-subagent.sh (SubagentStop):
#   axis 1 — hollow green  -> BLOCK
#   axis 2 — escalation    -> always ALLOW (fail-open)
# Builds REAL git repos in the exact state each case needs and feeds the hook REAL JSON.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/plugins/sdd-loop/hooks/sdd-verify-subagent.sh"
BASE="$(mktemp -d)"
PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

# run <name> <expect: BLOCK|ALLOW> <CLAUDE_PROJECT_DIR> <json>
run() {
  local name="$1" expect="$2" projdir="$3" json="$4"
  local out
  out="$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$projdir" bash "$HOOK" 2>/dev/null)"
  local got="ALLOW"
  printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' && got="BLOCK"
  if [ "$got" = "$expect" ]; then
    printf "${GREEN}PASS${NC}  %-42s want=%-5s got=%s\n" "$name" "$expect" "$got"; PASS=$((PASS+1))
  else
    printf "${RED}FAIL${NC}  %-42s want=%-5s got=%s\n" "$name" "$expect" "$got"; FAIL=$((FAIL+1))
    [ -n "$out" ] && printf '        reason: %s\n' "$(printf '%s' "$out" | jq -r '.reason' 2>/dev/null | cut -c1-80)"
  fi
}

# ---- worker repo factory: builds a repo with develop + one issue/* branch ----
# make_worker <dir> <mode: notest|empty|withtest>
make_worker() {
  local d="$1" mode="$2"
  mkdir -p "$d" && git -C "$d" init -q -b develop
  git -C "$d" config user.email t@t && git -C "$d" config user.name t
  mkdir -p "$d/.sdd"; printf 'integrity: prose+git +hook\n' > "$d/.sdd/profile.md"
  echo seed > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm seed
  git -C "$d" checkout -q -b issue/FR-1-thing
  case "$mode" in
    notest)   mkdir -p "$d/src"; echo 'def f(): return 1' > "$d/src/impl.py"
              git -C "$d" add -A; git -C "$d" commit -qm 'impl only, no test' ;;
    empty)    : ;;  # branch has no commits beyond base
    withtest) mkdir -p "$d/tests"; echo 'def test_f(): assert f()==1' > "$d/tests/test_impl.py"
              git -C "$d" add -A; git -C "$d" commit -qm 'behaviour test (RED)'
              mkdir -p "$d/src"; echo 'def f(): return 1' > "$d/src/impl.py"
              git -C "$d" add -A; git -C "$d" commit -qm 'impl' ;;
  esac
}

# ---- phase-opener repo factory ----
# make_opener <dir> <mode: nobacklog|emptybacklog|withbacklog>
make_opener() {
  local d="$1" mode="$2"
  mkdir -p "$d/.sdd"; printf 'integrity: prose+git +hook\n' > "$d/.sdd/profile.md"
  case "$mode" in
    nobacklog)    mkdir -p "$d/docs/phases" ;;
    emptybacklog) mkdir -p "$d/docs/phases/phase-1"; : > "$d/docs/phases/phase-1/backlog.md" ;;
    withbacklog)  mkdir -p "$d/docs/phases/phase-1"; printf -- '- FR-1: add\n' > "$d/docs/phases/phase-1/backlog.md" ;;
  esac
}

json_worker() { # <cwd> <msg>
  jq -nc --arg a sdd-loop:sdd-issue-worker --arg c "$1" --arg m "$2" \
    '{agent_type:$a, cwd:$c, last_assistant_message:$m}'
}
json_opener() { # <msg>
  jq -nc --arg a sdd-loop:sdd-phase-opener --arg m "$1" \
    '{agent_type:$a, cwd:"", last_assistant_message:$m}'
}

echo "== axis 1: hollow green -> BLOCK =="
d="$BASE/w-notest"; make_worker "$d" notest
run "worker green, impl but NO test"      BLOCK "$d" "$(json_worker "$d" 'Outcome: green — landed done. pytest passed.')"

d="$BASE/w-empty"; make_worker "$d" empty
run "worker green, EMPTY branch"          BLOCK "$d" "$(json_worker "$d" 'Outcome: green, all done, merged to develop.')"

d="$BASE/w-withtest"; make_worker "$d" withtest
run "worker green, test committed"        ALLOW "$d" "$(json_worker "$d" 'Outcome: green — test-first, pytest 1 passed.')"

echo
echo "== axis 2: escalation -> always ALLOW (even with no test) =="
d="$BASE/w-nd"; make_worker "$d" notest
run "worker needs-decision (no test)"     ALLOW "$d" "$(json_worker "$d" 'Outcome: needs-decision — which persistence layer? no ADR covers it.')"
d="$BASE/w-bl"; make_worker "$d" empty
run "worker blocked (empty branch)"       ALLOW "$d" "$(json_worker "$d" 'Outcome: blocked — fixture missing, issue left doing.')"
d="$BASE/w-rv"; make_worker "$d" notest
run "worker needs-revalidation (no test)" ALLOW "$d" "$(json_worker "$d" 'Outcome: needs-revalidation — the PRD scope gap surfaced.')"

echo
echo "== phase-opener: hollow open -> BLOCK; escalation -> ALLOW =="
d="$BASE/o-none"; make_opener "$d" nobacklog
run "opener 'opened' but NO backlog"      BLOCK "$d" "$(json_opener 'phase 1 opened · 3 issues · docs/phases/phase-1/')"
d="$BASE/o-empty"; make_opener "$d" emptybacklog
run "opener 'opened' but EMPTY backlog"   BLOCK "$d" "$(json_opener 'phase 1 opened · docs/phases/phase-1/')"
d="$BASE/o-ok"; make_opener "$d" withbacklog
run "opener opened, non-empty backlog"    ALLOW "$d" "$(json_opener 'phase 1 opened · 1 issue · docs/phases/phase-1/')"
d="$BASE/o-nd"; make_opener "$d" nobacklog
run "opener needs-decision (no backlog)"  ALLOW "$d" "$(json_opener 'needs-decision: split FR-3 into two phases?')"

echo
echo "== inner-TDD checkpoint: required flag must leave a PROGRESS trace =="
# make_tdd <dir> <flag-line> <progress-extra>  : a worker repo + a backlog entry + durable state
make_tdd() {
  local d="$1" flag="$2" prog="$3"
  make_worker "$d" withtest
  mkdir -p "$d/docs/phases/phase-1"
  printf '## Issue FR-1 — parse the thing\nInner loop (TDD): %s\nBlocked by: None\n' "$flag" \
    > "$d/docs/phases/phase-1/backlog.md"
  printf '# PROGRESS\n\n## Worklog\n%s\n' "$prog" > "$d/docs/PROGRESS.md"
}
d="$BASE/t-req-missing"; make_tdd "$d" 'required' '- FR-1: outer scenario green.'
run "required flag, NO unit checkpoint"   BLOCK "$d" "$(json_worker "$d" 'Outcome: green — landed done. pytest 1 passed.')"

d="$BASE/t-req-ok"; make_tdd "$d" 'required' '- FR-1: unit "tokenize" green; next: parse rows.'
run "required flag, checkpoint present"   ALLOW "$d" "$(json_worker "$d" 'Outcome: green — landed done. pytest 3 passed.')"

d="$BASE/t-skipped"; make_tdd "$d" 'skipped — declarative config, scenario covers it' '- FR-1: outer green.'
run "skipped flag, no checkpoint needed"  ALLOW "$d" "$(json_worker "$d" 'Outcome: green — landed done.')"

d="$BASE/t-nobacklog"; make_worker "$d" withtest      # no backlog at all -> cannot read the flag
run "no backlog entry -> fail-open allow" ALLOW "$d" "$(json_worker "$d" 'Outcome: green — landed done.')"

d="$BASE/t-req-esc"; make_tdd "$d" 'required' '- FR-1: nothing yet.'
run "required flag but honest blocked"    ALLOW "$d" "$(json_worker "$d" 'Outcome: blocked — fixture missing.')"

# The check must survive the worker having already merged and left the issue branch (serial auto-merge):
# with no issue/* branch to read, the issue id comes from the cursor's Doing field.
cursor_doing(){ printf '<!-- SDD-CURSOR -->\n- Phase: 1\n- Doing: %s\n- Next: none\n- Stop-reason: none\n<!-- /SDD-CURSOR -->\n' "$1"; }
d="$BASE/t-req-ondev"; make_tdd "$d" 'required' '- FR-1: outer scenario green.'
{ cursor_doing FR-1; printf '\n## Worklog\n- FR-1: outer scenario green.\n'; } > "$d/docs/PROGRESS.md"
git -C "$d" checkout -q develop
run "on develop, cursor names the issue"  BLOCK "$d" "$(json_worker "$d" 'Outcome: green — landed done.')"

d="$BASE/t-req-nocursor"; make_tdd "$d" 'required' '- FR-1: outer scenario green.'
{ cursor_doing none; printf '\n## Worklog\n- FR-1: outer scenario green.\n'; } > "$d/docs/PROGRESS.md"
git -C "$d" checkout -q develop
run "on develop, cursor Doing=none -> open" ALLOW "$d" "$(json_worker "$d" 'Outcome: green — landed done.')"

echo
printf "== %d passed, %d failed ==\n" "$PASS" "$FAIL"
rm -rf "$BASE"
[ "$FAIL" -eq 0 ]
