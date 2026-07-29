#!/usr/bin/env bash
# Faixa B · flow — WORKER-DISPATCH chain. Three independent two-level runs: a Haiku MAIN agent (the /sdd
# orchestrator) DISPATCHES a Haiku sdd-issue-worker via the Task tool, and a PreToolUse(Skill) probe records
# which skills the worker invokes. The thing under test is the fix that moved the skill directive onto the
# DISPATCH surface — the empirically-confirmed gap where a paths-only pack left the worker skipping /bdd+/tdd.
#
# Three dispatch VARIATIONS, each a fresh main-agent session on a clean issue branch (probe logs reset):
#   A  directive + required (FR-1)  → worker must invoke BOTH /bdd and /tdd            [HARD]
#   B  paths-only    + required (FR-1) → the contrast: no directive, system prompt alone  [OBSERVATIONAL]
#   C  directive + skipped  (FR-2)  → worker invokes /bdd, NOT /tdd (the flag gates it)  [HARD]
#
# A and C are the hard gates: they prove the directive fires the skills and that the `required/skipped` flag
# still gates the inner loop. B is the counterfactual the fix exists for — asserting the ABSENCE of a skill
# live is flaky (the system prompt alone sometimes triggers it), so B surfaces its counts as the contrast
# baseline rather than failing on them. Skills are counted across the whole session; only the worker invokes
# /bdd or /tdd (the orchestrator's skill is /sdd), so the count is the worker's.
#
# PURE harness — runs `claude` directly, NO isolation. Drive it through run-bwrap.sh.
#   Usage:  bash worker-chain.sh WORKDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:?usage: worker-chain.sh WORKDIR}"
PLUGIN_DIR="${PLUGIN_DIR:-$REPO/plugins/sdd-loop}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
PROJ="$WORK/worker-proj"; SETTINGS="$WORK/settings.json"
READLOG="$WORK/readlog.txt"; SKILLLOG="$WORK/skilllog.txt"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
: > "$WORK/stderr.txt"
. "$HERE/common.sh"

PACK='the pack as paths (.sdd/profile.md, docs/PROGRESS.md, docs/phases/phase-1/prd.md, docs/ARCHITECTURE.md,
and the issue in docs/phases/phase-1/backlog.md)'

# Keep each context to ONE dispatch: after the single worker returns, STOP. Otherwise the auto-merge
# orchestrator may land and run on to the next issue, mutating develop and inflating cost.
STOP='After that ONE worker returns, STOP and report only its outcome. Do NOT merge or land anything, do NOT
dispatch a merge-resolver or any second subagent, and do NOT build any other issue.'

DISPATCH_DIRECTIVE_REQUIRED="You are the /sdd orchestrator (main session). Do NOT build anything yourself.
Dispatch EXACTLY ONE sdd-issue-worker subagent via the Task tool (subagent_type: sdd-issue-worker) to build
issue FR-1 on the current branch issue/FR-1-add. In the Task prompt, give it $PACK AND explicitly direct it
to invoke the /bdd skill to realize the scenario as the failing behaviour test, then the /tdd skill for the
inner loop since Inner loop (TDD) is required. $STOP"

DISPATCH_PATHS_ONLY="You are the /sdd orchestrator (main session). Do NOT build anything yourself. Dispatch
EXACTLY ONE sdd-issue-worker subagent via the Task tool (subagent_type: sdd-issue-worker) to build issue FR-1
on the current branch issue/FR-1-add. In the Task prompt, give it ONLY $PACK. Do not add any other
instruction about how to build. $STOP"

DISPATCH_DIRECTIVE_SKIPPED="You are the /sdd orchestrator (main session). Do NOT build anything yourself.
Dispatch EXACTLY ONE sdd-issue-worker subagent via the Task tool (subagent_type: sdd-issue-worker) to build
issue FR-2 on the current branch issue/FR-2-sub. In the Task prompt, give it $PACK AND explicitly direct it
to invoke the /bdd skill to realize the scenario as the failing behaviour test, then the /tdd skill for the
inner loop ONLY IF the issue's Inner loop (TDD) flag is required. $STOP"

