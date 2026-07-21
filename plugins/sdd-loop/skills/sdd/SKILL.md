---
name: sdd
description: Drive a project through an agentic Spec-Driven Development loop — SDD on the outer loop, TDD on the inner loop — from a stakeholder-validated PRD.md and an engineer-validated ARCHITECTURE.md. Use when the user wants to start/continue building a project the "SDD" way, run the build loop, pick the next slice, or mentions "sdd", "spec-driven", "the loop", or "loop engineering".
---

# SDD Loop — the conductor

You orchestrate a build **from the main session** — you are the coordinator that survives compaction, not
a builder. You do **not** invent the process per project.

**Talk to the user in plain terms — don't leak the internal jargon** (`/bdd`, `/tdd`, `needs-decision`,
`phase-opener`, "outer loop", the cursor…). Say what's happening in the product/engineering language they'd
use; the mechanics are yours to run, not theirs to learn. (Their `PRD.md`/`ARCHITECTURE.md`/ADRs stay
plugin-agnostic for the same reason.)

The **invariant spine** is below (Layer 1). The
**per-project values** (what a slice is, the seams, the *régua*, the test command) live in `.sdd/profile.md`
(Layer 2) — read it, never hardcode its contents here. The **tools** you call (`/to-prd`, `/to-issues`,
`/to-adr`, `/to-rfc`, `/bdd`, `/tdd`, `/grill-me`, `/loop`, `/resolving-merge-conflicts`) are
Layer 3. You
dispatch bounded work to three subagents — **[`sdd-phase-opener`](../../agents/phase-opener.md)** (cut one
phase), **[`sdd-issue-worker`](../../agents/issue-worker.md)** (build one issue), and
**[`sdd-merge-resolver`](../../agents/merge-resolver.md)** (land one queued branch, resolving a conflict if any; parallel mode
only) — and shipped **hooks** (`hooks/`) inject state and enforce test-first deterministically. The
**dispatcher** (the loop's bottleneck) is specified in [`dispatcher.md`](dispatcher.md) — read it before
running the loop.

If `.sdd/profile.md` does not exist, STOP and tell the user to run `/sdd-init` first. If it exists but
any slot still holds template **placeholder/example** text — a `<…>` token, an unfilled `> e.g.` line
with no real value, or an empty section — STOP and tell the user exactly which slots to complete. A
half-filled profile silently degrades every downstream decision, and since phase-cutting is fully
autonomous the profile is the single highest-leverage input. Only proceed once every slot carries a
real, project-specific value.

**One slot is exempt: `## Phase roadmap`.** It is derived from the *validated* `PRD.md`, which does not
exist yet at `/sdd-init` time, so it legitimately reads `PENDING` until the spec gate fills it (below).
`PENDING` there is not a half-filled profile — it is the state that gate exists to resolve.

## Two sources of truth

- **`PRD.md`** — the **product** truth: what/why/scope/definition-of-done. **Validated with
  stakeholders.** Structural changes here require re-validation.
- **`ARCHITECTURE.md`** — the **technical** truth: how it's built, the seams, the decisions/ADRs.
  **Validated with the engineers.**

Everything else — phase specs, backlog, tests, code — is **derived** from these two. Spec flows
down; change flows up only as a controlled amendment (see *Change control*).

## Priming (fixed read order, every session)

1. `.sdd/profile.md` — the parameters for THIS project (régua, slice, seams, DoD, commands). Verify it
   is **fully filled** (no placeholder/example text) before using it — see the hard stop above.
2. `PROGRESS.md` (path from the profile) — durable state; read the **`SDD-CURSOR` block** first
   (`Phase / Doing / Next / Stop-reason`) for the exact resume point. The **`SessionStart` hook** already
   re-injects this on resume/compact; if it's missing/stale (fresh session, reboot), read it here.
3. `PRD.md` + `ARCHITECTURE.md` — only the parts the current slice needs.

Do not re-derive what these already record. Keep dynamic state in `PROGRESS.md`, not in your head.

> **Paths are the profile's, not hardcoded.** Every `docs/…` path in this skill is a **default** — the
> profile's **Paths** section (Baselines / Durable state / Phases dir / ADRs) governs the real locations; a
> project may relocate them out of `docs/`. Read them from the profile.

## The state machine

You are always in exactly one of these states. Decide which from `PROGRESS.md`, then act.

```
        ┌─────────────┐  no PRD/ARCH validated   ┌──────────────────────┐
  START │ prime files │ ───────────────────────▶ │ SPEC (gate)          │
        └──────┬──────┘                          │ /grill-me → PRD+ARCH │
               │ baselines validated             │ (human-validated)    │
               ▼                                 └──────────────────────┘
        ┌─────────────┐  no backlog for phase   ┌──────────────────────┐
        │ SELECT next │ ◀────────────────────── │ PLAN phase           │
        │   slice     │ ──────────────────────▶ │ phase PRD + backlog  │
        └──────┬──────┘   backlog ready         └──────────────────────┘
               │ next slice known
               ▼
        ┌─────────────┐  green + DoD met  ┌──────────────────┐
        │ BUILD slice │ ────────────────▶ │ RECORD progress  │
        │  (BDD+TDD)  │                   └────────┬─────────┘
        └──┬───────▲──┘                            ▼
   uncovered│      │ resolved         ┌──────────────────┐
   decision │      │ (ADR/PRD)        │ GATE?            │
            ▼      │                  └────────┬─────────┘
        ┌──────────┴──┐        ┌───────────────┼───────────────┬──────────────┐
        │ ESCALATE    │        ▼               ▼               ▼              ▼
        │ /grill-me   │     mid-work        phase end     project end    else → loop
        │ → ADR / PRD │     overflow →      (clean) →     (all IDs+DoD   to SELECT
        └─────────────┘     harness         re-prime, NO  done) →        (next slice)
                            compacts →       handoff →     STOP
                            SessionStart     PLAN next
                            re-prime

  Unplanned stops (surface to a human): blocked · needs-decision · needs-revalidation ·
  (human-review) awaiting-review.
```

> **BUILD → RECORD** lands each slice per the profile's **merge policy**: `auto-merge` → `done` in the
> same dispatch; `human-review` → `in-review` (PR) until a human merges. SELECT loops back to BUILD
> until the phase backlog is drained, then to PLAN for the next phase — see *Loop termination* below.

### SPEC (gate) — nothing gets built before this
- **`PRD.md` missing or only a skeleton?** If the conversation already carries the product intent, run
  **`/to-prd`** (use the template the profile points to) to synthesize it. If there is nothing to
  synthesize from — the repo has no PRD — run **`/grill-me` with the stakeholder** to author the product
  truth by interview (problem, scope, DoD), then `/to-prd` writes it. Either way it must be **validated
  with stakeholders**.
- **`ARCHITECTURE.md` missing/unvalidated?** Run **`/grill-me` with the engineer** to author the
  technical truth — the seams, the test mechanism, the key decisions, the component topology + hot path —
  then write `ARCHITECTURE.md` **from `templates/arch/ARCHITECTURE.template.md`** (rendering the
  container-and-seams diagram from the elicited topology), plus any ADRs (write each via **`/to-adr`**),
  and flag it for **engineer validation**. `ARCHITECTURE.md` itself needs no writer skill — its template +
  `/grill-me` fully specify it; only the small, numbered ADRs route through the thin `/to-adr` writer.
- **Do not proceed to SELECT until the profile's "spec gate" is satisfied.** This gate is a hard stop.
- **Both baselines validated → derive the phase roadmap, once, before the first PLAN.** While the profile's
  `## Phase roadmap` slot reads `PENDING`: apply the profile's **phase-cutting rule** to the validated root
  `PRD.md` and lay out **every** epic the project is expected to run, in order — one line each: the epic, the
  requirement IDs it realizes, and the root DoD item(s) it closes. **Present that list to the user in plain
  product terms and get a quick ok** (adjust and re-present if they reorder or re-cut something), then write
  it into the slot. This is the **macro** validation — the user sees the whole shape of the project before
  anything is built, instead of discovering it one phase at a time. It is a **sketch, not a spec**: it is
  derived, never grilled, carries no sign-off ceremony, and does not become a third baseline. Keep it to one
  line per phase — the detail belongs to each phase's own PRD, cut just-in-time at PLAN.

### PLAN phase → phase PRD + epic backlog
> **Internal, derived layer — no separate human sign-off.** `docs/phases/phase-N/prd.md` and its `backlog.md` are
> the assistant's own **scrum/kanban + context-management** design, derived deterministically from the
> two validated baselines. The **only** human-grilled/validated docs are the **root `PRD.md`**
> (stakeholders) and **`ARCHITECTURE.md`** (engineer). **Derive** the phase-cut and the backlog from those
> baselines with the rules below — do **not** interview the user to *construct* them (that is `/grill-me`'s
> job, and it belongs to the baselines, not here). The user's say comes **after**: the finished cut is
> reported, and under the **Backlog review** knob (default `confirm`) approved once, before any build.

**Spawn the [`sdd-phase-opener`](../../agents/phase-opener.md) subagent to do this cut** (a bounded,
one-window job): it reads the baselines + ADRs, writes the phase PRD + backlog, and returns a compact
status. Its exit is checked by the `SubagentStop` guard (a claimed "opened" with no non-empty backlog is
sent back). The steps it follows:
- Derive the current phase from the validated **root `PRD.md`** using the profile's **phase-cutting
  rule**, in dependency order with **MoSCoW priority as the must-first tiebreak** (Must before Should
  before Could; Won't is out of scope). **Inputs to the cut:** the root `PRD.md` (remaining requirement
  IDs, their MoSCoW priority, + DoD), `ARCHITECTURE.md`/ADRs (seams + dependency order), and
  `PROGRESS.md` + the backlog (what is already `done`, so you cut the *next* undone group). Dependency
  order still wins over priority — a Must that depends on a Should cannot jump it. You do **not** need the previous phase's `prd.md` —
  its scope is already realized and recorded; re-reading it is dead context (glance only if a boundary is
  genuinely ambiguous). One phase = one epic = one demoable vertical slice group, anchored to specific
  requirement IDs + DoD item(s).
- Write the **phase PRD** `docs/phases/phase-N/prd.md` **directly from the thin phase template**
  (`templates/prd/phase-PRD.template.md`) — this is a **deterministic projection** of the validated
  baselines, **not a `/to-prd` synthesis** (there is no conversation to synthesize; the inputs are the
  phase-cut above). It **references** the root `PRD.md` by requirement ID and `ARCHITECTURE.md` by seam
  and **must not** restate Problem/Solution: fill exactly the IDs this epic realizes, their stories, the
  seam(s) touched, this phase's DoD gate, its phase dependencies, and what is deferred to later phases.
- Run **`/to-issues`** on that phase PRD → append **vertical issues** to `docs/phases/phase-N/backlog.md`, each sized to
  **one demoable tracer bullet (~300 LOC anchor)**. Each issue has explicit boundaries and a **Gherkin `Scenario:`** as
  its acceptance criteria, authored via **`/bdd`** from the phase PRD + arch. This is the epic's backlog.
- **Backlog review** (profile knob `backlog-review`, default `confirm`): `confirm` **pauses** here and
  surfaces the freshly-cut **phase scope + backlog together** — what this phase delivers, its DoD gate, and
  the slices in the order they will run — for the user to approve or edit before any build. `auto` proceeds
  straight to BUILD. This is a human gate on the *derived* layer (the two baselines are still the only
  grilled docs).
  **It gates the phase, not each issue.** One approval covers the whole phase: once the user says go, BUILD
  runs **straight through the entire backlog without pausing again**, until the phase drains or a worker
  returns `blocked` / `needs-decision` / `needs-revalidation` (which halts the loop for a human under either
  setting). Never re-ask per issue.
- **Whatever the knob, always *report* the cut.** Even under `auto`, present the phase scope + slice list in
  plain product terms after the phase-opener returns, then continue. `confirm` decides whether you *wait*
  for approval — not whether the user gets to see what was planned.
- **Diverged from the roadmap? Say so, don't stop.** The profile's `## Phase roadmap` is **indicative**: the
  phase-opener re-derives every cut from the baselines, and dependency order wins over the list. When the cut
  differs from the roadmap's line for this phase, report the difference **and the reason** ("Phase 3 takes
  `FR-7` instead of `FR-9` — ADR-0004 made `FR-9` depend on it") as part of presenting the phase. It is
  information for the approval the user is already giving, **not** a separate gate and **not** a
  `needs-decision`.

### BUILD phase → dispatch issues (serial by default)
The build loop is the **issue dispatcher** — read [`dispatcher.md`](dispatcher.md); it is the loop's
critical seam. The **main session is the orchestrator**; each issue runs in a **bounded
[`sdd-issue-worker`](../../agents/issue-worker.md)** — a fresh subagent per issue (dispatch is always via
subagents). Every issue is built on **its own branch off the integration branch
(`develop`)** — the loop never commits to a protected branch. The profile's **`Concurrency`** knob is
`serial` by default (one issue at a time, the worker lands its own branch); `parallel` is opt-in and, to
avoid workers racing a moving `develop`, **builds parallel but lands serial** — see *build parallel, land
serial* in the dispatcher. Per issue:
- **Select:** first `todo` issue whose blockers are all `done` (**merged**); mark it `doing` and branch
  `issue/<id>-<slug>` off the freshly-pulled integration branch.
- **Dispatch the `sdd-issue-worker`** with the minimal context pack as **paths**: `.sdd/profile.md` + `PROGRESS.md` +
  `docs/phases/phase-N/prd.md` + `ARCHITECTURE.md`/relevant ADRs + **the one issue's scenario + its
  `Inner loop (TDD)` flag**. Not the whole PRD, not the backlog. The worker reads any other **existing**
  spec file itself; the orchestrator is not a file server.
- **Double loop inside the dispatch:** `/bdd` realizes the scenario as the failing behaviour test
  (outer red) → then, **only when the issue's `Inner loop (TDD)` flag is `required`**
  (default), `/tdd` runs the inner loop (unit → code → unit green); when it is **`skipped`** the minimal
  implementation makes the outer test green with no inner loop. Done only when the outer behaviour test —
  **and** the inner units, if the inner loop ran — are green **and** the phase DoD items it touches pass
  (run the profile's **slice** command — the slice-gate). Refactor while green.
- **Close:** land the issue per the profile's **merge policy** — `auto-merge` merges it to `done` in the
  same dispatch (green + passing checks); `human-review` opens a PR and stops at `in-review` until a
  human merges. **The regression-gate (the full accumulated suite) runs at this merge** — the provider's CI
  checks, or the profile's full-suite command locally when the provider is `none`; a failure re-opens the
  issue to fix the **code** (never a landed test). **In `parallel` mode the worker instead returns
  `ready-to-land` (no merge)** and the orchestrator drains a **serial land queue** by dispatching a bounded
  **`sdd-merge-resolver`** per item — one at a time — which rebases onto the current tip, resolves a conflict
  via `/resolving-merge-conflicts` **only if one arises**, runs the regression-gate, and merges to `done`.
  The coordinator never runs the suite or merges itself; it only serializes and records. The loop
  continues, **non-blocking**, to the next issue whose blockers are `done`.

### RECORD progress
- Update `PROGRESS.md` and the **backlog status**: mark the slice `done` (serial auto-merge),
  `ready-to-land` (parallel auto-merge — the serial land queue flips it to `done` once merged), or
  `in-review` with its **PR URL** (human-review); note what changed, what's next, any open question. Under
  human-review a human merging the PR flips the issue to `done`; under parallel the land queue merging
  flips `ready-to-land → done` (both reconciled on next prime). **Keep it lean** — one concise
  worklog line per slice, per PROGRESS.md's fixed structure; old phases are compacted to a mini-summary
  by the phase-opener, so don't accumulate old-issue detail.
- **Update the `SDD-CURSOR` block** (the four fixed fields the `SessionStart` hook reads): `Phase`, `Doing`
  (the issue now mid-build, or `none`), `Next` (the true next grabbable `todo`, or `none — phase drained` /
  `none — project complete` / `none — awaiting-review`), and `Stop-reason` (`none` while running, else the
  reason the loop paused). This block is the deterministic resume point — keeping it current at every RECORD
  is what lets a compacted or re-entered session (and the `ask` prompt) know exactly where it is.
- **Prune landed issues:** on `done`, remove the worktree + delete the local **and** remote issue branch
  (sweep earlier leftovers too). Never prune before the regression-gate has passed and the merge is landed,
  and never prune a `blocked` / `needs-decision` / regression-failed branch — it's quarantined.
- **Tactical** spec refinements (tighten a criterion) → record here and reflect into `PRD.md`.
  **Structural** changes (scope/architecture) → stop and flow up for re-validation.

### ESCALATE — an uncovered or critical decision → `/grill-me`
A subagent has **no interactive back-channel**: the `sdd-issue-worker` (or `sdd-phase-opener`) **returns
`needs-decision` + the exact question and terminates**; the orchestrator resolves it, then **re-dispatches**
the worker with the decision now in the baselines and the pack. The orchestrator never resolves a structural
decision from its own context — that is silent drift. The loop runs autonomously until it hits a decision
the baselines don't answer. If proceeding needs a
**technical / architecture / behaviour decision** that no `PRD.md`/`ARCHITECTURE.md`/ADR covers, and
it is **structural, critical, or hard to reverse** (changes a seam, a contract, scope, or a data
definition):
- **Stop — do not invent it.** A silent decision is drift.
- Run **`/grill-me`** to put the human who owns that truth in the loop — the **engineer** for a
  technical / architecture / behaviour call, the **stakeholder** for scope — on that single decision,
  one branch at a time (propose a recommendation per question).
- **For a weighty fork that needs asynchronous team sign-off** (real competing alternatives, hard to
  reverse, more than one owner), **suggest — never force** — raising a **Request for Comments** (**`/to-rfc`**)
  instead of resolving it in this one grill: it records the options + the team's decision as
  `docs/rfcs/RFC-N` (status `to-be-validated`). The issue **stays parked** — its `needs-decision` is still
  open — until the team validates the RFC; a quick, clearly-owned call skips the RFC and just grills.
- **Flow the resolution up:** technical → a new **ADR** (write it via **`/to-adr`**) + update
  `ARCHITECTURE.md` (engineer-validated); scope/product → a **PRD amendment** (stakeholder-validated). A
  validated RFC materializes the same way (`/to-adr` with Origin `RFC-N accepted`, then flip the RFC to
  `validated (ADR-M)`). The baseline now covers it.
- Resume the issue; future agents inherit the decision — the spec grew, controlled.

**Tactical, reversible** decisions do NOT escalate: make them and record them in `PROGRESS.md`.

### GATE — hook-driven, not self-measured
The old "agent measures ~40% context" trigger was impossible (a model can't read its own window). The
context gate is now **event-driven**, and recovery lives in **one** load-bearing hook plus durable files:

- **Mid-work overflow (main session)** — the harness compacts; the **`SessionStart` hook (resume|compact)**
  re-injects `PROGRESS.md` + the re-prime checklist (via `additionalContext`), and the loop continues.
  **No hand-authored handoff is required for correctness** — RECORD-after-every-issue keeps `PROGRESS.md`
  current and the re-prime reconstructs position. (There is deliberately no `PreCompact` handoff hook: it
  cannot inject context into the model, so any reminder there is invisible — it was removed).
- **Silent subagent overflow** — a subagent gets no lifecycle hook, so it compacts silently. Guarded by
  keeping each subagent bounded (one window), the **`SubagentStop`** verify guard (blocks a hollow-green
  exit), and the required-TDD `PROGRESS.md` checkpoint (mid-issue resume). See `dispatcher.md`.
- **Clean boundary (phase drained / project complete)** — nothing is mid-flight; `PROGRESS.md` + backlog +
  git describe it fully. A fresh tick re-primes and PLANs the next phase (or stops if the project is done).

The profile's **continuation mode** governs *whether to proceed* at the gate (not who holds context —
dispatch is always via subagents). Either way the `SessionStart` hook has already injected the resume cursor
(`Phase / Doing / Next / Stop-reason`) + the recommended next action deterministically:

- **`ask` (default):** at a **boundary or on re-entry** (phase drained, a resume/compaction, or a stop) —
  **not** before each intra-phase issue — **present the cursor + recommended action and ask whether to
  continue**, then wait. Within a phase the loop dispatches issues **consecutively** without re-asking —
  **except** a worker that returns `blocked` / `needs-decision` / `needs-revalidation`, which **always halts
  the loop for a human** (below), whatever the mode. The supervised default: the loop never silently barrels
  past a *boundary*.
- **`auto`:** the orchestrator keeps dispatching bounded `sdd-issue-worker` subagents without asking; its own
  overflow is caught by the `SessionStart` re-prime + the `/loop` driver — no human, and **no flat
  supervisor** (that pattern is retired: it put the long-running coordinator inside a subagent, which
  compacts silently).

**Regardless of mode**, a `blocked` / `needs-decision` / `needs-revalidation` / `awaiting-review` stop always
surfaces to a human — `auto` self-continues only the *plannable* boundaries (resume, phase-drained).

Either way `PROGRESS.md` + backlog + git are the durable truth — a fresh context (new session, or the
harness's own compaction) reconstructs exact position from files, so continuation is always safe.

### Crash recovery (session death)
A token limit, crash, or reboot kills the **process, not the state** — `PROGRESS.md` + backlog + git
survive. But the loop can't restart itself: something external must re-invoke `/sdd`, which re-primes,
reconciles landed issues, and resumes the `doing` issue. For unattended runs, register a **scheduled
watchdog** (`/schedule` / cron running `/sdd`) — a no-op when healthy, a resurrector when dead.

## Running the loop

The iteration **contract is host-agnostic**: repeatedly run **one dispatch** (one issue) per
[`dispatcher.md`](dispatcher.md) — select → fresh agent → double loop → record → gate — until a stop
condition. Because all state lives in files (backlog status + `PROGRESS.md` = state, `.sdd/profile.md` =
config), a dispatch never relies on memory across iterations; that is what lets **any** repeat mechanism
drive it. Nothing about correctness depends on a specific command existing — only on the dispatcher being
re-entered. Trigger each iteration with whichever driver the host offers, in order of preference:

- **`/loop`** (Claude Code's built-in iteration skill, the default and recommended driver) — self-paced (no
  interval) is ideal: each tick re-primes (aided by the `SessionStart` hook) and does the next issue. Now
  that the handoff is hook-driven, `/loop` is the whole iteration engine under `auto`.
- **A `/schedule` / cron watchdog** running `/sdd` — the unattended crash-recovery driver: a no-op when
  healthy, a resurrector after a session death.
- **A plain re-invocation of `/sdd`** — a human running `/sdd` again is one full iteration. The portable
  fallback when the host has no `/loop`-equivalent.

Whatever the driver, each tick re-reads `PROGRESS.md` + the phase PRD, reconciles any merged PRs
(human-review: `in-review` → `done`), and continues from the true next `todo` issue whose blockers are
landed — that files-are-truth reconcile is what makes a dispatch safe to replay under any of them.

### Loop termination (it is finite)
One iteration = one issue, so a phase's loop is **bounded by its backlog size** (≤ N dispatches for N
issues); the project is the sum of the phases' backlogs plus one PLAN per phase. The loop is not
open-ended — each iteration either lands an issue or hits a stop. Stop when:

- **Phase drained → advance or finish.** No grabbable `todo` left and all issues `done` → PLAN the next
  phase (if requirement IDs / DoD remain) or, if every requirement ID + DoD item is `done`, the
  **project is complete** — stop.
- **Awaiting review (human-review only).** No grabbable `todo`, but issues sit `in-review` blocking
  their dependents → **pause** and surface the open PRs; a human merge re-opens grabbable work.
- **`blocked` / `needs-decision` / `needs-revalidation`.** Surface per the dispatcher's failure
  handling — the only *unplanned* stops, and the only ones that need a human PRD/ARCH touch.
- **Gate tripped.** Mid-work overflow (issues remain) → the harness compacts, the `SessionStart` hook
  re-primes from `PROGRESS.md`, the loop continues. Clean boundary (phase drained / project done) →
  re-prime **without** handoff (files suffice) → PLAN the next phase, or stop if complete.

## Change control

- **Structural** (scope, v1 surface, an architectural decision) → re-validate: `PRD.md` with
  stakeholders, `ARCHITECTURE.md` with engineers. **Then refresh the phase roadmap in the same breath:**
  re-derive the profile's `## Phase roadmap` from the amended baseline and re-present **only the phases the
  amendment moves** for a quick ok (phases already `done` are never rewritten). Do this *at the amendment*,
  while the human is already here — that is what keeps an indicative roadmap honest without ever stopping
  the loop for it later. A **tactical** refinement changes no phase's scope or order, so it leaves the
  roadmap alone.
- **Uncovered decision** (the baselines are silent on a critical call) → **ESCALATE via `/grill-me`**
  (above), then record as an ADR or PRD amendment. This is how the spec grows without drift.
- **Tactical** (refine an acceptance criterion, detail a contract) → allowed mid-build; record in
  `PROGRESS.md` and reflect into the relevant source of truth.
- **Never** let the build agent resolve a critical decision silently, and **never** edit a test/
  scenario to fit the code — both are drift; the first escalates, the second is forbidden (see
  the dispatcher's integrity rules).

## Golden rules (carry into every project)

- **Rule of three applied to the process:** automate a step (new skill, new template) only after the
  manual step has hurt 3×. The process must not become a product.
- **Simple > flexible** when in doubt. Specs stay lean.
- **Skeptical, honest** on trade-offs — a recommendation, not a survey. Name the discarded alternative.
- **One régua governs everything:** apply the profile's dominant constraint as the filter for every
  decision, code and process alike.
