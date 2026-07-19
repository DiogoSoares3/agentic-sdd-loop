---
name: to-rfc
description: Write ONE Request for Comments (RFC) — a structured architectural proposal circulated for the team to validate BEFORE it becomes a decision — to the repo's RFCs directory. A thin writer, not a decision-maker. Picks the next RFC number, fills the template with the options plus a recommendation, and leaves it to-be-validated. SUGGEST it (never force it) when a weighty architectural fork — during ARCHITECTURE.md authoring, an ADR, or a build-time needs-decision — would benefit from asynchronous team sign-off. On validation the RFC is materialized into an ADR/PRD amendment and marked validated (ADR-NNNN). Triggers on "RFC", "request for comments", "formalize this decision for the team".
disable-model-invocation: false
---

# To RFC — a proposal for the team, before the decision

This skill **materializes an open architectural question as an RFC** — a structured proposal the **team**
comments on and validates **asynchronously**, so the decision (and everyone's sign-off) is recorded rather
than settled in a single head. It is the **heavier, async sibling** of the synchronous `/grill-me`
interview: same job (resolve a decision the baselines don't cover), different instrument (a durable doc the
team reviews out-of-band).

It does **not** decide anything and it does **not** replace `/to-adr`. An RFC comes **before** an ADR:

```
open architectural question
   ├─ light / reversible / a quick call ─────────►  /grill-me (sync) → /to-adr        (unchanged path)
   └─ weighty / hard-to-reverse / needs the team ─►  /to-rfc  →  RFC-N (to-be-validated)
                                                        team validates (out-of-band)
                                                        ├ accepted  → /to-adr (+ PRD/ARCHITECTURE amendment)
                                                        │             → flip RFC to `validated (ADR-N)`
                                                        └ rejected   → record the chosen alternative (as an ADR)
```

## When to SUGGEST it (never force it)

The régua wins: **simple > flexible**, and the *Rule of three*. An RFC is the opt-in heavy path, not the
default — most decisions still take the light `/grill-me` → `/to-adr` route. **Suggest** an RFC only when a
decision is **all** of:

- **architecturally significant / hard-to-reverse** (a seam, a contract, a data definition, a scope fork), and
- would genuinely benefit from **asynchronous, multi-person team validation** (not just one owner's quick call), and
- has **real competing alternatives** worth circulating for comment.

The three moments to offer it — always as a suggestion the human accepts or declines:
1. **Authoring `ARCHITECTURE.md`** (in `/grill-me`) — a weighty fork the engineer wants the team to validate async.
2. **Recording an ADR** (early, or mid-development) — when the decision behind the ADR is contested enough to
   warrant team comment first; the RFC precedes and then produces that ADR.
3. **A build-time `needs-decision`** surfaces — the orchestrator may suggest formalizing it as an RFC instead
   of (or before) a synchronous grill, so the team's decision is on record.

If a decision is not all three, do **not** raise an RFC — write the ADR directly. Don't turn process into a product.

## Process (a thin writer — same shape every time, like `/to-adr`)

1. **Resolve paths from `.sdd/profile.md` → `## Paths` — never hardcode `docs/`.** Take the **RFCs directory**
   (the backtick-quoted path after "RFCs" on the Baselines line, default `docs/rfcs/`), the **ADRs directory**,
   and the **`ARCHITECTURE.md`** path. A project may relocate any of them out of `docs/` — honor the profile;
   fall back to the defaults only if it is silent. Create the RFCs directory if it doesn't exist yet.
2. **Pick the next number.** Scan the RFCs directory for existing `RFC-NNNN…` files, take the highest, add one,
   zero-pad to four digits (first RFC = `RFC-0001`). File name: `RFC-<NNNN>-<kebab-title>.md`.
3. **Write from `${CLAUDE_PLUGIN_ROOT}/templates/rfc/rfc.template.md`** — fill the title, **Status:
   `to-be-validated`**, date, author, reviewers, and the **Origin** line (which of the three moments above it
   came from — name the issue id for a build escalation). Fill **Context & problem** (what forced it + why the
   baselines are silent), **Options considered** (the real alternatives with trade-offs — the heart of it),
   **Recommendation** (the recommended option + the discarded alternative and why), **Impact** (the seam(s) /
   contract(s) / scope + which baseline it will amend), and **Open questions for reviewers**. Leave **Outcome**
   empty — it is filled on validation.
4. **Do NOT index it into `ARCHITECTURE.md`.** An RFC is an open proposal, not a closed decision — the RFCs
   directory is its own list. Only the **ADR** it eventually produces gets indexed into `ARCHITECTURE.md`
   (by `/to-adr`, as usual). If the RFC blocks in-flight work, note it in `PROGRESS.md` → **Open questions**
   (`RFC-000N to-be-validated — blocks issue <id>`) so re-entry knows the decision is still open.
5. **One RFC per call.** If several independent questions arise at once, invoke the skill once per question.

## Validation → materialize → resume (closing the loop)

An RFC's own **Status line is the truth** — no new loop state, no hook change. Two terminal outcomes:

- **Validated (accepted).** The team signs off. **Materialize** the outcome exactly like any resolved
  decision: run **`/to-adr`** to record the ADR (Origin: `RFC-000N accepted`) and update `ARCHITECTURE.md`
  for a technical call, or make a **`PRD.md` amendment** for a scope call. Then **flip the RFC Status** to
  `validated (ADR-000M)` and fill its **Outcome**. The baseline now covers the decision, so the parked
  `needs-decision` clears and the orchestrator **re-dispatches** the affected issue.
- **Rejected / superseded.** Record why in **Outcome**, set the Status accordingly, and record the chosen
  alternative as its own ADR. The decision is still resolved — just not the recommended way.

**Reconcile on prime (files-are-truth).** When the loop re-primes and the repo has RFCs, confirm each one's
status: an RFC still `to-be-validated` is an **open** decision (surface it, do not build past what it blocks);
an RFC `validated (ADR-XXXX)` is **done** — verify its ADR/amendment actually landed, then it needs no
further action. This is the same "reconcile what the files already record" discipline the loop uses for
merged PRs, applied to RFCs.

Do not publish to any issue tracker. Do not invent a decision the team hasn't made — that is `/grill-me`'s and
the team's job; this skill only writes the proposal down and, once they decide, hands off to `/to-adr`.
