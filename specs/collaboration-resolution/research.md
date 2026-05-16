---
spec: collaboration-resolution
phase: research
created: 2026-05-15
---

# Research: collaboration-resolution

## Executive Summary

Spec 7 encodes an agent collaboration pattern that already works ad hoc — spec-executor and external-reviewer diagnosing a cross-branch E2E regression via chat.md — into explicit, repeatable rules. It is LOW complexity: no new infrastructure, only new reference docs, new chat collaboration signals, and one new fix-task trigger. It builds directly on Spec 6's `signals.jsonl` (control signals) / `chat.md` (collaboration) separation. Feasibility is HIGH.

## Problem Statement

In a live spec execution, spec-executor and external-reviewer collaborated to diagnose an E2E regression (a test green on `main`, red on `HEAD`). They ran `git diff main...HEAD`, exchanged hypotheses, ran experiments, and found the root cause (a renamed method that lost cache population). The behavior was correct — but it happened by improvisation, not by rule. Three concrete gaps make it unreliable:

1. **No cross-branch regression workflow** — no rule says "compare main vs HEAD on the failing code path."
2. **No experiment-propose-validate pattern** — chat.md has control/collaboration signals but no hypothesis→experiment→finding→root-cause vocabulary.
3. **No reviewer-initiated fix task** — fix tasks only fire on executor non-completion (`failure-recovery.md`). A bug the reviewer *discovers* (not via task failure) has no path to a fix task.

A fourth, related risk: agents may "fix" a failing E2E test by editing the test itself when the real cause is a backend regression — there is no baseline-check guardrail against this.

## External Research

### Prior Art — OpenHands SDK (`docs/harness-engineering/11-openhands-deep-dive.md`)

- **Immutable event log (§4)**: OpenHands records typed events (`ActionEvent`, `ObservationEvent`, `AgentErrorEvent`) in an append-only `EventLog`; events are never mutated. Transferable lesson: a *finding* in a collaboration thread should be an appended event, not an edit. Spec 6 already applied this principle to `signals.jsonl` (control signals append a `resolved` event rather than editing the original). Spec 7 follows the same discipline: HYPOTHESIS / EXPERIMENT / FINDING / ROOT_CAUSE entries accumulate in `chat.md` append-only, forming an auditable investigation trail.
- **Critic system (§7)**: OpenHands runs a critic on write actions *before* execution and enriches the `ActionEvent` with a `critic_result`. RalphHarness's external-reviewer is the *post-execution* analogue (`docs/.../11` §11.2 explicitly frames the two as complementary). The transferable lesson for Spec 7: the reviewer's investigative output (a discovered bug) deserves a structured, machine-actionable channel — `BUG_DISCOVERY` in `task_review.md` — exactly as a `critic_result` is structured metadata, not free text.
- **`security_risk` / structured event fields (§4.3)**: every OpenHands event carries typed metadata. Lesson: a `BUG_DISCOVERY` entry must carry evidence + fix suggestion as structured fields so the coordinator can mechanically turn it into a fix task.

### Prior Art — Harness Engineering (`docs/harness-engineering/README.md`, `10-deep-agents-deep-dive.md`)

- The harness-engineering corpus (Fowler, OpenAI, LangChain) frames a harness as interlocking systems where agent behavior is *codified*, not improvised. Spec 7 is a textbook codification: take an emergent behavior and make it a first-class workflow.
- Deep Agents' composable middleware (§10) shows behaviors layered as discrete, named units. Lesson for Spec 7: the cross-branch workflow and the experiment-propose-validate loop should be named, self-contained rule blocks in a dedicated reference file — referenced by agents, not duplicated into them.

### Best Practices

- **Append-only investigation log** — never edit prior hypotheses/findings; append corrections. Source: OpenHands EventLog (`11-openhands-deep-dive.md` §4.2).
- **Structured machine-actionable triage** — discovered bugs become structured records the coordinator can mechanically process, not prose. Source: OpenHands `critic_result` (§7).
- **Codify emergent behavior** — turn working improvisation into explicit rules. Source: harness-engineering corpus (`README.md`).

### Pitfalls to Avoid

