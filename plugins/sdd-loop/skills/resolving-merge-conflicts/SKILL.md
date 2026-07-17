---
name: resolving-merge-conflicts
description: Resolve an in-progress git merge/rebase conflict on an issue branch — truthfully and regression-safe. Inside the SDD loop it is the sdd-merge-resolver's method, used when landing a slice hits a conflict with work another slice already landed. Mentions "merge conflict", "rebase conflict", "resolve conflicts".
---

# Resolving merge conflicts — truthfully, regression-safe

A conflict is resolved so **both intents survive** where they compose, and **the specs decide** where they
don't — never by guessing and never by weakening a test. Inside the SDD loop this runs in the bounded
**`sdd-merge-resolver`** subagent on ONE `issue/<id>` branch, rebasing it onto the current integration
branch tip.

1. **See the current state.** Inspect the merge/rebase in progress: `git status`, the conflicting files, and
   the two sides (`git log --merge`, `git diff`). Know exactly which branch is being rebased onto what.

2. **Find the primary source of each side.** Understand *why* each change was made and what it intended —
   read the commit messages, the issue's **Gherkin `Scenario:`** and phase PRD, and the touched
   **ADRs / `ARCHITECTURE.md` seam**. In the loop the "stated goal" of each side is its issue's scenario,
   not a guess.

3. **Resolve each hunk.** Preserve **both** intents where they compose. Where they genuinely collide, the
   resolution is decided by the **specs** (the scenarios + phase PRD + `ARCHITECTURE.md`), not by you:
   - **Never resolve by weakening, deleting, or `xfail`-ing a LANDED test** — an earlier issue's behaviour
     depends on it (the `+hook` landed-test warning fires here on purpose). Make the code satisfy both sides.
   - **Do not invent new behaviour** to bridge the two sides.
   - If the two sides encode a **genuine behaviour collision the specs don't adjudicate** (each issue's
     scenario is right on its own, yet they contradict), **stop** — that is a `needs-revalidation` for a
     human (which behaviour wins is a baseline decision), not a silent pick. Return it; you may
     `git rebase --abort` to leave the branch clean and quarantined. Otherwise **always resolve — never
     abort to dodge the work.**

4. **Run the project's regression gate.** Discover and run the profile's **full-suite / regression command**
   (the WHOLE accumulated suite, not just the touched slice), plus any typecheck / format the project uses.
   The resolution is done only when the whole suite is green — fix whatever the merge broke **in the code**.

5. **Finish the rebase/merge.** Stage everything and continue until all commits are rebased; the resolution
   commits stay on the **issue branch** (one branch, one merge). Then the land can proceed.
