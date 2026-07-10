---
name: tdd
description: Test-driven development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
---

# Test-Driven Development

## Double loop (when driven by `/sdd` + `/bdd`)

TDD here is the **inner** loop of a double loop. The **outer** loop is the issue's Gherkin scenario,
realized by `/bdd` as a failing behaviour/integration test *before* you start. Then:

```
OUTER (BDD):  behaviour test from the scenario → red
INNER (TDD):  unit test → minimal code → unit green   (repeat, one behaviour at a time)
DONE:         inner units green AND the outer behaviour test green → refactor
```

"Unit" means the **next seam down**, still tested through its public interface — **not** a test welded
to implementation. Both loops assert behaviour; they differ only in granularity. Never mark a slice
done while the outer scenario is red.

**Per-issue toggle.** The inner TDD loop runs **only when the issue's `Inner loop (TDD)` field (set by
`/to-issues` at planning) is `required`** — the default. When it is `skipped`, there is no inner unit loop
for that slice: make the **outer** behaviour test green with the minimal implementation, still committing
the test before the code and re-running clean at close (all other integrity guards hold). The flag is
**immutable to you** — honour it; if it looks wrong, escalate (`needs-decision`), never flip it. The outer
BDD scenario is **always** required.

**Integrity:** make the *code* satisfy the test, never the reverse. Do not weaken, delete, `xfail`, or
rewrite a test to go green. If a test is wrong, stop and escalate — a weakened test that passes is a
failed cycle, not a done slice. Prove RED before GREEN; commit the test before the code.

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### 1. Planning

When exploring the codebase, use the project's domain glossary so that test names and interface vocabulary match the project's language, and respect ADRs in the area you're touching.

> **Inside the SDD loop (driven by `/sdd` + `/bdd`) you run autonomously in an isolated dispatch — do not
> stop to confirm or get approval.** The interface and the behaviours to test are already fixed by the
> issue's scenario + the phase PRD + `ARCHITECTURE.md`; derive the plan from those. If something genuinely
> can't be resolved from the specs, **escalate** (`needs-decision`) — never pause to ask the user. The
> user-confirmation steps below apply to **standalone** use only.

Before writing any code:

- [ ] *(standalone only)* Confirm with user what interface changes are needed
- [ ] *(standalone only)* Confirm with user which behaviors to test (prioritize)
- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the behaviors to test (not implementation steps)
- [ ] *(standalone only)* Get user approval on the plan

Standalone, ask: "What should the public interface look like? Which behaviors are most important to test?"

**You can't test everything.** Focus testing effort on critical paths and complex logic, not every possible
edge case — standalone, confirm with the user which behaviors matter most; in the loop, the scenario + phase
PRD already fix them.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet - proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
