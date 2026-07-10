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

At the context gate the `sdd` loop calls this skill to write the durable checkpoint, then continues per
the profile's **handoff mode**: under `auto` a **flat supervisor** spawns the next fresh **worker
subagent**, which re-primes from this doc + `PROGRESS.md` and resumes the loop (no human); under `manual`
a human starts the clean session. Under `auto` **the worker authors this doc itself** — it is the one
holding the context — before returning to the supervisor. Write it so **any** fresh consumer can resume
from files alone; that is what makes the context gate a checkpoint rather than a stop.