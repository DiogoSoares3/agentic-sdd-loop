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
| Technical truth | `docs/ARCHITECTURE.md` | devs |

## Spec gate (hard stop before any build)
What must be true to leave SPEC and start building.
> e.g. "PRD.md validated with stakeholders AND ARCHITECTURE.md validated with devs."

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
- **Fresh-agent mode:** `reprime` (default — re-prime the context pack each `/loop` iteration) or
  `subagent` (spawn a fresh agent per issue **in its own git worktree on the issue branch**). Both use
  the branch-per-issue flow below; the mode only changes the checkout. See the dispatcher spec.
- **Handoff mode:** `manual` (default, host-agnostic — at the context gate write `/handoff` and a human
  starts a clean session) or `auto` (self-continuing — a **flat supervisor** spawns **sequential worker
  subagents**: workers hold all context and hit the gate, the near-empty supervisor only respawns them
  from files + handoff; see the dispatcher's *Autonomous handoff* spec). `auto` **requires subagent
  support**; files + handoff are the durable state either way, so the context gate is a checkpoint, not
  a stop.
- **Backlog review:** `auto` (default — cut the phase backlog and go straight to BUILD) or `confirm`
  (pause after `/to-issues` and surface the backlog for human approval/edit before building). The two
  baselines stay the only human-validated docs; this is an optional gate on the derived layer.
- **Integrity enforcement:** `prose+git` (default — immutable scenario, RED proof, test-first commit,
  clean re-run) | `+verifier` (independent agent re-reads the **branch/PR diff** for test-gaming) | `+hook`
  (block edits to test paths during GREEN). Escalate uncovered critical decisions via `/grill-me` → ADR/PRD.

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
- **Phases dir:** `docs/phases/` — each epic gets `docs/phases/phase-N/` holding **`prd.md`** (the phase
  projection) and **`backlog.md`** (that phase's issues). Deterministic dir name `phase-N` (N = phase
  number); the epic's human name lives in the `prd.md` H1.
- **Baselines:** root PRD `docs/PRD.md` · technical truth `docs/ARCHITECTURE.md` · ADRs `docs/adrs/`.
- **Durable state:** `docs/PROGRESS.md` — the single **global** loop cursor (phase/issue, latest handoff).
  One file, never per-phase.
- **Templates:** root PRD for `/to-prd` = (path, or "skill default"); phase PRD (filled by PLAN) =
  `templates/prd/phase-PRD.template.md`.
