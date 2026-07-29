---
description: Bootstrap the SDD loop in the current repo — scaffold .sdd/profile.md (Layer 2), PROGRESS.md, and PRD/ARCHITECTURE skeletons, then interview the user to fill the profile slots.
argument-hint: "[project domain — freeform, e.g. web app · data pipeline · ML · library · CLI · dashboard] (optional)"
---

# Initialize the SDD loop in this repo

The plugin ships the invariant methodology (Layer 1) and the tools (Layer 3). This command creates
the **only per-project file**: `.sdd/profile.md` (Layer 2), plus the durable state and spec skeletons.

> **Speak standard technical language — never leak the plugin's internal jargon.** Throughout this
> command (detecting the domain, interviewing one slot at a time, reporting the next move), translate
> the mechanics into the domain and engineering terms the user already speaks. Do **not** surface
> internal names like `sdd-phase-opener`, `sdd-issue-worker`, `needs-decision`, the
> `SDD-CURSOR`, "outer/inner loop", or "dispatcher". Explain each profile slot in plain terms — *what*
> it controls and why — rather than by its internal knob name. This is the same rule the `/sdd` skill
> follows; apply it here too, and the reminder is carried into the generated `.sdd/profile.md` so every
> downstream agent inherits it.

## Steps

1. **Detect / confirm the project's domain** from `$ARGUMENTS` or by exploring the repo. The domain is
   **open, not a fixed menu** — a web app, a data pipeline , an ML system, a dashboard, 
   software library, a CLI, a game, an infra service, whatever fits. It is used **only** to propose
   sensible profile defaults in step 3, never as a behaviour switch, so infer whatever describes the repo.
   State your guess; ask only if ambiguous.

