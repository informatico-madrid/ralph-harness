---
spec: harness-enforcement-gates
basePath: specs/harness-enforcement-gates
phase: requirements
created: 2026-05-19
---

# Requirements: harness-enforcement-gates

## Goal

Harden the RalphHarness plugin by replacing 5 prose-only execution rules with
deterministic shell enforcement gates, so the coordinator LLM can no longer
silently skip VERIFY tasks, advance phases ungated, fabricate fixes, drop
metrics, or un-mark verified tasks.

## User Stories

### US-1: Sequential VERIFY blocking gate
**As a** RalphHarness maintainer
**I want to** mechanically block loop continuation while any preceding `[VERIFY]` task is unsatisfied
**So that** the coordinator cannot skip a mandatory verification task and advance anyway (diagnostic §2.3)

**Acceptance Criteria:**
- [ ] AC-1.1: Given a `tasks.md` where a `[VERIFY]` task at index < `taskIndex` is still `- [ ]`, `stop-watcher.sh` does NOT emit a continuation prompt.
- [ ] AC-1.2: On detection the gate appends a DEADLOCK `control` signal (status `active`) to `signals.jsonl` and halts the loop.
- [ ] AC-1.3: ALL preceding unsatisfied `[VERIFY]` tasks block — no `deferred` marker is recognized or introduced.
- [ ] AC-1.4: The gate logs `BLOCKED: preceding VERIFY task N unsatisfied` (N = task index) for incident review.
- [ ] AC-1.5: When all preceding `[VERIFY]` tasks are `[x]`, the gate is transparent (loop continues unchanged).
- [ ] AC-1.6: The external-reviewer emits DEADLOCK as an `active` `control` signal in `signals.jsonl` (not only `chat.md`), so the existing HOLD-GATE enforces it.
- [ ] AC-1.7: Legacy specs without `signals.jsonl` skip the gate and log a WARN; the loop is not aborted by the gate's absence.

### US-2: Robust fix-presence verification
**As a** RalphHarness maintainer
**I want to** verify a claimed fix against the branch merge-base across committed, staged, and working-tree state
**So that** a fix that is already committed or staged is not misread as absent, and a fabricated fix is not misread as present (diagnostic §3.1)

**Acceptance Criteria:**
- [ ] AC-2.1: A helper script `verify-fix-present.sh` exists, taking `<file> [<pattern>]`.
- [ ] AC-2.2: It computes the base ref with `git merge-base HEAD origin/main` and returns 0 iff `<file>` changed since that base in any of: committed (`git diff <base> HEAD -- <file>`), staged (`git diff --cached -- <file>`), or working tree (`git diff -- <file>`).
- [ ] AC-2.3: When `<pattern>` is supplied, it additionally requires the pattern present in `git show HEAD:<file>` before returning 0.
- [ ] AC-2.4: It returns a non-zero exit code with a diagnostic message when the file is unchanged in all three states.
- [ ] AC-2.5: spec-executor's post-commit check uses `verify-fix-present.sh` instead of `git diff HEAD~1 --stat`.
- [ ] AC-2.6: The coordinator's Layer 3 anti-fabrication review uses `verify-fix-present.sh` instead of bare `git diff HEAD`.
- [ ] AC-2.7: When `origin/main` is unreachable, the script falls back to a documented base (recorded checkpoint SHA) and logs a WARN rather than failing the loop.

### US-3: Phase exit gate
**As a** RalphHarness maintainer
**I want to** task-planner to emit a synthetic `[VERIFY] Phase X exit gate` task as the last task of each phase
**So that** phase advancement is mechanically blocked until the outgoing phase's gates are green (diagnostic §3.3)

