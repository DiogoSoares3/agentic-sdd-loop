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
The concrete, checkable "done" for this epic: the subset of the root Definition of Done these IDs
satisfy, plus any phase-specific check. This is what the backlog's issues must collectively make green.

## Deferred to later phases
Requirement IDs / behaviour deliberately NOT in this phase, so the boundary is explicit.
