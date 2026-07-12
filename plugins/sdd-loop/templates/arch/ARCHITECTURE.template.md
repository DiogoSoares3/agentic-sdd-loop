# ARCHITECTURE — <PROJECT NAME>

> **DRAFT — awaiting engineer validation.** Technical truth (how it's built). Referenced by `PRD.md`, not
> duplicated. A living document — update it when a decision closes; keep discarded alternatives.

## Overview
The shape of the solution in a few sentences.

### System diagram (container + seams)
One whole-project view a fresh agent primes on — **container/component altitude, not code-level**:
external actors, the main components/layers, data stores, external deps. **Mark the seams** (where
`/bdd` + `/tdd` intercept) — that is what makes this diagram load-bearing for the loop, not decoration.
Use **Mermaid** (text diffs in git; no binary assets). Keep it to **one** diagram; the régua wins if a
truthful diagram gets expensive — prose beats a stale picture.

```mermaid
flowchart LR
  client([Client]) --> api[API layer]:::seam
  api --> svc[Domain service]
  svc --> repo[(Repository)]:::seam
  svc --> ext[External dep]
  classDef seam stroke-width:3px,stroke-dasharray:4;
  %% dashed = seam: where behaviour/unit tests intercept
```

### Hot-path flow (optional — only the régua's dominant path)
Add **at most one** more diagram, for the single flow the régua cares about (e.g. the read/redirect hot
path), and only if it is not obvious from the container view above. Finer-grained per-scenario sequences
live in the phase PRDs / Gherkin, not here. Rule of three before a third diagram.

## Seams
Where behavior is intercepted for testing (prefer existing, highest, fewest). These are what the
phases and `/tdd` reference.

## Components / layers
The modules/layers and their responsibilities.

## Key decisions (ADRs)
Index of closed decisions → link to `docs/adrs/`. Each ADR names the discarded alternative and why.

## Discarded alternatives
| Considered | Rejected because |
|---|---|

## Open questions
Pendências to resolve before or during the affected phase.
