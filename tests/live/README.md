# Faixa B — live-model tests (isolated)

Where **Faixa A** (`../faixa-a.sh`) checks the hooks deterministically with no model, **Faixa B** runs a
**real headless `claude`** against a throwaway `calc` SDD project and asserts the loop actually behaves —
end to end, including compaction survival. It needs a **model + network**, so it is **not** part of the
deterministic suite; run it on demand.

Because a headless model writes files (and can run arbitrary commands), Faixa B **must be isolated** so it
can never touch your system. Two OS-sandbox wrappers do that; both build the fixture, run the harness confined,
and print a PASS/FAIL summary:

| Wrapper | Isolation | When |
|---|---|---|
| `run-bwrap.sh` | Linux **bubblewrap**: `/` read-only, only a throwaway `WORK` dir writable, `~/.claude` a fresh tmpfs, and just the credentials **file** re-exposed read-only for auth | Linux |
| `run-macos-sandbox.sh` | macOS `sandbox-exec` (seatbelt) using the host's logged-in `claude` | macOS |

Both use the host's already-logged-in `claude` (no token juggling) — the OS sandbox, not a container, is what
makes the run safe: the model can neither write outside `WORK` nor modify your real `~/.claude`.

## Run it (Linux)

```bash
# needs: bubblewrap (`bwrap`) + a logged-in `claude` (~/.claude/.credentials.json) + network
bash tests/live/run-bwrap.sh
```

`bwrap` binds `/` read-only, makes only the throwaway `WORK` dir writable, shadows `~/.claude` with an empty
tmpfs (so session state is ephemeral and your real login is untouched), and re-binds **only**
`~/.claude/.credentials.json` read-only so the CLI can authenticate. One short Haiku run. On macOS use
`run-macos-sandbox.sh` (seatbelt) instead.

## What it asserts (`compact-chain.sh`)

A single persisted session driven as **PLAN → `/compact` → CONTINUE**, forcing a *real* main-session
compaction, then checking the `SessionStart(compact)` re-prime lets the orchestrator resume correctly:

- `SessionStart` fired with **`source=compact`** (the hooklog shows `startup … resume, compact … resume`);
- after the compaction, step 3 **dispatched `sdd-issue-worker`** (resumed BUILD) rather than re-planning;
- the **baselines/profile were untouched** after planning (no freelancing rewrite);
- **`pytest` is green** on `develop` (both issues built test-first and merged).

## Pieces

- `fixture.sh [WORKDIR]` — builds the disposable `calc` project + a `settings.json` that registers the
  plugin's five hooks (plus a SessionStart-source probe). Pure setup, no model. `PLUGIN_HOOKS` env points
  the settings at the hooks dir.
- `compact-chain.sh WORKDIR` — the pure harness (runs `claude`, no isolation of its own).
- `run-bwrap.sh` (Linux) / `run-macos-sandbox.sh` (macOS) — the OS-sandbox wrappers above.

> **Status:** the macOS/`sandbox-exec` path was validated in development (source=compact re-prime,
> test-first BUILD, auto-merge, pytest green). The Linux `bwrap` wrapper mirrors it; smoke-test it once in
> your environment (it needs `bwrap` + a logged-in `claude`) before relying on it in CI.

## Parallel / merge-resolver scenario (`parallel/`)

Exercises the **`Concurrency: parallel`** feature live, as **two separate scenarios** (each on the repo state
it actually runs in) — one wrapper runs both:

```bash
bash tests/live/parallel/run-bwrap.sh     # Linux (bwrap); macOS: adapt run-macos-sandbox.sh
```

1. **PLAN + Touches** (`fixture-plan.sh` — a **clean** repo + `plan-chain.sh`): the `sdd-phase-opener`/
   `/to-issues` cut a phase-1 backlog whose issues carry a **`Touches`** parallel-safety hint, a Gherkin
   `Scenario:`, and an `Inner loop (TDD)` flag.
2. **RESOLVE conflict** (`fixture-parallel.sh` — a **seeded** repo + `resolve-chain.sh`): `issue/1-add` is
   landed and `issue/2-subtract` is ready-to-land but conflicts on the shared registry line. The orchestrator
   **dispatches `sdd-merge-resolver`**, which **invokes `/resolving-merge-conflicts`**; `develop` ends with
   **both** ops, the **full suite is green (2 passed)**, and the **landed `add` test is not weakened**.
3. **MULTI-item land queue** (`fixture-multi.sh` — three independent `ready-to-land` branches +
   `multi-chain.sh`): `add`/`subtract`/`multiply` all edit the shared registry line, so draining the queue
   forces a cascade of conflicts. Verifies the orchestrator dispatches **one lander per queue item, in
   backlog order, serially**; all three land green (**3 passed**), no landed test weakened. (Validated: 3
   distinct landers, order add→subtract→multiply, linear ff history.)

> These are ambitious single-session live flows; Haiku can need a rerun (its headless git handling is
> flaky). The **deterministic** proof of the same mechanics — the conflict is real, a correct resolution
> passes the full suite, a *weakening* one is caught, the landed test stays byte-identical, the warn hook
> fires — is `tests/parallel-merge.sh` (real git + pytest, **no model**: `bash tests/parallel-merge.sh`).
