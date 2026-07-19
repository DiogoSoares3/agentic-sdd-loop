# Grilling to author `ARCHITECTURE.md` (with the engineer)

> **Load this on demand** when the grilling task is **authoring a missing `ARCHITECTURE.md`**. Apply
> `grill-me`'s shared interview method (in `SKILL.md`) — this file carries only the **architecture-specific**
> targets and hand-off. Unlike the PRD there is **no separate writer skill**: grill-me writes
> `ARCHITECTURE.md` from the template once the interview is done. Do not restate the interview method here.

**It realizes the validated `PRD.md`.** One level below it in the hierarchy (PRD = *why/what*, architecture =
*how-to-realize-it*) though both are equal-weight validated baselines. So keep decisions **minimally in
accordance with the PRD** — a seam/decision should trace to the FR/NFR it serves or the régua it satisfies.
Don't force it: this is a sanity check, not a gate. A decision that answers no requirement is *likely*
gold-plating; one that **conflicts** is a `needs-revalidation` back to the stakeholder.

**Ground it in what exists.** For an existing repo, **start by exploring the codebase** — its current
structure, key modules, and where behaviour is already intercepted — so every proposal (decisions, seams,
folder layout) is grounded in what's actually there, not invented in a vacuum. For a greenfield repo there's
little to read, so propose from the PRD + régua.

**Start from the system context, sized to the project's level — only if it fits.** Establish the
application's **level and scale** by realizing the PRD's NFRs (level, load, SLA, scalability, operability);
if a scale that matters isn't in the PRD, flag it to flow up — don't invent product scope. Let that level
**size** how much operational shape to design (deployment, delivery, infrastructure, tooling) —
**proportional, only what this project actually needs**, skipped where it doesn't fit (a prototype needs
almost none; a production system more). Capture the **architecture style only if it fits** the project (a
real, hard-to-reverse fork → an ADR).

**What does NOT belong here.** Conventions, design patterns and coding best practices do **not** go in
`ARCHITECTURE.md` or the ADRs — they live in the user's ambient conventions. Only a *structural* decision
becomes an ADR.

**Interview the engineer for the technical truth:**

- the **seams** — highest, fewest;
- the **test mechanism**;
- the **components / layers** and their responsibilities;
- the **key decisions**;
- the **repository / directory / script structure** — map an existing layout and sanity-check it makes
  sense, or propose one for a fresh repo. The shape of the codebase is part of the architecture, so
  **validate it with the user**.

**Draw the diagrams the template wants.** Ask enough to render them: the components/layers and their
**edges** (who calls/depends on whom, direction of data flow), the external actors + data stores, and
**which boundaries are the seams**. Then write `ARCHITECTURE.md`, rendering the container-and-seams
**Mermaid** overview from those answers — and **validate that overview with the user**: the whole-system
picture must be one they confirm, whatever the project's size.

Add more granular diagrams **only where one would show a fresh agent something the overview can't** (a hot
path the régua cares about, a tricky interaction, a state machine). How many is your read on the project's
complexity — often none or one, no fixed cap — each validated with the user and earning its place (the
régua: prose beats a stale picture).

**Capture weighty decisions as ADRs while you go.** As decisions land, a weighty one — a real fork,
hard-to-reverse, or a stakeholder/engineer call others will inherit — **may be worth an ADR right then**
(write it via **`/to-adr`**, which numbers it and names the discarded alternative), *while* building the
architecture rather than only after. **Nothing forces an ADR per decision** — it's a judgment call on what a
future agent will need to know.

**For a team-level fork, consider an RFC first.** When such a fork has **real competing alternatives and
would benefit from asynchronous, multi-person team sign-off** (not just this session's owner), **suggest —
never force** — formalizing it as a **Request for Comments** (**`/to-rfc`** → `docs/rfcs/`, status
`to-be-validated`): the team comments and validates out-of-band, and once accepted it materializes into the
ADR / `ARCHITECTURE.md` amendment (`validated (ADR-NNNN)`). The light path (grill here → `/to-adr`) stays the
default; the RFC is the opt-in heavy path for a genuinely team-level decision.

**The finished `ARCHITECTURE.md` needs engineer validation** before the spec gate opens on the technical side.
