---
name: to-prd
description: Turn the current conversation into a root/product-level PRD and write it to a local markdown file — no interview, just synthesis of what you've already discussed. (Not for SDD phase PRDs — those are projected by the loop's PLAN step.)
disable-model-invocation: false
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already — **including any documentation already present** (README, `docs/`, design notes, an existing partial PRD/spec) to ground the PRD in what's there, not a blank page. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

2. **(Standalone use only — skip this step inside the SDD loop.)** Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better - the ideal number is one. Check with the user that these seams match their expectations.

   **In the SDD loop, do not sketch seams here** — seams are `ARCHITECTURE.md`'s truth (authored with the engineer via `/grill-me`), and the root PRD must not own or restate the technical "how". Skip straight to step 3.

3. **Choose the structure, then write.** If the caller names a template, write to **that** one — inside the SDD loop this is the structure named in `.sdd/profile.md` ("PRD template for `/to-prd`", default `templates/prd/PRD.template.md`), or a path passed as an argument. Only when **no** template is specified (standalone use) fall back to the generic `<prd-template>` below.

   **Inside the SDD loop the profile template wins**, because it (a) prioritizes scope with a **MoSCoW** table for stakeholders to sign off and numbers requirements `FR-n`/`NFR-n` so phases and DoD can anchor to IDs, and (b) deliberately omits the technical "how" — implementation, schema, API contracts, testing decisions/seams — since that is `ARCHITECTURE.md`'s job, not the PRD's. Do **not** pull those into an SDD PRD.

   **Fill every section the template asks for — do not leave a heading with only its placeholder.** In particular, populate **Personas & user stories** from the conversation: name each persona and give it **at least one** story in "As a <persona>, I want <capability>, so that <benefit>" form, anchored to the `FR`/`NFR` ID(s) it motivates. A persona with no stories is an incomplete PRD.

   **This skill writes the root/whole-product PRD** (SDD root, or standalone use) — synthesis from the conversation + codebase, optionally after `/grill-me`, flagged for **human validation**. It does **not** write **phase** PRDs: a phase PRD is a deterministic **projection** of the already-validated baselines into `templates/prd/phase-PRD.template.md`, written by the SDD loop's PLAN step — there is no conversation to synthesize there, so it does not route through this skill.

   Write to the profile's configured **PRD path** (its *Sources of truth* / *Baselines* location — the same file `/sdd-init` scaffolded, which a project may have relocated out of `docs/`), or to a path passed as an argument. Fall back to `docs/PRD.md` only in standalone use with no profile. Never hardcode `docs/` when a profile says otherwise. Do not publish to any issue tracker and do not apply labels.

**Fallback template — standalone use only. The SDD loop uses the profile's template instead (it splits
the technical "how" out into `ARCHITECTURE.md`); this generic one folds "how" and "what" together.**

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>