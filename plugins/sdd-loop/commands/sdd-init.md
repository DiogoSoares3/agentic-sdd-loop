---
description: Bootstrap the SDD loop in the current repo — scaffold .sdd/profile.md (Layer 2), PROGRESS.md, and PRD/ARCHITECTURE skeletons, then interview the user to fill the profile slots.
argument-hint: "[project domain — freeform, e.g. web app · data pipeline · ML · library · CLI · dashboard] (optional)"
---

# Initialize the SDD loop in this repo

The plugin ships the invariant methodology (Layer 1) and the tools (Layer 3). This command creates
the **only per-project file**: `.sdd/profile.md` (Layer 2), plus the durable state and spec skeletons.

## Steps

1. **Detect / confirm the project's domain** from `$ARGUMENTS` or by exploring the repo. The domain is
   **open, not a fixed menu** — a web app, a data pipeline , an ML system, a dashboard, 
   software library, a CLI, a game, an infra service, whatever fits. It is used **only** to propose
   sensible profile defaults in step 3, never as a behaviour switch, so infer whatever describes the repo.
   State your guess; ask only if ambiguous.

2. **Create the files** if they do not already exist (never clobber existing ones — report and skip):
   - `.sdd/profile.md` — from `${CLAUDE_PLUGIN_ROOT}/templates/profile.template.md`.
   - `docs/PROGRESS.md` (the profile's durable-state path) — from `${CLAUDE_PLUGIN_ROOT}/templates/PROGRESS.template.md`.
   - `docs/PRD.md` skeleton — from `${CLAUDE_PLUGIN_ROOT}/templates/prd/PRD.template.md`, marked
     *DRAFT — awaiting stakeholder validation*.
   - `docs/ARCHITECTURE.md` skeleton — from `${CLAUDE_PLUGIN_ROOT}/templates/arch/ARCHITECTURE.template.md`,
     marked *DRAFT — awaiting dev validation*.
   In each created file, replace the `<PROJECT NAME>` title placeholder with the repo's real project name
   (an unfilled `<…>` token trips `/sdd`'s profile gate).

3. **Fill the profile slots** by interviewing the user briefly (one question at a time). The slots:
   - **Régua** — the single dominant constraint that filters every decision.
   - **Sources of truth** — paths + who validates each (`PRD.md` → stakeholders, `ARCHITECTURE.md` → devs).
   - **Spec gate** — what must be true to leave SPEC and start building (default: `PRD.md` validated with
     stakeholders AND `ARCHITECTURE.md` validated with devs).
   - **Vertical slice** — what a tracer-bullet slice cuts through in THIS domain.
   - **Issue granularity** — one demoable tracer bullet as the unit, ~300 LOC as the default anchor; adjust
     the number (or the domain's own sizing unit) if this domain's slices run larger or smaller.
   - **Seams** — where tests intercept behavior (prefer existing, highest, fewest).
   - **Fakes/fixtures** — how tests avoid live infra.
   - **DoD gates** — what "done" means per phase.
   - **Phase-cutting rule** — how epics are sized and ordered.
   - **Test command(s)** — the exact command that proves a slice green.
   - **Git strategy** — protected branch (default `main`, never committed to), integration branch
     (default `develop`), issue branch naming (`issue/<id>-<slug>`), **PR provider** (`none` default |
     `gh` | `bitbucket-mcp`), and **merge policy** (`auto-merge` default — land on green+checks, fully
     autonomous | `human-review` — open a PR, non-blocking, human merge flips `in-review → done`).
     `human-review` **requires** a provider: if none is configured/available, default to `auto-merge`
     (with `none` provider → local merge into the integration branch). Confirm the provider is reachable
     (`gh auth status` / the Bitbucket MCP) before selecting `human-review`.
   - **Dispatch mode** — `subagent` (recommended; the main-session orchestrator spawns a fresh
     `sdd-issue-worker` per issue, and `sdd-phase-opener` to cut each phase — requires subagent support) or
     `reprime` (host-agnostic fallback; no subagents, the main session runs each issue inline). Both use the
     same branch-per-issue flow; the mode only changes who holds the context.
   - **Handoff mode** — `manual` (default; at a boundary a human starts a clean session, which the
     `SessionStart` hook re-primes) or `auto` (self-continuing; the orchestrator keeps dispatching workers
     and its own overflow is caught by the `PreCompact`/`SessionStart` hooks + `/loop` — no flat supervisor).
     `auto` **requires subagent support**; if the host lacks it, default to `manual`. For unattended runs,
     offer to register a **scheduled watchdog** (`/schedule` running `/sdd`) that re-triggers after a session death.
   - **Backlog review** — `auto` (default; the cut phase backlog goes straight to build) or `confirm`
     (pause after `/to-issues` to approve/edit the backlog before building).
   - **Integrity enforcement** — `prose+git` (default; immutable scenario, RED proof, test-first commit,
     clean re-run) plus optional `+verifier` (independent agent re-reads the branch/PR diff for
     test-gaming) and/or `+hook` (block edits to test paths while green).
   - **Phases dir + PROGRESS path** — default `docs/phases/` (each epic → `docs/phases/phase-N/prd.md` +
     `backlog.md`) and a single global `docs/PROGRESS.md`.
   For each, propose a recommended default for the detected project type; let the user correct it.
   Leave **no** placeholder behind: every `<…>` token and every `> e.g.` example line in `.sdd/profile.md`
   must end up replaced with a real, project-specific value — `/sdd` refuses to run while any slot still
   holds template text.

4. **Tell the user the next move:** draft & validate `PRD.md` and `ARCHITECTURE.md`, then run `/sdd`
   to start the loop. Nothing gets built before the spec gate. If the repo has **no** PRD/ARCHITECTURE
   material to synthesize from, point them at **`/grill-me`** to author these by interview — the
   **stakeholder** for `PRD.md`, the **engineer** for `ARCHITECTURE.md` — before `/sdd`.
