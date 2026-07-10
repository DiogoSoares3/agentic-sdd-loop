# The issue dispatcher (the loop's critical seam)

This is where context hygiene, resumability and the double loop meet. It runs **exactly one issue to
green in an isolated context, then reports back**. Get this right and the loop scales; get it wrong
and context rot or half-done issues creep in. Treat every dispatch as **atomic and idempotent**.

## The context pack (what the fresh agent gets — and nothing else)

Minimal and deterministic. The agent must be able to do the whole issue from *only* this:

1. `.sdd/profile.md` — the régua, seams, DoD, test command, fresh-agent mode.
2. `PROGRESS.md` — current state (which issue, prior decisions, open questions).
3. `docs/phases/phase-N/prd.md` — the phase PRD this issue derives from (NOT the whole canonical PRD).
4. `ARCHITECTURE.md` + the ADRs the issue touches — the seam + test mechanism.
5. **The one issue** — its Gherkin `Scenario:`, its `Inner loop (TDD)` flag, and boundaries. One issue, never a batch.

Do **not** hand it the full backlog, unrelated phases, or the whole PRD. Scope is the point.

(`CLAUDE.md` code conventions are ambient — the harness auto-loads them; the build follows them without
being handed them in the pack.)

## Git strategy (branch-per-issue)