2. **Create the files** if they do not already exist (never clobber existing ones — report and skip).
   The locations below follow the profile's **Paths** + **Sources of truth** slots. If the user wants the
   baselines / `PROGRESS.md` / phases dir **anywhere other than `docs/`**, confirm those path slots **first**
   (jump to step 3's Paths / Sources-of-truth questions) and create the files at the chosen locations —
   every downstream agent, skill, and hook reads these locations from the profile, so they must agree.
   - `.sdd/profile.md` — from `${CLAUDE_PLUGIN_ROOT}/templates/profile.template.md`.
   - `docs/PROGRESS.md` (the profile's durable-state path) — from `${CLAUDE_PLUGIN_ROOT}/templates/PROGRESS.template.md`.
   - `docs/PRD.md` skeleton — from `${CLAUDE_PLUGIN_ROOT}/templates/prd/PRD.template.md`, marked
     *DRAFT — awaiting stakeholder validation*.
   - `docs/ARCHITECTURE.md` skeleton — from `${CLAUDE_PLUGIN_ROOT}/templates/arch/ARCHITECTURE.template.md`,
     marked *DRAFT — awaiting engineer validation*.
   In each created file, replace the `<PROJECT NAME>` title placeholder with the repo's real project name
   (an unfilled `<…>` token trips `/sdd`'s profile gate).

3. **Fill the profile slots** by interviewing the user briefly (one question at a time).

   > **Signal the consequential slots — don't let the user skim past these four.** Most slots have safe
   > defaults, but four carry outsized consequence:
   > - **Paths** *(most important)* — where `PRD.md` / `ARCHITECTURE.md` / `PROGRESS.md` / the phases and ADRs dirs
   >   live. **Everything downstream — the agents, the skills, and the `SessionStart` re-prime + `SubagentStop`
   >   verify hooks — reads these locations from the profile.** If the user wants the main `.md` files outside
   >   `docs/`, set this here (and create the files there in step 2). Keep every path in backticks so the hooks
   >   can parse it (the re-prime reads the **Durable state** line; the verify guard reads the **Phases dir** line).
   > - **Git strategy** — protected/integration branch, PR provider, merge policy; wrong values land code on the
   >   wrong branch or stall the loop.
   > - **Continuation mode + Backlog review** *(the loop knobs)* — whether the loop pauses for a human at a
   >   boundary / after planning, i.e. supervised vs unattended.
   > - **Integrity enforcement** — the test-first guard level.

   The slots:
   - **Régua** — the single dominant constraint that filters every decision.
   - **Sources of truth** — paths + who validates each (`PRD.md` → stakeholders, `ARCHITECTURE.md` → engineers).
   - **Spec gate** — what must be true to leave SPEC and start building (default: `PRD.md` validated with
     stakeholders AND `ARCHITECTURE.md` validated with engineers).
   - **Vertical slice** — what a tracer-bullet slice cuts through in THIS domain.
   - **Issue granularity** — one demoable tracer bullet as the unit, ~300 LOC as the default anchor; adjust
     the number (or the domain's own sizing unit) if this domain's slices run larger or smaller.
   - **Seams** — where tests intercept behavior (prefer existing, highest, fewest).
   - **Fakes/fixtures** — how tests avoid live infra.
   - **DoD gates** — what "done" means per phase.
   - **Phase-cutting rule** — how epics are sized and ordered.
   - **Phase roadmap** — *do not fill this one, and do not interview for it.* It is derived from the
     **validated** `PRD.md`, which is still a skeleton at this point. Leave the slot's `PENDING` line as-is;
     `/sdd` derives the phases at the spec gate and gets the user's ok on the macro plan before the first
     phase is built. Mention that this is coming, so the user isn't surprised by the question later.
   - **Test command(s)** — the exact command that proves a slice green.
   - **Git strategy** — protected branch (default `main`, never committed to), integration branch
     (default `develop`), issue branch naming (`issue/<id>-<slug>`), **PR provider** (`none` default |
     `gh` | `bitbucket-mcp`), and **merge policy**.
     **The merge-policy default is conditional — probe first, then recommend.** Check whether a provider is
     actually reachable (`gh auth status`, or the Bitbucket MCP responding):
     - **Provider reachable → recommend `human-review`** (open a PR, non-blocking, a human merge flips
       `in-review → done`). A human seeing each slice before it lands is the better default when it costs
       nothing, so offer it as the recommendation — never force it.
     - **No provider → `auto-merge` with provider `none`** (local merge into the integration branch, land on
       green + a local full-suite run). This is a **first-class** configuration, not a degraded one: it is
       what makes the plugin work out-of-the-box in a repo with no GitHub/Bitbucket, and what the unattended
       mode is built on. Do **not** nag the user to install a provider.
     `human-review` **requires** a provider — never select it without confirming one is reachable.
   - **Continuation mode** (gate at a boundary / on resume) — `ask` (default; the alive session pauses at a
     boundary or on re-entry, shows the resume cursor + recommended action, and asks the user whether to
     continue before dispatching) or `auto` (self-continuing/unattended; keeps dispatching without asking,
     its own overflow caught by the `SessionStart` re-prime + `/loop` — no flat supervisor). This is *whether
     to proceed at a boundary*, not who holds context (dispatch is always via subagents). A `blocked` /
     `needs-decision` / `needs-revalidation` stop surfaces to a human either way. For unattended (`auto`)
     runs, offer to register a **scheduled watchdog** (`/schedule` running `/sdd`) that re-triggers after a
     session death.
   - **Backlog review** — `confirm` (default; once a phase is cut, its scope + slice list are presented for a
     **one-time** approval before any build — then the loop runs the **whole** phase straight through, never
     re-asking per issue; only an escalation or the phase draining stops it) or `auto` (the cut goes straight
     to build — for unattended runs). Either way the cut is **reported** to the user; the knob only decides
     whether the loop waits for an ok.
   - **Integrity enforcement** — `prose+git +hook` (**default**): the base (`prose+git`: immutable scenario,
     RED proof, test-first commit, clean re-run) **plus** the shipped `PreToolUse` guard (`+hook`: on an
     `issue/*` branch, deny an implementation edit until a **behaviour/BDD test** is committed — this gates
     the BDD outer test, which is required for every issue, so it is orthogonal to the `Inner loop (TDD)`
     flag; docs/spec/state edits are always allowed). Separately, when a PR is opened the `sdd-merge-resolver`
     re-reads the branch diff for test-gaming and records advisory notes on it — there is no separate verifier
     agent to configure. If the project's test paths don't match the default detector,
     mention setting `SDD_TEST_PATTERN` (else drop to bare `prose+git`). Independently of this knob, the
     `SubagentStop` guard verifies every worker's exit (a "green" with no committed test is blocked) — that
     backstop is always on.
   - **Phases dir + PROGRESS path** — default `docs/phases/` (each epic → `docs/phases/phase-N/prd.md` +
     `backlog.md`) and a single global `docs/PROGRESS.md`.
   - **ADRs + RFCs dirs** — default `docs/adrs/` (closed decisions, written by `/to-adr`) and `docs/rfcs/`
     (Request-for-Comments proposals a team validates before a decision closes, written by `/to-rfc`). Both
     are created on demand at the first write; set the paths here if the project keeps them outside `docs/`.
   For each, propose a recommended default for the detected project type; let the user correct it.
   Leave **no** placeholder behind: every `<…>` token and every `> e.g.` example line in `.sdd/profile.md`
   must end up replaced with a real, project-specific value — `/sdd` refuses to run while any slot still
   holds template text. **The one exception is `## Phase roadmap`**, which stays `PENDING` on purpose (see
   above); `/sdd` tolerates that single marker and resolves it at the spec gate.

4. **Tell the user the next move:** draft & validate `PRD.md` and `ARCHITECTURE.md`, then run `/sdd`
   to start the loop — which will first lay out the project's phases for them to sanity-check, and then ask
   them to ok each phase's scope before it is built. Nothing gets built before the spec gate. If the repo has **no** PRD/ARCHITECTURE
   material to synthesize from, point them at **`/grill-me`** to author these by interview — the
   **stakeholder** for `PRD.md`, the **engineer** for `ARCHITECTURE.md` — before `/sdd`.
