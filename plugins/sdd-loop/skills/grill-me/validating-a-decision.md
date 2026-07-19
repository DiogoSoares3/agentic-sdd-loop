# Grilling to validate one escalated decision

> **Load this on demand** when the grilling task is **validating a single escalated `needs-decision`** — the
> loop stopped on a structural / critical / hard-to-reverse call no baseline covers. Apply `grill-me`'s
> shared interview method (in `SKILL.md`), but grill **one decision only**. Do not restate the method here.

**Validate one escalated `needs-decision` (with the engineer).** The loop stopped on a structural /
critical / hard-to-reverse call no baseline covers. Grill **one decision only**, with the **engineer**
for a technical/architecture/behaviour call (or the **stakeholder** for scope). Record the resolution
as a new **ADR** (via **`/to-adr`**) + `ARCHITECTURE.md` update (engineer-owned) or a **PRD amendment** (stakeholder-owned)
— never let the build agent invent it silently. Then the loop resumes and future agents inherit it.
**If the escalated call is weighty enough to need async team sign-off** rather than this one grill,
**suggest** raising a **Request for Comments** (**`/to-rfc`**) instead: it records the options + the team's
decision as `docs/rfcs/RFC-N` (`to-be-validated`); the escalated issue stays parked (its `needs-decision`
is still open) until the RFC is `validated (ADR-NNNN)`, at which point the same `/to-adr` + amendment step
materializes it and the loop re-dispatches. Suggested, never forced — a quick, clearly-owned call just
grills here and writes the ADR.
