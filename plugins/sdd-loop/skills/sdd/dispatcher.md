# The dispatcher — main orchestrator + bounded subagents + hooks

This is where context hygiene, resumability and the double loop meet. The architecture has **one rule that
explains everything**:

> **The long, continuous coordinator lives in the MAIN session** (only it gets the `SessionStart`
> lifecycle hook that re-primes it after compaction). **Subagents are bounded leaves** — a phase cut, or
> one issue — because a subagent gets **no lifecycle hook** and auto-compacts **silently**, so it must never
> hold long-running work it can't checkpoint from files.

Everything below follows from that. Get it right and the loop survives compaction, resumes from files, and
never games its own test.

## The three roles

```
MAIN SESSION = the phase orchestrator   (you, running /sdd; re-driven by /loop)
│  • holds the state machine + the re-prime gate
│  • the SessionStart (re-prime) lifecycle hook lives HERE
│  • spawns bounded subagents; relays their status; handles escalation via /grill-me
│  • each subagent's exit is checked by the SubagentStop guard (verify, not coordinate)
│
├─ PLAN a phase  →  spawn  [sdd-phase-opener]   (agents/phase-opener.md — bounded, one phase)
│                     └─ writes docs/phases/phase-N/prd.md + backlog.md → returns status
│
└─ BUILD an issue →  spawn [sdd-issue-worker]   (agents/issue-worker.md — bounded, ONE issue)
                      └─ runs the double loop, lands per merge policy → returns report
```

- **Orchestrator (main session).** Its loop: re-prime → read state → spawn the right subagent for the next
  step → receive one compact status/report → update `PROGRESS.md` + backlog → continue or stop at a gate.
  It **never** builds an issue itself in `subagent` mode; it dispatches. It **never** nests — only the main
  session spawns.
- **`sdd-phase-opener`.** One bounded spawn per phase: derive the next epic from the validated baselines +
  ADRs, write the phase PRD + backlog (issues with a Gherkin `Scenario:` and the `Inner loop (TDD)` flag).
  Builds nothing. Fits one window.
- **`sdd-issue-worker`.** One bounded spawn per issue: the double loop to green, land per merge policy,
  return the report. One issue fits one window — which is exactly why it is a subagent.

Dispatch is **always** via subagents — the whole shape (coordinator in the main session, bounded leaves in
subagents) depends on it, so it is not a knob. Both bounded agents fit one window by design.

## Deterministic context — injected, not requested

The old failure was leaning on the agent to *choose* to re-read files. Now context is **placed** in the
context deterministically:

- **`SessionStart` hook (resume|compact)** → re-injects `PROGRESS.md` + the re-prime checklist (via
  `additionalContext`) every time the main session resumes or compacts. The agent doesn't decide to
  re-prime — the state is already there. This is the **one** load-bearing compaction-survival mechanism;
  real recovery = it **+** RECORD-after-every-issue keeping `PROGRESS.md` current. (There is deliberately no
  `PreCompact` handoff hook: `PreCompact` cannot inject context into the model — it can only run a command
  or block — so a "flush reminder" there never reaches the agent. It was removed; the durable files + this
  re-inject do the job.)
- **Spawn pack** → when the orchestrator spawns a subagent, the pack (Task prompt) is assembled
  deterministically from **file paths**. The subagent then reads those files itself.

> These hooks are shipped in `hooks/` and are **self-gating**: silent no-op outside an SDD project; the
> test-first `PreToolUse` guard only bites when the profile sets `integrity: +hook`; the `SubagentStop`
> verify guard only acts on our two bounded agents and fails open otherwise. (Hook↔subagent lifecycle
> semantics — esp. that `SessionStart` is main-session-only, `PreToolUse`/`SubagentStop` fire for subagents,
> and subagents get no compaction hook so they compact silently — are per current Claude Code docs; confirm
> empirically on your host, they are load-bearing.)