The loop **never commits to a protected branch**. Each issue is built on its own `issue/<id>-<slug>`
branch off the **integration branch** (`develop` by default) and lands there; `main` is human-only
(`develop → main` promotion is out of the loop's scope). *How* an issue lands is two profile knobs:

- **PR provider** — `none` (default) | `gh` (GitHub CLI) | `bitbucket-mcp` (Bitbucket MCP). The provider
  is the PR **surface**; `none` lands locally with no PR.
- **Merge policy** — how the green branch reaches `develop`:
  - **`auto-merge` (default, fully autonomous):** on green **+ passing checks/CI**, land the issue and
    mark it `done` in the same dispatch. With a provider: open the PR and merge it once checks pass; with
    `none`: merge the issue branch into `develop` locally. **No `in-review` state** — the backlog drains
    straight to `done`, so the loop runs unattended until the phase (or project) is complete.
  - **`human-review` (requires a provider):** on green, **push + open a PR and stop at `in-review` — do
    not merge.** The loop is **non-blocking**: it moves to the next issue whose blockers are `done`. A
    human reviews and merges, flipping the issue to `done`. Autonomous *within* a phase; a human
    merge-gate falls at each phase boundary (the next phase's issues stay `todo` until this phase lands).

```
auto-merge:    todo → doing → done
human-review:  todo → doing → in-review (PR open, green) → done (PR merged)
```

**Selection always requires every blocker to be `done`** (landed on the integration branch), so a
dependent slice branches off a base that already contains its blocker's code.

**Reconcile on prime (both policies):** landing can happen out-of-band — a human PR merge, or an
`auto-merge` interrupted after the merge but before the status write. At the start of every dispatch,
mark **any `in-review` or `doing` issue whose work is already in the integration branch** as `done`
(check via the provider `gh pr view`, or `git branch --merged` / log for the `issue/<id>` commits). Files
stay the truth; this just records a landing that already happened. The commit is the integrity surface
(guard `[#5]`).

## Two modes (profile: `fresh-agent mode`)

Both modes use the branch-per-issue → PR strategy above; the mode only changes *where the branch is
checked out* and *who holds the context*.

- **`reprime` (default, host-agnostic):** each `/loop` iteration re-reads the context pack and does
  one issue in the current session — `git switch -c`'ing to a fresh `issue/<id>-<slug>` branch off the
  integration branch, running the double loop, landing per the merge policy, then switching back.
  Freshness comes from the handoff gate (context ~40% / end of phase → `/handoff` → clean session).
  Simple; ship first.
- **`subagent` (opt-in):** the orchestrator spawns a genuinely fresh agent per issue with the pack
  above, **in its own git worktree on the issue branch**; it runs the double loop, lands per the merge
  policy, and returns the report contract below. Truly clean context per issue. Use only when
  accumulation in `reprime` actually hurts (rule of three), and only if the host supports subagents.

The rest of this file is identical for both modes — only the checkout mechanism and *who* holds the
context differ.

### Isolation (worktrees, `subagent` mode)

One issue = one worktree = one branch. This makes the integrity guards cheap and mechanical:
- The **clean re-run** `[#4]` runs against a fresh checkout by construction.
- The **two-commit** rule `[#3]` is auditable: the branch's first commit must touch **only test
  files**; the verifier reads exactly this branch's diff (the PR, under `human-review`) to check the
  test wasn't moved to fit the code.
- **Land only on green** is the gate — a `blocked` issue never lands (never opens a PR / never merges);
  its partial state stays quarantined on its branch (discard the worktree; the integration branch stays
  pristine, and the harness auto-cleans an unchanged one).

Worktrees isolate and audit; they do **not** prevent an agent from weakening its *own* test on its
*own* branch — that is still the immutable-scenario rule `[#1]` + the land/merge gate + the verifier.
Default to **one issue at a time**; do not run worktrees in parallel unless throughput genuinely
demands it (merge conflicts + context hygiene cost more than they return on a solo/graded project).

## Per-issue procedure (the double loop)

```
PRE    reconcile: mark any `in-review`/`doing` issue already landed in the integration branch as `done`.
       select: first `todo` whose blockers are all `done` (landed). Mark it `doing`.
       branch: from the freshly-pulled integration branch, create `issue/<id>-<slug>`
       (reprime: `git switch -c`; subagent: new worktree on that branch). Never work on a protected branch.
OUTER  (BDD)  /bdd realize → write the behaviour/integration test from the scenario.
       Run it → it FAILS. Capture the RED output (feature absent, not a typo) into PROGRESS.  [#2]
       COMMIT the test alone — a test-only commit, before any implementation.                 [#3]
INNER  (TDD)  Run this step **only if the issue's `Inner loop (TDD)` is `required`** (the default).
       /tdd loop: unit test → minimal code → unit green  (repeat, one behaviour at a time).
       COMMIT the implementation separately from the test commit.                             [#3]
       When `skipped`: write the **minimal implementation that makes the OUTER test green**, committed
       separately from the test commit — no inner unit loop; every other guard is unchanged.
CLOSE  - inner units green  (n/a when `Inner loop (TDD)` is `skipped`)  AND
       - outer behaviour test green  AND
       - the phase DoD items this issue touches pass (run the profile's test command)
       - re-run the test command from a CLEAN checkout; assertions unchanged-or-stronger vs the
         RED snapshot — a weakened-but-green test FAILS the dispatch                           [#4]
       - refactor while green
POST   LAND per the profile's merge policy:                                                         [#5]
       - auto-merge:   land on green + passing checks (provider: open+merge the PR; none: merge the
                       branch into `develop` locally). Mark the issue `done`.
       - human-review: push + open a PR into the integration branch (scenario + green proof in the
                       body); mark `in-review`, record the PR URL. Do NOT merge — a human does.
       PROGRESS: worklog line + next issue + any open question. subagent: discard the worktree.
       Continue to the next issue whose blockers are `done`.
```

Bracketed `[#n]` map to the Integrity guards below. **Never** land / open a PR before the outer
behaviour test is green — green unit tests with a red scenario = not done. The **scenario itself is
never edited to pass** `[#1]`; a wrong scenario escalates (`needs-decision`), it does not get rewritten.

## Integrity — the test is the spec, not a target to move

Reward-hacking guard. The build agent makes the **code** satisfy the test, **never the reverse**.
Prose alone can't self-police motivation, so these are structural:

- **The scenario is immutable to the builder.** It was authored at planning time from the phase PRD.
  The build agent realizes it but must not weaken, delete, `xfail`, comment out, or rewrite it.
  Wanting to change it = a spec gap → **escalate** (`needs-decision`), never edit. The issue's
  **`Inner loop (TDD)` flag is likewise fixed at planning** — the builder honours it and must not flip
  `required → skipped` to skip unit testing (that is drift); a flag that looks wrong escalates, never edits.
- **Prove RED for the right reason.** Before any implementation, run the behaviour test and capture
  the *failing* output (feature absent, not a typo). Record it. No RED proof = not a valid cycle.
- **Two commits, test-first.** Commit the behaviour test (test-only) before the implementation commit.
  Git history is the audit trail; a test edited with/after the code is the smell.
- **Re-run from clean at close.** Re-run the profile's test command from a clean state: the outer test
  must pass **and** its assertions be unchanged-or-stronger vs the RED snapshot. A weakened test fails
  the dispatch, even if it is "green".
- **Independent check (when enabled).** A separate verifier (hook and/or verifier agent — see the
  profile) re-reads the **branch diff** (the PR under `human-review`; the issue branch pre-merge under
  `auto-merge`): did the test move to fit the code? Under `human-review` this runs on the PR before a
  human merges; under `auto-merge` it must run **before the merge** (e.g. a pre-merge hook / CI check),
  so a test-gaming diff never lands.

## Report-back contract (what a dispatch returns)

Whether via subagent message or the session's own summary, every dispatch yields:

- **Outcome:** `green` (landed `done` under auto-merge, or PR open `in-review` under human-review) |
  `blocked` | `needs-decision` | `needs-revalidation`.
- **Scenario status:** outer behaviour test pass/fail; inner test count (`n/a` when the issue's `Inner loop (TDD)` is `skipped`).
- **Changes:** files/models touched (paths), test command output (the green proof), and the **merge/PR
  ref** (merge commit under auto-merge; PR URL under human-review).
- **PROGRESS delta:** the worklog line + the next issue.
- **Escalations:** any structural gap to flow up (see failure handling).

The orchestrator **relays what matters** to the user (a subagent's final message is not user-visible).

## Idempotency & resume

State lives in **files**, never in agent memory: the backlog status
(`todo`/`doing`/`in-review`†/`done`) + `PROGRESS.md` are the single source of truth (†`in-review` only
under human-review). A crashed or interrupted dispatch is recovered by:

1. Reconcile: any `in-review`/`doing` issue already landed in the integration branch → `done`.
2. Read the backlog: any issue stuck in `doing` is the one to resume — its `issue/<id>-…` branch
   already exists, so switch/attach to it rather than re-branching.
3. Re-run the per-issue procedure from PRE, but **continue from actual git/test state**: if the branch
   already has commits, run the test command to read current red/green and pick up there — do **not**
   demand a fresh RED (the feature may be partly built). Re-writing an existing test / re-landing a
   landed branch is a no-op; the loop is safe to replay.

Because dispatch is atomic (one issue, one branch, marked `doing`→`done`/`in-review` around it), replay
never double-lands or double-opens a PR.

## Failure handling (no silent failure)

- **`blocked`** (missing fixture, unclear boundary, dependency not landed): stop, record the blocker
  in `PROGRESS.md` under Open questions, leave the issue `doing` (it does not land — the branch stays
  quarantined), surface it. Do not fake green.
- **`needs-decision`** (a technical/behaviour/architecture decision is required to proceed and **no
  PRD/ARCHITECTURE/ADR covers it**, and it is structural/critical/hard-to-reverse): **stop — do not
  invent it.** Run `/grill-me` to validate that single decision with the **engineer** (technical) or
  **stakeholder** (scope), then record the resolution as a new **ADR** (`docs/adrs/`) + `ARCHITECTURE.md`
  update, or a **PRD amendment**; resume. Tactical, reversible micro-decisions are NOT this — make them
  and log them in `PROGRESS.md`.
- **`needs-revalidation`** (the issue reveals a scope/architecture gap in an *existing* baseline):
  stop, flow it **up** — `PRD.md` gap → stakeholders, `ARCHITECTURE.md`/ADR gap → devs. The loop does
  not silently amend a baseline.

## Gate (after every dispatch)

Two kinds of stop, and they checkpoint **differently**:

- **Mid-work cut (context ~40%, issues still left in the phase)** — work is in flight. Run **`/handoff`**
  (OS temp) to capture what is mid-doing, record its path atop `PROGRESS.md`, then continue per the
  handoff mode. **The `/handoff` is required** — the next context needs the volatile "where I was" that
  files alone don't hold.
- **Clean boundary (phase drained — all issues `done`/merged — or project complete)** — nothing is
  mid-flight; `PROGRESS.md` + backlog + git already describe the boundary in full. **Skip the
  `/handoff`** — the next context reconstructs from files alone. (Under `human-review`, a phase boundary
  with open PRs is instead `awaiting-review`: pause and surface, do not respawn.)

Then continue per the profile's **handoff mode**: `auto` self-continues via the flat supervisor below (no
human); `manual` tells the user to start a clean session. Either way the next context (subagent, new
session, or compaction) re-primes, reconciles merged PRs (human-review), and continues at the next `todo`
whose blockers are landed — or, at a drained phase, at **PLAN for the next phase**.

## Autonomous handoff — the flat supervisor (`handoff: auto`)

`auto` makes the context gate a checkpoint with **no human**, using one structural trick: a **flat
supervisor** spawns **sequential worker subagents**, where *the workers hold all the context and hit the
gate, and the supervisor holds almost none*. The workers are where context accumulates; the supervisor
only respawns them. This trick exists **solely** to make the handoff autonomous — nothing else changes.

**Two roles, strictly separated:**

- **Supervisor (root session — must hold ~zero context).** Its entire job: spawn a worker → receive one
  compact status line → spawn the next worker. It **must not** read the PRD, ARCHITECTURE, backlog,
  issues, code, or diffs into its own context — it passes **file paths, never file contents**, and
  relays only the worker's status line. Holding no domain context is what keeps it flat, so it can
  sequence unboundedly many workers. If the supervisor ever needs a fact, it points a worker at the
  file; it does not read it itself.
- **Worker (a fresh subagent per context budget — holds everything).** Primes from files + the latest
  handoff, then runs the loop — `PLAN` a phase if the files say one is due, then dispatch its issues — for
  **as many steps as fit**, until either it trips its own ~40% gate **or it drains the phase**. On a
  **~40% mid-work cut** it **authors its own `/handoff`** (it alone holds the mid-doing context) before
  returning; on a **clean phase drain** it writes no handoff (files fully describe the boundary) and
  leaves `PLAN` of the next phase to the next worker — that keeps the next phase's context out of the
  dying worker. Either way it updates `PROGRESS.md` + backlog and **returns a compact status**, then
  terminates. All heavy reading/writing/testing lives here.

**The cycle:**

```
supervisor:  loop
               spawn Worker(pack = {profile path, PROGRESS path, latest-handoff path})   # paths only
                 └─ Worker: prime → dispatch until ~40% OR phase drains → (/handoff only if mid-work) → update files → return status
               read the one-line status
               if terminal (project-complete / awaiting-review / backlog-review) or escalation → stop, surface to user
               else → spawn the NEXT Worker (fresh context)          # sequential — never nested
```

**Invariants (what makes the trick sound):**

- **Sequential, never nested.** One worker at a time; the supervisor waits for a worker to return before
  spawning the next. A worker **never spawns its own successor** — that would nest context and defeat the
  flatness. Respawning is the supervisor's job alone.
- **All context lives in the worker; the supervisor stays empty.** The supervisor never accumulates
  domain context — that is the whole point.
- **Files are the truth; the status line is only control flow.** A worker's durable outputs are the
  commits/PRs, `PROGRESS.md`, the backlog statuses, and the handoff doc. Even if a worker dies before
  writing a handoff, the next worker recovers from files alone (see *Idempotency & resume*) — the
  handoff is an optimization, not the guarantee.
- **Requires subagent support.** Without it, fall back to `handoff: manual`.

**Worker status line (the only thing that crosses back up):** `outcome` (continuing | project-complete |
awaiting-review | backlog-review | blocked | needs-decision | needs-revalidation) · next `todo` issue id ·
latest handoff path. Nothing else — no diffs, no code, no PRD prose. Keep it one line so the supervisor
stays flat.

Under `backlog-review: confirm` the worker cuts the phase backlog, then returns `backlog-review` and
stops — a headless worker can't collect the human's approval, so the supervisor surfaces the backlog and
waits for the human to approve/edit before the next worker starts building.
