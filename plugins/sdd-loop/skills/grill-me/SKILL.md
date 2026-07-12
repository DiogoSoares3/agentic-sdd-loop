---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use to stress-test a plan, to AUTHOR a missing PRD (with the stakeholder) or ARCHITECTURE.md (with the engineer) from scratch, or to validate a single escalated technical decision with the engineer before recording it as an ADR/PRD amendment. Triggers on "grill me", "stress-test", "no PRD/ARCHITECTURE yet", or an SDD `needs-decision` escalation.
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Uses inside the SDD loop

This is the **human-in-the-loop** primitive for the loop. Interview the human who **owns the truth** in
question, then hand the result to the writer skill (`/to-prd` for the PRD) — grill-me's job is elicitation.
The **one exception** is `ARCHITECTURE.md`: it has no separate writer skill, so grill-me writes it directly
from the template once the interview is done (item 2 below).

1. **Author a missing `PRD.md` (with the stakeholder).** The repo has no product truth to synthesize.
   Interview the stakeholder down the tree — problem, users, scope of v1, requirements, definition of
   done, out-of-scope — then hand off to **`/to-prd`** to write `PRD.md`. It still needs **stakeholder
   validation** before the spec gate opens.
2. **Author a missing `ARCHITECTURE.md` (with the engineer).** Interview the engineer for the technical
   truth — the **seams** (highest, fewest), the **test mechanism**, components, and the key decisions.
   Ask enough to **draw the diagrams the template wants**: the components/layers and their **edges**
   (who calls/depends on whom, direction of data flow), the external actors + data stores, **which
   boundaries are the seams**, and the régua's **hot path**. Then write `ARCHITECTURE.md` — rendering the
   container-and-seams **Mermaid** diagram (+ optional hot-path) from those answers — plus any
   `docs/adrs/` ADRs. It needs **engineer validation**.
3. **Validate one escalated `needs-decision` (with the engineer).** The loop stopped on a structural /
   critical / hard-to-reverse call no baseline covers. Grill **one decision only**, with the **engineer**
   for a technical/architecture/behaviour call (or the **stakeholder** for scope). Record the resolution
   as a new **ADR** + `ARCHITECTURE.md` update (engineer-owned) or a **PRD amendment** (stakeholder-owned)
   — never let the build agent invent it silently. Then the loop resumes and future agents inherit it.