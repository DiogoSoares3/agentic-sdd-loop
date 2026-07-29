# SDD Project Profile — <PROJECT NAME>

> Layer 2. The **only** file that changes between projects. The plugin's `/sdd` skill reads this to
> parametrize the invariant methodology. Keep it lean; fill every slot.

> **Communication reminder (inherited by every agent/skill that reads this profile).** When talking to
> stakeholders or engineers, use standard domain and engineering language — do **not** leak the plugin's
> internal jargon (`/bdd`, `/tdd`, `sdd-phase-opener` / `sdd-issue-worker`, `needs-decision`, the
> `SDD-CURSOR`, "outer/inner loop", "dispatcher"). Translate the mechanics into the terms the reader
> already uses. This covers both the chat and every human-readable artifact: `PRD.md`,
> `ARCHITECTURE.md`, ADRs, and the readable content of the phase PRDs and backlog (issue descriptions and
> Gherkin scenarios in domain language — only planning fields like the `Inner loop (TDD)` flag and issue
> ids stay). **This profile is the sole exception:** as internal config it keeps the knob names.

## Régua (dominant constraint)
The single filter for every decision, code and process alike. One paragraph.
> e.g. "Solo maintainer — simple > flexible." / "Graded, reproducible deliverable — every number
> reconciles to source and a grader can re-run it."

## Sources of truth
| Artifact | Path | Validated by |
|---|---|---|
| Product truth | `docs/PRD.md` | stakeholders |
| Technical truth | `docs/ARCHITECTURE.md` | engineers |

## Spec gate (hard stop before any build)
What must be true to leave SPEC and start building.
> e.g. "PRD.md validated with stakeholders AND ARCHITECTURE.md validated with engineers."

## Vertical slice (what a tracer bullet cuts through)
The end-to-end path a single slice must complete in THIS domain.
> library: `Protocol → battery → build() → tests`
> data:    `source → staging → dim/fact → tests → dashboard tile`
> web app: `schema → API → UI → tests`

## Issue granularity (one demoable tracer bullet; ~300 LOC anchor)
The real unit is **one thin, demoable behaviour** end-to-end; **~300 LOC is the default size anchor** for
it — a norte, not a hard limit. Split clearly above it; merge trivially small ones below it. LOC is a
**proxy** (some domains size by model+tests, feature+eval, etc.), so the régua and demoability win on
conflict. Set the anchor — or this domain's own sizing unit — for THIS project here.

## Seams (where tests intercept behavior)
Prefer existing seams; use the highest; the fewer the better (ideal: one).
> library: Ports / build() boundary / tool wrapper
> data:    dbt sources / model contracts / schema + singular tests / reconciliation tests

## Fakes / fixtures (no live infra in tests)
How tests run without cloud/live systems.
> library: fakes implementing the Protocol
> data:    dbt seeds (tiny CSV fixtures)

## Definition of Done (per-phase gates)
The checklist a phase must satisfy to be done. At least one item must be **observable behaviour of the
delivered system**, not only "the tests pass" — a gate defined solely by the suite cannot catch a suite that
goes green over a system that was never wired up.
> e.g. "test command green + PK/source/data-quality tests pass + audited number reconciles"

## Phase-cutting rule
How epics are sized and ordered (dependency order, must-first, one seam group per phase).

## Phase roadmap (derived; validated once, before the first PLAN)
The project's epics in the order they are expected to run — the **macro plan the user signs off on** before
any building, so nobody discovers the project's shape one phase at a time. Applying the rule above to the
validated `PRD.md`, **one entry per phase**: a header (the epic, the requirement IDs it realizes, the DoD
item(s) it closes) plus an **`Excludes:`** line naming what this phase defers and to which neighbouring
phase. `Excludes` is the load-bearing field — the inter-phase **boundary** the `sdd-phase-opener` cannot
re-derive from the baselines (they say *what* to build, not *whose* phase owns it), so it is the one detail
worth writing here. Add a one-line **`Delivers:`** only where the IDs don't make the deliverable obvious;
leave ADR / test / constraint detail to each phase's own PRD, cut just-in-time at PLAN. Still a **scope
sketch, not a spec**.

**Left `PENDING` by `/sdd-init`** (the PRD is still a skeleton then, so there is nothing to derive from).
`/sdd` fills it at the **spec gate** — once both baselines are validated and before the first PLAN — by
deriving the phases, presenting them in plain product terms, and writing them here on the user's ok. The
`PENDING` marker is the one slot value `/sdd` tolerates; every other slot must be filled to run.

**Indicative, not binding.** The `sdd-phase-opener` still re-derives each phase from `PRD.md` +
`PROGRESS.md` + ADRs at PLAN time — dependency order wins over this list. When a cut diverges, the
phase-opener says so (and why) as it presents the phase; the roadmap is not an amendment gate. What keeps it
honest is change control: a **structural** amendment to `PRD.md`/`ARCHITECTURE.md` re-derives this list and
re-presents the affected phases for a quick ok, in the same conversation as the amendment. Phases already
`done` are never rewritten.

