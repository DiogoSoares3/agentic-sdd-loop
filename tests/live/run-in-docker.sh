#!/usr/bin/env bash
# Faixa B in Docker (cross-platform isolation). Builds the image, then runs the fixture + compact-chain
# INSIDE a container with the real repo mounted READ-ONLY — so the headless model is fully sandboxed
# from your working tree by the container, not by any host-specific mechanism.
#
# Prereqs: Docker running · a Claude auth token in the environment. Get one on the host with
#   `claude setup-token`  → export CLAUDE_CODE_OAUTH_TOKEN=…    (or export ANTHROPIC_API_KEY=…)
# Cost: one short Haiku run. Nothing is written outside the container (`--rm`, ephemeral /work).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Set CLAUDE_CODE_OAUTH_TOKEN (run 'claude setup-token') or ANTHROPIC_API_KEY before running." >&2
  exit 2
fi

docker build -t sdd-loop-faixab "$REPO/tests/live"

docker run --rm \
  -e CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -v "$REPO/plugins/sdd-loop:/plugin:ro" \
  -v "$REPO/tests/live:/harness:ro" \
  sdd-loop-faixab \
  bash -lc '
    set -e
    PLUGIN_HOOKS=/plugin/hooks bash /harness/fixture.sh /work >/dev/null
    PLUGIN_DIR=/plugin           bash /harness/compact-chain.sh /work
  '