- **Don't modify a test to make it pass when the cause is a code regression.** This masks the real bug. Mitigation: the "before modifying tests, check baseline" hard rule (3-condition check on `git diff main...HEAD`).
- **Don't over-prescribe.** The roadmap warns against micro-rules — encode the *workflow* (hypothesis → experiment → root cause), not every step.
- **Don't duplicate the failure-recovery fix-task format.** `BUG_DISCOVERY` must reuse the existing `failure-recovery.md` fix-task generation, with a different *trigger* only.

## Codebase Analysis

### Current State — files Spec 7 modifies (verified against real content)

| File | Current state | Spec 7 change |
|------|---------------|---------------|
| `references/failure-recovery.md` | Fix tasks fire **only** when spec-executor does not output `TASK_COMPLETE` ("Parse Failure Output", "Recovery Mode Entry Point"). Fix task format is `X.Y.N [FIX X.Y] [fix_type:...]`, inserted after the original task via Edit tool, tracked in `fixTaskMap`. No reviewer-initiated trigger exists. | **Extend**: add a second trigger — a `BUG_DISCOVERY` entry in `task_review.md` makes the coordinator generate a fix task using the *same* format and `fixTaskMap` machinery. |
| `templates/chat.md` | Signal Legend has two tables: Control signals (→ `signals.jsonl`: HOLD, PENDING, URGENT, DEADLOCK, INTENT-FAIL, SPEC-ADJUSTMENT, SPEC-DEFICIENCY) and Collaboration markers (→ `chat.md`: OVER, ACK, CONTINUE, STILL, ALIVE, CLOSE). Spec 6 separation already in place. | **Update**: add HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY to the Collaboration markers table. |
| `agents/spec-executor.md` | Has `<external_review>` (reads `task_review.md` before each task), `<exit_code_gate>` (attributes failures, checks `git diff --name-only HEAD`), `<stuck>` (false-fix-loop detection), `<chat>` (ACK/HOLD/PENDING). It already does breadth-first investigation but has **no cross-branch (main vs HEAD) regression workflow**. | **Append**: a reference to `collaboration-resolution.md` so the executor follows the cross-branch investigation workflow. |
| `agents/external-reviewer.md` (v0.2.1) | Has Judge Pattern, Supervisor Role, Test Surveillance (§3), E2E/VE Review (§3b — includes a `progress-regression` FAIL when a previously-green test goes red, but **only in the mid-flight VE/E2E submode**, §3b Step 6), `Signal Emission Contract`. Reviewer **can** write `task_review.md`, can produce FAIL with `fix_hint`. Reviewer **cannot** create fix tasks and has **no baseline-check rule** before suggesting test edits. | **Add**: the "before modifying tests, check baseline" hard rule + a reference to `collaboration-resolution.md`. (`BUG_DISCOVERY` is written to `task_review.md`, which the reviewer already owns — no new write permission needed.) |
| `references/collaboration-resolution.md` | **Does not exist.** | **New file**: cross-branch regression investigation workflow + experiment-propose-validate pattern. |

### Existing Patterns to Leverage

- **Fix-task machinery** (`failure-recovery.md`): `fixTaskMap`, depth/limit checks, `Insert Fix Task into tasks.md`, `X.Y.N [FIX X.Y]` format. `BUG_DISCOVERY` reuses all of it — only the trigger differs.
- **`task_review.md` as reviewer-owned channel** (`channel-map.md`: single writer, no lock). The reviewer already writes review entries there as **markdown table rows** (columns: status / severity / reviewed_at / task_id / criterion_failed / evidence / fix_hint / resolved_at — verified against `templates/task_review.md`; status values are `FAIL | WARNING | PASS | PENDING`). **Design decision surfaced**: a `BUG_DISCOVERY` entry must either (a) use a new `status: BUG_DISCOVERY` value within the existing table schema (evidence/fix_hint columns carry the structured payload), or (b) require a documented additional row/section format if the table columns are insufficient. This is a decision for the design phase — it is not pre-resolved.
- **`signals.jsonl` / `chat.md` separation** (Spec 6, completed): control signals are mechanical JSONL; `chat.md` is the rich-collaboration channel. The 6 new signals are **collaboration markers** in `chat.md` — consistent with Spec 6's design, not control signals.
- **`progress-regression` FAIL** (`external-reviewer.md` §3b): the reviewer detects "test green in cycle N, now red." **Scoped narrowly**: verified against `external-reviewer.md`, this FAIL fires **only in the mid-flight VE/E2E submode** (`### Step 6 — Progress-real check (mid-flight only)`). A non-E2E regression — e.g. a unit test green on `main` but red on `HEAD` — would **not** hit `progress-regression`. So it is a detection point for E2E regressions only, not a general one. Requirements must clarify whether the cross-branch workflow triggers solely on VE/E2E regressions or on any regression (and, if the latter, what detects non-E2E regressions).
- **`git diff --name-only HEAD`** already used by `<exit_code_gate>` for failure attribution — extending to `git diff main...HEAD` is a small, idiomatic step.

