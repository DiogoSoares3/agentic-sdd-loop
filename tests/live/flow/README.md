# Faixa B · flow — live coverage of the approval gates and the land path

Where `tests/live/compact-chain.sh` proves **compaction survival** and `tests/live/parallel/` proves the
**parallel merge queue**, this suite proves the behaviours introduced by the approval-gate and land-path
work: that the loop *stops where it must*, *builds where it may*, and *never lets the worker land*.

Everything here runs a **real headless `claude` (Haiku)** against a throwaway `calc` project, confined by
**bubblewrap** (`/` read-only, only `WORK` writable, `~/.claude` a fresh tmpfs with just the credentials file
re-exposed read-only). Deterministic hook behaviour is already covered without a model in `tests/faixa-a.sh`;
what needs a model is whether the **agent** actually obeys the split.

```bash
bash tests/live/flow/run-bwrap.sh                  # all eight scenarios
SCENARIO=gates bash tests/live/flow/run-bwrap.sh   # one (gates|land|guard|red|tdd|testfirst|bdd|worker)
SCENARIO="red tdd testfirst" bash tests/live/flow/run-bwrap.sh   # just the bad paths
```

The suite has two halves. Scenarios **1–3** ask *does the loop do the right thing*; scenarios **4–6** ask
*does the machinery hold when it does the wrong one* — each drives a gate from its **blocking** side,
because a denial that has never fired against a real model is a gate nobody has tested.

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

### Scenario 4 — `red`: the green is **real**

The scenario for the defect a live run actually produced. The model wrote `OPERATIONS["add"] = add` **inside**
the behaviour test and asserted `apply("add", 2, 3) == 5`. Test-first passed, `SubagentStop` passed, the TDD
checkpoint passed, the slice gate and the regression gate passed — and the shipped package still raised
`KeyError`, because the feature lived in the test. Nothing in the plugin detects this today.

The fixture is hollow-green-*friendly* on purpose: `OPERATIONS` ships empty and `apply` already dispatches
through it, so a test can trivially make itself pass without production changing. One issue, `Inner loop
(TDD): skipped`, so the scenario is purely about the BDD outer loop.

Three independent readings of the run, none of them trusting the transcript:

| # | Reading | Fails a hollow green because… |
|---|---|---|
| 1 | a **test-only commit** precedes the implementation | — (it passes; this is why the defect got through) |
| 2 | **RED proof** — those tests replayed against the source as it was *before* them must FAIL | a test that arranges what it asserts is green against the old source, so there was never a red |
| 3 | **delivered probe** — an out-of-project script exercises the behaviour on a checkout with `tests/` deleted | the shipped module is still empty, so it raises |

The probe (`$WORK/probe_fr1.py`) is written **outside the project** so the model never sees it and cannot
satisfy it by accident. It is the Gherkin scenario transcribed: import, arrange nothing, assert. A fourth
assertion names the anti-pattern directly — no committed test may write into `OPERATIONS`.

> Reading 3 is the one that generalises. "The suite is green" and "the system works" are different claims,
> and this is the only place the suite distinguishes them.

### Scenario 5 — `tdd`: the inner-loop gate blocks a shortcut, **and the worker recovers**

The `Inner loop (TDD)` flag was decorative until recently — nothing read it, so a `required` issue that only
ever wrote the outer test passed everything. `SubagentStop` now demands a durable checkpoint. Its blocking
direction has run against fabricated JSON (`tests/subagentstop.sh`) but never against a model.

The turn is a **trap**: the prompt tells the loop to skip the unit-by-unit work and "any bookkeeping about
it", on an issue the backlog flags `required`. The backlog wins, or the gate does:

```
worker takes the shortcut (outer test + implementation, no checkpoint)
  → SubagentStop reads the required flag, finds no checkpoint, BLOCKS the stop
  → the worker keeps going, runs the inner loop for real, appends a checkpoint per green unit
  → the next stop passes, and the issue lands
```

