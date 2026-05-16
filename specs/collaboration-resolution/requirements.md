# Requirements: collaboration-resolution

## Goal

Encode an already-working ad-hoc agent collaboration pattern — cross-branch regression investigation and experiment-propose-validate debugging — into explicit, repeatable rules so agents resolve regressions autonomously instead of improvising or escalating to a human.

## User Stories

### US-1: Cross-branch regression investigation workflow

**As an** agent (spec-executor) facing a failing test
**I want to** follow a named first-class workflow for investigating a test that was green on `main` and is red on `HEAD`
**So that** I find the root cause via `git diff main...HEAD` instead of improvising or masking the failure.

**Acceptance Criteria:**
- AC-1.1: A new file `plugins/ralphharness/references/collaboration-resolution.md` exists.
- AC-1.2: The file contains a named workflow block "Cross-branch regression investigation" that, given a test green on `main` and red on `HEAD` with neither test nor fixture changed, prescribes: (a) run `git diff main...HEAD` on the failing code path, (b) identify the semantic change that broke the test, (c) propose a fix, (d) run the test to verify.
- AC-1.3: The workflow is described as a workflow (steps + entry condition + exit condition), not as a list of micro-rules for every situation.
- AC-1.4: The workflow explicitly states its trigger surface is ANY regression (test green on `main`, red on `HEAD`), covering non-E2E unit-test regressions, not only VE/E2E regressions.

### US-2: Experiment-propose-validate collaboration pattern

**As an** agent collaborating in `chat.md`
**I want to** a formalized hypothesis → experiment → finding → root-cause → fix-proposal pattern with named vocabulary
**So that** investigation exchanges are structured, auditable, and repeatable rather than ad hoc prose.

**Acceptance Criteria:**
- AC-2.1: `collaboration-resolution.md` contains a named workflow block "Experiment-propose-validate" describing the loop: reviewer proposes HYPOTHESIS → executor runs EXPERIMENT → both compare FINDING → converge on ROOT_CAUSE → emit FIX_PROPOSAL.
- AC-2.2: The 6 signals HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY are added to the Collaboration markers table in `plugins/ralphharness/templates/chat.md`.
- AC-2.3: The 6 signals are added as Collaboration markers (channel `chat.md`), NOT as Control signals (channel `signals.jsonl`); `signals.jsonl` and its schema are not modified.
- AC-2.4: Each new signal in the legend has a one-line definition of its meaning and which agent typically emits it.

### US-3: Reviewer-discovered bug triggers a fix task

**As a** coordinator
**I want to** generate a fix task when the external-reviewer records a `BUG_DISCOVERY` entry in `task_review.md`
**So that** a bug found by investigation (not by task failure) gets repaired through the existing fix-task machinery.

**Acceptance Criteria:**
- AC-3.1: `plugins/ralphharness/references/failure-recovery.md` is extended with a second fix-task trigger: a `BUG_DISCOVERY` entry in `task_review.md` carrying evidence and a fix suggestion.
- AC-3.2: The `BUG_DISCOVERY` trigger reuses the existing `X.Y.N [FIX X.Y]` fix-task format, `fixTaskMap`, and `tasks.md` insertion logic — only the trigger differs from executor non-completion.
- AC-3.3: The extension does not change the coordinator core loop; the `BUG_DISCOVERY` entry is processed by the coordinator's existing pre-delegation read of `task_review.md`.
- AC-3.4: The reviewer is not granted any new write permission; `BUG_DISCOVERY` is written to `task_review.md`, which the reviewer already owns. The coordinator (not the reviewer) inserts the fix task into `tasks.md`.

### US-4: Executor follows the collaboration workflow

**As a** spec-executor
**I want to** a reference to `collaboration-resolution.md` in my agent definition
**So that** I follow the cross-branch investigation workflow during regression investigation instead of improvising.

**Acceptance Criteria:**
- AC-4.1: `plugins/ralphharness/agents/spec-executor.md` contains an appended reference to `references/collaboration-resolution.md`.
- AC-4.2: The reference is positioned so it is naturally invoked during regression investigation (e.g. adjacent to `<exit_code_gate>` failure attribution, which already uses `git diff --name-only HEAD`).
- AC-4.3: The change to `spec-executor.md` is additive (append) and does not remove or rewrite existing sections.

### US-5: Reviewer checks baseline before modifying tests