# run_context <name> <issue-branch> <dispatch-prompt> <sim-var>  → resets to a clean branch + probe logs,
# runs one main-agent dispatch, snapshots the per-context skilllog/readlog.
run_context() {
  local name="$1" branch="$2" prompt="$3" sim="$4"
  # Each context is fully independent. Under `auto-merge` a prior context's orchestrator can land its issue
  # (and even run on to the next) onto develop — so a later context would find its issue ALREADY built on
  # develop and the worker, correctly, builds nothing and invokes no skill. Park off every mutable branch,
  # force develop AND the issue branch back to the fixture's pristine BASE, scrub untracked cruft, start clean.
  git -C "$PROJ" checkout -q main 2>/dev/null
  git -C "$PROJ" branch -f develop "$BASE" 2>/dev/null
  git -C "$PROJ" checkout -q -B "$branch" "$BASE" 2>/dev/null
  git -C "$PROJ" reset -q --hard "$BASE" 2>/dev/null; git -C "$PROJ" clean -fdq 2>/dev/null
  : > "$SKILLLOG"; : > "$READLOG"
  run_turn "$WORK/stream-$name.jsonl" "$sim" --session-id "$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)" "$prompt"
  cp -f "$SKILLLOG" "$WORK/skilllog.$name.txt"
  cp -f "$READLOG"  "$WORK/readlog.$name.txt"
}

BASE="$(git -C "$PROJ" rev-parse develop 2>/dev/null)"   # the fixture's pristine tip — reset target per context
run_context A issue/FR-1-add "$DISPATCH_DIRECTIVE_REQUIRED" SIM_A
run_context B issue/FR-1-add "$DISPATCH_PATHS_ONLY"          SIM_B
run_context C issue/FR-2-sub "$DISPATCH_DIRECTIVE_SKIPPED"   SIM_C

cnt() { grep -c "$1" "$2" 2>/dev/null; true; }   # occurrences of a skill in a per-context skilllog
bddA="$(cnt bdd "$WORK/skilllog.A.txt")"; tddA="$(cnt tdd "$WORK/skilllog.A.txt")"
bddB="$(cnt bdd "$WORK/skilllog.B.txt")"; tddB="$(cnt tdd "$WORK/skilllog.B.txt")"
bddC="$(cnt bdd "$WORK/skilllog.C.txt")"; tddC="$(cnt tdd "$WORK/skilllog.C.txt")"
realA="$(cnt 'skills/bdd/realizing\.md' "$WORK/readlog.A.txt")"
realC="$(cnt 'skills/bdd/realizing\.md' "$WORK/readlog.C.txt")"

echo
echo "===== WORKER-DISPATCH assertions ====="
echo "  A directive+required (FR-1): bdd=$bddA tdd=$tddA  (bdd realizing.md reads=$realA)"
echo "  B paths-only  +required (FR-1): bdd=$bddB tdd=$tddB   [contrast baseline]"
echo "  C directive+skipped  (FR-2): bdd=$bddC tdd=$tddC  (bdd realizing.md reads=$realC)"
ok=0; bad=0
chk(){ if eval "$2"; then echo "PASS $1"; ok=$((ok+1)); else echo "FAIL $1"; bad=$((bad+1)); fi; }

echo "--- the main agent actually dispatched a worker (subagent seen in each stream) ---"
chk "A dispatched an sdd-issue-worker" 'grep -q sdd-issue-worker "$WORK/stream-A.jsonl"'
chk "B dispatched an sdd-issue-worker" 'grep -q sdd-issue-worker "$WORK/stream-B.jsonl"'
chk "C dispatched an sdd-issue-worker" 'grep -q sdd-issue-worker "$WORK/stream-C.jsonl"'

echo "--- A: directive + required → the worker invoked BOTH skills ---"
chk "A invoked /bdd"                 '[ "${bddA:-0}" -gt 0 ]'
chk "A invoked /tdd"                 '[ "${tddA:-0}" -gt 0 ]'
chk "A read the BUILD-mode bdd sibling (realizing.md)" '[ "${realA:-0}" -gt 0 ]'

echo "--- C: directive + SKIPPED → /bdd yes, /tdd NOT (the flag gates the inner loop) ---"
chk "C invoked /bdd"                 '[ "${bddC:-0}" -gt 0 ]'
chk "C did NOT invoke /tdd"          '[ "${tddC:-0}" -eq 0 ]'

echo "--- B: paths-only contrast (observational — not a gate) ---"
if [ "${bddB:-0}" -lt "${bddA:-0}" ] || [ "${tddB:-0}" -lt "${tddA:-0}" ]; then
  echo "note  paths-only invoked FEWER skills than the directive (bdd $bddB<$bddA / tdd $tddB<$tddA) — the directive is load-bearing, as observed."
else
  echo "note  paths-only invoked skills too this run (bdd=$bddB tdd=$tddB) — the system prompt alone fired them here; the directive still guarantees it (Context A)."
fi

echo "===== $ok passed, $bad failed ====="
if [ "$bad" -ne 0 ]; then
  echo "--- skilllog A ---"; cat "$WORK/skilllog.A.txt" 2>/dev/null || echo "(none)"
  echo "--- skilllog C ---"; cat "$WORK/skilllog.C.txt" 2>/dev/null || echo "(none)"
  echo "--- stderr tail ---"; tail -8 "$WORK/stderr.txt" 2>/dev/null
fi
[ "$bad" -eq 0 ]
