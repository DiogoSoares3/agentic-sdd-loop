# Faixa B — live-model tests (isolated)

Where **Faixa A** (`../faixa-a.sh`) checks the hooks deterministically with no model, **Faixa B** runs a
**real headless `claude`** against a throwaway `calc` SDD project and asserts the loop actually behaves —
end to end, including compaction survival. It needs a **model + network**, so it is **not** part of the
deterministic suite; run it on demand.

Because a headless model writes files, Faixa B **must be isolated** so it can never touch your working
tree. Two wrappers do that; both build the fixture, run the harness, and print a PASS/FAIL summary:

| Wrapper | Isolation | When |
|---|---|---|
| `run-in-docker.sh` | container + the repo mounted **read-only** | anywhere Docker runs (cross-platform) |
| `run-macos-sandbox.sh` | macOS `sandbox-exec` (seatbelt) using the host's logged-in `claude` | macOS, quick local run (the path validated in dev) |

## Run it in Docker (recommended)

```bash
export CLAUDE_CODE_OAUTH_TOKEN=$(claude setup-token)   # or: export ANTHROPIC_API_KEY=…
bash tests/live/run-in-docker.sh
```

Builds `tests/live/Dockerfile` (claude CLI + git/jq/python/pytest), then runs inside a `--rm` container
with `plugins/sdd-loop` mounted **`:ro`** — the real repo is physically unwritable from the run, and all
scratch lives in the container's ephemeral `/work`. One short Haiku run.

## What it asserts (`compact-chain.sh`)

A single persisted session driven as **PLAN → `/compact` → CONTINUE**, forcing a *real* main-session
compaction, then checking the `SessionStart(compact)` re-prime lets the orchestrator resume correctly:

- `SessionStart` fired with **`source=compact`** (the hooklog shows `startup … resume, compact … resume`);
- after the compaction, step 3 **dispatched `sdd-issue-worker`** (resumed BUILD) rather than re-planning;
- the **baselines/profile were untouched** after planning (no freelancing rewrite);
- **`pytest` is green** on `develop` (both issues built test-first and merged).

## Pieces

- `fixture.sh [WORKDIR]` — builds the disposable `calc` project + a `settings.json` that registers the
  plugin's three hooks (plus a SessionStart-source probe). Pure setup, no model. `PLUGIN_HOOKS` env points
  the settings at the hooks dir (`/plugin/hooks` inside Docker).
- `compact-chain.sh WORKDIR` — the pure harness (runs `claude`, no isolation of its own).
- `run-in-docker.sh` / `run-macos-sandbox.sh` — the isolation wrappers above.
- `Dockerfile` — the throwaway isolation image.

> **Status:** the macOS/`sandbox-exec` path was validated in development (source=compact re-prime,
> test-first BUILD, auto-merge, pytest green). The Docker wrapper is provided for portability — smoke-test
> it once in your environment (it needs a token + a running Docker daemon) before relying on it in CI.