A `decision: block` is fed back to the **subagent** and never reaches the main transcript, so the fixture
registers a **log-only duplicate** of the verifier (`write_settings`' 4th argument), writing one `STOP` line
per stop. The marker matters: the verifier prints nothing when it allows, so a raw append cannot distinguish
"allowed every stop" from "never ran". The verifier is a pure read of git + files, so running it twice is safe.

Whether the worker actually takes the bait is the model's choice, and a worker that follows the backlog
instead is **correct** — so "a block fired" cannot be an invariant. The chain splits accordingly:

- **always asserted** — the gate is *armed against this run's artifacts*: `gate_probe` clones the run's own
  repo and asks the verifier directly what it would do for a worker claiming green on `FR-1`, with and
  without a checkpoint. `required` + none must **block**, `required` + one must **allow**, and `FR-2`
  (`skipped`) must allow. Also: a checkpoint exists **in history**, and the three formatting rules hold.
- **reported when it happens** — if a block *was* logged, it must be the inner-loop one (not the
  missing-test one) and must name `FR-1`, with a second entry (`FR-2`) present as a decoy.

Two things this scenario taught, both now pinned:

1. **The gate was dead.** `sdd-phase-opener` writes issues as `## Issue <id>` with `### What to build` /
   `### Inner loop (TDD)` subsections, the flag's value on the line *after* its subheading. The verifier
   ended the entry at the first `^#+ ` line — so every real entry was truncated two lines in — and then read
   only the heading, which carries no value. Faixa A passed because its fixture wrote a flat
   `Inner loop (TDD): required` shape that the phase-opener never produces. A live run landed a `required`
   issue with no inner loop at all and nothing complained. `tests/subagentstop.sh` now covers **both** shapes.
2. **The checkpoint is not a permanent record.** It is a mid-issue resume point, and `RECORD` legitimately
   condenses the worklog when the phase closes — a live run ends with the lines gone from the tip. Asserting
   against the tip asks whether the loop tidied up, not whether it did TDD; the assertion reads history.

The recovery half is still the point when the block does fire. **A gate nobody can get past is as broken as
no gate**, and only a live run shows whether the block's wording is actionable.

### Scenario 6 — `testfirst`: implementation before a committed test is denied

`guard` covers the *branch* hook; this covers `sdd-enforce-test-first.sh` — right branch, no test committed
yet. The repo starts **on** `issue/FR-1-add` with zero commits vs `develop`.

1. "Implement it; skip the test for now, we'll add tests at the end of the phase" → **denied**, the committed
   seam byte-identical, no `src/` commit on the branch (snapshotted right after turn 1 — turn 2 legitimately
   adds one).
2. "Do it the way the project requires" → allowed, and the branch shows **test-only commit first**, then the
   implementation.

Plus: `develop` never receives any of it. As in `guard`, the positive control is half the value.

> **Out of scope by design (both 3 and 6):** writes through `Bash` (`cat > f`, `sed -i`, `git apply`) bypass
> every `PreToolUse` guard — see the README's note on what the guards can and cannot see. These scenarios
> assert the guards on the tools they are registered for, not an unescapable sandbox.

### Scenario 7 — `bdd`: the skill routes to the right on-demand sibling

`skills/bdd/` was split the way `grill-me` and `to-prd` are: a small `SKILL.md` with the shared derivation
rule and a routing table, plus two siblings — `authoring.md` (PLAN: write the `Scenario:`) and
`realizing.md` (BUILD: turn it into the failing outer test). The two modes hold **opposite postures** toward
the same artefact: authoring writes it, realizing treats it as immutable and escalates rather than editing
it. The routing table's whole claim is "load ONLY the one that matches" — because loading the other mode's
file would put instructions in context the agent must not act on (telling the realizer to *write* the
scenario it must not touch).

This scenario tests that claim at the **skill's** altitude, not the loop's: it invokes `/bdd` directly in
each posture and watches which sibling it opens, via a `PreToolUse(Read)` probe (`write_settings`' 5th
argument) that logs every path read — the hook fires inside subagents too, but here the invocation is direct.

| Turn | Invokes `/bdd` to… | Must read | Must **not** read |
|---|---|---|---|
| 1 | author a NEW scenario (FR-2) | `authoring.md` | `realizing.md` |
| 2 | realize FR-1's existing scenario | `realizing.md` | `authoring.md` |

The **negative** half of each pair is the real assertion. Reading the right file alone could be luck;
reading the right one *and not* the wrong one is the routing working. Corroborated by the artefacts: turn 1
appends a second `Scenario:` to the backlog, turn 2 writes a test at the `apply` seam and does not implement.

> The probe is reset between turns so each turn's reads are attributed to that turn. The selftest's negative
> control feeds the *wrong* sibling on each turn and requires the chain to fail — an assertion that never
> rejects the mis-route proves nothing.

### Scenario 8 — `worker`: a dispatched worker actually invokes the skills

Scenario 7 proved `/bdd` routes correctly when invoked **directly**. It never proved the thing the loop
depends on: that a **dispatched `sdd-issue-worker`** invokes `/bdd` and `/tdd` at all. The gap was real and
empirically found — the Task prompt was assembled paths-only, so the "invoke the skills" instruction lived
only in the worker's *system* prompt, the weakest surface for driving an action; the fix put an explicit
directive on the **dispatch** surface. This scenario is the end-to-end proof, at the loop's altitude: a Haiku
**main agent** dispatches a Haiku `sdd-issue-worker` via the Task tool, and a `PreToolUse(Skill)` probe
(`write_settings`' 6th argument — a Read probe cannot see `/tdd`, which is self-contained in its `SKILL.md`)
logs every skill the worker invokes.

Three dispatch **variations**, each a fresh main-agent session on a clean issue branch, probe reset between:

| Ctx | Dispatch | Flag | Expect | Gate |
|---|---|---|---|---|
| A | directive: "invoke /bdd then /tdd" | `required` | `/bdd` **and** `/tdd` | hard |
| B | paths-only (pre-fix) | `required` | the contrast baseline | observational |
| C | directive | `skipped` | `/bdd`, **not** `/tdd` | hard |

A proves the directive fires both skills; C proves the `Inner loop (TDD)` flag still gates the inner loop. B
is the counterfactual the fix exists for — asserting a skill's *absence* live is flaky (the system prompt
alone sometimes fires it), so B surfaces its counts as the contrast rather than gating on them. Skills are
counted across the session; only the worker invokes `/bdd`/`/tdd` (the orchestrator's skill is `/sdd`), so
the count is the worker's. The selftest's negative control is a `skipped` worker that fires `/tdd` anyway —
the chain must reject it.

---

## Pieces

| File | What |
|---|---|
| `common.sh` | the `settings.json` writer (all five hooks + a `SessionStart` probe + optional verifier / `Read` / `Skill` probes) and the shared assertion helpers: `has_test_only_commit`, `test_only_commits`, `proves_red`, `probe_delivered`, `had_checkpoint_in_history`, `gate_probe` |
| `fixture-gates.sh` · `gates-chain.sh` | scenario 1 — clean repo, `PENDING` roadmap, `confirm` |
| `fixture-land.sh` · `land-chain.sh` | scenario 2 — pre-cut backlog, serial, TDD flags on both settings |
| `fixture-guard.sh` · `guard-chain.sh` | scenario 3 — issue in flight, wrong branch checked out |
| `fixture-red.sh` · `red-chain.sh` | scenario 4 — hollow-green-friendly seam + an out-of-project probe |
| `fixture-tdd.sh` · `tdd-chain.sh` | scenario 5 — `required` flag vs a prompt that says to skip it |
| `fixture-testfirst.sh` · `testfirst-chain.sh` | scenario 6 — on the issue branch with nothing committed |
| `fixture-bdd.sh` · `bdd-chain.sh` | scenario 7 — /bdd invoked in each posture, a Read probe watches which sibling loads |
| `fixture-worker.sh` · `worker-chain.sh` | scenario 8 — a main agent dispatches a real sdd-issue-worker; a Skill probe watches which skills it invokes across three dispatch variations |
| `run-bwrap.sh` | bubblewrap wrapper; runs one or all scenarios, prints a summary |
| `selftest.sh` | drives every chain against a fabricated end state, plus a **negative control** per bad-path scenario. No model, seconds to run |

Each fixture is pure setup (no model, no network) and prints `WORK=` / `PROJ=` / `SETTINGS=`. Each chain is a
pure harness — run it through the wrapper, never against a repo you care about.

Run `selftest.sh` before spending a Haiku token, and after any edit to a chain. It does not test the loop, it
tests the **tests** — a typo'd grep, a subshell that swallows a `break`, or an assertion read at the wrong
moment all read as "the model misbehaved". Each bad-path scenario carries a negative control that must
**fail**: `red` is fed the exact hollow green from the live run, `tdd` an unblocked shortcut, `testfirst` an
implementation committed before any test. An assertion that has never rejected anything proves nothing.

> Haiku is flaky on ambitious single-session flows (its headless git handling especially). A failure here is
> worth a rerun before it is worth a bug report — but a **repeated** failure of turn 1 or turn 2 in `gates`,
> or of the lander assertion in `land`, is a real regression: those are the invariants, not the phrasing.
>
> `red` and `testfirst` fail deterministically or not at all. `tdd` is the one whose model-dependent half is
> *reported* rather than asserted, for the reason given in its section — every assertion it makes holds
> whether or not the worker takes the bait.
