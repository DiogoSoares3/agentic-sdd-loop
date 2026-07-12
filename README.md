# sdd-loop

An **agentic Spec-Driven Development** methodology for code assistants (Claude Code), packaged as an
installable plugin. **SDD on the outer loop, TDD on the inner loop**, driven from two validated sources
of truth: a stakeholder-validated `PRD.md` and an engineer-validated `ARCHITECTURE.md`.

It is **project-agnostic**. The plugin ships the invariant methodology and tools; each repo supplies one
small `.sdd/profile.md` that parametrizes it for **any** domain — web app, data pipeline, ML / recsys,
library, CLI, and so on.

> This `README.md` lives at the repo root and is **not** part of the installed plugin (the plugin is
> `plugins/sdd-loop/`). It documents what the plugin is and how to set it up.

## Three layers

| Layer | What | Ships where |
|---|---|---|
| **1. Core methodology** | the invariant SDD+TDD loop — state machine, gates, escalation, dispatcher, the two build subagents, the lifecycle/enforcement hooks | `skills/sdd/*` · `agents/*` · `hooks/*` |
| **2. Project profile** | régua, slice, seams, DoD, test command, loop/git knobs | `.sdd/profile.md` *(per repo, via `/sdd-init`)* |
| **3. Tools** | `/to-prd`, `/to-issues`, `/to-adr`, `/bdd`, `/tdd`, `/handoff`, `/grill-me` (+ builtin `/loop`, `/schedule`) | `skills/*` |

## How the loop works

Two validated baselines gate everything. **`PRD.md`** (product truth — **personas & user stories**, MoSCoW
scope + `FR-n`/`NFR-n` requirements + Definition of Done, validated with stakeholders) and
**`ARCHITECTURE.md`** (technical truth — seams, components, a Mermaid container+seams diagram, ADR index,
validated with engineers). Everything below is **derived**: phase PRDs, backlog, tests, code.

- **PLAN** — the bounded **`sdd-phase-opener`** subagent cuts the next epic from the root PRD in
  **dependency order**, with **MoSCoW priority as the must-first tiebreak**, and writes a thin **phase PRD**
  (`docs/phases/phase-N/prd.md`) + backlog — a projection that references the baselines by ID/seam, never a
  second full PRD.
- **`/to-issues`** breaks the phase into **vertical slices** — each **one demoable tracer bullet** (~300
  LOC as the default size anchor) — each carrying a **Gherkin `Scenario:`** (`/bdd`) as its acceptance test.
- **BUILD** — the **main session is the orchestrator**; it dispatches issues **one at a time to a bounded
  `sdd-issue-worker` subagent** via the per-issue **dispatcher**
  (`skills/sdd/dispatcher.md`) — the loop's critical seam, kept atomic, idempotent, minimally-scoped.
  Inside each dispatch runs the **double loop**: the scenario (`/bdd`) is the **always-required** outer
  behaviour test; `/tdd` drives the inner unit loop **when the issue calls for it** (its `Inner loop (TDD)`
  flag, default on) until both are green. Integrity guards (immutable scenario+flag, prove-RED,
  test-first commits, clean re-run) prevent the agent from gaming its own test.

Each issue is built on its **own branch off the integration branch** (`develop`); the loop never commits
to `main`. **Escalation:** a subagent has no back-channel, so when a decision the baselines don't answer
arises (structural/critical) the worker **returns `needs-decision`**; the orchestrator runs **`/grill-me`**
with the engineer (→ ADR) or stakeholder (→ PRD amendment) and **re-dispatches** — the spec grows,
controlled. It never resolves a structural decision on its own.

