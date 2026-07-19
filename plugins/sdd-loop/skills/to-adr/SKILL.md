---
name: to-adr
description: Write ONE Architecture Decision Record to the repo's ADR directory from a decision already reached (via /grill-me, or a needs-decision a human resolved) — a thin writer, not a decision-maker. Picks the next ADR number, fills the ADR template, names the discarded alternative, and links it into ARCHITECTURE.md's decisions index. Orchestrator / human-in-the-loop level; a build worker escalates needs-decision instead of calling this.
disable-model-invocation: false
---

This skill **materializes an already-reached decision as an ADR** — it does not decide anything. The
decision comes from `/grill-me` (authoring/validating a baseline) or from a `needs-decision` a human has
already resolved. It mirrors `/to-prd`: the thinking happens elsewhere; this just writes it down, the same
way every time.

Use it **wherever a decision closes along the loop** — while authoring `ARCHITECTURE.md`, during the PRD
grill, at a phase/issue decision, or after a `needs-decision` escalation. It is **not forced**: capture a
decision only when a future agent would need to know it. A build **worker never calls this** — it escalates
`needs-decision`, and the orchestrator (with the human) resolves and records.

**A decision may reach this skill via a validated RFC.** For a weighty fork the team validated
asynchronously, the accepted `docs/rfcs/RFC-NNNN` is the closed decision — record it as
an ADR here (set the **Origin** line to `RFC-NNNN accepted`), then **flip that RFC's Status to
`validated (ADR-<this NNNN>)`** and fill its Outcome, so the RFC points at the ADR it produced. The RFC is
the proposal; this ADR is the durable record.

## Process

1. **Resolve paths from `.sdd/profile.md` → `## Paths` — never hardcode `docs/`.** From the **Baselines**
   line take the **ADRs directory** (the backtick-quoted path after "ADRs", default `docs/adrs/`) and the
   **`ARCHITECTURE.md`** path (the "technical truth" path, default `docs/ARCHITECTURE.md`). A project may
   relocate either out of `docs/` — honor what the profile states; fall back to the defaults only if it is
   silent. Create the ADRs directory if it doesn't exist yet.
2. **Pick the next number.** Scan the ADRs directory for existing `ADR-NNNN…` files, take the highest,
   add one, zero-pad to four digits (first ADR = `ADR-0001`). File name: `ADR-<NNNN>-<kebab-title>.md`.
3. **Write from `${CLAUDE_PLUGIN_ROOT}/templates/arch/adr.template.md`** — fill the title, status
   (`proposed` unless the decision is already accepted), date, deciders, and the **Origin** line (which
   capture point this came from). Fill **Context** (what forced it — optionally the PRD requirement/constraint
   it serves; not every ADR maps to one, and that's fine), **Decision**, **Discarded alternatives** (name at
   least the rejected option and why), and **Consequences**. Keep each section tight — an ADR is a record,
   not an essay.
4. **Index it.** Add one line under `ARCHITECTURE.md`'s **Key decisions (ADRs)** section linking to the new
   file. Skip this gracefully if `ARCHITECTURE.md` doesn't exist yet (e.g. an ADR raised during the PRD grill,
   before the technical baseline is authored).
5. **One ADR per call.** If several decisions closed at once, invoke the skill once per decision so each gets
   its own number and file.

Do not publish to any issue tracker. Do not invent a decision the human hasn't made — that is `/grill-me`'s job.