### Dependencies

- **Spec 6 `signal-log-and-ci-autodetect`** (completed): established `signals.jsonl` (control) vs `chat.md` (collaboration). Spec 7's 6 new signals are collaboration markers — they belong in `chat.md`, not `signals.jsonl`. No change to `signals.jsonl`.
- **Spec 3 (role-boundaries)**: modifies the same two agent files (`spec-executor.md`, `external-reviewer.md`) in different sections. Spec 7's changes are additive (append a reference; add a hard rule) — no conflict, per `plan.md`.
- No external libraries. All changes are markdown reference/template/agent files.

### Constraints

- **No coordinator core-loop change.** `BUG_DISCOVERY` must be processed by the coordinator's *existing* fix-task path (the coordinator already reads `task_review.md` pre-delegation per `channel-map.md`).
- **No new agent types, no E2E diagnostic scripts** (roadmap NOT-in-scope).
- **Reviewer write boundaries unchanged** — reviewer writes `task_review.md` (already permitted); it does not gain implementation-file or `tasks.md` fix-insertion rights. The coordinator inserts the fix task.
- **Channel-map**: no new channel — `BUG_DISCOVERY` rides in the existing `task_review.md` channel; the 6 new signals ride in the existing `chat.md` channel.
- **INFO — `channel-map.md` writer discrepancy (for design phase)**: the Channel Registry lists `chat.md` writers as only `coordinator, reviewer` (verified, line 20). Yet `spec-executor.md` has a `<chat>` section that writes to `chat.md` via fd 200, and Spec 7 formalizes executor↔reviewer chat collaboration. The design phase must either **add `spec-executor` as a `chat.md` writer in `channel-map.md`** or **explicitly confirm** the executor's existing chat writes are intentional and document why the registry omits it. This is not asserted to need "no change" — it must be reconciled in design.

## Related Specs

| Spec | Relevance | Relationship | May Need Update |
|------|-----------|--------------|-----------------|
| signal-log-and-ci-autodetect (Spec 6) | High | Established `signals.jsonl`/`chat.md` split that Spec 7 builds on; defines where the 6 new signals live (`chat.md`) | No |
| role-boundaries (Spec 3) | Medium | Modifies the same two agent files; Spec 7 changes are additive in different sections | No |
| engine-state-hardening (Spec 1) | Low | Original grep-based HOLD check, superseded by Spec 6 | No |

### Coordination Notes

Spec 7 must land after Spec 3 if both touch `spec-executor.md`/`external-reviewer.md`, but changes are additive (append reference, add rule block) — low merge risk. Spec 7 assumes Spec 6's `chat.md` is already freed of control signals; this is satisfied. No spec needs a follow-up update because of Spec 7.

## Feasibility Assessment

| Aspect | Assessment | Notes |
|--------|------------|-------|
| Technical Viability | High | All changes are markdown; reuses existing fix-task and review machinery |
| Effort Estimate | S | 1 new reference file + 4 small edits to existing files |
| Risk Level | Low | Additive changes; no coordinator loop or schema change |

## Recommendations for Requirements

