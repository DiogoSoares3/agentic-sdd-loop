#!/usr/bin/env bash
# Faixa B · flow — bubblewrap runner for the approval-gate + land-path scenarios. Each scenario gets its own
# throwaway WORK and runs fully confined: `/` READ-ONLY, only WORK writable, `~/.claude` a fresh tmpfs (the
# real one untouched), and ONLY the credentials FILE re-exposed read-only so the CLI can authenticate.
#
#   1. gates     — the roadmap gate and the backlog gate fire in order, and neither is skipped
#   2. land      — the worker never lands; a bounded lander does, in SERIAL mode; TDD flags honoured
#   3. guard     — the issue-branch guard denies an edit on develop, and allows it on the issue branch
#   4. red       — the green is REAL: the test was red first, and the DELIVERED system works with no tests
#   5. tdd       — the inner-loop checkpoint gate BLOCKS a shortcut, and the worker recovers from the block
#   6. testfirst — the test-first guard denies implementation before a committed test, and allows it after
#
# 4-6 are the bad-path half: 1-3 ask whether the loop does the right thing, 4-6 whether the machinery holds
# when it does the wrong one. They are the ones worth re-running after any change to the hooks.
#
# Prereqs: bubblewrap (`bwrap`) · a logged-in claude CLI (`~/.claude/.credentials.json`) · network · pytest.
# Cost: six Haiku runs (gates is three turns; testfirst two). Nothing persists outside the WORK mktemp dirs.
#
#   bash run-bwrap.sh                 # all six
#   SCENARIO=land bash run-bwrap.sh   # one of: gates | land | guard | red | tdd | testfirst
#   SCENARIO="red tdd testfirst" bash run-bwrap.sh   # just the bad paths
#   KEEP=1 bash run-bwrap.sh          # keep WORK dirs for post-mortem
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
command -v bwrap >/dev/null || { echo "bubblewrap (bwrap) not found; install it, or adapt run-macos-sandbox.sh." >&2; exit 2; }
CREDS="$HOME/.claude/.credentials.json"
[ -f "$CREDS" ] || { echo "No $CREDS — log in with 'claude' first so the CLI can authenticate." >&2; exit 2; }

run_scenario(){ # $1 name  -> builds a fresh WORK, runs fixture-$1 + $1-chain confined
  local name="$1" WORK; WORK="$(mktemp -d)"
  echo "WORK=$WORK"
  bash "$HERE/fixture-$name.sh" "$WORK" >/dev/null || { echo "fixture-$name.sh failed" >&2; return 2; }
  timeout "${TIMEOUT:-1800}" bwrap \
    --ro-bind / / --dev /dev --proc /proc \
    --bind "$WORK" "$WORK" \
    --tmpfs "$HOME/.claude" --ro-bind "$CREDS" "$CREDS" \
    --die-with-parent \
    bash -c '
      set -e
      export TMPDIR="'"$WORK"'/tmp"; mkdir -p "$TMPDIR"
      PLUGIN_DIR="'"$REPO"'/plugins/sdd-loop" bash "'"$HERE"'/'"$name"'-chain.sh" "'"$WORK"'"
    '
  local rc=$?
  [ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
  return $rc
}

declare -A RC
for s in ${SCENARIO:-gates land guard red tdd testfirst}; do
  echo; echo "########## SCENARIO — $s ##########"
  run_scenario "$s"; RC[$s]=$?
done

echo; echo "########## SUMMARY ##########"
fail=0
for s in "${!RC[@]}"; do
  if [ "${RC[$s]}" -eq 0 ]; then echo "$s: PASS"; else echo "$s: FAIL (rc=${RC[$s]})"; fail=1; fi
done
exit $fail