**Acceptance Criteria:**
- [ ] AC-3.1: task-planner emits exactly one `[VERIFY] Phase X exit gate` task as the final task of each phase block in `tasks.md`.
- [ ] AC-3.2: The exit-gate task is a normal `[VERIFY]` task — it is picked up by US-1's gate with no special-casing.
- [ ] AC-3.3: The exit-gate task is not coupled to `ciSnapshot` or `.metrics.jsonl` semantics; its only contract is "an unsatisfied `[VERIFY]` task blocks advancement".
- [ ] AC-3.4: A phase with no explicit checkpoint still receives an exit-gate task, so every phase boundary is gated.
- [ ] AC-3.5: Legacy `tasks.md` files generated before this change still run; the gate degrades to "no exit-gate task present" without error.

### US-4: Deterministic per-task metrics
**As a** RalphHarness maintainer
**I want to** `stop-watcher.sh` to call `write_metric()` on every task advancement
**So that** `.metrics.jsonl` is populated deterministically instead of depending on an LLM-discretionary prompt block (diagnostic §4.2)

**Acceptance Criteria:**
- [ ] AC-4.1: On every task advancement, `stop-watcher.sh` sources `write-metric.sh` and calls `write_metric()` for the just-completed task (index, iteration, commit SHA, outcome).
- [ ] AC-4.2: The outcome is derived mechanically — `taskIndex` advanced ⇒ pass; `taskIteration` incremented without advance ⇒ retry/fail — not from an LLM claim.
- [ ] AC-4.3: The LLM-discretionary metrics prompt block in `implement.md` is removed, or demoted to a documented non-authoritative fallback that never duplicates a hook-written line.
- [ ] AC-4.4: `.metrics.jsonl` gains exactly one line per task advancement; the write uses the existing `flock` discipline in `write-metric.sh`.
- [ ] AC-4.5: A spec run that completes N task advancements produces N metric lines with no empty lines.

### US-5: Task-mark integrity guard
**As a** RalphHarness maintainer
**I want to** detect and tier-escalate illegitimate `[x]`→`[ ]` task un-marks
**So that** the coordinator cannot silently un-mark verified tasks, while genuine false positives are filtered before bothering a human (diagnostic §4.3 / §2.2)

**Acceptance Criteria:**
- [ ] AC-5.1: The guard persists a snapshot of `[x]` task IDs each invocation and, on the next invocation, detects any task that was `[x]` and is now `[ ]`.
- [ ] AC-5.2: An un-mark is flagged ILLEGITIMATE when the task has a PASS entry in `task_review.md` AND `external_unmarks[taskId]` did not increase since the prior snapshot.
- [ ] AC-5.3: Tier 1 — on an illegitimate un-mark, the guard emits a DEADLOCK `control` signal to `signals.jsonl` and HALTS advancement immediately.
- [ ] AC-5.4: Tier 2 — before any human escalation, a subagent review/triage runs to filter false positives; if the triaging subagent understands the cause and can resolve it autonomously, it resolves it and the loop resumes.
- [ ] AC-5.5: Tier 3 — the issue is escalated to a human ONLY when the subagent triage determines it is a genuine conflict needing human intervention.
- [ ] AC-5.6: The guard never performs a blind auto-revert of the `[x]` mark.
- [ ] AC-5.7: An un-mark with a matching `external_unmarks[taskId]` increment is LEGITIMATE and is not flagged.
- [ ] AC-5.8: All `tasks.md` reads/writes by the guard use `flock -e 201` on `tasks.md.lock`.
- [ ] AC-5.9: Legacy specs without `task_review.md` skip the guard and log a WARN.

### US-6: Enforcement-as-shell discipline
**As a** RalphHarness maintainer
**I want to** every new enforcement rule to live in a deterministic shell gate, never in coordinator prose
**So that** an LLM under load cannot skip the rule (the master root cause of all 5 diagnostic points)

