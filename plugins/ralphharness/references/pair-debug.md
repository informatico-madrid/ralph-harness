# Pair Debug — Auto-Triggered Collaborative Regression

A two-instance coordination protocol for debuggable regression investigation, triggered automatically when the CI/CD pipeline breaks.

## Section 1 — 3-Condition Auto-Trigger

The pair-debug loop triggers when ALL of the following conditions hold simultaneously:

1. **Condition (a): Pre-existing test failure with unchanged test file** — A test that was passing on a prior commit now fails, and the test file itself has not been modified (so the regression is in production code, not test code).

2. **Condition (b): taskIteration >= 2** — At least 2 full iteration cycles have been attempted on the current task, confirming the failure is persistent and not a transient flake.

3. **Condition (c): No reviewer FAIL row** — There is no `FAIL` entry for this task in `task_review.md`, confirming the external reviewer has not already rejected the work and that we are in a genuine investigation scenario.

**ALL THREE conditions must hold.** If any one is false, the pair-debug loop does NOT fire.

> The roadmap states 3 conditions; plan.md listed 4 by splitting condition (a) into two parts. The canonical count is 3: (a) pre-existing test failing + test file unchanged, (b) taskIteration >= 2, (c) no reviewer FAIL row. ALL THREE must hold.

## Section 2 — Driver / Navigator Roles

| Role | Who | Responsibilities |
|------|-----|------------------|
| **Driver** | spec-executor | Writes code, runs commands, applies fixes, adds debug logging |
| **Navigator** | external-reviewer | Reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings |

**Shared instruction:** Both agents formulate hypotheses, respond to the other's hypotheses, and do not escalate to a human unless an explicit product/design decision is required.

## Section 3 — Anti-Anchoring Rule

To prevent confirmation bias during regression investigation:

1. The Navigator MUST propose **>= 2 independent hypotheses** BEFORE the pair commits to investigating any one of them.
2. A hypothesis becomes a **ROOT_CAUSE** only after an **EXPERIMENT** has produced **direct evidence** (not reasoning alone).
3. Reuse `references/collaboration-resolution.md`'s `>10-cycle` escalation bound as the stalled-loop exit.

## Section 4 — Two-Instance / Filesystem-Coordination

The Driver and Navigator run as **two separate instances** coordinating ONLY through the shared filesystem:

- `chat.md` — Collaboration messages, HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL markers
- `signals.jsonl` — Control signals (HOLD, PENDING, CONTINUE, ACK)
- `.ralph-state.json` — Shared state (taskIndex, taskIteration)

No in-memory handoff. No Task-tool call between instances.

## Section 5 — Runtime-to-Destination-Path Map

| Runtime | Destination Path |
|---------|-----------------|
| Roo Code | `.roo/commands/pair-debug-{driver,navigator}.md` |
| Qwen | `.qwen/commands/` |
| Cursor | `.cursor/commands/` |
| Other / Unknown | Manual fallback |

## Section 6 — Loop Body Reference

See `references/collaboration-resolution.md` for the full HYPOTHESIS -> EXPERIMENT -> FINDING -> ROOT_CAUSE -> FIX_PROPOSAL loop body. Do NOT re-document the loop here.

## Section 7 — Example Flow

1. **Trigger fires** — All 3 conditions are met.
2. **Chat.md announcement** — Driver or Navigator appends a PENDING message announcing the pair-debug loop is starting.
3. **Navigator writes HYPOTHESIS** — Proposes at least 2 independent root-cause theories.
4. **Driver runs EXPERIMENT** — Implements probes, adds logs, runs targeted tests.
5. **Both write FINDING** — Record observed results back to chat.md.
6. **ROOT_CAUSE agreed** — Both agents confirm the underlying defect.
7. **Driver implements FIX_PROPOSAL** — Applies the concrete fix.
8. **Verification passes** — The original test now passes.
9. **Grep-clean PAIR-DEBUG: logs** — Remove any debug logging added during investigation; commit the fix.
