---
name: to-prd
description: Turn the current conversation into a root/product-level PRD and write it to a local markdown file — no interview, just synthesis of what you've already discussed. (Not for SDD phase PRDs — those are projected by the loop's PLAN step.)
disable-model-invocation: false
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already — **including any documentation already present** (README, `docs/`, design notes, an existing partial PRD/spec) to ground the PRD in what's there, not a blank page. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

2. **Seams are not the PRD's concern in the SDD loop** — they are `ARCHITECTURE.md`'s truth (authored with the engineer via `/grill-me`), and the root PRD must not own or restate the technical "how". Skip straight to step 3. *(Standalone only: optional seam-sketching guidance lives in [`standalone.md`](standalone.md).)*

3. **Choose the structure, then write.** If the caller names a template, write to **that** one — inside the SDD loop this is the structure named in `.sdd/profile.md` ("PRD template for `/to-prd`", default `templates/prd/PRD.template.md`), or a path passed as an argument. Only when **no** template is specified (standalone use) fall back to the generic template in [`standalone.md`](standalone.md).

   **Inside the SDD loop the profile template wins**, because it (a) prioritizes scope with a **MoSCoW** table for stakeholders to sign off and numbers requirements `FR-n`/`NFR-n` so phases and DoD can anchor to IDs, and (b) deliberately omits the technical "how" — implementation, schema, API contracts, testing decisions/seams — since that is `ARCHITECTURE.md`'s job, not the PRD's. Do **not** pull those into an SDD PRD.

   **Fill every section the template asks for — do not leave a heading with only its placeholder.** In particular, populate **Personas & user stories** from the conversation: name each persona and give it **at least one** story in "As a <persona>, I want <capability>, so that <benefit>" form, anchored to the `FR`/`NFR` ID(s) it motivates. A persona with no stories is an incomplete PRD.

   **This skill writes the root/whole-product PRD** (SDD root, or standalone use) — synthesis from the conversation + codebase, optionally after `/grill-me`, flagged for **human validation**. It does **not** write **phase** PRDs: a phase PRD is a deterministic **projection** of the already-validated baselines into `templates/prd/phase-PRD.template.md`, written by the SDD loop's PLAN step — there is no conversation to synthesize there, so it does not route through this skill.

   Write to the profile's configured **PRD path** (its *Sources of truth* / *Baselines* location — the same file `/sdd-init` scaffolded, which a project may have relocated out of `docs/`), or to a path passed as an argument. Fall back to `docs/PRD.md` only in standalone use with no profile. Never hardcode `docs/` when a profile says otherwise. Do not publish to any issue tracker and do not apply labels.

> **Standalone use (outside the SDD loop)** — the optional seam-sketching (step 2) and the generic fallback
> PRD template live in [`standalone.md`](standalone.md), loaded on demand. Inside the loop you never need it:
> the profile's template wins.