## The context pack (what a subagent gets — and nothing else)

Paths, not contents — the worker reads them itself:

1. `.sdd/profile.md` — régua, seams, DoD, test command, merge policy, integrity level.
2. `PROGRESS.md` — current state.
3. `docs/phases/phase-N/prd.md` — the phase PRD (NOT the whole root PRD).
4. `ARCHITECTURE.md` + the ADRs the issue touches — seam + test mechanism.
5. **The one issue** — its Gherkin `Scenario:`, its `Inner loop (TDD)` flag, boundaries.

Do **not** hand it the full backlog, unrelated phases, or the whole PRD. If it needs another **existing**
spec file, it **reads it itself** — the orchestrator is not a file server, only an escalation resolver.
(`CLAUDE.md` conventions are ambient — inherited by the subagent, not packed.) Every `docs/…` path here is a
**default** — the profile's **Paths** section governs the real locations (a project may relocate them).

## Git strategy (branch-per-issue)

The loop **never commits to a protected branch**. Each issue is built on its own `issue/<id>-<slug>` branch
off the **integration branch** (`develop` by default) and lands there; `main` is human-only. **One branch,
one merge:** all of the issue's work — code, tests, docs, `PROGRESS.md` — lands on that single branch; never
a second branch. Two knobs:

- **PR provider** — `none` (default, local merge) | `gh` | `bitbucket-mcp`. The provider is the PR surface.
- **Merge policy** — how a green branch reaches `develop`:
  - **`auto-merge` (default):** on green **+ passing checks**, land and mark `done` in the same dispatch. No
    `in-review` state; the backlog drains straight to `done`, so the loop runs unattended.
  - **`human-review` (requires a provider):** on green, push + open a PR and stop at `in-review`. The loop
    is **non-blocking** — it moves to the next issue whose blockers are `done`; a human merge flips it to `done`.

```
auto-merge:    todo → doing → done
human-review:  todo → doing → in-review (PR open, green) → done (PR merged)
```

**Selection always requires every blocker to be `done`** (landed on the integration branch).

**Reconcile on prime (both policies):** at the start of every orchestration tick, mark any `in-review`/`doing`
issue whose work is already in the integration branch as `done` (check `gh pr view`, or `git branch
--merged` / log for the `issue/<id>` commits). Files stay the truth; this records a landing that already
happened.

**Prune on `done`:** once an issue lands, remove its leftovers — `git worktree remove` (if a worktree),
`git branch -d` the local branch, and delete the remote branch if pushed (provider "delete on merge", else
`git push origin --delete`). Also sweep already-merged leftovers from earlier issues. **Never prune a
`blocked` / `needs-decision` branch** (local or remote) — that quarantine is a human's to inspect.

## Dispatch (always via subagents)

The orchestrator spawns a fresh `sdd-issue-worker` per issue (optionally in its own git worktree on the
issue branch) and a bounded `sdd-phase-opener` to cut each phase. Truly clean context per issue; the
flag/scenario are re-asserted by the agent definition every spawn, so compaction can't erode them. This is
**not a knob** — the architecture (long-running coordinator in the main session, bounded leaves in
subagents) depends on it, and the plugin ships for a host (Claude Code) that has subagents. The old
`reprime` inline fallback is retired: it put the per-issue build inside the long-running main context — the
exact anti-pattern this design exists to prevent — and it forfeits the `SubagentStop` verify guard.

### Silent subagent compaction — the residual risk, and its defenses
A subagent gets **no lifecycle hook**, so if it overflows mid-work it compacts **silently** and may lose its
place, then return claiming success. Three layers guard this, in order of leverage:
1. **Prevention — bounded size.** One phase / one issue is sized to fit one window (the `~300 LOC` issue
   anchor). Keep it small enough that a worker never approaches its own compaction. This is the real defense.
