---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use to stress-test a plan, to AUTHOR a missing PRD (with the stakeholder) or ARCHITECTURE.md (with the engineer) from scratch, or to validate a single escalated technical decision with the engineer before recording it as an ADR/PRD amendment. Triggers on "grill me", "stress-test", "no PRD/ARCHITECTURE yet", or an SDD `needs-decision` escalation.
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a fact can be found by exploring the environment (filesystem, tools, etc.), look it up rather than asking me. The decisions, though, are mine — put each one to me and wait for my answer.

You're done when every branch of the decision tree has been visited and nothing is left silently assumed. Do not act on it until I confirm we have reached a shared understanding.

**Ground before you grill.** First sweep the repo for material that already exists — a README, a `docs/`
folder, design notes, an existing partial PRD/spec, ADRs, even rich code comments — and read it, so you
interview from a base rather than a blank page. Absorb and reconcile what's there; don't restate it. (A fresh
repo may have nothing — then grill from the PRD + régua.)

## Uses inside the SDD loop

This is the **human-in-the-loop** primitive for the loop: interview the human who **owns the truth** — the
**stakeholder** for product, the **engineer** for technical — then hand the result to the writer skill.
`grill-me`'s job is **elicitation**; the writing belongs to the writers (`/to-prd`, `/to-adr`). The one
exception is `ARCHITECTURE.md` — it has no separate writer skill, so grill-me writes it from the template
once the interview is done.

**The interview method above is shared by every use.** What differs per use — the specific **targets to
grill** and the **hand-off** — lives in a sibling file. **Load ONLY the one that matches the grilling task at
hand, on demand** (each is injected into context just for that task; a generic grill needs none of them):

| When the grilling task is… | Read (on demand) | Truth owner | Produces / hands off to |
|---|---|---|---|
| authoring a missing `PRD.md` | [`authoring-prd.md`](authoring-prd.md) | stakeholder | `/to-prd` writes `PRD.md` → stakeholder validation |
| authoring a missing `ARCHITECTURE.md` | [`authoring-architecture.md`](authoring-architecture.md) | engineer | grill-me writes it from the template (+ ADRs via `/to-adr`) → engineer validation |
| validating one escalated `needs-decision` | [`validating-a-decision.md`](validating-a-decision.md) | engineer (technical) / stakeholder (scope) | an ADR / PRD amendment — or an RFC for a team-level fork |

Read the matching sibling for its specifics; **do not restate the interview method there** — it is
single-sourced above. A **standalone / generic** grill (outside the loop) needs none of the siblings — the
method above is the whole skill.