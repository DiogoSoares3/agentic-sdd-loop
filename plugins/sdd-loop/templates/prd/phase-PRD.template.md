# Phase N — <EPIC NAME>

> **Derived, internal — no separate human sign-off** (the root `PRD.md` + `ARCHITECTURE.md` are the only
> human-validated baselines). This is a **thin projection** of one epic: it **references** the baselines
> by requirement ID / seam and **must not duplicate** their Problem/Solution/architecture prose.

## Realizes (requirement IDs)
The root `PRD.md` requirement IDs this phase delivers — e.g. `FR-3, FR-4, NFR-1`. This is the phase's
scope; nothing outside these IDs is built here.

## Capabilities in scope
The root MoSCoW capabilities these IDs deliver — reference the root `PRD.md` rows (do not restate them).

## Seam(s) touched
The seam(s) from `ARCHITECTURE.md` this epic builds on / through — name them, link the relevant ADRs.

## Depends on
Prior phases that must be `done` before this one starts — or "None — first phase".

## DoD gate (this phase)
The checkable "done" for this epic — a `- [ ]` checkbox list at **intermediate granularity**: finer than
the root Definition of Done (decompose the root DoD items these IDs realize into phase-checkable
conditions), yet coarser than the backlog's Gherkin scenarios (each item is an epic-level acceptance
condition, **not** a copy of one `Scenario:`). This is what the phase's issues **collectively** make green.

**Every item traces to a requirement ID / root DoD item** — decomposing a validated root item into finer
conditions is projection, not new scope; a phase-specific *operational* check (a migration ran, a tile
renders) is fine too. An item that traces to neither is un-validated product scope → escalate for
re-validation (a root PRD amendment), never invent it here.

- [ ] <phase-level acceptance condition — checkable, traces to a root DoD item> → `FR-3`
- [ ] <phase-level acceptance condition / phase-specific operational check> → `NFR-1`
- [ ] …

## Deferred to later phases
Requirement IDs / behaviour deliberately NOT in this phase, so the boundary is explicit.
