---
name: bdd
description: Author and realize Gherkin acceptance scenarios for vertical issues, always derived from the phase PRD and ARCHITECTURE.md/ADRs. Use when writing an issue's acceptance criteria (with /to-issues) or the outer behaviour test — commonly an integration test — at the start of a slice (before /tdd). Mentions "bdd", "gherkin", "given/when/then", "acceptance scenario".
---

# BDD — behaviour scenarios, derived from the specs

Gherkin is a **format**, not a framework. Never wire a Cucumber/behave/pytest-bdd runner. A scenario
is authored on the issue and **realized** by whatever test mechanism the project's `ARCHITECTURE.md`
/ADRs prescribe (dbt test, pytest, eval set, …). The plugin owns no domain assumptions — the
**baselines own them**:

> **Every scenario derives from the phase PRD (behaviour/why) + `ARCHITECTURE.md`/ADRs (seam/how).**
> If the specs don't say it, you don't invent it — you flow the gap up (see the orchestrator's change control).

## Two modes

The modes run at **different times, for different callers, with opposite postures toward the scenario**: one
writes it, the other treats it as immutable. **Load ONLY the one that matches the task at hand, on demand** —
reading the other half puts instructions in your context that you must not act on.

| When the task is… | Read (on demand) | Called by | Produces |
|---|---|---|---|
| writing an issue's acceptance criteria (PLAN) | [`authoring.md`](authoring.md) | `/to-issues`, `sdd-phase-opener` | one `Scenario:` on the backlog issue |
| realizing that scenario as the outer test (BUILD) | [`realizing.md`](realizing.md) | `sdd-issue-worker`, before `/tdd` | the failing behaviour test at the seam |

The derivation rule above governs **both** — do not restate it in the siblings, it is single-sourced here.

## Example (data project — realized as a dbt singular test)

```gherkin
Scenario: 2011 gross sales reconcile to the audited figure
  Given fct_sales built from the adventure_works sources
  When gross revenue is summed for order dates in calendar year 2011
  Then the total equals 12,646,112.16
```

The seam (`fct_sales`, sources) and the mechanism (dbt singular test) both come from
`ARCHITECTURE.md`; the number and the behaviour come from the phase PRD.
