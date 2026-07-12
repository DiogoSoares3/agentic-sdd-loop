#!/usr/bin/env bash
# Faixa B on macOS (seatbelt isolation) — the path actually validated in dev. Uses the host's
# logged-in claude (Keychain). `sandbox-exec` confines the run so it cannot write to the real repo
# (see the profile fixture.sh generates); every other write lands in a throwaway mktemp dir.
#
# Prereqs: macOS · a logged-in claude CLI (`claude` already authenticated) · network.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="$REPO/tests/live"
command -v sandbox-exec >/dev/null || { echo "sandbox-exec not found (macOS only); use run-in-docker.sh." >&2; exit 2; }

WORK="$(mktemp -d)"
bash "$HARNESS/fixture.sh" "$WORK" >/dev/null
echo "WORK=$WORK"
sandbox-exec -f "$WORK/sandbox.sb" bash "$HARNESS/compact-chain.sh" "$WORK"