The loop is **finite** (one iteration = one issue; a phase is bounded by its backlog size) and its
iteration **contract is host-agnostic** — any mechanism that re-enters the dispatcher works: builtin
`/loop` (recommended), a `/schedule` watchdog, or a plain re-invocation of `/sdd`. The context gate is
**hook-driven, not self-measured**: when the harness compacts the main session, the **`SessionStart` hook**
re-injects `PROGRESS.md` on resume — so the loop re-enters itself instead of freelancing (the old "agent
guesses ~40% context" trigger was impossible and is gone; there is no `PreCompact` handoff because that hook
can't inject context into the model). Recovery = `SessionStart` re-inject **+** RECORD-after-every-issue
keeping `PROGRESS.md` current. A **clean boundary** (phase drained / project done) needs no handoff — files
fully describe it. State lives entirely in files, so any fresh context resumes from exact position. With
**`auto-merge` + `continuation: auto`** the loop runs unattended, stopping only for a genuine PRD/ARCHITECTURE
decision.

## Architecture — main orchestrator + bounded subagents + hooks

One rule explains the whole shape:

> **The long-running coordinator lives in the MAIN session** — only it receives the `SessionStart`
> lifecycle hook that re-primes it after compaction. **Subagents are bounded leaves** (a phase cut, or one
> issue), because a subagent gets no lifecycle hook and auto-compacts **silently**, so it must never hold
> work it can't checkpoint from files.

```
MAIN SESSION = phase orchestrator   (you, running /sdd; re-driven by /loop)
│  • holds the state machine + the re-prime gate; survives compaction via hooks
│  • spawns bounded subagents, relays their status, resolves escalations via /grill-me
│
├─ PLAN a phase  → spawn  [sdd-phase-opener]   reads PRD+ARCH+ADRs → writes phase PRD + backlog → returns
│
└─ BUILD, one issue at a time → spawn [sdd-issue-worker]   double loop → land per merge policy → returns report
        │  (needs an existing ADR/PRD/ARCH? it READS it itself — the orchestrator is not a file server)
        └─ hits an uncovered structural decision? → returns `needs-decision`
               → orchestrator runs /grill-me with the human → new ADR / PRD amendment → re-dispatches
```

**Two agents** (`agents/`), each self-contained and bounded to one context window:

| Agent | Job | Returns |
|---|---|---|
| `sdd-phase-opener` | cut ONE phase: derive the epic, write its phase PRD + backlog (scenarios + TDD flags) | `phase N opened · M issues` |
| `sdd-issue-worker` | build ONE issue to green via the BDD/TDD double loop, land per merge policy | `green` / `blocked` / `needs-decision` / `needs-revalidation` |

**Three hooks** (`hooks/`), self-gating (silent no-op outside an SDD project; the `+hook` guard bites only
when the profile enables it; the `SubagentStop` guard fails open on anything but our two agents) — this is
how context injection and enforcement become **deterministic** instead of relying on the agent's
self-discipline:

| Hook | Fires | Does |
|---|---|---|
| `SessionStart` (resume\|compact) | main session resumes/compacts | **re-injects** `PROGRESS.md` + the re-prime checklist (via `additionalContext`) so the loop re-enters instead of freelancing — the one load-bearing compaction-survival mechanism |
| `PreToolUse` (Edit\|Write) | any implementation edit, incl. inside subagents | **test-first enforcement** (`integrity: +hook`) — denies impl edits on an `issue/*` branch before a test is committed |
| `SubagentStop` | a bounded subagent (phase-opener / issue-worker) finishes | **verifies the exit** — blocks a "green" with no committed test, or an "opened" with no backlog; lets honest `blocked`/`needs-decision` returns through |

There is deliberately **no `PreCompact` hook**: `PreCompact` cannot inject context into the model (it can
only run a command or block), so a "flush reminder" there never reaches the agent — recovery lives in
`SessionStart` + RECORD-after-every-issue instead. And there is no subagent-side compaction hook at all, so
a subagent that overflows compacts undetectably — which is exactly why the coordinator must be the main
session and subagents must be bounded to one window. The old flat-supervisor pattern is **retired** for
putting the coordinator in the wrong place.

> **Host caveat:** the hook↔subagent lifecycle semantics this design leans on (`SessionStart` is
> main-session-only; subagents get no compaction hook and compact silently; `PreToolUse` and `SubagentStop`
> fire for subagents) are per current Claude Code docs — confirm them on your host, they are load-bearing.
> `${CLAUDE_PLUGIN_ROOT}` inside hook
> commands is not formally documented; if your host doesn't resolve it, point the hook at an absolute path.

## Artifacts it produces

| File | What | Authored / validated by |
|---|---|---|
| `docs/PRD.md` | root product truth — personas & user stories, MoSCoW scope, `FR-n`/`NFR-n`, DoD | `/to-prd` → **stakeholders** |
| `docs/ARCHITECTURE.md` | technical truth — seams, components, Mermaid diagram, ADR index | `/grill-me` + template → **engineers** |
| `docs/adrs/*.md` | closed decisions (from `templates/arch/adr.template.md`) | **`/to-adr`** — recorded wherever a decision closes (grill / build / escalation) |
| `docs/phases/phase-N/prd.md` | thin phase projection (derived, no sign-off) | PLAN step |
| `docs/phases/phase-N/backlog.md` | that phase's vertical issues + Gherkin scenarios | `/to-issues` + `/bdd` |
| `docs/PROGRESS.md` | durable loop state + the `SDD-CURSOR` resume block (single global cursor) | the loop |
| `.sdd/profile.md` | the per-repo configuration (below) | `/sdd-init` |

```
docs/
  PRD.md                    # product baseline (MoSCoW)            — stakeholders
  ARCHITECTURE.md           # technical baseline (+ Mermaid diagram) — engineers
  adrs/NNNN-*.md            # closed decisions (global)
  phases/
    phase-1/prd.md          # thin projection of epic 1
    phase-1/backlog.md      # epic 1's issues
    phase-2/prd.md
    phase-2/backlog.md
  PROGRESS.md               # single global loop cursor
.sdd/profile.md             # configuration
```

## Install (local, for testing)

```
/plugin marketplace add <path-to-this-repo>   # the repo root (holds .claude-plugin/marketplace.json)
/plugin install sdd-loop@sdd-loop
```

## Configure — there are no shell env vars

All runtime configuration is the **`.sdd/profile.md`** file, scaffolded and filled by `/sdd-init` (it
interviews you one slot at a time). The only actual environment variable, `${CLAUDE_PLUGIN_ROOT}`, is set
by the harness — you never touch it.

**How to set a knob:** run `/sdd-init` and answer each prompt, or edit its slot in `.sdd/profile.md`
directly at any time. Leaving the recommended value = accepting the default. `/sdd` refuses to run while
any slot still holds placeholder text. The knobs:

| Slot | Default | Options / notes |
|---|---|---|
| **Régua** | — | the single dominant decision filter |
| **Sources of truth** | `docs/PRD.md`, `docs/ARCHITECTURE.md` | paths + who validates each |
| **Vertical slice** | — | what a tracer slice cuts through in this domain |
| **Issue granularity** | ~300 LOC | anchor for one demoable tracer bullet (LOC is a proxy) |
| **Seams** | — | where tests intercept (prefer existing, highest, fewest) |
| **Fakes / fixtures** | — | how tests avoid live infra |
| **Definition of Done** | — | per-phase gates |
| **Phase-cutting rule** | — | how epics are sized & ordered |
| **Test command(s)** | — | the command that proves a slice green |
| **Continuation mode** | `ask` | gate at a **boundary/resume**: `ask` (alive session shows the resume cursor + next action and asks before dispatching) \| `auto` (unattended; proceed without asking) |
| **Backlog review** | `auto` | gate at **PLAN** (phase scope): `auto` (build straight away) \| `confirm` (pause after `/to-issues` to approve/edit the backlog) |
| **Integrity enforcement** | `prose+git +hook` | base + shipped `PreToolUse` guard (deny impl edits before a **BDD test** is committed on an `issue/*` branch — gates the always-required outer test, not the TDD flag). Add `+verifier` (agent) for a diff re-read. `SubagentStop` verify is always on regardless. |
| **PR provider** | `none` | `none` (local merge) \| `gh` \| `bitbucket-mcp` |
| **Merge policy** | `auto-merge` | `auto-merge` (unattended) \| `human-review` (PR gate; needs a provider) |
| **Git branches** | `main` / `develop` | protected (never committed) / integration; issues on `issue/<id>-<slug>` |
| **Paths** | `docs/…` | baselines, PROGRESS, phases dir — **relocatable; agents, skills & the hooks all read the locations from here** |

### Prerequisites (only if you opt into them)

- **`human-review` or PR provider `gh`** → the `gh` CLI installed and `gh auth status` authenticated.
- **PR provider `bitbucket-mcp`** → the Bitbucket MCP server configured and reachable.
- **`continuation: auto`** → for a truly unattended run; pair with a `/schedule` watchdog for crash recovery.
- **Unattended crash recovery** → register a watchdog (`/schedule` or cron running `/sdd`) that
  re-triggers the loop after a session death. A no-op when healthy.
- **Earlier auto-compaction (optional)** → the auto-compact threshold is **not** a plugin knob and **not**
  settable via `.claude/settings.json`'s `env` block (that only reaches subprocesses). To make the main
  session compact sooner, `export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=<pct>` in your shell **before** launching
  Claude Code (it only lowers, never raises past the internal ~83% cap, and doesn't target subagents — keep
  those bounded instead).

### Example (a filled `.sdd/profile.md`, abridged)

```markdown
## Régua
Latency p95 < 100ms on the redirect hot path — nothing lands that degrades reads.

## Test command(s)
pytest -q

## Loop
- Continuation mode: auto
- Backlog review: auto
- Integrity enforcement: prose+git +hook

## Git strategy
- Protected: main   · Integration: develop   · Issue branch: issue/<id>-<slug>
- PR provider: gh    · Merge policy: auto-merge

## Paths
- Phases dir: docs/phases/   · Durable state: docs/PROGRESS.md
```

For an **unattended** run, the fully-autonomous combination is `merge policy: auto-merge` +
`continuation: auto` + a `/schedule` watchdog. For a **supervised** run, keep `continuation: ask` (the
default — it asks before continuing at each boundary) and/or a **human gate per phase** via `merge policy:
human-review` (with a provider) and/or `backlog review: confirm`.

## Use

```
/sdd-init          # scaffold .sdd/profile.md + PROGRESS.md + PRD/ARCHITECTURE skeletons, fill the profile
# --- author & validate the two baselines (the spec gate) ---
# have the material?  /to-prd synthesizes PRD.md;  write ARCHITECTURE.md from templates/arch/ + engineer
# nothing yet?        /grill-me authors them by interview — stakeholder for PRD, engineer for ARCHITECTURE
/sdd               # run the loop: PLAN phase → select slice → BDD+TDD → land → record → gate → continue
```

`/sdd` reads `.sdd/profile.md` and **refuses to build until the spec gate** (validated PRD +
ARCHITECTURE) is green — and until every profile slot is filled with real values. It keeps durable state
in `PROGRESS.md` and drives iterations via `/loop` (or the `auto` supervisor / a re-invocation of `/sdd`).

## Design rules

- **Rule of three:** automate a step only after the manual step has hurt 3×. The process must not become
  a product.
- **Determinism lives in files** (`PROGRESS.md` = state, `.sdd/profile.md` = config), not in soft
  skill-to-skill chaining — that is what makes every dispatch safe to replay.
- **Two sources of truth, human-validated;** everything else is derived. Change flows up as a controlled
  amendment, never a silent edit.
- **Deliverables stay plugin-agnostic.** `PRD.md` / `ARCHITECTURE.md` / ADRs read for any stakeholder or
  engineer — the plugin mechanics (`/bdd`, `/tdd`, the loop, the cursor) live in the profile & skills, and
  the orchestrator talks to you in plain product/engineering terms, never internal jargon.
- **Simple > flexible.** One régua governs every decision.
