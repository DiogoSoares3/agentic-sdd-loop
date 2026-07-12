# SDD Project Profile — <PROJECT NAME>

> Layer 2. The **only** file that changes between projects. The plugin's `/sdd` skill reads this to
> parametrize the invariant methodology. Keep it lean; fill every slot.

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
The checklist a phase must satisfy to be done.
> e.g. "test command green + PK/source/data-quality tests pass + audited number reconciles"

## Phase-cutting rule
How epics are sized and ordered (dependency order, must-first, one seam group per phase).

## Test command(s)
The exact command(s) that prove a slice green.
> e.g. `pytest -q` / `dbt build` + `dbt test --select source:*`

## Loop
- **Acceptance scenarios:** issues carry a Gherkin `Scenario:` (authored via `/bdd`), realized as the
  outer behaviour test using the seam/mechanism named in `ARCHITECTURE.md`/ADRs. No matrix here — the
  arch doc owns "how a behaviour is tested in this project".
- **Dispatch (fixed — always subagents):** the main-session orchestrator spawns a fresh **`sdd-issue-worker`**
  per issue (optionally in its own git worktree on the issue branch) and a bounded **`sdd-phase-opener`** to
  cut each phase. Not a knob — the whole architecture (coordinator in the main session, bounded leaves in
  subagents) depends on it. See the dispatcher spec.
- **Continuation mode (gate at a boundary / on resume):** governs what the orchestrator does when the loop
  reaches a boundary or re-enters after a compaction/crash — **not** who holds context (dispatch is always
  via subagents).
  - `ask` (**default**) — the *alive* session pauses, presents the resume cursor from `PROGRESS.md`
    (`Phase / Doing / Next / Stop-reason`) + the recommended next action, and **asks the user whether to
    continue** before dispatching. Supervised runs.
  - `auto` — self-continuing (unattended): keep dispatching workers without asking; own overflow is caught
    by the `SessionStart` re-prime + `/loop`; **no flat supervisor**. A `blocked` / `needs-decision` /
    `needs-revalidation` stop always surfaces to a human regardless of this knob.
  The `SessionStart` hook re-injects the cursor + next action deterministically either way; this knob only
  decides ask-first vs proceed.
- **Backlog review (gate at PLAN, before BUILD):** governs the human gate on the *derived scope* of a phase.
  - `auto` (**default**) — the `sdd-phase-opener`'s cut goes straight to BUILD.
  - `confirm` — pause after the backlog is cut and surface it for the user to **approve/edit the phase scope**
    before any build. The two baselines stay the only human-validated docs; this is an optional gate on the
    derived layer.
  Orthogonal to Continuation mode: this gates *what gets built* (the plan); Continuation gates *whether to
  proceed* at a boundary.
- **Integrity enforcement:** `prose+git +hook` (**default**) — the base (`prose+git`: immutable
  scenario+flag, RED proof, test-first commit, clean re-run) plus the shipped `PreToolUse` guard
  (`+hook`: on an `issue/*` branch, deny an implementation edit until a **behaviour/BDD test** is committed
  — universal, since the BDD outer test is required even for TDD-`skipped` issues; docs/spec/state edits are
  always allowed). Optionally add `+verifier` (an independent agent re-reads the **branch/PR diff** for
  test-gaming). Drop to bare `prose+git` only if the project's test paths don't match the default and you
  don't want to set `SDD_TEST_PATTERN`. Escalate uncovered critical decisions via `/grill-me` → ADR/PRD.

## Git strategy (branch-per-issue)
- **Protected branch:** `main` — the loop **never** commits here (human-only `develop → main` promotion).
- **Integration branch:** `develop` — every issue lands here; dependents branch off it once the blocker lands.
- **Issue branch naming:** `issue/<id>-<slug>`.
- **PR provider:** `none` (default) | `gh` (GitHub CLI) | `bitbucket-mcp` (Bitbucket MCP). The provider is
  the PR surface; `none` lands locally with no PR. `human-review` **requires** a provider.
- **Merge policy:**
  - `auto-merge` (default) — land each issue on green **+ passing checks/CI**, no human gate. With a
    provider: open the PR and merge it when checks pass. With `none`: merge the issue branch into
    `develop` locally. Fully autonomous; the backlog drains straight to `done`.
  - `human-review` — open a PR and stop at `in-review`; the loop is **non-blocking** (moves to the next
    issue whose blockers are landed); a human merges, flipping it to `done`. Autonomous within a phase,
    human merge-gate at each phase boundary.
- **Backlog statuses:** `todo → doing → done` (auto-merge) · `todo → doing → in-review → done` (human-review).

## Paths
> **Load-bearing — every downstream tool + hook reads artifact locations from here.** Relocate the baselines /
> `PROGRESS.md` / phases dir by editing the paths below; **keep each path in backticks** so the hooks can parse
> it. The `SessionStart` re-prime reads the **Durable state** path; the `SubagentStop` verify reads the
> **Phases dir** path (both fall back to `docs/…` if unset).
- **Phases dir:** `docs/phases/` — each epic gets `docs/phases/phase-N/` holding **`prd.md`** (the phase
  projection) and **`backlog.md`** (that phase's issues). Deterministic dir name `phase-N` (N = phase
  number); the epic's human name lives in the `prd.md` H1.
- **Baselines:** root PRD `docs/PRD.md` · technical truth `docs/ARCHITECTURE.md` · ADRs `docs/adrs/`.
- **Durable state:** `docs/PROGRESS.md` — the single **global** loop cursor (the `SDD-CURSOR` block:
  phase / doing / next / stop-reason). One file, never per-phase.
- **Templates:** root PRD for `/to-prd` = (path, or "skill default"); phase PRD (filled by PLAN) =
  `templates/prd/phase-PRD.template.md`.
