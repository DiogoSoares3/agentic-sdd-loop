# The dispatcher — main orchestrator + bounded subagents + hooks

This is where context hygiene, resumability and the double loop meet. The architecture has **one rule that
explains everything**:

> **The long, continuous coordinator lives in the MAIN session** (only it gets the `SessionStart`
> lifecycle hook that re-primes it after compaction). **Subagents are bounded leaves** — a phase cut, or
> one issue — because a subagent gets **no lifecycle hook** and auto-compacts **silently**, so it must never
> hold long-running work it can't checkpoint from files.

Everything below follows from that. Get it right and the loop survives compaction, resumes from files, and
never games its own test.

## The roles

```
MAIN SESSION = the phase orchestrator   (you, running /sdd; re-driven by /loop)
│  • holds the state machine + the re-prime gate
│  • the SessionStart (re-prime) lifecycle hook lives HERE
│  • spawns bounded subagents; relays their status; handles escalation via /grill-me
│  • each subagent's exit is checked by the SubagentStop guard (verify, not coordinate)
│
├─ PLAN a phase     →  spawn [sdd-phase-opener]  (agents/phase-opener.md — bounded, one phase)
│                        └─ writes docs/phases/phase-N/prd.md + backlog.md → returns status
│
├─ BUILD an issue   →  spawn [sdd-issue-worker]  (agents/issue-worker.md — bounded, ONE issue)
│                        └─ runs the double loop on issue/*; NEVER merges → returns ready-to-land
│
└─ LAND a queued branch →  spawn [sdd-merge-resolver]  (agents/merge-resolver.md — bounded, ONE branch)
                            └─ rebase → resolve conflict IF any → FULL regression suite → merge (auto-merge)
                               or open the PR (human-review) → returns status.  THE single land path.
```

- **Orchestrator (main session).** Its loop: re-prime → read state → spawn the right subagent for the next
  step → receive one compact status/report → update `PROGRESS.md` + backlog → continue or stop at a gate. In
  parallel mode it also **owns the serial land queue** (below). It **never** builds an issue itself in
  `subagent` mode; it dispatches. It **never** nests — only the main session spawns.
- **`sdd-phase-opener`.** One bounded spawn per phase: derive the next epic from the validated baselines +
  ADRs, write the phase PRD + backlog (issues with a Gherkin `Scenario:` and the `Inner loop (TDD)` flag).
  Builds nothing. Fits one window.
- **`sdd-issue-worker`.** One bounded spawn per issue: the double loop to green on its own `issue/*` branch,
  then `ready-to-land`. It **never merges, never opens a PR, never leaves its branch** — in any mode. One
  issue fits one window — which is exactly why it is a subagent.
- **`sdd-merge-resolver`.** One bounded spawn per land-queue item, and **the only way anything reaches the
  integration branch**: rebase a `ready-to-land` branch onto the current tip, resolve a conflict via
  `/resolving-merge-conflicts` **only if one arises**, run the **full** regression suite, then merge
  (`auto-merge` → `done`) or open the PR (`human-review` → `in-review`). Dispatched for **every** land,
  conflict or not, serial or parallel — the heavy rebase + suite + merge stays OUT of both the main context
  and the worker's.

**Why the worker doesn't land (it used to, in serial).** Merging forces a checkout of the integration branch,
so the worker ended its dispatch *off* its `issue/*` branch — and every integrity guard keys on that branch,
including the `SubagentStop` verify, which then could not tell "landed correctly" from "never branched at
all" and had to fail open. Keeping the worker on its branch to the very end restores that check, makes the
worktree isolation real, and collapses two land paths into one. The cost is one extra bounded dispatch per
issue in serial mode; the guarantee is worth it.

Dispatch is **always** via subagents — the whole shape (coordinator in the main session, bounded leaves in
subagents) depends on it, so it is not a knob. Every bounded agent fits one window by design.

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
> verify guard only acts on the two agents it verifies (`sdd-phase-opener` / `sdd-issue-worker`; the
> `sdd-merge-resolver` is not verified, fail-open) and fails open otherwise. (Hook↔subagent lifecycle
> semantics — esp. that `SessionStart` is main-session-only, `PreToolUse`/`SubagentStop` fire for subagents,
> and subagents get no compaction hook so they compact silently — are per current Claude Code docs; confirm
> empirically on your host, they are load-bearing.)

