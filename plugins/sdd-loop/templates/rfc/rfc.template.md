# RFC-NNNN: <short title of the proposal>

> **Status: to-be-validated** | validated (ADR-MMMM) | rejected | superseded-by RFC-PPPP
> Date: YYYY-MM-DD · Author: <who> · Reviewers: <the team / roles who validate this>
> Origin: where this proposal came from — `ARCHITECTURE.md` authoring · an ADR-level decision ·
> a build-time `needs-decision` escalation (issue `<id>`) · an explicit request.
>
> An RFC is a **proposal circulated for the team to comment on and validate** — it is **not yet a
> decision**. While it is **`to-be-validated`** the decision it proposes is still **open** (the loop
> treats it exactly like an unresolved `needs-decision`). When the team accepts it, **materialize** the
> outcome as an ADR (via `/to-adr`) and/or a `PRD.md` / `ARCHITECTURE.md` amendment, then flip this status
> to **`validated (ADR-MMMM)`** — that flip is the single signal that the baseline now covers it and the
> parked work can resume.

## Context & problem
What forces this decision and **why the current `PRD.md` / `ARCHITECTURE.md` / ADRs are silent on it**.
Note the `FR`/`NFR` / régua / seams it touches, if any. Keep it tight — enough for a reviewer to grasp the stakes.

## Options considered
The competing alternatives — the heart of the "for comments". One sub-section per option, each with its
trade-offs. This is what the team weighs in on.

### Option A — <name>
- **Pros:** …
- **Cons:** …

### Option B — <name>
- **Pros:** …
- **Cons:** …

## Recommendation
The recommended option **and why** (an RFC always carries a recommendation, like `/grill-me`). Name the
alternative you would discard and the reason — reviewers push back against a concrete proposal, not a menu.

## Impact
Which **seam(s) / contract(s) / scope** this changes; any migration; and **which baseline it will amend on
acceptance** — an `ARCHITECTURE.md` section, a new ADR, and/or a `PRD.md` requirement.

## Open questions for reviewers
The specific points the team must decide before this can be validated. These are what keep it
`to-be-validated`.

## Outcome (filled on validation)
The team's decision + the artifact it produced — e.g. *"Accepted 2026-07-20 → ADR-0007 + `ARCHITECTURE.md`
§Seams"*. Then set the **Status** line above to `validated (ADR-0007)`. If **rejected**, record why and which
alternative was chosen instead (that chosen path is itself a decision — record it as an ADR too).
