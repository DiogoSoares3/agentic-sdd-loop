#!/usr/bin/env bash
# Faixa B (parallel feature) on Linux — bubblewrap isolation (the seatbelt equivalent). Runs BOTH live
# scenarios of the Concurrency:parallel feature, each in its own throwaway WORK, fully confined: `/` is
# READ-ONLY, only WORK is writable, `~/.claude` is a fresh tmpfs (the real one is untouched), and ONLY the
# credentials FILE is re-exposed read-only so the CLI can authenticate. A headless model can neither damage
# your system nor write anywhere that matters.
#
#   1. PLAN + Touches   (clean fixture)   — the cut backlog carries the Touches hint + Scenario + TDD flag.
#   2. RESOLVE conflict (seeded fixture)  — the sdd-merge-resolver + /resolving-merge-conflicts land the
#                                           conflicting branch, full suite green, landed test not weakened.
#
# Prereqs: bubblewrap (`bwrap`) · a logged-in claude CLI (`~/.claude/.credentials.json`) · network.
# Cost: two short Haiku runs. Nothing persists outside the WORK mktemp dirs.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HARNESS="$REPO/tests/live"; P="$HARNESS/parallel"
command -v bwrap >/dev/null || { echo "bubblewrap (bwrap) not found; install it, or use run-macos-sandbox.sh on macOS." >&2; exit 2; }
CREDS="$HOME/.claude/.credentials.json"
[ -f "$CREDS" ] || { echo "No $CREDS — log in with 'claude' first so the CLI can authenticate." >&2; exit 2; }

# $1 fixture-script  $2 chain-script  -> builds a fresh WORK, runs the chain confined by bwrap. Echoes rc.
run_scenario(){
  local fixture="$1" chain="$2" WORK; WORK="$(mktemp -d)"
  bash "$P/$fixture" "$WORK" >/dev/null
  timeout "${TIMEOUT:-1200}" bwrap \
    --ro-bind / / --dev /dev --proc /proc \
    --bind "$WORK" "$WORK" \
    --tmpfs "$HOME/.claude" --ro-bind "$CREDS" "$CREDS" \
    --die-with-parent \
    bash -c '
      set -e
      export TMPDIR="'"$WORK"'/tmp"; mkdir -p "$TMPDIR"
      PLUGIN_DIR="'"$REPO"'/plugins/sdd-loop" bash "'"$P/$chain"'" "'"$WORK"'"
    '
  local rc=$?
  rm -rf "$WORK"
  return $rc
}

echo "########## SCENARIO 1 — PLAN + Touches ##########"
run_scenario fixture-plan.sh     plan-chain.sh;    r1=$?
echo; echo "########## SCENARIO 2 — RESOLVE conflict ##########"
run_scenario fixture-parallel.sh resolve-chain.sh; r2=$?
echo; echo "########## SCENARIO 3 — MULTI-ITEM land queue ##########"
run_scenario fixture-multi.sh    multi-chain.sh;   r3=$?

echo; echo "########## SUMMARY ##########"
[ "$r1" -eq 0 ] && echo "PLAN+Touches: PASS"      || echo "PLAN+Touches: FAIL"
[ "$r2" -eq 0 ] && echo "RESOLVE conflict: PASS"  || echo "RESOLVE conflict: FAIL"
[ "$r3" -eq 0 ] && echo "MULTI-item queue: PASS"  || echo "MULTI-item queue: FAIL"
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ]
