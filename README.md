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
| **1. Core methodology** | the invariant SDD+TDD loop — state machine, gates, escalation, dispatcher, the three bounded subagents, the lifecycle/enforcement hooks | `skills/sdd/*` · `agents/*` · `hooks/*` |
| **2. Project profile** | régua, slice, seams, DoD, test command, loop/git knobs | `.sdd/profile.md` *(per repo, via `/sdd-init`)* |
| **3. Tools** | `/to-prd`, `/to-issues`, `/to-adr`, `/to-rfc`, `/bdd`, `/tdd`, `/grill-me`, `/resolving-merge-conflicts` (+ builtin `/loop`, `/schedule`) | `skills/*` |

## How the loop works

Two validated baselines gate everything. **`PRD.md`** (product truth — **personas & user stories**, MoSCoW
scope + `FR-n`/`NFR-n` requirements + Definition of Done, validated with stakeholders) and
**`ARCHITECTURE.md`** (technical truth — seams, components, a Mermaid container+seams diagram, ADR index,
validated with engineers). Everything below is **derived**: phase PRDs, backlog, tests, code.

- **ROADMAP** — once both baselines are validated and **before anything is built**, `/sdd` derives the
  project's epics in order from the root PRD and **shows you the whole plan** for a quick ok, recording it in
  the profile's **Phase roadmap** slot. You see the shape of the project up front instead of one phase at a
  time. It is **indicative**: every phase is still re-derived at PLAN, and a divergence (an ADR reordered a
  dependency) is *reported* with its reason, never a block. A structural PRD/ARCHITECTURE amendment refreshes
  it on the spot.
- **PLAN** — the bounded **`sdd-phase-opener`** subagent cuts the next epic from the root PRD in
  **dependency order**, with **MoSCoW priority as the must-first tiebreak**, and writes a thin **phase PRD**
  (`docs/phases/phase-N/prd.md`) + backlog — a projection that references the baselines by ID/seam, never a
  second full PRD. The cut is then **presented to you** — scope, DoD, and the slices in order — for a
  **one-time approval per phase** (`backlog review: confirm`, the default; `auto` skips the wait but still
  reports). Approve once and the whole phase builds through without further prompts.
- **`/to-issues`** breaks the phase into **vertical slices** — each **one demoable tracer bullet** (~300
  LOC as the default size anchor) — each carrying a **Gherkin `Scenario:`** (`/bdd`) as its acceptance test.
- **BUILD** — the **main session is the orchestrator**; it dispatches issues **one at a time to a bounded
  `sdd-issue-worker` subagent** via the per-issue **dispatcher**
  (`skills/sdd/dispatcher.md`) — the loop's critical seam, kept atomic, idempotent, minimally-scoped.
  Inside each dispatch runs the **double loop**: the scenario (`/bdd`) is the **always-required** outer
  behaviour test; `/tdd` drives the inner unit loop **when the issue calls for it** (its `Inner loop (TDD)`
  flag, default on) until both are green. Integrity guards (immutable scenario+flag, prove-RED,
  test-first commits, clean re-run) prevent the agent from gaming its own test.

Each issue is built on its **own branch off the integration branch** (`develop`), **created by the
orchestrator before the worker is spawned** — the worker only attaches to it, and never leaves it: it builds
to green, returns `ready-to-land`, and a bounded **lander** does the rebase, the full regression suite and
the merge (or opens the PR). One land path in every mode. That split is not tidiness — every integrity guard
keys on the worker being on an `issue/*` branch, so a worker that merged (and thus checked out `develop`)
used to leave those guards unable to tell a correct landing from a worker that never branched at all. The
loop never commits to `main`. **Escalation:** a subagent has no back-channel, so when a decision the baselines don't answer
arises (structural/critical) the worker **returns `needs-decision`**; the orchestrator runs **`/grill-me`**
with the engineer (→ ADR) or stakeholder (→ PRD amendment) and **re-dispatches** — the spec grows,
controlled. It never resolves a structural decision on its own. For a **weighty fork that needs asynchronous
team sign-off**, the assistant may **suggest** (never force) a **Request for Comments** (**`/to-rfc`** →
`docs/rfcs/`, status `to-be-validated`) — the team validates it out-of-band, and on acceptance it materializes
into an ADR/PRD amendment (`validated (ADR-NNNN)`) and the parked issue resumes; the RFC file's own status is
the truth, so no new loop state is added.