2. **Detection — the `SubagentStop` guard** (`hooks/sdd-verify-subagent.sh`). At exit it re-reads git/files:
   a worker that reports `green` with **no committed test** on its `issue/*` branch (or an empty branch), or
   a `phase-opener` that reports "opened" with **no non-empty backlog**, is **blocked** (`decision: block`)
   and sent back to fix it. An honest `blocked`/`needs-decision`/`needs-revalidation` return is always let
   through. This converts "compacted and got confused" from a silent success into an explicit retry.
3. **Recovery — the required-TDD checkpoint.** When `Inner loop (TDD): required`, the worker appends a
   one-line checkpoint to `PROGRESS.md` after each inner unit goes green, so a silent mid-issue compaction
   resumes from git + `PROGRESS.md`.

### Isolation (worktrees)
One issue = one worktree = one branch makes the integrity guards mechanical: the clean re-run runs against a
fresh checkout; the test-first two-commit rule is auditable on the branch diff; a `blocked` issue never
lands (discard the worktree, the integration branch stays pristine). Default to **one issue at a time**; do
not run worktrees in parallel unless throughput genuinely demands it.

## Per-issue procedure (the double loop) — carried by `sdd-issue-worker`

```
PRE    reconcile landed issues → done. Select first `todo` whose blockers are all `done`; mark `doing`.
       Branch issue/<id>-<slug> off the freshly-pulled integration branch. Never a protected branch.
OUTER  (BDD)  realize the scenario as the behaviour test at the arch seam → run → it FAILS (feature absent).
       Record the RED output.  [#2]   COMMIT the test alone, before any implementation.  [#3]
INNER  (TDD — only if `Inner loop (TDD)` is `required`)  unit → minimal code → unit green (repeat).
       COMMIT the implementation separately from the test.  [#3]
       When `skipped`: minimal implementation to make the OUTER test green — no inner loop; other guards hold.
CLOSE  inner units green (n/a if skipped) AND outer green AND phase DoD items pass (profile test command)
       AND a CLEAN re-run with assertions unchanged-or-stronger vs the RED snapshot.  [#4]  Refactor while green.
POST   LAND per merge policy (auto-merge → done | human-review → in-review + PR URL).  [#5]
       Update PROGRESS worklog + next issue. subagent: discard the worktree. Return the report.
```

Bracketed `[#n]` map to the Integrity guards. **Never** land before the outer behaviour test is green. The
**scenario and the `Inner loop (TDD)` flag are never edited by the builder** `[#1]` — a wrong one escalates
(`needs-decision`), it is not rewritten.

## Integrity — the test is the spec, not a target to move

Structural, not just prose (the full statements live in `agents/issue-worker.md`):

- **`[#1]` Scenario + TDD flag immutable to the builder.** Fixed at planning; wanting to change = spec gap →
  escalate.
- **`[#2]` Prove RED for the right reason** before any implementation.
- **`[#3]` Two commits, test-first.** Behaviour test committed before implementation.
- **`[#4]` Re-run from clean at close.** A weakened-but-green test fails the dispatch.
- **`[#5]` Independent checks.** Two are always-on and one is opt-in:
  - **`SubagentStop` verify guard (always on).** At the worker's exit it re-reads git: a reported `green`
    with no committed test on the `issue/*` branch (or an empty branch) is **blocked** and the worker is
    sent back. Honest escalations pass through. This is the mechanical backstop for a silently-compacted
    worker that returns a hollow green.
  - **`PreToolUse` test-first hook (opt-in, `integrity: +hook`).** Denies an implementation edit on an
    `issue/*` branch until a test is committed (BDD outer is always required); editing a test is allowed.
  - **Verifier agent (opt-in, `integrity: +verifier`).** Re-reads the branch/PR diff for test-gaming
    before the merge.

## Escalation — the orchestrator handles what a leaf can't

A subagent has **no interactive back-channel**: it cannot pause and ask mid-flight. So it **returns and the
orchestrator resolves**:

