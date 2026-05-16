# Collaboration Resolution

> Used by: implement.md, spec-executor.md

## Cross-branch regression investigation

A workflow for diagnosing regressions that appear after branching operations — tests pass on `main` but fail on the feature branch, with no changes to the test or its fixtures.

**Entry condition**: Test is green on `main`, red on `HEAD`, and neither the test file nor its fixtures changed between branches.

**Scope**: This workflow covers ANY regression, including non-E2E unit-test failures. The trigger surface is not limited to end-to-end tests.

### Steps

1. **Run `git diff main...HEAD` on the failing code path** — identify what changed in the production code (not tests or fixtures) between `main` and the current branch.
2. **Identify the semantic change** — determine whether the diff is a behavioral modification (logic changed), an interface change (signature/contract changed), or a collateral change (dependency was refactored).
3. **Propose a fix** — write the minimal change that restores the failing test without altering intended behavior. If the change on `main` was intentional, align the feature branch code with the new behavior.
4. **Run the test to verify** — confirm the test is green. If it passes, check for side effects by running the broader test suite for the affected module.

**Exit condition**: Test is green (investigation complete) or escalation (cause is ambiguous, the regression affects public contracts, or the fix requires architectural changes beyond the current scope).

## Experiment-propose-validate

A workflow for collaborative root-cause debugging between the reviewer and executor when a regression's origin is unclear — the two agents iteratively narrow down the defect through hypothesis, experiment, and evidence sharing.

**Entry condition**: A failing task whose cause is ambiguous (the executor cannot fix it and the reviewer cannot determine the root cause from the error alone). The ambiguity may stem from a cross-branch regression (covered above) or from a deeper architectural / behavioral defect.

**Scope**: This workflow covers the full signal loop from initial hypothesis through to a concrete fix proposal. It is the general-purpose debugging collaboration pattern; the cross-branch workflow above is a specialized variant triggered at a specific detection point.

### Signal Loop

The loop proceeds through five signals. Each signal is written as a `chat.md` collaboration marker (C2). The loop runs iteratively until either a `FIX_PROPOSAL` is agreed or escalation is triggered.

```
reviewer   emits  HYPOTHESIS   →  "I suspect the bug is in module X because Y"
executor   emits  EXPERIMENT   →  "I ran probe Z on module X and observed W"
both       emits  FINDING      →  recorded result of the experiment (either agent)
both       emit     ROOT_CAUSE →  converged diagnosis, agreed by both agents
reviewer   emits  FIX_PROPOSAL →  "The fix is to do A because B"
```

#### Step-by-step

1. **Reviewer emits `HYPOTHESIS`** — The reviewer proposes a root-cause theory based on the failure evidence. *Typical emitter: external-reviewer*. Content is a natural-language statement in `chat.md`.
2. **Executor emits `EXPERIMENT`** — The executor runs a targeted test or probe to validate the hypothesis. *Typical emitter: spec-executor*. The experiment should be minimal and bounded — one variable changed at a time.
3. **Both emit `FINDING`** — The result of the experiment is recorded by whichever agent observes it. *Typical emitter: both*. A `FINDING` is the raw observation; it may confirm or falsify the hypothesis but does not yet claim a root cause.
4. **Both emit `ROOT_CAUSE`** — After one or more hypothesis-experiment-finding cycles, the agents converge on the confirmed underlying defect. *Typical emitter: either, once confirmed*. `ROOT_CAUSE` marks the point of agreement; both agents treat this as the shared diagnosis.
5. **Reviewer emits `FIX_PROPOSAL`** — Derived from the root cause, the reviewer proposes a concrete fix. *Typical emitter: external-reviewer*. The executor then implements the fix and runs verification.

#### Termination

- **Success**: `FIX_PROPOSAL` is implemented and verified (test green).
- **Loop bound**: If the hypothesis-experiment-finding cycle repeats more than 10 times without converging on a `ROOT_CAUSE`, escalate (same exit condition as the cross-branch workflow).

### Ambiguous Baseline Cross-Reference

When the root cause of a regression is ambiguous (e.g., a test file changed only cosmetically between branches, making it unclear whether the change is the cause or symptom), the **baseline check** from `external-reviewer.md` applies: the reviewer performs a 3-condition check via `git diff main...HEAD` before modifying any test. If any condition is ambiguous, the check is treated as NOT satisfied and the ambiguity is recorded via a `FINDING` marker so the experiment-propose-validate loop can continue investigating. See `references/external-reviewer.md` for the full baseline-check rule.