## Branch ownership — the orchestrator creates it, the worker only attaches

**One owner, and it is the orchestrator.** Before spawning a worker it creates and checks out
`issue/<id>-<slug>` off the freshly-pulled integration branch (or sets up its worktree), and names that
branch in the pack. The worker **attaches** to it; it never branches, never switches to the integration
branch to "get started", never opens a second branch.

This is not bookkeeping — **every integrity guard is keyed on being on an `issue/*` branch**. The test-first
`PreToolUse` guard, the landed-test warning, and the `SubagentStop` verify all check the current branch and
**fail open when it isn't one**. A worker that never branched would silently switch the whole `+hook` layer
off and commit straight to the integration branch. Two things prevent it: this single owner, and the shipped
`PreToolUse` **issue-branch guard**, which denies any implementation/test edit on the integration or
protected branch while an issue is `doing` (below).

## The context pack (what a subagent gets — and nothing else)

Paths, not contents — the worker reads them itself:

1. `.sdd/profile.md` — régua, seams, DoD, test commands (slice + full-suite), merge policy, integrity level.
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

- **PR provider** — `none` (local merge) | `gh` | `bitbucket-mcp`. The provider is the PR surface.
- **Merge policy** — what the **lander** does once the regression gate is green:
  - **`auto-merge`** (the default without a provider, and the basis of unattended runs): merge and mark
    `done`. The backlog drains straight through, no human gate.
  - **`human-review`** (the default when a provider is reachable; requires one): open the PR and stop at
    `in-review`. The loop is **non-blocking** — it moves to the next issue whose blockers are `done`; a human
    merge flips it to `done`.

```
auto-merge:    todo → doing → ready-to-land → done                  (the lander merges)
human-review:  todo → doing → ready-to-land → in-review → done      (the lander opens the PR, a human merges)
```

`ready-to-land` is now on **every** path — serial and parallel alike — because the worker never lands. In
serial the queue simply never holds more than one item.

**Selection always requires every blocker to be `done`** (landed on the integration branch). A blocker in
`ready-to-land` is **not** `done` — a dependent cannot start until that blocker actually lands.

**Reconcile on prime (all policies):** at the start of every orchestration tick, mark any
`in-review`/`ready-to-land`/`doing` issue whose work is already in the integration branch as `done` (check
`gh pr view`, or `git branch --merged` / log for the `issue/<id>` commits). Files stay the truth; this
records a landing that already happened. **Also reconcile any open RFCs:** if `docs/rfcs/` holds RFCs, read
each one's Status — a `to-be-validated` RFC is an **open** decision (keep whatever it blocks parked; do not
build past it), while a `validated (ADR-XXXX)` RFC is **resolved** (confirm its ADR/amendment actually
landed, then it needs no further action). The RFC's own status line is the signal — there is no separate
loop state for it.

**Prune on `done`:** once an issue lands, remove its leftovers — `git worktree remove` (if a worktree),
`git branch -d` the local branch, and delete the remote branch if pushed (provider "delete on merge", else
`git push origin --delete`). Also sweep already-merged leftovers from earlier issues. **Never prune before
the regression gate has passed and the merge is confirmed landed** — a branch whose CI / local full-suite is
pending or failed is still needed to re-dispatch the fix. **Never prune a `blocked` / `needs-decision` /
regression-failed branch** (local or remote) — that quarantine is a human's to inspect.

## Two test gates — slice (worker) vs regression (merge)

Testing accretes: every issue commits its behaviour/integration test + its units, and they stay in the repo
for good. Two gates check them at two scopes:

