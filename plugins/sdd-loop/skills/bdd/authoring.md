# BDD · authoring a scenario (called by `/to-issues`)

For each vertical issue, write **one `Scenario:`** capturing the slice's observable behaviour.

- **Given** = the seam the behaviour is observed through (name it from `ARCHITECTURE.md`) plus any
  **external** fixture the slice needs. Name the **system as delivered** — never the state this slice is
  supposed to establish. A `Given` that describes the slice's own outcome leaves the test nothing to do but
  arrange that outcome and assert it back.
- **When** = the single action the slice performs.
- **Then** = the observable outcome that makes it demoable — the acceptance boundary.
- **Declarative, not imperative:** state *what*, not UI/SQL steps. Use the project's domain glossary.
- **One behaviour per scenario.** Extra chores (docs, cleanup) go in a plain checklist beneath it,
  not in the scenario.
- **Boundaries explicit:** the scenario is the contract of what this slice does and does **not** cover.

What you write here is **immutable to the build agent** that later realizes it. Under-specify and it has
nothing to escalate against; over-specify the *how* and you have written the implementation.
