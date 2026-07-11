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

In the current architecture the context gate is **hook-driven**: the `PreCompact` hook fires when the main
session is about to compact, and the `SessionStart` hook re-injects `PROGRESS.md` afterward — so
**correctness no longer depends on a hand-authored handoff**. `RECORD`-after-every-issue keeping
`PROGRESS.md` current is the durable checkpoint.

This skill is now the **optional, richer checkpoint** — write it when the volatile "where I was" is worth
more than the terse `PROGRESS.md` worklog (a gnarly mid-issue state, a subtle open thread). It is also the
portable fallback on hosts without the compaction hooks. Write it so **any** fresh consumer resumes from
files alone; keep the durable truth in `PROGRESS.md` + backlog + git regardless.