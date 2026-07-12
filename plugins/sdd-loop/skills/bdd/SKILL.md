---
name: bdd
description: Author and realize Gherkin acceptance scenarios for vertical issues, always derived from the phase PRD and ARCHITECTURE.md/ADRs. Use when writing an issue's acceptance criteria (with /to-issues) or when writing the behaviour/integration test at the start of a slice (the outer loop before /tdd). Mentions "bdd", "gherkin", "given/when/then", "acceptance scenario".
---

# BDD — behaviour scenarios, derived from the specs

Gherkin is a **format**, not a framework. Never wire a Cucumber/behave/pytest-bdd runner. A scenario
is authored on the issue and **realized** by whatever test mechanism the project's `ARCHITECTURE.md`
/ADRs prescribe (dbt test, pytest, eval set, …). The plugin owns no domain assumptions — the
**baselines own them**:

> **Every scenario derives from the phase PRD (behaviour/why) + `ARCHITECTURE.md`/ADRs (seam/how).**
> If the specs don't say it, you don't invent it — you flow the gap up (see the orchestrator's change control).

## Two modes

### 1. Authoring (called by `/to-issues`)
For each vertical issue, write **one `Scenario:`** capturing the slice's observable behaviour.

- **Given** = the state/fixtures the slice assumes (name the seam from `ARCHITECTURE.md`).
- **When** = the single action the slice performs.
- **Then** = the observable outcome that makes it demoable — the acceptance boundary.
- **Declarative, not imperative:** state *what*, not UI/SQL steps. Use the project's domain glossary.
- **One behaviour per scenario.** Extra chores (docs, cleanup) go in a plain checklist beneath it,
  not in the scenario.
- **Boundaries explicit:** the scenario is the contract of what this slice does and does **not** cover.

### 2. Realizing (called by the build agent, before `/tdd`)
The scenario is **immutable to you here.** It was authored at planning time from the phase PRD; you
realize it, you do not rewrite/weaken/`xfail` it. If it seems wrong or under-specified, that is a
spec gap → escalate (`needs-decision` / `/grill-me`), never edit the scenario to fit the code.

Turn the issue's scenario into the **outer-loop behaviour test (red)** — it asserts observable behaviour of
the slice, so it is **usually an integration test, but not by definition**: its form follows the seam/mechanism
`ARCHITECTURE.md` names (integration/API · contract · threshold/eval · reconciliation · CLI e2e · …), not a
fixed type. Steps:

1. Read `ARCHITECTURE.md`/ADRs to find the **seam** and the **test mechanism** for THIS project.
2. Write the behaviour test at that seam so it **fails** for the right reason (feature absent).
3. Hand off to `/tdd` for the inner loop **when the issue's `Inner loop (TDD)` flag is `required`** (the
   default) — the slice is done when the inner units **and** this outer behaviour test are green. When the
   flag is `skipped`, there is no inner loop: the slice is done when **this outer behaviour test** is green
   (plus the phase DoD). Either way the outer scenario is **always** authored and realized — BDD is never skipped.
4. If the outcome is **non-deterministic** (ML/GenAI), the `Then` asserts the property/threshold/
   pass-rate the arch doc defines (e.g. "holdout F1 ≥ 0.80", "0 PII leaks over N runs") — never an
   exact match. The threshold comes from the specs, not from you.

## Example (data project — realized as a dbt singular test)

```gherkin
Scenario: 2011 gross sales reconcile to the audited figure
  Given fct_sales built from the adventure_works sources
  When gross revenue is summed for order dates in calendar year 2011
  Then the total equals 12,646,112.16
```

The seam (`fct_sales`, sources) and the mechanism (dbt singular test) both come from
`ARCHITECTURE.md`; the number and the behaviour come from the phase PRD.