**Acceptance Criteria:**
- [ ] AC-6.1: Every gate added by this spec is a `stop-watcher.sh` append-only function, a PRE-EXEC-GATE-style block in `implement.md`, or a standalone helper script — never a discretionary prompt instruction.
- [ ] AC-6.2: No existing `stop-watcher.sh` control flow is edited; new gates are appended functions only (loop-safety.md Decision 3).
- [ ] AC-6.3: `plugin.json` and `marketplace.json` versions are bumped for the change set.
- [ ] AC-6.4: Each new gate has `bats` coverage exercising its pass path, block path, and legacy-degradation path.

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | `stop-watcher.sh` MUST NOT emit a continuation prompt while any `[VERIFY]` task at index < `taskIndex` is `[ ]`; an append-only function scans `tasks.md` before the existing continuation check. | High | AC-1.1, AC-1.2, AC-1.5 |
| FR-2 | On a detected preceding unsatisfied `[VERIFY]`, the gate appends a DEADLOCK `control` signal (status `active`) to `signals.jsonl` and halts the loop. | High | AC-1.2, AC-1.4 |
| FR-3 | ALL preceding unsatisfied `[VERIFY]` tasks block advancement; no `deferred` marker is introduced or recognized. | High | AC-1.3 |
| FR-4 | external-reviewer MUST emit DEADLOCK as an `active` `control` signal in `signals.jsonl` so the existing HOLD-GATE enforces it mechanically. | High | AC-1.6 |
| FR-5 | Provide `verify-fix-present.sh <file> [<pattern>]` using `git merge-base HEAD origin/main` plus a three-state diff (committed ∪ staged ∪ working-tree); returns 0 iff the file changed in any state since the base. | High | AC-2.1, AC-2.2, AC-2.4 |
| FR-6 | With a `<pattern>` argument, `verify-fix-present.sh` additionally asserts the pattern is present in `git show HEAD:<file>`. | Medium | AC-2.3 |
| FR-7 | spec-executor's post-commit check MUST call `verify-fix-present.sh` instead of `git diff HEAD~1 --stat`. | High | AC-2.5 |
| FR-8 | The coordinator's Layer 3 anti-fabrication review MUST call `verify-fix-present.sh` instead of bare `git diff HEAD`. | High | AC-2.6 |
| FR-9 | task-planner MUST emit a synthetic `[VERIFY] Phase X exit gate` task as the final task of each phase block in `tasks.md`. | High | AC-3.1, AC-3.4 |
| FR-10 | The phase exit-gate task is an ordinary `[VERIFY]` task enforced by FR-1; it is NOT coupled to `ciSnapshot` or `.metrics.jsonl` semantics. | High | AC-3.2, AC-3.3 |
| FR-11 | `stop-watcher.sh` MUST source `write-metric.sh` and call `write_metric()` on every task advancement, deriving outcome mechanically from `taskIndex`/`taskIteration` deltas. | High | AC-4.1, AC-4.2, AC-4.4 |
| FR-12 | The LLM-discretionary metrics prompt block in `implement.md` MUST be removed or demoted to a documented non-authoritative fallback that never duplicates a hook-written line. | Medium | AC-4.3 |
| FR-13 | A task-mark integrity guard MUST snapshot `[x]` task IDs each invocation and detect `[x]`→`[ ]` transitions on the next invocation. | High | AC-5.1 |
| FR-14 | An un-mark is ILLEGITIMATE when the task has a PASS entry in `task_review.md` AND `external_unmarks[taskId]` did not increase; a matching increment makes it LEGITIMATE. | High | AC-5.2, AC-5.7 |
| FR-15 | Tier 1 — on an illegitimate un-mark the guard emits a DEADLOCK `control` signal to `signals.jsonl` and HALTS advancement immediately. | High | AC-5.3 |
| FR-16 | Tier 2 — before human escalation, a subagent review/triage runs to filter false positives and resolves the issue autonomously when it can. | High | AC-5.4 |
| FR-17 | Tier 3 — the issue is escalated to a human ONLY when the subagent triage classifies it as a genuine conflict needing human intervention. | High | AC-5.5 |
| FR-18 | The integrity guard MUST NOT perform a blind auto-revert; all `tasks.md` access uses `flock -e 201` on `tasks.md.lock`. | High | AC-5.6, AC-5.8 |
| FR-19 | All new gates MUST be deterministic shell (append-only `stop-watcher.sh` function, PRE-EXEC-GATE block, or helper script); no enforcement lives in coordinator prose. | High | AC-6.1, AC-6.2 |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Enforcement-as-shell — every gate is a deterministic shell gate, never an LLM-discretionary prompt instruction. | gates implemented as prose | 0 |
| NFR-2 | Append-only `stop-watcher.sh` — new gates are appended functions; no existing control flow is edited (loop-safety.md Decision 3). | edited pre-existing lines in `stop-watcher.sh` | 0 |
| NFR-3 | Two-writer safety — every `tasks.md` mark read/write uses `flock -e 201` on `tasks.md.lock`. | unlocked `tasks.md` accesses in new code | 0 |
| NFR-4 | Backwards compatibility — missing new state fields default safely; legacy specs without `signals.jsonl` / `task_review.md` skip the affected gate and log a WARN. | loop aborts caused by a missing legacy artifact | 0 |
| NFR-5 | Version discipline — `plugin.json` and `marketplace.json` are bumped (semantic versioning) for the change set. | unbumped plugin manifests after change | 0 |
| NFR-6 | Test coverage — each new gate has `bats` tests covering pass, block, and legacy-degradation paths. | new gates without `bats` coverage | 0 |
| NFR-7 | Performance — each gate's shell scan adds negligible latency per loop iteration. | added wall time per iteration | < 500 ms |

