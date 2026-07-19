# PROGRESS — <PROJECT NAME>

> **Durable loop state — the single dynamic file. Lives in the repo (never temp).** It exists to resume the
> loop from *any* interruption, so it holds the **current** state in full and the **past** only as one-line
> summaries. Static conventions/decisions belong in the sources of truth (`PRD.md` / `ARCHITECTURE.md` /
> ADRs), never here. Priming read order: `.sdd/profile.md` → **this file** → `PRD.md` / `ARCHITECTURE.md`.
>
> **Keep it lean — WHAT / WHEN / PRUNE:**
> - **WHAT** goes in: the cursor (always), the in-flight issue's live detail, the current phase's worklog,
>   open decisions. No essays, no rationale, no old-issue spoils.
> - **WHEN** to write: update the cursor + append one worklog line at every RECORD (per issue); the worker
>   appends one checkpoint line per required-TDD unit; the phase-opener sets the cursor at PLAN.
> - **WHEN to PRUNE:** when a new phase opens, the phase-opener collapses the finished phase into ONE
>   *Completed phases* line and clears the *Worklog* + resolved *Open questions* + merged *In review* rows.

<!-- SDD-CURSOR — machine-read by the SessionStart hook; the loop MUST keep these four fields current at
     every RECORD. Fixed keys, one value each, no prose. This block is the deterministic resume point. -->
- Phase: none
- Doing: none
- Next: none
- Stop-reason: none
<!-- /SDD-CURSOR -->

**Cursor field meanings** (the loop maintains them; the hook echoes them and derives the next action):
- **Phase** — current phase number (e.g. `3`), or `none` before the first PLAN.
- **Doing** — the issue id currently in `doing` (mid-build), or `none` if nothing is mid-flight.
- **Next** — the true next grabbable `todo` id (all blockers `done`), or `none — phase drained` /
  `none — project complete` / `none — awaiting-review`.
- **Stop-reason** — why the loop last paused, from this fixed set:
  `none` (running) · `clean-boundary` (phase drained / project done) · `blocked` · `needs-decision` ·
  `needs-revalidation` · `awaiting-review` (human-review PRs blocking dependents) · `compacted` (overflow).

## Current status
_One or two lines: current phase + which slice is `doing` (the human-readable expansion of the cursor). Not a history._

## Completed phases (mini-summaries)
_One line per finished phase — `Phase N — <epic>: done · <what shipped, high-level> · DoD met`. Written by the
phase-opener as it opens the next phase, replacing that phase's detailed worklog. The ONLY record kept of old phases._

## In review (PR open, awaiting merge) — human-review policy only
_One line each with the PR URL for issues green-but-unmerged (`in-review`). Dependents stay blocked until their
blocker here merges (`done`). Drop the row once merged. Empty under `auto-merge`._

## Next actions
_The very next slice to pick up (mirrors cursor `Next`) + any prep it needs. Not a copy of the backlog._

## Open questions
_Decisions pending / to flow up for re-validation. For a `needs-decision` / `needs-revalidation` stop, state the
exact question here so the re-entry resolves it. If the decision was formalized as a Request for Comments, note
its file + status (`RFC-000N to-be-validated — blocks issue <id>`) so re-entry knows the decision is still open
until the team validates it. **Delete each once resolved** (the RFC is `validated (ADR-XXXX)`) — never keep answered ones._

## Worklog — current phase only (most recent first)
_One concise line per slice of the CURRENT phase: what shipped + gate result + PR URL (+ note `in-review`→`done`
when a human merges). Required-TDD mid-build checkpoints land here too (`<id>: unit "<x>" green; next: …`). When
the phase closes, the phase-opener compacts this into a *Completed phases* line and clears it — keep it to the live phase._
