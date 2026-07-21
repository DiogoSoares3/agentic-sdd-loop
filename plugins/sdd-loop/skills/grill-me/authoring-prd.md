# Grilling to author a `PRD.md` (with the stakeholder)

> **Load this on demand** when the grilling task is **authoring a missing `PRD.md`**. Apply `grill-me`'s
> shared interview method (in `SKILL.md`) — this file carries only what's **PRD-specific**: the targets to
> grill and the hand-off. Do not restate the method here.

**Author a missing `PRD.md` (with the stakeholder).** The repo has no product truth to synthesize. You are
eliciting the raw product truth; **`/to-prd` then projects it into the PRD template** — so **use the profile's
PRD template (`templates/prd/PRD.template.md`, mirrored as the scaffolded `docs/PRD.md`) as your elicitation
checklist**: everything it asks for must be answerable from this interview, or `/to-prd` has to invent it.
Grill in the stakeholder's own terms; don't recite the template's structure back at them.

What to draw out, down the decision tree:

- **Problem** — the pain from the user's / stakeholder's perspective; concrete.
- **Solution** — the approach at product altitude (the *what*). Never the technical *how* — seams, schema,
  API, test mechanism are `ARCHITECTURE.md`'s truth, elicited separately with the engineer.
- **Personas & their user stories** — each persona, and **at least one** "as a … I want … so that …" story
  per persona, so personas → scope → requirements stay one connected chain.
- **Scope & priority (MoSCoW)** — negotiate every capability into **Must / Should / Could / Won't (this
  version)**. This is the stakeholder's sign-off contract **and** it feeds phase-cutting's must-first
  tiebreak, so it is load-bearing — don't settle for a flat "v1 scope"; get the priorities. The **Won't**
  bucket *is* the out-of-scope list (there is no separate out-of-scope section).
- **Requirements** — the functional capabilities (`FR`) **and the app's level & scale as non-functionals**
  (`NFR`): PoC vs MVP vs production; expected load (users / RPS / volume); SLA; data & privacy/compliance;
  scalability & operability — *whichever fit this project*. If a scale that matters is unclear, grill for it
  — it sizes the architecture later.
- **Definition of done** — the checkable, observable acceptance for this version.

Then hand off to **`/to-prd`** to write `PRD.md` — it fills every section (incl. **Personas & user stories**,
every persona with at least one story) and anchors stories / DoD to the `FR`/`NFR` IDs. It still needs
**stakeholder validation** before the spec gate opens.