- **`needs-decision`** (structural/critical decision no baseline covers): the worker returns the exact
  question and terminates. The orchestrator runs **`/grill-me`** with the **engineer** (technical) or
  **stakeholder** (scope), records the resolution as a new **ADR** (via **`/to-adr`**) + `ARCHITECTURE.md` update
  or a **PRD amendment**, then **re-dispatches the worker** with the decision now in the baselines (and in
  the pack). The orchestrator **never resolves a structural decision from its own context** — that is
  silent drift; structural always goes to the human.
- **`blocked`** (missing fixture / unclear boundary / dependency not landed): the branch stays quarantined
  (`doing`, never lands); surface it. Do not fake green.
- **`needs-revalidation`** (a gap in an *existing* baseline): flow up — `PRD.md` → stakeholders,
  `ARCHITECTURE.md`/ADR → engineers.

Existing files a worker merely *lacks in context* are **not** escalations — it reads them itself.

## Report-back contract (what a dispatch returns)

- **Outcome:** `green` (landed `done` / PR `in-review`) | `blocked` | `needs-decision` | `needs-revalidation`.
- **Scenario status:** outer pass/fail; inner test count (`n/a` when `skipped`).
- **Changes:** files touched, test-command output (green proof), merge/PR ref.
- **PROGRESS delta:** worklog line + next issue.

The orchestrator **relays what matters** to the user (a subagent's final message is not user-visible).

## Idempotency & resume

State lives in **files**, never in agent memory: backlog status (`todo`/`doing`/`in-review`/`done`) +
`PROGRESS.md` are the single source of truth. Recovery after a crash/compaction:

1. **Reconcile:** any `in-review`/`doing` issue already landed → `done`.
2. **Resume:** an issue stuck in `doing` is the one to resume — its `issue/<id>-…` branch exists, so
   attach to it rather than re-branching.
3. **Continue from actual git/test state:** if the branch already has commits, run the test command to read
   red/green and pick up there — do **not** demand a fresh RED. Re-landing a landed branch is a no-op.

Because a dispatch is atomic (one issue, marked `doing`→`done`/`in-review`), replay never double-lands.

## The gate (after every dispatch)

- **Mid-work overflow (main session)** — the harness compacts; the `SessionStart` hook re-injects
  `PROGRESS.md` + the re-prime checklist, and the loop continues. No hand-authored handoff is required for
  correctness — RECORD-after-every-issue keeping `PROGRESS.md` current + this re-inject reconstruct position
  (the `/handoff` skill remains an optional, human-initiated richer checkpoint). In `subagent` dispatch the
  main context grows mostly *between* issues (it relays reports; the build lives in the worker), so its
  compaction tends to land at issue boundaries where `PROGRESS.md` is already current.
- **Clean boundary** (phase drained / project complete) — nothing mid-flight; `PROGRESS.md` + backlog + git
  describe it fully. A fresh tick re-primes and PLANs the next phase, or stops if the project is done. (Under
  `human-review`, a phase boundary with open PRs is `awaiting-review`: pause and surface.)

## Loop termination (it is finite)

One iteration = one issue → a phase's loop is bounded by its backlog size; the project = the sum of the
phases' backlogs + one PLAN per phase. Stop when: **phase drained** → PLAN next or (all IDs+DoD done)
**project complete**; **awaiting-review** (human-review PRs blocking dependents); **`blocked` /
`needs-decision` / `needs-revalidation`** (the only unplanned stops).

## Continuation drivers (host-agnostic)

Re-enter the orchestrator with whichever the host offers: **`/loop`** (self-paced — each tick re-primes and
does the next issue, the default and recommended driver now that handoff is hook-driven); a **`/schedule` /
cron watchdog** running `/sdd` (also the unattended crash-recovery mechanism); or a plain human
re-invocation of `/sdd`. Every tick re-reads files, reconciles landings, and continues from the true next
`todo` — that files-are-truth reconcile is what makes any driver safe.
