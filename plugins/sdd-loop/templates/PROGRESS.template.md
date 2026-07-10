# PROGRESS — <PROJECT NAME>

> **Durable loop state. Lives in the repo (never temp).** The single dynamic file — update it per
> completed slice. Static conventions/decisions go in the sources of truth, not here.
> Priming read order: `.sdd/profile.md` → **this file** → latest handoff (below) →
> `PRD.md` / `ARCHITECTURE.md` as needed.

## Current status
_Which phase, which slice is `doing`._

## In review (PR open, awaiting merge) — human-review policy only
_Issues that are green with a PR open but not yet merged (`in-review`) — one line each with the PR URL.
Dependents stay blocked until their blocker here is merged (`done`). Empty under `auto-merge`, where
issues land straight to `done`._

## Latest handoff
_Path to the most recent `/handoff` file in OS temp, or "none"._

## Next actions
_The very next slice to pick up._

## Open questions
_Tactical refinements, decisions pending, things to flow up for re-validation._

## Worklog (most recent first)
_One line per slice: what shipped + gate result + PR URL. Note when a human merged it (`in-review` → `done`)._