The loop is **finite** (one iteration = one issue; a phase is bounded by its backlog size) and its
iteration **contract is host-agnostic** — any mechanism that re-enters the dispatcher works: builtin
`/loop` (recommended), a `/schedule` watchdog, or a plain re-invocation of `/sdd`. The context gate is
**hook-driven, not self-measured**: when the harness compacts the main session, the **`SessionStart` hook**
re-injects `PROGRESS.md` on resume — so the loop re-enters itself instead of freelancing (the old "agent
guesses ~40% context" trigger was impossible and is gone; there is no `PreCompact` handoff because that hook
can't inject context into the model). Recovery = `SessionStart` re-inject **+** RECORD-after-every-issue
keeping `PROGRESS.md` current. A **clean boundary** (phase drained / project done) needs no handoff — files
fully describe it. State lives entirely in files, so any fresh context resumes from exact position. With
**`auto-merge` + `continuation: auto` + `backlog review: auto`** the loop runs unattended, stopping only for a
genuine PRD/ARCHITECTURE decision.

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
├─ BUILD an issue (serial by default) → orchestrator CREATES issue/<id> → spawn [sdd-issue-worker]
│       │  double loop on that branch → never merges, never leaves it → returns ready-to-land
│       │  (needs an existing ADR/PRD/ARCH? it READS it itself — the orchestrator is not a file server)
│       └─ hits an uncovered structural decision? → returns `needs-decision`
│              → orchestrator runs /grill-me with the human → new ADR / PRD amendment → re-dispatches
│
└─ LAND a queued branch (EVERY mode) → spawn [sdd-merge-resolver]   rebase → resolve conflict IF any
        → FULL regression suite → merge or open PR → returns `landed` / `in-review` / `needs-revalidation`
```

**Three agents** (`agents/`), each self-contained and bounded to one context window:

| Agent | Job | Returns |
|---|---|---|
| `sdd-phase-opener` | cut ONE phase: derive the epic, write its phase PRD + backlog (scenarios + TDD flags) | `phase N opened · M issues` |
| `sdd-issue-worker` | build ONE issue to green via the BDD/TDD double loop, on the branch the orchestrator handed it — **never merges, never leaves that branch** | `ready-to-land` / `blocked` / `needs-decision` / `needs-revalidation` |
| `sdd-merge-resolver` | LAND ONE `ready-to-land` branch — **the single land path, in every mode**: rebase onto the tip, resolve a conflict via `/resolving-merge-conflicts` only if one arises, run the full regression suite, then merge (`auto-merge`) or open the PR (`human-review`) | `landed` / `in-review` / `needs-revalidation` / `needs-decision` / `blocked` |

**Five hooks** (`hooks/`), self-gating (silent no-op outside an SDD project; the `+hook` guards bite only
when the profile enables them; the branch guard only while an issue is `doing`; the `SubagentStop` guard
fails open on anything but the two agents it verifies) — this is how context injection and enforcement become
**deterministic** instead of relying on the agent's self-discipline:

| Hook | Fires | Does |
|---|---|---|
| `SessionStart` (resume\|compact) | main session resumes/compacts | **re-injects** `PROGRESS.md` + the re-prime checklist (via `additionalContext`) so the loop re-enters instead of freelancing — the one load-bearing compaction-survival mechanism |
| `PreToolUse` (Edit\|Write) | any implementation edit, incl. inside subagents | **test-first enforcement** (`integrity: +hook`) — denies impl edits on an `issue/*` branch before a test is committed |
| `PreToolUse` (Edit\|Write) | editing a test that already lives on the integration branch | **regression warning** (`integrity: +hook`, non-blocking) — flags editing a *landed* test on an `issue/*` branch (fix the code, not the test), with a false-positive caveat for shared fixtures |
| `PreToolUse` (Edit\|Write) | any code/test edit while an issue is `doing` | **issue-branch guard** (always on) — denies it on the integration/protected branch, so the loop can't build off an `issue/*` branch. Load-bearing: every other guard keys on that branch and **fails open** without it. Docs/spec/state stay allowed; with the cursor's `Doing: none` it never fires, so a human editing their own repo is untouched |
| `SubagentStop` | a bounded subagent (phase-opener / issue-worker) finishes | **verifies the exit** — blocks a "green" with no committed test, a `required`-TDD issue with no inner-loop checkpoint in `PROGRESS.md`, or an "opened" with no backlog; lets honest `blocked`/`needs-decision` returns through |

> **What the `PreToolUse` guards can and cannot see.** They are registered on **`Edit|Write`**, so they see
> every edit made through those tools — and **nothing written through `Bash`**. A `cat > src/x.py <<EOF`,
> a `sed -i`, a `git apply`, a `python -c` that writes a file: all invisible to test-first, to the
> landed-test warning, and to the branch guard. This is not fixable by widening the matcher — deciding
> whether an arbitrary shell command writes an implementation file means parsing arbitrary shell, which
> fails open in more interesting ways than it closes. The guards also match on **paths, never contents**, so
> a committed empty test satisfies test-first, and an implementation file living under a `spec/` directory
> reads as a test. Treat `+hook` as what it is: a deterministic floor that makes the *honest* path the easy
> one and catches the common slip — not a sandbox against a determined agent. The layers that do see through
> it are `SubagentStop` (re-reads git and the durable files at exit, whatever tool wrote them) and the
> optional `+verifier` (reads the diff's contents).

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
| `docs/adrs/*.md` | closed decisions (from `templates/arch/adr.template.md`) | **`/to-adr`** — recorded wherever a decision closes (grill / build / escalation / a validated RFC) |
| `docs/rfcs/*.md` | Request-for-Comments proposals a team validates before a decision closes (from `templates/rfc/rfc.template.md`); status `to-be-validated` → `validated (ADR-NNNN)` | **`/to-rfc`** — *suggested*, not forced, for a weighty fork needing async team sign-off |
| `docs/phases/phase-N/prd.md` | thin phase projection (derived, no sign-off) | PLAN step |
| `docs/phases/phase-N/backlog.md` | that phase's vertical issues + Gherkin scenarios | `/to-issues` + `/bdd` |
| `docs/PROGRESS.md` | durable loop state + the `SDD-CURSOR` resume block (single global cursor) | the loop |
| `.sdd/profile.md` | the per-repo configuration (below) | `/sdd-init` |

```
docs/
  PRD.md                    # product baseline (MoSCoW)            — stakeholders
  ARCHITECTURE.md           # technical baseline (+ Mermaid diagram) — engineers
  adrs/NNNN-*.md            # closed decisions (global)
  rfcs/NNNN-*.md            # team-validated proposals (to-be-validated → validated (ADR-NNNN))
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
| **Phase roadmap** | `PENDING` | the project's epics in order — **derived** from the validated PRD and okayed by you at the spec gate, before the first phase is built. **Indicative:** each phase is still re-derived at PLAN; a divergence is reported, not blocked. The one slot that may read `PENDING` when `/sdd` starts |
| **Test command(s)** | — | the command that proves a slice green |
| **Continuation mode** | `ask` | gate at a **boundary/resume**: `ask` (alive session shows the resume cursor + next action and asks before dispatching) \| `auto` (unattended; proceed without asking) |
| **Backlog review** | `confirm` | gate at **PLAN** (phase scope): `confirm` (present the cut phase — scope + DoD + slices in order — for a **one-time** approval covering the whole phase, never per issue) \| `auto` (build straight away). The cut is reported either way |
| **Integrity enforcement** | `prose+git +hook` | base + shipped `PreToolUse` guard (deny impl edits before a **BDD test** is committed on an `issue/*` branch — gates the always-required outer test, not the TDD flag). Add `+verifier` (agent) for a diff re-read. `SubagentStop` verify is always on regardless. |
| **PR provider** | `none` | `none` (local merge) \| `gh` \| `bitbucket-mcp` |
| **Merge policy** | *conditional* | `human-review` (PR gate per slice — **the default when a provider is reachable**) \| `auto-merge` (**the default without one**, and the basis of unattended runs; lands on green + a local full-suite run). Both are first-class — the plugin never requires a provider |
| **Git branches** | `main` / `develop` | protected (never committed) / integration; issues on `issue/<id>-<slug>` |
| **Paths** | `docs/…` | baselines, PROGRESS, phases dir — **relocatable; agents, skills & the hooks all read the locations from here** |

### Prerequisites (only if you opt into them)

- **`human-review` or PR provider `gh`** → the `gh` CLI installed and `gh auth status` authenticated.
  `/sdd-init` probes for this: found → it recommends `human-review`; not found → `auto-merge` + provider
  `none`, which is a fully supported setup, not a fallback.
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

## Phase roadmap
- Phase 1 — Redirect hot path: FR-1, NFR-1 · DoD: p95 < 100ms under the load fixture
- Phase 2 — Link management: FR-2, FR-3 · DoD: a link survives create → resolve → expire

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
`continuation: auto` + `backlog review: auto` + a `/schedule` watchdog. For a **supervised** run, keep the
defaults — `backlog review: confirm` (approve each phase's scope once, before it is built) and
`continuation: ask` (ask before continuing at each boundary) — and optionally add a PR gate via `merge
policy: human-review` (with a provider).

## Use

```
/sdd-init          # scaffold .sdd/profile.md + PROGRESS.md + PRD/ARCHITECTURE skeletons, fill the profile
# --- author & validate the two baselines (the spec gate) ---
# have the material?  /to-prd synthesizes PRD.md;  write ARCHITECTURE.md from templates/arch/ + engineer
# nothing yet?        /grill-me authors them by interview — stakeholder for PRD, engineer for ARCHITECTURE
/sdd               # ok the phase roadmap, then loop: PLAN phase → ok its scope → BDD+TDD → land → record → gate
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

---

### Testing Suite

*   **Deterministic Hook Suite (`bash tests/faixa-a.sh`):** Runs the deterministic hook suite, completely independent of any model or network dependencies. It exercises all five core hooks—`SessionStart` re-prime, `PreToolUse` test-first, `PreToolUse` landed-test regression warning, `PreToolUse` issue-branch guard, and `SubagentStop` verify—alongside path-awareness tested against real, throwaway git repositories and profiles.
*   **Sub-suites:** You can also run `tests/subagentstop.sh` and `tests/test-paths.sh` standalone, as these are the specific sub-suites called by the main script.
*   **Parallel / merge-resolver mechanics (`bash tests/parallel-merge.sh`):** A deterministic proof (real `git` + `pytest`, no model) that the `Concurrency: parallel` conflict scenario is sound: two parallel branches really conflict on rebase, a correct resolution makes the **full** suite green, a *weakening* resolution is caught by the regression gate, the landed test stays byte-identical, the landed-test warning fires, and a **multi-item land queue** drains N branches in dependency→backlog order (dependent-before-blocker goes red). Needs `python3`+`pytest`, so it runs on demand rather than inside `faixa-a.sh`.
*   **PR/CI proxy (`bash tests/pr-ci-proxy.sh`):** A deterministic stand-in (real `git` + `pytest`, **no GitHub, no model**) for the `provider`/CI surface: a **bare repo as the remote** + a **merge gate that runs the full regression suite** before landing on a protected branch. Asserts a green feature lands, a *regressing* feature is **rejected** with the protected branch left pristine, and `develop → main` promotion is gated the same way — the isolatable equivalent of `provider: gh` + required checks.
*   **Live End-to-End Run (Faixa B):** To run the live end-to-end execution—driven through a real headless model following the `PLAN` → `/compact` → `CONTINUE` flow to verify compaction survival—refer to the `tests/live/` directory. It needs a logged-in `claude` + network, and is confined by the **OS sandbox**: **bubblewrap** on Linux (`run-bwrap.sh` — `/` read-only, only a throwaway dir writable, `~/.claude` a fresh tmpfs with just the credentials file re-exposed read-only) or **`sandbox-exec`** (seatbelt) on macOS. The `tests/live/parallel/` scenario additionally exercises the `Concurrency: parallel` feature (the merge queue, `sdd-merge-resolver`, and `/resolving-merge-conflicts`).