**As an** external-reviewer
**I want to** a hard rule to verify the `main` baseline before suggesting any edit to a test that passed on `main`
**So that** I do not mask a backend regression by editing the test itself.

**Acceptance Criteria:**
- AC-5.1: `plugins/ralphharness/agents/external-reviewer.md` contains a hard rule: before modifying any test that passed on `main`, verify (a) the test file is unchanged in this spec (`git diff main...HEAD -- <test path>`), (b) the fixture/environment is unchanged, (c) the backend code path differs — and if all three hold, the cause is a backend/environmental regression and the test MUST NOT be modified.
- AC-5.2: `external-reviewer.md` contains an appended reference to `references/collaboration-resolution.md`.
- AC-5.3: The change to `external-reviewer.md` is additive and does not remove or rewrite existing sections.

### US-6: Regression detection covers any test type

**As a** harness
**I want to** a defined detection point for non-E2E unit-test regressions, not only VE/E2E regressions
**So that** the cross-branch workflow triggers on ANY regression, since `external-reviewer.md` §3b `progress-regression` FAIL only fires in the mid-flight VE/E2E submode.

**Acceptance Criteria:**
- AC-6.1: Requirements (and downstream design) define an explicit detection point for a non-E2E unit-test regression (test green on `main`, red on `HEAD`), distinct from the VE/E2E-only `progress-regression` FAIL.
- AC-6.2: The designated detection point is the spec-executor's `<exit_code_gate>`, which already attributes failures and uses `git diff --name-only HEAD` — extended to recognize a cross-branch (`git diff main...HEAD`) regression.
- AC-6.3: The cross-branch workflow's entry condition in `collaboration-resolution.md` references this general detection point and does not restrict itself to VE/E2E regressions.

### US-7: Duplicate BUG_DISCOVERY does not create duplicate fix tasks

**As a** coordinator
**I want to** detect when the same bug is reported twice via `BUG_DISCOVERY`
**So that** I do not generate two fix tasks for one bug.

**Acceptance Criteria:**
- AC-7.1: `failure-recovery.md` specifies that before generating a fix task from a `BUG_DISCOVERY` entry, the coordinator checks whether a fix task for the same underlying bug already exists (e.g. via `fixTaskMap` / matching task_id + criterion).
- AC-7.2: When a duplicate `BUG_DISCOVERY` is detected, no second fix task is generated, and the duplicate is recorded as already-handled rather than silently dropped.

### US-8: BUG_DISCOVERY fix tasks respect the depth limit

**As a** harness
**I want to** `BUG_DISCOVERY`-triggered fix tasks to obey the existing `failure-recovery.md` depth/limit checks
**So that** there are no infinite fix-task chains.

**Acceptance Criteria:**
- AC-8.1: `failure-recovery.md` states that a `BUG_DISCOVERY`-triggered fix task is subject to the same fix-task depth/limit checks as an executor-failure-triggered fix task.
- AC-8.2: When the depth/limit is reached, a `BUG_DISCOVERY` does not generate a further fix task; the existing limit-exceeded handling (block/escalate) applies unchanged.

### US-9: Reviewer handles an ambiguous baseline check

**As an** external-reviewer
**I want to** defined behavior when the 3-condition baseline check is ambiguous (e.g. the test file changed but only cosmetically)
**So that** I neither wrongly modify a test nor stall.