## Glossary

- **Continuation prompt**: the text `stop-watcher.sh` emits to keep the Ralph Loop running for another task.
- **`[VERIFY]` task**: a task in `tasks.md` whose title is prefixed `[VERIFY]`, delegated to qa-engineer for independent verification.
- **Phase exit gate**: a synthetic `[VERIFY] Phase X exit gate` task task-planner appends as the last task of a phase; blocks phase advancement via the VERIFY gate.
- **Three-state diff**: union of committed, staged, and working-tree diffs of a file against the branch merge-base.
- **Merge-base**: `git merge-base HEAD origin/main` — the commit where the current branch diverged from main.
- **DEADLOCK signal**: a `control`-type entry in `signals.jsonl` with status `active`; the HOLD-GATE halts the loop while any active control signal exists.
- **HOLD-GATE**: the existing mechanical block in `implement.md` / `stop-watcher.sh` that stops the loop on active `signals.jsonl` control signals.
- **PRE-EXEC-GATE**: the established `implement.md` pattern for a deterministic shell gate that runs before delegation and routes on exit code.
- **Illegitimate un-mark**: an `[x]`→`[ ]` transition on a task with a PASS entry in `task_review.md` without a matching `external_unmarks` increment.
- **`external_unmarks`**: `.ralph-state.json` map of `taskId → count`; only the external-reviewer is authorized to increment it.
- **Tiered escalation**: halt → subagent triage → conditional human escalation; the integrity guard's response to an illegitimate un-mark.

## Out of Scope

- **Coordinator auto-recovery (diagnostic §3.2)** — automatic re-delegation after coordinator idle/DEADLOCK. Conflicts with the circuit-breaker "manual reset only" philosophy (loop-safety.md Decision 5) and deserves its own spec.
- **qa-engineer fabrication detection (diagnostic §2.1)** — contrasting a VERIFICATION_PASS report against real command output. Owned by the anti-fabrication / reality-verification area, not this spec.
- **2.0-ADJ NFR enforcement (diagnostic §4.4)** — enforcing expert adjudication of surviving mutants. Spec-specific, not a plugin gate.
- **Duplicate chat.md message suppression (diagnostic §4.1)** — re-delegation noise; not an enforcement gate.
- **Blind auto-revert of an illegitimate un-mark** — explicitly excluded; the guard detects and tier-escalates, it never silently rewrites the two-writer file.
- **A `deferred` `[VERIFY]` marker** — explicitly not introduced; all preceding unsatisfied `[VERIFY]` tasks block.
- **Inconsistent-data validation against `.progress.md` baseline (diagnostic §3.4)** — separate concern.

