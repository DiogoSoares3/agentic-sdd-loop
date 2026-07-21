# Faixa B · flow — live coverage of the approval gates and the land path

Where `tests/live/compact-chain.sh` proves **compaction survival** and `tests/live/parallel/` proves the
**parallel merge queue**, this suite proves the behaviours introduced by the approval-gate and land-path
work: that the loop *stops where it must*, *builds where it may*, and *never lets the worker land*.

Everything here runs a **real headless `claude` (Haiku)** against a throwaway `calc` project, confined by
**bubblewrap** (`/` read-only, only `WORK` writable, `~/.claude` a fresh tmpfs with just the credentials file
re-exposed read-only). Deterministic hook behaviour is already covered without a model in `tests/faixa-a.sh`;
what needs a model is whether the **agent** actually obeys the split.

```bash
bash tests/live/flow/run-bwrap.sh            # all three scenarios
SCENARIO=gates bash tests/live/flow/run-bwrap.sh   # just one (gates | land | guard)
```

---

## Expected execution

### Scenario 1 — `gates`: two gates, in order, and neither skipped

A clean repo with **validated** baselines, `Phase roadmap: PENDING`, and `Backlog review: confirm`.
Three turns on one persisted session, each a separate `claude --resume`, so the "user" answers between them.

| Turn | Input | The loop is expected to… | Must **not**… |
|---|---|---|---|
| 1 | `/sdd` | pass the spec gate, derive the **phase roadmap** from the root PRD (FR-1..FR-3 → two phases), present it in product terms, and **stop for approval** | write the roadmap into the profile, cut a phase, create a branch, or build |
| 2 | "roadmap approved" | write the roadmap into `.sdd/profile.md` (replacing `PENDING`), dispatch `sdd-phase-opener` to cut phase 1, present scope + DoD + slices, and **stop again** (`confirm`) | build any issue, create an `issue/*` branch |
| 3 | "backlog approved" | build the **whole** phase straight through — worker per issue, then lander per issue — without asking again | ask for approval per issue |

**Asserted after turn 1:** profile still says `PENDING` · no `docs/phases/` · no `issue/*` branch ·
the transcript names both phases.
**After turn 2:** profile carries `Phase 1 —` and no `PENDING` · `docs/phases/phase-1/backlog.md` non-empty
with a `Scenario:` and an `Inner loop (TDD)` per issue · still no `issue/*` branch, still nothing built.
**After turn 3:** `pytest` green on `develop` · every phase-1 issue `done` · **no second approval prompt**
between issues.

This is the scenario that fails if the roadmap gate is silently skipped, if `confirm` degrades into a
per-issue prompt, or if the phase-opener builds.

### Scenario 2 — `land`: the worker never lands, in **serial**

Repo with phase 1 **already cut** (so PLAN is out of the way), `Concurrency: serial`,
`Backlog review: auto`, `auto-merge`, provider `none`. Two issues:

- `FR-1` — `apply()` dispatch with an unknown-op error path → **`Inner loop (TDD): required`**
- `FR-2` — a `VERSION` constant → **`Inner loop (TDD): skipped`**

One turn: continue the loop. The expected execution, per issue:

```
orchestrator creates+checks out issue/FR-n-… off develop
  → spawns sdd-issue-worker   (BDD red → commit test alone → TDD inner if required → green)
  → worker returns ready-to-land, STILL on its branch, having merged nothing
  → orchestrator spawns sdd-merge-resolver → rebase → FULL suite → merge → done
```

**Asserted:** `sdd-issue-worker` **and** `sdd-merge-resolver` both dispatched — the lander in **serial** is
the whole point · `develop` carries both features · `pytest` green · `PROGRESS.md` carries an inner-loop
checkpoint (`unit "…" green`) for **FR-1** and none is required for FR-2 · the branch history shows a
**test-only commit before** the implementation commit.

Fails if the worker merges its own branch (the pre-change behaviour), if the lander is treated as
parallel-only, or if `required` produces no inner loop.

### Scenario 3 — `guard`: the branch guard actually bites

Repo with an `issue/FR-1-subtract` branch existing but `develop` checked out, and the cursor saying
`Doing: FR-1`. Two turns:

1. Asked to implement, **on `develop`**, using Edit/Write → the `PreToolUse` guard must **deny** it and
   `src/calc/__init__.py` on `develop` must be **byte-identical** afterwards.
2. Asked to do the same **after checking out `issue/FR-1-subtract`** → the edit must go through.

The positive control matters as much as the block: a guard that denies everything is as broken as one that
denies nothing.

> **Out of scope by design:** writes through `Bash` (`cat > f`, `sed -i`, `git apply`) bypass every
> `PreToolUse` guard — see the README's note on what the guards can and cannot see. This scenario asserts the
> guard on the tools it is registered for, not an unescapable sandbox.

---

## Pieces

| File | What |
|---|---|
| `common.sh` | writes the `settings.json` registering all five hooks + a `SessionStart` source probe |
| `fixture-gates.sh` · `gates-chain.sh` | scenario 1 — clean repo, `PENDING` roadmap, `confirm` |
| `fixture-land.sh` · `land-chain.sh` | scenario 2 — pre-cut backlog, serial, TDD flags on both settings |
| `fixture-guard.sh` · `guard-chain.sh` | scenario 3 — issue in flight, wrong branch checked out |
| `run-bwrap.sh` | bubblewrap wrapper; runs one or all scenarios, prints a summary |

Each fixture is pure setup (no model, no network) and prints `WORK=` / `PROJ=` / `SETTINGS=`. Each chain is a
pure harness — run it through the wrapper, never against a repo you care about.

> Haiku is flaky on ambitious single-session flows (its headless git handling especially). A failure here is
> worth a rerun before it is worth a bug report — but a **repeated** failure of turn 1 or turn 2 in `gates`,
> or of the lander assertion in `land`, is a real regression: those are the invariants, not the phrasing.