**Acceptance Criteria:**
- AC-9.1: `external-reviewer.md` (or `collaboration-resolution.md`) specifies that when any of the 3 baseline conditions is ambiguous, the reviewer treats the baseline check as NOT satisfied and does not modify the test.
- AC-9.2: In the ambiguous case, the reviewer records the ambiguity (e.g. via a `chat.md` collaboration marker or a `task_review.md` entry) so investigation continues rather than terminating.

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria | Traces to |
|----|-------------|----------|---------------------|-----------|
| FR-1 | Create `references/collaboration-resolution.md` with a "Cross-branch regression investigation" workflow block (entry condition, `git diff main...HEAD` steps, propose-fix, verify). | High | File exists; block present with the 4 prescribed steps; written as a workflow not micro-rules. | Roadmap #1 |
| FR-2 | The cross-branch workflow's entry condition covers ANY regression (test green on `main`, red on `HEAD`), explicitly including non-E2E unit-test regressions. | High | Workflow text states ANY-regression trigger surface; does not restrict to VE/E2E. | User Decision 1 |
| FR-3 | Define an explicit detection point for non-E2E unit-test regressions at the spec-executor `<exit_code_gate>`, distinct from the VE/E2E-only `progress-regression` FAIL. | High | Requirements/design name `<exit_code_gate>` extended to recognize `git diff main...HEAD` regressions. | User Decision 1 |
| FR-4 | Add a "Experiment-propose-validate" workflow block to `collaboration-resolution.md` (HYPOTHESIS → EXPERIMENT → FINDING → ROOT_CAUSE → FIX_PROPOSAL loop). | High | Block present; describes the named loop and which agent emits each step. | Roadmap #2 |
| FR-5 | Add the 6 collaboration signals (HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY) to the Collaboration markers table in `templates/chat.md`, each with a one-line definition. | High | All 6 rows present in the Collaboration markers table; `signals.jsonl` untouched. | Roadmap #2, #4 |
| FR-6 | Extend `references/failure-recovery.md` with a `BUG_DISCOVERY`-in-`task_review.md` fix-task trigger, reusing the existing `X.Y.N [FIX X.Y]` format, `fixTaskMap`, and `tasks.md` insertion. | High | New trigger documented; reuses existing downstream machinery; coordinator core loop unchanged. | Roadmap #3 |
| FR-7 | The `BUG_DISCOVERY` trigger introduces no new reviewer write permission and no new channel; the reviewer writes `task_review.md` (already owned) and the coordinator inserts the fix task. | High | `failure-recovery.md` states reviewer write boundary unchanged; coordinator performs `tasks.md` insertion. | Roadmap #3, research Constraints |
| FR-8 | Specify duplicate-`BUG_DISCOVERY` handling in `failure-recovery.md`: detect a duplicate before fix-task generation and do not create a second fix task. | High | Dedup check documented; duplicate recorded as handled. | User Decision 2 (edge case) |
| FR-9 | Specify that `BUG_DISCOVERY`-triggered fix tasks are subject to the existing `failure-recovery.md` fix-task depth/limit checks. | High | `failure-recovery.md` states depth/limit applies to the new trigger; limit-exceeded handling unchanged. | User Decision 2 (edge case) |
| FR-10 | Append a reference to `references/collaboration-resolution.md` in `agents/spec-executor.md`, positioned for use during regression investigation. | High | Reference present, additive, adjacent to `<exit_code_gate>`. | Roadmap #4 |
| FR-11 | Add to `agents/external-reviewer.md` a hard "before modifying tests, check baseline" rule (3-condition check on `git diff main...HEAD`) plus a reference to `collaboration-resolution.md`. | High | Hard rule and reference present; change additive. | Roadmap #5 |
| FR-12 | Specify reviewer behavior for an ambiguous 3-condition baseline check: treat as NOT satisfied (do not modify the test) and record the ambiguity so investigation continues. | Medium | Ambiguous-case behavior documented in `external-reviewer.md` or `collaboration-resolution.md`. | User Decision 2 (edge case) |
| FR-13 | Carry forward the research's open design decisions as design-phase constraints (do not pre-resolve): (a) `BUG_DISCOVERY` entry shape in `task_review.md` — design decides between a new `status` value in the existing table schema or a documented additional row/section format; (b) `channel-map.md` spec-executor `chat.md`-writer reconciliation. | Medium | Both items listed as design-phase constraints, not resolved in requirements. | Research Open Questions |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Additivity — Spec 7 changes to existing files are additive (append reference / add rule block), not rewrites. | Sections removed or rewritten in `spec-executor.md`, `external-reviewer.md`, `failure-recovery.md`, `chat.md` | 0 |
| NFR-2 | No new infrastructure — no new agent types, no E2E diagnostic scripts, no coordinator core-loop change, no new channel. | New agents / scripts / loop changes / channels introduced | 0 |
| NFR-3 | Auditability — collaboration entries (HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE) accumulate append-only in `chat.md`, never overwritten. | Prior chat entries mutated by a later entry | 0 (append-only) |
| NFR-4 | Machine-actionability — a `BUG_DISCOVERY` entry carries evidence and a fix suggestion as structured fields the coordinator can process mechanically. | `BUG_DISCOVERY` entries the coordinator can convert to a fix task without LLM free-text interpretation | 100% |
| NFR-5 | Consistency — the 6 new signals follow the Spec 6 collaboration-marker convention (live in `chat.md`, not `signals.jsonl`). | New signals placed in the wrong channel | 0 |