- **Slice-gate — the worker, at CLOSE.** Proves THIS issue: outer behaviour/integration test green, inner
  units green (n/a when `skipped`), from a clean checkout, assertions unchanged-or-stronger vs the RED
  snapshot. Scope = what the issue touches (the profile's **slice command**). Runs before the branch is
  handed off.
- **Regression-gate — at the merge to a non-feature branch.** Proves the slice didn't break earlier
  behaviour, and catches semantic breaks from concurrent merges no single branch can see. Scope = the
  **whole** accumulated suite (the profile's **full-suite/regression command**) against the integration
  branch tip. The plugin does **not** force where it runs:
  - **Recommended: CI.** The provider's checks run the full suite on the PR / on push and on merge to a
    protected branch — this is what `auto-merge`'s "green **+ passing checks**" and `human-review`'s PR
    already hook into. Minimum: an e2e/regression run at each merge to a non-feature branch.
  - **Fallback (provider `none`, local merge): the loop runs the full-suite command locally** before
    landing, so the default is never unprotected.

**A regression-gate failure is a non-green re-dispatch, not a new escalation type.** If CI (or the local
full-suite) fails after a worker returned green, the orchestrator re-dispatches a fresh worker on the SAME
`issue/*` branch — it resumes from git/test state, exactly as a `doing` issue does — to make the full suite
green by **fixing the code**. The worker **must not** edit a landed test to silence the failure (the same
integrity line as the immutable scenario); a genuine behaviour change is `needs-revalidation`, never a quiet
test edit.

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
lands (discard the worktree, the integration branch stays pristine). The profile's **`Concurrency`** knob
picks the shape: **`serial` (default) — one issue at a time** (simplest; the land queue never holds more than
one item, so no cross-branch conflict is possible). **`parallel` — opt-in**, only when throughput truly
demands it, and only *safe* with the serial land queue below. The knob governs **how many workers build at
once — never how a branch lands**: the land is always one bounded lander at a time.

### Parallel mode — build parallel, land serial (the merge queue)
The failure parallel invites is **many workers racing to merge into a moving `develop`** — each rebases onto
what another just changed, and the resolutions thrash without converging. The fix is not to parallelize the
merge; it is to **serialize the land**:

- **Build parallel, land serial.** The orchestrator may co-dispatch several workers **only** for issues that
  are all-blockers-`done` **and** touch **disjoint files/seams** (read each issue's optional *Touches* hint;
  when overlap is unknown, serialize — the safe default). Workers build to green but **do not merge** — each
  returns **`ready-to-land`** with its branch pushed.
- **The land queue (orchestrator-owned) — a derived view of the backlog, not a separate structure.** The
  queue *is* the set of issues whose backlog status is **`ready-to-land`**; it is recomputed from the
  backlog file every tick (files-are-truth — there is no in-memory queue to lose on a crash). The
  orchestrator drains it **one at a time**, **dependency-first, then in backlog order** (the backlog is
  written blockers-first, so no timestamp is needed — first-ready-by-position wins). Ordering is by
  dependency + arrival, **not** by ease of resolution — a branch's conflict is only discovered at rebase
  time and shifts as each land moves the tip, so it cannot be pre-sorted.
- **The land itself is DELEGATED — the coordinator never rebases, runs the suite, or merges in its own
  context.** For each queue item the orchestrator spawns a bounded **`sdd-merge-resolver`** that takes that
  ONE branch to `done`: rebase onto the **current** integration tip → **resolve a conflict via
  `/resolving-merge-conflicts` only if one arises** → **regression-gate** (full suite) → merge → mark `done`.
  The rebase + full suite + merge is exactly the heavy, context-bloating work that must live in a disposable
  leaf, not the long-running coordinator — so it is dispatched for **every** land, conflict or not. The
  orchestrator's job is only to **serialize** (one lander at a time, so every rebase is against a settled tip
  → conflicts are sequential and single-owner, never a mutual scramble) and to **record** the report
  (`landed` → `done` + prune; `in-review` → record the PR URL; `needs-revalidation` for a genuine behaviour
  collision the specs don't adjudicate — never a silent side-pick, never by weakening a landed test). Under
  `human-review` the lander stops at the PR and the human merge is the serialization point.

Serial mode runs the **same** queue with at most one item in it: no moving target, no conflict to resolve,
but still the same bounded lander doing the rebase, the full suite and the merge. Prefer serial unless the
backlog has many genuinely-independent slices.

## Per-issue procedure (the double loop) — carried by `sdd-issue-worker`

```
PRE    (ORCHESTRATOR, before the spawn) reconcile landed issues → done. Select first `todo` whose blockers
       are all `done`; mark `doing`; create issue/<id>-<slug> off the freshly-pulled integration branch and
       check it out (or make its worktree). The WORKER never creates its own branch — it ATTACHES to the one
       it was handed and must already be on it when it starts. Never a protected branch.
OUTER  (BDD)  realize the scenario as the behaviour test at the arch seam → run → it FAILS (feature absent).
       Record the RED output.  [#2]   COMMIT the test alone, before any implementation.  [#3]
INNER  (TDD — only if `Inner loop (TDD)` is `required`)  unit → minimal code → unit green (repeat).
       COMMIT the implementation separately from the test.  [#3]
       When `skipped`: minimal implementation to make the OUTER test green — no inner loop; other guards hold.
CLOSE  (slice-gate) inner units green (n/a if skipped) AND outer green AND phase DoD items pass (profile
       SLICE command) AND a CLEAN re-run, assertions unchanged-or-stronger vs the RED snapshot.  [#4]  Refactor while green.
POST   NEVER land — in any mode. Push the issue/* branch, set its backlog status to `ready-to-land`, stay [#5]
       on the branch, return. The orchestrator drains the queue via a bounded lander (rebase →
       resolve-if-conflict → REGRESSION-gate → merge, or open the PR under human-review).
       Update PROGRESS worklog + next issue. Return the report.
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
- **`[#5]` Independent checks.** One is always-on; the rest are opt-in:
  - **`SubagentStop` verify guard (always on).** At the worker's exit it re-reads git + the durable files:
    a reported `green` with no committed test on the `issue/*` branch (or an empty branch) is **blocked** and
    the worker is sent back. It also reads the issue's **`Inner loop (TDD)` flag** from the backlog and, when
    it is `required`, blocks a success return that left **no inner-loop checkpoint line** in `PROGRESS.md` —
    the one deterministic trace that the inner loop actually ran (nothing else in the system reads that
    flag). Honest escalations pass through. This is the mechanical backstop for a silently-compacted worker
    that returns a hollow green.
  - **`PreToolUse` issue-branch guard (always on).** While the cursor says an issue is `doing`, it denies a
    code/test edit on the integration or protected branch — the loop builds on an `issue/*` branch or not at
    all. It is always on because every *other* guard keys on that branch and fails open without it, so this
    one is what makes the rest reachable; and it is cursor-gated, so with `Doing: none` a human editing the
    repo normally never sees it. Docs/spec/state are always allowed.
  - **`PreToolUse` test-first hook (opt-in, `integrity: +hook`).** Denies an implementation edit on an
    `issue/*` branch until a test is committed (BDD outer is always required); editing a test is allowed.
  - **`PreToolUse` landed-test warning (opt-in, `integrity: +hook`, non-blocking).** When a worker edits a
    test that already lives on the integration branch, it emits an advisory (fix the code, not a landed
    test earlier issues depend on) — a *warning*, not a block, since a shared fixture may legitimately
    evolve. This is the soft guard for the regression-gate's "never edit a landed test" rule.
  - **Verifier agent (opt-in, `integrity: +verifier`).** Re-reads the branch/PR diff for test-gaming
    before the merge.

**What the `PreToolUse` guards cannot see.** They are registered on `Edit|Write`, so anything written through
**`Bash`** (`cat > f <<EOF`, `sed -i`, `git apply`, `python -c`) bypasses all three. Widening the matcher
does not fix it — deciding whether an arbitrary shell command writes an implementation file means parsing
arbitrary shell. They also match **paths, not contents**: an empty committed test satisfies test-first, and
an impl file under `spec/` reads as a test. So `+hook` is a deterministic floor that makes the honest path
the easy one and catches the common slip; the layers that see through it are `SubagentStop` (re-reads git and
the durable files at exit, whatever wrote them) and `+verifier` (reads the diff's contents).

## Escalation — the orchestrator handles what a leaf can't

A subagent has **no interactive back-channel**: it cannot pause and ask mid-flight. So it **returns and the
orchestrator resolves**:

- **`needs-decision`** (structural/critical decision no baseline covers): the worker returns the exact
  question and terminates. The orchestrator runs **`/grill-me`** with the **engineer** (technical) or
  **stakeholder** (scope), records the resolution as a new **ADR** (via **`/to-adr`**) + `ARCHITECTURE.md` update
  or a **PRD amendment**, then **re-dispatches the worker** with the decision now in the baselines (and in
  the pack). The orchestrator **never resolves a structural decision from its own context** — that is
  silent drift; structural always goes to the human. **For a weighty fork that needs asynchronous team
  sign-off**, the orchestrator may instead **suggest** (never force) formalizing it as a **Request for
  Comments** (**`/to-rfc`** → `docs/rfcs/RFC-N`, `to-be-validated`): the issue **stays parked on its
  `needs-decision`** (no new stop-reason — the RFC file's own status is the truth) until the team validates
  it, at which point the RFC materializes via `/to-adr` (+ amendment) and is flipped to `validated (ADR-M)`,
  and the worker is re-dispatched. This closes over the same baseline the light grill would have — just with
  the team's decision on record.
- **`blocked`** (missing fixture / unclear boundary / dependency not landed): the branch stays quarantined
  (`doing`, never lands); surface it. Do not fake green.
- **`needs-revalidation`** (a gap in an *existing* baseline): flow up — `PRD.md` → stakeholders,
  `ARCHITECTURE.md`/ADR → engineers.

Existing files a worker merely *lacks in context* are **not** escalations — it reads them itself.

## Report-back contract (what a dispatch returns)

- **Outcome (issue-worker):** `ready-to-land` (green + pushed, still on its branch, awaiting the land queue —
  the success outcome in every mode) | `blocked` | `needs-decision` | `needs-revalidation`.
- **Outcome (merge-resolver):** `landed` (rebased, conflict resolved if any, full suite green, merged →
  `done`) | `in-review` (human-review: PR open + URL) | `needs-revalidation` | `needs-decision` | `blocked`.
- **Scenario status:** outer pass/fail; inner test count (`n/a` when `skipped`).
- **Changes:** files touched, test-command output (green proof), merge/PR ref.
- **PROGRESS delta:** worklog line + next issue.

The orchestrator **relays what matters** to the user (a subagent's final message is not user-visible).

## Idempotency & resume

State lives in **files**, never in agent memory: backlog status
(`todo`/`doing`/`ready-to-land`/`in-review`/`done`) + `PROGRESS.md` are the single source of truth. The
parallel land queue is **not** held in memory — it is the backlog filtered to `ready-to-land`, so a crash
loses nothing. Recovery after a crash/compaction:

1. **Reconcile:** any `in-review`/`ready-to-land`/`doing` issue already merged into the integration branch → `done`.
2. **Resume:** an issue stuck in `doing` is the one to resume its **build** — attach to its `issue/<id>-…`
   branch rather than re-branching. An issue in `ready-to-land` (green, unmerged) re-enters the **land
   queue** (rebase → regression-gate → merge), **not** a rebuild.
3. **Continue from actual git/test state:** if the branch already has commits, run the test command to read
   red/green and pick up there — do **not** demand a fresh RED. Re-landing a landed branch is a no-op.

Because a dispatch is atomic (one issue, marked `doing`→`ready-to-land`/`done`/`in-review`), replay never double-lands.

## The gate (after every dispatch)

- **Mid-work overflow (main session)** — the harness compacts; the `SessionStart` hook re-injects
  `PROGRESS.md` + the re-prime checklist, and the loop continues. No hand-authored handoff is required for
  correctness — RECORD-after-every-issue keeping `PROGRESS.md` current + this re-inject reconstruct position.
  In `subagent` dispatch the main context grows mostly *between* issues (it relays reports; 
  the build lives in the worker), so its compaction tends to land at issue boundaries where `PROGRESS.md` is already current.
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