1. **Create `references/collaboration-resolution.md`** with two named workflow blocks: (a) **Cross-branch regression investigation** — when a test green on `main` is red on `HEAD` and neither test nor fixture changed: run `git diff main...HEAD` on the failing code path, identify the semantic change, propose a fix, run the test to verify; (b) **Experiment-propose-validate** — reviewer proposes HYPOTHESIS → executor runs EXPERIMENT → both compare FINDING → converge on ROOT_CAUSE → FIX_PROPOSAL.
2. **Add 6 collaboration signals to `templates/chat.md`** Collaboration markers table: HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY. They are collaboration markers (→ `chat.md`), not control signals — consistent with Spec 6.
3. **Extend `references/failure-recovery.md`** with a new fix-task trigger: a `BUG_DISCOVERY` entry in `task_review.md` (evidence + fix suggestion) makes the coordinator generate a fix task using the existing `X.Y.N [FIX X.Y]` format and `fixTaskMap` machinery. Document it as a *trigger* distinct from executor non-completion — reuse all downstream logic.
4. **Append a `collaboration-resolution.md` reference to `agents/spec-executor.md`** so the executor follows the cross-branch workflow during regression investigation (natural extension of `<exit_code_gate>` failure attribution).
5. **Add to `agents/external-reviewer.md` a hard rule**: "Before modifying any E2E test that passed on `main`, verify (a) the test file is unchanged in this spec (`git diff main...HEAD -- tests/e2e/`), (b) the fixture/environment is unchanged, (c) the backend code path differs. If all three hold, the problem is environmental/a backend regression — DO NOT modify the test." Plus a reference to `collaboration-resolution.md`.

## Scope Boundary — Turn-Taking / Blocking-Wait is OUT OF SCOPE

The experiment-propose-validate loop (HYPOTHESIS → EXPERIMENT → FINDING → ROOT_CAUSE)
reads like a multi-turn synchronous exchange. It is **not** — and the requirements/design
agents must not infer that Spec 7 needs a "wait for a reply" mechanism. There are two
distinct worlds; only one is relevant here:

- **World A — a single agent and its Claude subagents** (parallel or sequential Task-tool
  subagents). Waiting and sequencing here is **already handled** by the existing
  parallel-vs-dependent task machinery. Not a problem, not in scope.
- **World B — `chat.md` communication between two agents from DIFFERENT executables**
  (e.g. the spec-executor process and the external-reviewer process). A synchronous
  "wait for the answer before proceeding" protocol genuinely **is** needed here — but
  that runtime turn-handoff mechanism is **owned by Spec 8 (pair-debug-auto-trigger)**,
  not Spec 7.

**Spec 7 encodes only the collaboration *content* pattern**: the HYPOTHESIS / EXPERIMENT /
FINDING / ROOT_CAUSE / FIX_PROPOSAL / BUG_DISCOVERY vocabulary, the cross-branch regression
workflow, and the BUG_DISCOVERY → fix-task trigger. **Spec 7 adds NO blocking-wait /
turn-handoff mechanism.**

## Open Questions

- **OUT OF SCOPE — not an open question for Spec 7.** The cross-executable `chat.md`
  synchronous turn-handoff protocol (blocking wait for a reply) is a known gap and is
  intentionally **out of scope for Spec 7** — it is owned by **Spec 8
  (pair-debug-auto-trigger)**. Spec 7 encodes only the collaboration vocabulary and
  workflows; the runtime turn-taking mechanism that makes the propose-validate loop
  synchronous is Spec 8's responsibility. The requirements/design agents must NOT build
  a wait protocol into Spec 7.
- **Cross-branch workflow trigger surface** — requirements must clarify whether the
  cross-branch regression workflow triggers only on VE/E2E regressions (where
  `progress-regression` fires) or on any regression including non-E2E unit-test
  regressions. See Codebase Analysis note on `progress-regression`.
- **`BUG_DISCOVERY` entry shape in `task_review.md`** — design must decide between a new
  `status: BUG_DISCOVERY` value within the existing table schema or a documented
  additional row/section format. See Codebase Analysis note on `task_review.md`.
- **`channel-map.md` spec-executor `chat.md` writer** — design must reconcile the
  registry (see INFO item in Constraints).

## Sources

- `docs/ENGINE_ROADMAP.md` — Spec 7 section (authoritative 5-change table)
- `docs/harness-engineering/11-openhands-deep-dive.md` — §4 immutable event log, §7 critic system, §11 lessons
- `docs/harness-engineering/README.md`, `docs/harness-engineering/10-deep-agents-deep-dive.md` — composable middleware, codifying behavior
- `specs/collaboration-resolution/plan.md` — triage output, acceptance criteria, interface contracts
- `specs/signal-log-and-ci-autodetect/research.md` — Spec 6 `signals.jsonl`/`chat.md` separation
- `plugins/ralphharness/references/failure-recovery.md`, `templates/chat.md`, `templates/task_review.md`, `references/channel-map.md`
- `plugins/ralphharness/agents/spec-executor.md`, `agents/external-reviewer.md` (v0.2.1)
