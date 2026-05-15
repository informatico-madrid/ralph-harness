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