PENDING — derived and validated at the spec gate.

> - Phase 1 — <epic>: `FR-1`, `FR-2` · DoD: <the root DoD item(s) it closes>
> - Phase 2 — <epic>: `FR-3`, `NFR-1` · DoD: <…>

## Test command(s)
Two scopes (they may be the same command in a small project):
- **Slice command** — proves ONE issue green (its behaviour/integration test + its units). The worker runs
  it at close, before handing off the branch. Scope it to what the issue touches; keep it fast.
  > e.g. `pytest -q tests/<area>` / `dbt build --select state:modified+`
- **Full-suite / regression command** — runs EVERY test in the project (all prior issues' behaviour +
  units), proving new work didn't break earlier behaviour. This backs the regression gate below — keep it
  whole, not scoped.
  > e.g. `pytest -q` / `dbt build` + `dbt test`

## Loop
- **Acceptance scenarios:** issues carry a Gherkin `Scenario:` (authored via `/bdd`), realized as the
  outer behaviour test using the seam/mechanism named in `ARCHITECTURE.md`/ADRs. No matrix here — the
  arch doc owns "how a behaviour is tested in this project".
- **Dispatch (fixed — always subagents):** the main-session orchestrator spawns a fresh **`sdd-issue-worker`**
  per issue (optionally in its own git worktree on the issue branch), a bounded **`sdd-phase-opener`** to
  cut each phase, and a bounded **`sdd-merge-resolver`** to land each green branch. Not a knob — the whole
  architecture (coordinator in the main session, bounded leaves in subagents) depends on it. The orchestrator
  also **creates the issue branch before dispatching**; the worker only attaches to it. See the dispatcher spec.
- **Concurrency (how many issues *build* at once — never how they land):**
  - `serial` (**default**) — one issue at a time. The land queue never holds more than one item, so no
    cross-branch conflict is possible. Prefer this unless the backlog has many genuinely-independent slices.
  - `parallel` — opt-in: the orchestrator may co-dispatch workers for issues that are all-blockers-`done`
    **and** touch **disjoint files/seams**. Only safe *because* the land is serialized — build parallel,
    land serial.
  **In both modes the worker never lands.** It builds to green on its own `issue/*` branch, returns
  `ready-to-land`, and stays on that branch; the orchestrator then drains the queue one item at a time via a
  bounded `sdd-merge-resolver` that rebases onto the current tip, resolves a conflict only if one arises,
  runs the regression gate, and merges (or opens the PR). The coordinator never runs the suite or merges
  itself, and the worker never leaves its branch — which is what keeps every integrity guard (all of which
  key on being on an `issue/*` branch) actually reachable.
- **Continuation mode (gate at a boundary / on resume):** governs what the orchestrator does when the loop
  reaches a boundary or re-enters after a compaction/crash — **not** who holds context (dispatch is always
  via subagents).
  - `ask` (**default**) — at a boundary / on re-entry only (**not** before each intra-phase issue), the
    *alive* session pauses, presents the resume cursor from `PROGRESS.md` (`Phase / Doing / Next /
    Stop-reason`) + the recommended next action, and **asks whether to continue** before dispatching; within
    a phase, issues run consecutively. Supervised runs.
  - `auto` — self-continuing (unattended): keep dispatching workers without asking; own overflow is caught
    by the `SessionStart` re-prime + `/loop`; **no flat supervisor**. A `blocked` / `needs-decision` /
    `needs-revalidation` stop always surfaces to a human regardless of this knob.
  The `SessionStart` hook re-injects the cursor + next action deterministically either way; this knob only
  decides ask-first vs proceed.
- **Backlog review (gate at PLAN, before BUILD):** governs the human gate on the *derived scope* of a phase.
  - `confirm` (**default**) — a **one-time** pause once the phase is cut: the user **approves/edits the phase
    scope (its PRD) + the backlog together**, then BUILD proceeds straight through the **whole** backlog
    **without pausing per issue** (only a worker's `blocked` / `needs-decision` / `needs-revalidation`, or
    the phase draining, stops it). One approval per phase — never one per issue.
  - `auto` — the `sdd-phase-opener`'s cut goes straight to BUILD. Pick this for unattended runs, together
    with the unattended continuation mode below.
  Under **either** setting the orchestrator **reports** the cut (scope + DoD + the slices in order) in plain
  terms; this knob only decides whether it *waits* for approval. The two baselines stay the only
  human-validated docs — this is a lightweight gate on the derived layer.
  Orthogonal to Continuation mode: this gates *what gets built* (the plan); Continuation gates *whether to
  proceed* at a boundary.
