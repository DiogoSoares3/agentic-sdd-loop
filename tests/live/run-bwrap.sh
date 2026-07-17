#!/usr/bin/env bash
# Faixa B on Linux — bubblewrap isolation (the seatbelt equivalent; the counterpart to run-macos-sandbox.sh).
# Runs the load-bearing compact-chain confined: `/` is READ-ONLY, only a throwaway WORK dir is writable,
# `~/.claude` is a fresh tmpfs (the real one is untouched), and ONLY the credentials FILE is re-exposed
# read-only so the CLI can authenticate. A headless model can neither damage your system nor write anywhere
# that matters.
#
# Prereqs: bubblewrap (`bwrap`) · a logged-in claude CLI (`~/.claude/.credentials.json`) · network.
# Cost: one short Haiku run. Nothing persists outside WORK (a mktemp dir).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="$REPO/tests/live"
command -v bwrap >/dev/null || { echo "bubblewrap (bwrap) not found; install it, or use run-macos-sandbox.sh on macOS." >&2; exit 2; }
CREDS="$HOME/.claude/.credentials.json"
[ -f "$CREDS" ] || { echo "No $CREDS — log in with 'claude' first so the CLI can authenticate." >&2; exit 2; }

WORK="$(mktemp -d)"
bash "$HARNESS/fixture.sh" "$WORK" >/dev/null
echo "WORK=$WORK"

timeout "${TIMEOUT:-1200}" bwrap \
  --ro-bind / / --dev /dev --proc /proc \
  --bind "$WORK" "$WORK" \
  --tmpfs "$HOME/.claude" --ro-bind "$CREDS" "$CREDS" \
  --die-with-parent \
  bash -c '
    set -e
    export TMPDIR="'"$WORK"'/tmp"; mkdir -p "$TMPDIR"
    PLUGIN_DIR="'"$REPO"'/plugins/sdd-loop" bash "'"$HARNESS"'/compact-chain.sh" "'"$WORK"'"
  '
rc=$?
rm -rf "$WORK"
exit $rc
