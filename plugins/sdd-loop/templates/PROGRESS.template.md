# PROGRESS — <PROJECT NAME>

> **Durable loop state. Lives in the repo (never temp).** The single dynamic file — update it per
> completed slice. Static conventions/decisions go in the sources of truth, not here.
> Priming read order: `.sdd/profile.md` → **this file** → `PRD.md` / `ARCHITECTURE.md` as needed.

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
_Which phase, which slice is `doing` — the human-readable expansion of the cursor above._

## In review (PR open, awaiting merge) — human-review policy only
_Issues that are green with a PR open but not yet merged (`in-review`) — one line each with the PR URL.
Dependents stay blocked until their blocker here is merged (`done`). Empty under `auto-merge`, where
issues land straight to `done`._

## Next actions
_The very next slice to pick up (mirrors cursor `Next`), plus any prep it needs._

## Open questions
_Tactical refinements, decisions pending, things to flow up for re-validation. For a `needs-decision` /
`needs-revalidation` stop, state the exact question here so the re-entry can resolve it._

## Worklog (most recent first)
_One line per slice: what shipped + gate result + PR URL. Note when a human merged it (`in-review` → `done`).
For a required-TDD issue mid-build, the inner-unit checkpoints land here too (`<id>: unit "<x>" green; next: …`)._