## Glossary

- **Cross-branch regression**: a test that passes on `main` but fails on `HEAD`, with neither the test nor its fixture changed in the current spec.
- **Experiment-propose-validate**: the collaboration loop HYPOTHESIS → EXPERIMENT → FINDING → ROOT_CAUSE → FIX_PROPOSAL used by executor and reviewer to converge on a bug's cause.
- **BUG_DISCOVERY**: a structured entry the external-reviewer writes to `task_review.md` recording a bug found via investigation (not via task failure), carrying evidence and a fix suggestion.
- **Collaboration marker**: a `chat.md` signal carrying investigation content (vs a Control signal, which is mechanical JSONL in `signals.jsonl`).
- **Fix task**: a coordinator-generated task in `X.Y.N [FIX X.Y]` format, tracked in `fixTaskMap`, that repairs a defect.
- **`fixTaskMap`**: existing `failure-recovery.md` machinery mapping original tasks to their generated fix tasks, also used for depth/limit checks.
- **Baseline check**: the 3-condition verification (test unchanged, fixture unchanged, backend code path differs) the reviewer performs before modifying a test that passed on `main`.
- **`<exit_code_gate>`**: the spec-executor section that attributes a failure to changed files using `git diff --name-only HEAD`.
- **`progress-regression` FAIL**: an `external-reviewer.md` §3b FAIL that fires only in the mid-flight VE/E2E submode when a previously-green test goes red — not a general regression detector.

## Out of Scope

- **Cross-executable synchronous turn-handoff / blocking-wait protocol** — the runtime mechanism that makes the experiment-propose-validate loop synchronous between two agents from different executables (World B). This is owned by Spec 8 (`pair-debug-auto-trigger`). Spec 7 encodes only the collaboration vocabulary and workflows; it adds NO wait/blocking mechanism. No FR or NFR in this spec describes a wait protocol.
- Single-agent + Claude-subagent sequencing (World A) — already handled by existing parallel-vs-dependent task machinery.
- Coordinator core-loop changes.
- New agent types.
- E2E diagnostic scripts.
- Changes to `signals.jsonl` or its schema.
- Driver/Navigator role concept and auto-trigger conditions for pair-debug mode (Spec 8).
- Resolving the `BUG_DISCOVERY` entry shape inside `task_review.md` and the `channel-map.md` writer reconciliation — these are design-phase decisions, carried forward as constraints (FR-13).

## Dependencies

