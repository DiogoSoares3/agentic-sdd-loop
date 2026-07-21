# BDD · realizing a scenario as the outer test (called by the build agent, before `/tdd`)

The scenario is **immutable to you here.** It was authored at planning time from the phase PRD; you
realize it, you do not rewrite/weaken/`xfail` it. If it seems wrong or under-specified, that is a
spec gap → escalate (`needs-decision` / `/grill-me`), never edit the scenario to fit the code.

Turn the issue's scenario into the **outer-loop behaviour test (red)** — it asserts observable behaviour of
the slice, so it is **usually an integration test, but not by definition**: its form follows the seam/mechanism
`ARCHITECTURE.md` names (integration/API · contract · threshold/eval · reconciliation · CLI e2e · …), not a
fixed type. Steps:

1. Read `ARCHITECTURE.md`/ADRs to find the **seam** and the **test mechanism** for THIS project.
2. Write the behaviour test at that seam so it **fails** for the right reason (feature absent).
   **Arrange nothing you are about to assert.** External fixtures are fine; writing to the public surface
   you then check is not — registering, patching or seeding the very state the slice is supposed to produce
   makes the test pass over an unbuilt system, because the `Then` only re-reads what the `Given` just wrote.
   The tell: if the test goes red once you remove that setup, the setup **was** the feature, and it belongs
   in the implementation.
3. Hand off to `/tdd` for the inner loop **when the issue's `Inner loop (TDD)` flag is `required`** (the
   default) — the slice is done when the inner units **and** this outer behaviour test are green. When the
   flag is `skipped`, there is no inner loop: the slice is done when **this outer behaviour test** is green
   (plus the phase DoD). Either way the outer scenario is **always** realized — BDD is never skipped.
4. If the outcome is **non-deterministic** (ML/GenAI), the `Then` asserts the property/threshold/
   pass-rate the arch doc defines (e.g. "holdout F1 ≥ 0.80", "0 PII leaks over N runs") — never an
   exact match. The threshold comes from the specs, not from you.
