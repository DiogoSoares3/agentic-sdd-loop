---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: false
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

## In the SDD loop

In the current architecture recovery is **automatic and file-based**: the `SessionStart` hook (resume|compact)
re-injects `PROGRESS.md` on every resume/compaction, and `RECORD`-after-every-issue keeps `PROGRESS.md`
current — so **correctness never depends on a hand-authored handoff**. (There is no `PreCompact` handoff: that
hook cannot inject context, so it was removed; the load-bearing mechanism is `SessionStart` + durable files.)

This skill therefore has **no role in the automated loop** — it is never invoked by `/sdd`. It is a **human,
on-demand tool**: run it when the volatile "where I was" is worth more than the terse `PROGRESS.md` worklog
(a gnarly mid-issue state, a subtle open thread) and you want a readable narrative to hand to a person or a
later session. Write it so **any** fresh consumer resumes from files alone; keep the durable truth in
`PROGRESS.md` + backlog + git regardless.