- **Spec 6 (`signal-log-and-ci-autodetect`, completed via PR #17)** — established the `signals.jsonl` (control) vs `chat.md` (collaboration) separation that the 6 new collaboration markers rely on.
- **Spec 3 (`role-boundaries`)** — modifies the same two agent files (`spec-executor.md`, `external-reviewer.md`) in different sections; Spec 7 changes are additive, low merge risk. Spec 7 should land after Spec 3 if both touch these files.
- Existing `failure-recovery.md` fix-task machinery (`fixTaskMap`, `X.Y.N [FIX X.Y]` format, depth/limit checks, `tasks.md` insertion).
- Existing `task_review.md` reviewer-owned channel.

## Success Criteria

- `references/collaboration-resolution.md` exists with both named workflow blocks (cross-branch regression investigation, experiment-propose-validate).
- The 6 collaboration signals appear in `templates/chat.md` Collaboration markers table; `signals.jsonl` unchanged.
- A `BUG_DISCOVERY` entry in `task_review.md` causes the coordinator to generate exactly one fix task via existing machinery — and zero fix tasks on a duplicate or when the depth limit is reached.
- The cross-branch workflow triggers on any regression type (verifiable by intentionally breaking a non-E2E unit test and confirming the workflow's entry condition matches).
- `external-reviewer.md` carries the hard baseline-check rule; a test that passed on `main` is not modified when the 3-condition check holds or is ambiguous.
- All edits to existing files are additive (no removed/rewritten sections).

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Design infers a blocking-wait protocol from the experiment-propose-validate loop. | Medium | Out of Scope section + research Scope Boundary explicitly forbid it; no FR/NFR describes a wait mechanism. |
| `BUG_DISCOVERY` fix-task trigger duplicates `failure-recovery.md` logic instead of reusing it. | Medium | FR-6/FR-7 mandate reuse of `fixTaskMap`, format, and insertion — only the trigger is new. |
| `<exit_code_gate>` extension is treated as a coordinator/loop change. | Low | FR-3 scopes detection to the executor agent file; NFR-2 forbids loop changes. |
| Merge conflict with Spec 3 on the two shared agent files. | Low | Changes are additive in different sections; Spec 7 lands after Spec 3. |
| Duplicate or runaway fix tasks from repeated `BUG_DISCOVERY` entries. | Medium | FR-8 dedup check + FR-9 depth/limit reuse. |

## Verification Contract

**Project type**: library

**Entry points**:
- `plugins/ralphharness/references/collaboration-resolution.md` (NEW reference file)
- `plugins/ralphharness/references/failure-recovery.md` (extended fix-task trigger)
- `plugins/ralphharness/templates/chat.md` (Collaboration markers legend table)
- `plugins/ralphharness/agents/spec-executor.md` (appended reference)
- `plugins/ralphharness/agents/external-reviewer.md` (baseline-check hard rule + reference)
- Coordinator pre-delegation read of `task_review.md` (existing path; consumes `BUG_DISCOVERY`)

**Observable signals**:
- PASS looks like: `collaboration-resolution.md` exists with both named workflow blocks; `chat.md` Collaboration markers table contains all 6 new signals; `failure-recovery.md` documents the `BUG_DISCOVERY` trigger reusing `fixTaskMap`/`X.Y.N [FIX X.Y]`; `spec-executor.md` and `external-reviewer.md` each contain a reference to `collaboration-resolution.md`; `external-reviewer.md` contains the 3-condition baseline-check hard rule; a single `BUG_DISCOVERY` entry yields exactly one fix task, a duplicate yields zero, and a depth-limit-exceeded case yields zero.
- FAIL looks like: missing file or workflow block; signals placed in `signals.jsonl` instead of `chat.md`; `failure-recovery.md` re-implements fix-task logic rather than reusing it; a coordinator core-loop change present; duplicate `BUG_DISCOVERY` generating two fix tasks; the cross-branch workflow restricted to VE/E2E only; an existing section removed or rewritten.

**Hard invariants**:
- `signals.jsonl` and its schema are not modified.
- The coordinator core loop is not modified.
- The reviewer gains no new write permission (no implementation-file or `tasks.md` write access).
- No new channel, agent type, or E2E diagnostic script is introduced.
- All edits to existing files are additive.

**Seed data**:
- A spec workspace with `tasks.md`, `task_review.md`, `chat.md`, and `.ralph-state.json` containing `fixTaskMap`.
- A git history where at least one test is green on `main` and red on `HEAD` (to exercise the cross-branch workflow).
- An existing fix task in `fixTaskMap` (to exercise duplicate-`BUG_DISCOVERY` detection).

**Dependency map**:
- Spec 6 (`signal-log-and-ci-autodetect`) — owns the `signals.jsonl`/`chat.md` split.
- Spec 3 (`role-boundaries`) — shares `spec-executor.md` and `external-reviewer.md`.
- Spec 8 (`pair-debug-auto-trigger`) — owns the turn-handoff/blocking-wait protocol deliberately excluded here.
- `failure-recovery.md` fix-task machinery and `task_review.md` channel.

**Escalate if**:
- The design appears to require a blocking-wait / turn-handoff mechanism (this is Spec 8, not Spec 7).
- The `BUG_DISCOVERY` entry shape cannot fit `task_review.md` without a schema change.
- A `BUG_DISCOVERY` trigger would require a coordinator core-loop change.
- The `channel-map.md` spec-executor `chat.md`-writer discrepancy cannot be reconciled additively.

## Unresolved Questions

- `BUG_DISCOVERY` entry shape in `task_review.md` — new `status: BUG_DISCOVERY` value within the existing table schema vs a documented additional row/section. Deferred to design (FR-13a) — genuinely open, not pre-resolved.
- `channel-map.md` lists `chat.md` writers as `coordinator, reviewer` only, but `spec-executor.md` writes to `chat.md` via fd 200. Design must add `spec-executor` as a writer or document why the registry omits it (FR-13b).

## Next Steps

1. User approval of these requirements.
2. Run `/ralphharness:design` — resolve FR-13 design decisions (BUG_DISCOVERY entry shape, channel-map reconciliation) and detail the two workflow blocks.
3. Run `/ralphharness:tasks` — break the 5 roadmap changes + 4 edge-case requirements into tasks.