## Dependencies

| Dependency | Relationship |
|------------|--------------|
| `loop-safety-infra` | Owns the circuit breaker, heartbeat, `write-metric.sh`, and the append-only `stop-watcher.sh` convention. FR-1, FR-2, FR-11, FR-13 extend it; not modified. |
| `signal-log-and-ci-autodetect` | Owns `signals.jsonl`, `lib-signals.sh`, `ciSnapshot`. FR-2, FR-4, FR-15 build on its DEADLOCK `control` signal semantics. May need a note on DEADLOCK signal usage. |
| `collaboration-resolution` | Owns the external-reviewer FAIL/un-mark protocol, `chat.md` DEADLOCK, and `external_unmarks`. FR-4 changes reviewer DEADLOCK routing; FR-14 reads `external_unmarks`. |
| `reviewer-warmup` | Owns the liveness heartbeat and convergence detection. No change; relevant context for loop-halt behavior. |
| `engine-state-hardening` | Owns `.ralph-state.json` field hardening. Any new state field (mark snapshot persistence) follows its conventions. |
| `reality-verification-principle` / `qa-verification` | Own anti-fabrication / VF reality-check. FR-8 (Layer 3 robust diff) overlaps the anti-fabrication layer. |
| External tooling | `git` (merge-base, diff, show, log), `flock`, `jq`, `awk`/`grep`, `bats` for tests. |

## Success Criteria

- A spec run that skips a preceding `[VERIFY]` task is halted by FR-1 with a DEADLOCK signal — no later task is delegated.
- `verify-fix-present.sh` returns the correct result for a fix in each of the three git states (committed, staged, working-tree) and for an absent fix.
- task-planner output for a multi-phase feature contains one `[VERIFY] Phase X exit gate` task per phase.
- A completed spec run yields one `.metrics.jsonl` line per task advancement, with zero empty lines.
- An illegitimate `[x]`→`[ ]` un-mark triggers halt → subagent triage, and reaches a human only when triage classifies it as a genuine conflict.
- All new gates pass their `bats` suites including the legacy-degradation path; `plugin.json` + `marketplace.json` versions are bumped.

## Verification Contract

**Project type**: `cli`

**Entry points**:
- `plugins/ralphharness/hooks/scripts/stop-watcher.sh` — new append-only functions: sequential VERIFY gate, per-task metric emission, task-mark integrity guard.
- `plugins/ralphharness/hooks/scripts/verify-fix-present.sh` — new standalone helper script.
- `plugins/ralphharness/commands/implement.md` — Layer 3 review uses `verify-fix-present.sh`; metrics prompt block removed/demoted.
- `plugins/ralphharness/agents/spec-executor.md` — post-commit check uses `verify-fix-present.sh`.
- `plugins/ralphharness/agents/external-reviewer.md` — DEADLOCK routed to `signals.jsonl`.
- `plugins/ralphharness/agents/task-planner.md` — emits `[VERIFY] Phase X exit gate` tasks.
- `bats` test files under the plugin's test directory exercising each gate.

**Observable signals**:
- PASS looks like:
  - VERIFY gate: with an unsatisfied preceding `[VERIFY]`, `stop-watcher.sh` produces no continuation prompt and `signals.jsonl` gains an `active` `control` DEADLOCK line; exit code halts the loop.
  - `verify-fix-present.sh`: exit 0 when the file changed in any git state since merge-base; non-zero with a diagnostic message when unchanged.
  - Metrics: `.metrics.jsonl` line count equals task-advancement count after a run.
  - Phase gate: generated `tasks.md` contains a `[VERIFY] Phase X exit gate` line as the last task of each phase.
  - Integrity guard: an illegitimate un-mark yields an `active` DEADLOCK signal and a triage subagent invocation; a legitimate un-mark yields no signal.
  - `bats` suites exit 0.
