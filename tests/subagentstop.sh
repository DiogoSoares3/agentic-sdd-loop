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
printf "== %d passed, %d failed ==\n" "$PASS" "$FAIL"
rm -rf "$BASE"
[ "$FAIL" -eq 0 ]