- **Integrity enforcement:** `prose+git +hook` (**default**) — the base (`prose+git`: immutable
  scenario+flag, RED proof, test-first commit, clean re-run) plus the shipped `PreToolUse` guard
  (`+hook`: on an `issue/*` branch, deny an implementation edit until a **behaviour/BDD test** is committed
  — universal, since the BDD outer test is required even for TDD-`skipped` issues; docs/spec/state edits are
  always allowed). `+hook` also enables a **non-blocking** warning when a worker edits a test that already
  lives on the integration branch (a *landed* test — fix the code, not the test). Separately, when a PR is
  opened the `sdd-merge-resolver` re-reads the **branch diff** for test-gaming and records advisory notes on
  it. Drop to bare `prose+git` only if the project's test paths don't match the default and you
  don't want to set `SDD_TEST_PATTERN`. **Independent of this knob, two guards are always on:** the
  `SubagentStop` exit verification, and the `PreToolUse` **issue-branch guard** — while an issue is `doing`,
  no code/test edit is allowed on the integration/protected branch, so the loop builds on an `issue/*` branch
  or not at all (docs/spec/state stay allowed; idle loop = never fires).
  Escalate uncovered critical decisions via `/grill-me` → ADR/PRD;
for a **weighty fork that needs asynchronous team sign-off**, the assistant may instead **suggest** a
**Request for Comments** (`/to-rfc` → `docs/rfcs/`, status `to-be-validated`) that, once the team validates
it, materializes into an ADR/PRD amendment (`validated (ADR-NNNN)`) — suggested, never forced.

## Git strategy (branch-per-issue)
- **Protected branch:** `main` — the loop **never** commits here (human-only `develop → main` promotion).
- **Integration branch:** `develop` — every issue lands here; dependents branch off it once the blocker lands.
- **Issue branch naming:** `issue/<id>-<slug>`.
- **PR provider:** `none` (default) | `gh` (GitHub CLI) | `bitbucket-mcp` (Bitbucket MCP). The provider is
  the PR surface; `none` lands locally with no PR. `human-review` **requires** a provider.
- **Merge policy** — the default is **conditional on a provider being reachable**, decided at `/sdd-init`:
  - `human-review` (**default when a provider is reachable**) — open a PR and stop at `in-review`; the loop
    is **non-blocking** (moves to the next issue whose blockers are landed); a human merges, flipping it to
    `done`. Autonomous within a phase, human merge-gate per slice. If every remaining issue is blocked by an
    open PR, the phase pauses at `awaiting-review` until someone merges — that pause is the point.
  - `auto-merge` (**default when there is no provider**, and the basis of unattended runs) — land each issue
    on green **+ passing checks/CI**, no human gate. With a provider: open the PR and merge it when checks
    pass. With `none`: run the full-suite command locally, then merge the issue branch into `develop`. Fully
    autonomous; the backlog drains straight to `done`. This is a **first-class** configuration — a repo with
    no GitHub/Bitbucket runs the loop with the same guarantees, the regression gate just runs locally.
- **Regression gate (at merge to a non-feature branch):** the **full-suite/regression command** must pass
  before an issue lands on the integration branch (and before `develop → main`). Placement is flexible —
  the plugin does **not** impose a CI config:
  - **Recommended: CI.** Wire your provider's checks to run the full suite on the PR / on push of an
    `issue/*` branch and on merge to any protected branch (`develop`, `main`, …). Shape it however you
    like — the **minimum** is an e2e/regression run at each merge to a non-feature branch.
  - **Fallback (provider `none`, local merge): the loop runs the full-suite command locally** before
    landing, so the default config is never unprotected.
  A failure here never weakens a test — it re-opens the issue to fix the **code** (a genuine behaviour
  change escalates as `needs-revalidation`).
- **Backlog statuses** (`ready-to-land` = green + pushed, awaiting the lander — it is on **every** path,
  serial and parallel alike, because the worker never lands):
  `todo → doing → ready-to-land → done` (auto-merge) ·
  `todo → doing → ready-to-land → in-review → done` (human-review).

## Paths
> **Load-bearing — every downstream tool + hook reads artifact locations from here.** Relocate the baselines /
> `PROGRESS.md` / phases dir by editing the paths below; **keep each path in backticks** so the hooks can parse
> it. The `SessionStart` re-prime reads the **Durable state** path; the `SubagentStop` verify reads the
> **Phases dir** path (both fall back to `docs/…` if unset).
- **Phases dir:** `docs/phases/` — each epic gets `docs/phases/phase-N/` holding **`prd.md`** (the phase
  projection) and **`backlog.md`** (that phase's issues). Deterministic dir name `phase-N` (N = phase
  number); the epic's human name lives in the `prd.md` H1.
- **Baselines:** root PRD `docs/PRD.md` · technical truth `docs/ARCHITECTURE.md` · ADRs `docs/adrs/` · RFCs `docs/rfcs/`.
- **Durable state:** `docs/PROGRESS.md` — the single **global** loop cursor (the `SDD-CURSOR` block:
  phase / doing / next / stop-reason). One file, never per-phase.
- **Templates:** root PRD for `/to-prd` = (path, or "skill default"); phase PRD (filled by PLAN) =
  `templates/prd/phase-PRD.template.md`.
