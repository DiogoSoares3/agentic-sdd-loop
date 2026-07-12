# PRD — <PROJECT NAME>

> **DRAFT — awaiting stakeholder validation. Development does not start until validated.**
> Product truth (what / why / scope / priority). The technical "how" — components, seams, test
> mechanism — lives in `ARCHITECTURE.md`; it is referenced, not duplicated.

## Problem
The problem from the user's / stakeholder's perspective. Short and concrete.

## Solution
The approach, from the perspective of whoever uses the result. Short.

## Personas & user stories
Who the product serves and what each needs from it — the human layer the scope below is negotiated for.
**One sub-list per persona**, and **every persona carries at least one story** (never leave a persona
storyless). Write each story as "**As a** <persona>, **I want** <capability>, **so that** <benefit>", at
product altitude (a need, not a UI detail). Anchor each story to the requirement ID(s) that realize it, so
personas → scope → requirements stay one connected chain.

### <Persona name> — <one-line role / context / primary goal>
- As a <persona>, I want <capability>, so that <benefit>. → `FR-1`, `FR-3`
- …

### <Persona name> — …
- …

## Scope & prioritization (MoSCoW)
The **stakeholder-negotiated scope contract** — what they validate and sign off. Every capability sits in
exactly one priority bucket. **Won't (this version)** *is* the out-of-scope list — there is no separate
"out of scope" section. Each capability links to the requirement IDs that specify it.

| Priority | Capability | Requirements |
|---|---|---|
| **Must** | <capability — the persona need it delivers (see *Personas & user stories*)> | FR-1, NFR-2 |
| **Should** | … | FR-3 |
| **Could** | … | FR-4 |
| **Won't (this version)** | <deferred / explicit non-goal> | — |

> Priority is the **stakeholder signal**; it feeds the *must-first* tiebreak of phase-cutting. Execution
> **order** is still governed by dependency order + the régua (a Must that depends on a Should cannot jump
> it) — MoSCoW **prioritizes, it does not sequence**.

## Requirements
Numbered so phases and DoD can anchor to IDs. Functional and non-functional split apart.

### Functional (FR-n)
- `FR-1` — <testable capability statement, from the user's perspective>
- `FR-2` — …

### Non-functional (NFR-n)
- `NFR-1` — <measurable constraint: performance / security / operability / …>
- `NFR-2` — …

## Definition of done
The **complete, validated** "done" for this version, per the régua — concrete and checkable, anchored to
requirement IDs. This is **product-level** acceptance. The *technical* testing decisions (seams, test
types, mocking, prior art) live in `ARCHITECTURE.md`, not here.

## Notes
Open questions; links to `ARCHITECTURE.md` sections / ADRs.
