---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable issues recorded in a local markdown backlog file using tracer-bullet vertical slices.
disable-model-invocation: false
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a path or reference to a source plan/PRD as an argument, read its full content.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

<vertical-slice-rules>

- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Any prefactoring should be done first
- **Granularity — one demoable tracer bullet, ~300 LOC as the anchor:** the real unit is **one thin,
  demoable behaviour** end-to-end; **~300 LOC is the concrete default anchor** for that size — a norte to
  aim at, not a straitjacket. If a slice would clearly blow past it, split it; if several would each be
  trivially small, merge them. LOC is only a **proxy** — some domains size differently (a data slice by
  model+tests, an ML slice by feature+eval) — so when the number conflicts with demoability or the régua,
  demoability and the régua win. Tune the anchor per project via `.sdd/profile.md`.

</vertical-slice-rules>

### 4. Sanity-check the granularity

Self-check the breakdown against the **~300 LOC** anchor (one demoable tracer bullet) and the dependency
graph — split anything too coarse, merge anything trivially small.

**Inside the SDD loop this is an internal, derived artifact** (the assistant's scrum/kanban layer) — the
two validated baselines (root `PRD.md` + `ARCHITECTURE.md`) already gate the work, so do **not** block on
user approval of the breakdown; size it with the heuristic + régua and proceed.

**Only when run standalone** (outside the loop), optionally present the breakdown as a numbered list —
Title / Blocked by / User stories covered — and confirm granularity and dependencies before recording.

### 5. Record the issues in a local backlog file

**Idempotent append (safe replay):** before writing, check the backlog for issues already recorded for this phase/parent and skip those — re-running after an interrupt must not duplicate. For each *new* slice, append an entry to the phase's backlog file (in the SDD loop: `docs/phases/phase-N/backlog.md`; standalone: the path from the user's argument, or a default under `docs/`). Use the issue body template below. Do not publish to any issue tracker and do not apply triage labels.

Record issues in dependency order (blockers first) so you can reference earlier slices in the "Blocked by" field.

<issue-template>
## Parent

A reference to the parent plan/PRD (path or heading) this slice derives from. Omit if not applicable.

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

Write the slice's behaviour as a **Gherkin `Scenario:`** via `/bdd`, derived from the phase PRD +
`ARCHITECTURE.md`/ADRs. This scenario is the outer-loop (integration/behaviour) test the build agent
realizes before the inner loop (`/tdd`, when required). One behaviour per scenario; state boundaries explicitly.

```gherkin
Scenario: <observable behaviour of this slice>
  Given <state / fixtures — name the seam from ARCHITECTURE.md>
  When <the single action this slice performs>
  Then <the observable outcome that makes the slice demoable>
```

Non-behavioural chores (docs, cleanup) go in a plain checklist beneath the scenario, not inside it:

- [ ] Chore 1
- [ ] Chore 2

## Inner loop (TDD)

`required` (default) | `skipped — <one-line reason>`

Whether the build agent runs the inner **unit TDD** loop for this slice. **Set here at planning time and
immutable to the builder** (exactly like the scenario) — the build agent honours it and must never flip it
to dodge testing. Keep **`required`** whenever the slice has unit-decomposable logic (branching,
algorithms, parsing, state machines). Mark **`skipped`** only when there is no such logic and the Gherkin
scenario already covers the slice end-to-end — declarative/config/glue/data-shaping work, or
model/experiment work where the outer threshold test is the real gate. When `skipped`, the one-line reason
is **mandatory**. The **outer BDD scenario is always required** — this flag never disables it.

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

Do NOT modify the source plan/PRD.