- FAIL looks like:
  - Loop continues past an unsatisfied preceding `[VERIFY]`; no DEADLOCK signal appended.
  - `verify-fix-present.sh` reports a committed/staged fix as absent (or an absent fix as present).
  - `.metrics.jsonl` empty or short after a multi-task run.
  - No exit-gate task in a multi-phase `tasks.md`.
  - An illegitimate un-mark passes silently, or the guard blind-auto-reverts the mark.
  - An edited pre-existing line in `stop-watcher.sh`; a `tasks.md` write without `flock -e 201`.

**Hard invariants**:
- Existing `stop-watcher.sh` control flow is unchanged — gates are appended functions only (loop-safety.md Decision 3).
- The existing HOLD-GATE, circuit breaker, and heartbeat behavior continue to work unchanged.
- Only the external-reviewer increments `external_unmarks`; the integrity guard never writes it.
- Every `tasks.md` mark access uses `flock -e 201` on `tasks.md.lock`.
- Legacy specs without `signals.jsonl` / `task_review.md` are not aborted by a missing artifact — the affected gate skips with a WARN.
- The integrity guard never blind-auto-reverts a `[x]`/`[ ]` mark.

**Seed data**:
- A fixture spec directory with `tasks.md` (multi-phase, mixed `[x]`/`[ ]` `[VERIFY]` tasks), `signals.jsonl`, `task_review.md` (PASS entries), `.ralph-state.json` (`taskIndex`, `taskIteration`, `external_unmarks`), `.metrics.jsonl`.
- A git repo fixture with a branch diverged from `origin/main` and a fix staged in each of: committed, staged, working-tree, and absent.
- A legacy fixture lacking `signals.jsonl` and `task_review.md` for the degradation path.

**Dependency map**:
- Shares `stop-watcher.sh` and `write-metric.sh` with `loop-safety-infra`.
- Shares `signals.jsonl` / `lib-signals.sh` with `signal-log-and-ci-autodetect`.
- Shares `external_unmarks`, external-reviewer protocol, and `chat.md` DEADLOCK with `collaboration-resolution`.
- Shares `.ralph-state.json` field conventions with `engine-state-hardening`.

**Escalate if**:
- A proposed gate cannot be implemented append-only and would require editing existing `stop-watcher.sh` flow.
- An illegitimate un-mark triage is genuinely ambiguous (genuine conflict — Tier 3 human escalation).
- `verify-fix-present.sh` cannot resolve a base ref (no `origin/main`, no recorded checkpoint SHA).
- A change to DEADLOCK signal semantics would break `signal-log-and-ci-autodetect` or `collaboration-resolution` consumers.

## Unresolved Questions

- Where the `[x]` task-mark snapshot is persisted — a sidecar file (`.task-marks.prev`) vs a `.ralph-state.json` field. Resolve in design per `engine-state-hardening` conventions.
- Which subagent type runs the Tier 2 integrity triage (external-reviewer vs a dedicated triage agent), and how its autonomous-resolution authority is bounded.
- How task-planner names the exit-gate task when a phase already ends with a `[VERIFY]` checkpoint — append a second gate task, or label the existing one. Recommend always appending a distinct `Phase X exit gate` task for an unambiguous mechanical marker.

## Next Steps

1. Approve requirements, then run `/ralphharness:design` to produce `design.md`.
2. Design resolves the snapshot-persistence location, the Tier 2 triage agent, and the exit-gate naming.
3. task-planner breaks the design into POC-first tasks with `bats` coverage per gate.
