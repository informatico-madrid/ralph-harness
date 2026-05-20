---
spec: harness-enforcement-gates
phase: research
created: 2026-05-19
---

# Research: harness-enforcement-gates

## Executive Summary

RalphHarness provides correct *structure* (phases, delegation, separate VERIFY,
external reviewer) but enforces almost none of its own rules mechanically. The
coordinator advances on a single check — `taskIndex < totalTasks` — with no
sequential VERIFY gate, no phase-exit gate, no auto-recovery, and no integrity
guard against un-marking tasks. Metrics never get written because the emission
code is buried in a coordinator *prompt* that the LLM silently skips. The
cross-cutting root cause: enforcement lives as English prose in agent/reference
markdown, where an LLM can ignore it, instead of as deterministic shell gates in
the hooks. 4 of 5 points are HIGH feasibility because the plugin already has the
machinery (PRE-EXEC-GATE pattern, `flock` locks, `signals.jsonl`, circuit
breaker, `write-metric.sh`) — the fix is to *wire* it, not invent it.

## External Research

Research is internal-only (this spec fixes the plugin itself). No web search
performed — the authoritative sources are the diagnostic and the plugin source.
Prior-art search was done against the repo's own spec history (see Related Specs).

### Pitfalls to Avoid

- **Prose-as-enforcement**: every diagnostic finding traces to a rule that exists
  only in markdown prose. Adding *more* prose will not fix it. Gates must be shell.
- **Decision 3 (loop-safety.md)**: `stop-watcher.sh` is append-only by policy —
  new gates append functions, never edit existing flow.
- **Two-writer files**: `tasks.md` has two writers (executor marks `[x]`,
  reviewer unmarks). Any integrity guard MUST use `flock -e 201` on
  `tasks.md.lock` (channel-map.md).

## Codebase Analysis

### Point 1 — Skipped [VERIFY] task / unresolved DEADLOCK (diagnostic §2.3)

**(a) Current behavior.**
- The ONLY continuation condition is `stop-watcher.sh:676`:
  `if [ "$PHASE" = "execution" ] && [ "$TASK_INDEX" -lt "$TOTAL_TASKS" ]`.
- Advancement is purely numeric: `coordinator-pattern.md:690-727` "State Update"
  does `taskIndex += 1` after TASK_COMPLETE. Nothing inspects whether a *prior*
  `[VERIFY]` task is still `[ ]`.
- VERIFY detection (`coordinator-pattern.md:399-408`) only routes the *current*
  task to qa-engineer. There is no look-back.
- `implement.md:284-292` "Drift Detection": case 2 (`CURRENT_INDEX > COMPLETED`)
  explicitly logs `"tasks may have been unmarked intentionally"` and **"No
  correction: allow execution to continue"** — i.e. skipping is tolerated by
  design.
- DEADLOCK handling (`coordinator-pattern.md:242`) is a *prose* HARD STOP for the
  coordinator, but it depends on the coordinator reading `chat.md` and obeying.
  The mechanical `HOLD-GATE` (`implement.md:639-661`, `stop-watcher.sh:688-707`)
  only blocks on `signals.jsonl` `status:"active"` control signals — and DEADLOCK
  in §2.3 was escalated in `chat.md`, not `signals.jsonl`, so the mechanical gate
  never fired.

**(b) Root cause.** No "preceding mandatory VERIFY unsatisfied" predicate exists
anywhere. Advancement is `taskIndex+1` with zero precondition. DEADLOCK is only a
hard stop if it lands in `signals.jsonl` AND the coordinator LLM honors prose.

**(c) Enforcement options.**
1. **Sequential VERIFY blocking gate in `stop-watcher.sh`** (append-only fn).
   Before emitting the continuation prompt, scan `tasks.md` lines `0..TASK_INDEX-1`;
   if any line matching `[VERIFY]` is still `- [ ]`, do not continue — log
   `"BLOCKED: preceding VERIFY task N unsatisfied"` and append a DEADLOCK signal
   to `signals.jsonl`. Tradeoff: needs reliable VERIFY line detection (grep
   `\[VERIFY\]` on unchecked lines) and a way to distinguish "skipped" from
   "legitimately deferred" (none exists today — treat all as blocking).
2. **Pre-delegation gate in `implement.md` PRE-EXEC-GATE block.** Same scan, run
   inside the existing gate plumbing. Tradeoff: relies on coordinator LLM running
   the bash block; weaker than (1) which runs unconditionally in the hook.
3. **Route reviewer DEADLOCK to `signals.jsonl`.** Make external-reviewer emit
   DEADLOCK as a `control` signal (status `active`) so the existing HOLD-GATE
   stops the loop mechanically. Tradeoff: requires external-reviewer.md change;
   complements (1), does not replace it.

**(d) Feasibility: HIGH.** Option 1+3 combined. The scan is a 5-line awk; the
hook already iterates `tasks.md` to extract `TASK_BLOCK` (`stop-watcher.sh:743-758`).

### Point 2 — git diff insufficient to confirm a claimed fix (diagnostic §3.1)

**(a) Current behavior.**
- spec-executor post-commit check: `spec-executor.md:73` —
  `git diff HEAD~1 --stat` (last-commit-vs-its-parent; only catches *unexpected
  deletions*, not "claimed fix absent").
- `<exit_code_gate>` (`spec-executor.md:213-228`) uses `git diff --name-only HEAD`
  (working-tree only) to attribute a failing file, and `git diff main...HEAD` for
  cross-branch regression.
- Coordinator Layer 4 artifact review: `coordinator-pattern.md:356` records
  `TASK_START_SHA` and later does `git diff --name-only $TASK_START_SHA HEAD`.
- **The §3.1 bug**: the coordinator validated a claimed fix with `git diff HEAD`
  (working tree only). If the change is already committed or staged, working-tree
  diff is empty — so an empty diff was wrongly read as "fix absent" (and
  conversely could hide a fix that *does* exist). `git diff HEAD~1` is also wrong:
  it only sees the single most recent commit.

**(b) Root cause.** No single comparison covers all three states the change can
live in (working tree, index/staged, committed since branch point). Each existing
check covers exactly one or two states, so any check is defeatable by the change
being in a different state.

**(c) Enforcement options.**
1. **Branch-point three-state check.** `git merge-base HEAD origin/main`
   (or the recorded `TASK_START_SHA` / checkpoint SHA), then
   `git diff <base> HEAD -- <files>` (all commits on the branch) **plus**
   `git diff HEAD -- <files>` (uncommitted) — union proves whether the path
   changed *anywhere* since branch divergence. Tradeoff: needs a reliable base
   ref; `TASK_START_SHA` is per-task, `checkpoint.sha` is per-spec — pick the spec
   checkpoint for "does this fix exist in the branch at all".
2. **`git log -p <base>..HEAD -- <file>`** to confirm the *specific lines* of the
   claimed fix exist (semantic confirmation, not just file-touched). Tradeoff:
   heavier; best reserved for the coordinator's anti-fabrication Layer 3.
3. **Helper script `verify-fix-present.sh`** that takes `<file> [<pattern>]` and
   returns 0 if the path changed since branch-point in any state (and, with a
   pattern, that the pattern is present in `HEAD:<file>`). Tradeoff: new script,
   but makes the check reusable by both executor and coordinator.

**Recommended approach.** Verification of "a claimed fix exists" = path changed
since the branch's `merge-base` with `main` across committed+staged+working-tree.
Concretely: `git diff "$(git merge-base HEAD origin/main)" HEAD -- <file>` is
non-empty, OR `git diff -- <file>` (uncommitted) is non-empty. For semantic
fixes, additionally assert the fix pattern is in `git show HEAD:<file>`.

**(d) Feasibility: HIGH.** Pure git/shell; encapsulate as a helper script and
call it from spec-executor's post-commit check and the coordinator's Layer 3.

### Point 3 — Phase gate not enforced (diagnostic §3.3)

**(a) Current behavior.**
- Phases exist as prose in `phase-rules.md` and as section headers in `tasks.md`
  (`## Phase 1: ...`). `executionPhase` (`coordinator-pattern.md:44-50`,
  `729-751`) is written purely to scope *reference loading* in `implement.md` —
  it carries no exit criteria.
- Phase transition = the coordinator notices the next task's `## Phase` header
  differs (used only for the git-push heuristic, `coordinator-pattern.md:797`).
- `[VERIFY]` checkpoint tasks are inserted *within* phases
  (`phase-rules.md:372-421`) but a failing checkpoint only blocks its own task —
  there is no "all of Phase A's gates green" predicate before Phase B's first
  task. The §3.3 design said "Phase A green before Phase B"; the coordinator has
  no concept of phase *exit criteria* at all.

**(b) Root cause.** `executionPhase` is a context-loading hint, not a gate.
There is no machine-readable phase-exit contract; the design-level gate lived
only in `design.md` prose.

**(c) Enforcement options.**
1. **Phase-boundary VERIFY gate.** On phase transition (next task's `## Phase`
   header differs), require that every `[VERIFY]` task in the *outgoing* phase is
   `[x]` AND its last `.metrics.jsonl` entry / `ciSnapshot` is `pass`. This
   reuses Point 1's scan, scoped to the phase block. Tradeoff: only as strong as
   VERIFY tasks being honestly marked — pair with Point 1 + Point 5.
2. **Explicit phase-exit gate task.** task-planner emits a synthetic
   `[VERIFY] Phase X exit gate` as the last task of each phase; the coordinator
   already blocks on unsatisfied VERIFY (after Point 1). Tradeoff: changes
   task-planner output; cleanest because the gate becomes a first-class task.
3. **`phaseGate` state field** written by the coordinator (`{phase, status}`)
   and checked by `stop-watcher.sh` before continuing into a new phase.
   Tradeoff: another state field to maintain; mechanically strongest.

**(d) Feasibility: MEDIUM.** The transition point is detectable (phase header
change) but a generic "gate green" predicate needs a data source (ciSnapshot,
metrics, or a dedicated gate task). Option 2 is the lowest-risk: it reduces the
phase gate to "an unsatisfied VERIFY task", which Point 1 already enforces.

### Point 4 — `.metrics.jsonl` left empty (diagnostic §4.2)

**(a) Current behavior.**
- `implement.md:162` creates the file: `touch "$SPEC_PATH/.metrics.jsonl"`.
- The writer exists and is sound: `write-metric.sh` provides `write_metric()`
  with `flock` and full JSONL schema.
- It is *invoked* only from a prose code block inside the coordinator prompt
  ("After TASK_COMPLETE — write metrics", `implement.md:680-708`). That block
  hard-codes `VERIFY_EXIT=0` and depends entirely on the coordinator LLM choosing
  to run it.
- `lib-context.sh:111-130` also appends *condensation* events — but only when a
  condense fires.
- Net: the only per-task metric path is an LLM-discretionary prompt block. In the
  §4.2 run the coordinator never executed it, so the file stayed empty.

**(b) Root cause.** Metrics emission is in a *prompt*, not a *hook*. Nothing
deterministic ever calls `write_metric()` per task. It is the same prose-as-
enforcement failure as Points 1–3.

**(c) Enforcement options.**
1. **Emit the metric from `stop-watcher.sh`** on each continuation, after state
   advance, by sourcing `write-metric.sh` and calling `write_metric` with the
   just-completed task's index/iteration/commit SHA. Tradeoff: the hook must know
   the *outcome* (pass/fail) — derive from whether `taskIndex` advanced vs
   `taskIteration` incremented since last invocation.
2. **PostToolUse / SubagentStop hook** that fires when spec-executor or
   qa-engineer finishes and writes the metric. Tradeoff: needs hook wiring and
   parsing the subagent transcript for the completion signal — more moving parts.
3. **Keep the prompt block but add a hook-side backstop**: stop-watcher checks
   "did `.metrics.jsonl` gain a line for the last completed task?" and writes a
   `status:"ambiguous"` line if not. Tradeoff: backstop only, still depends on
   detecting the gap.

**(d) Feasibility: HIGH.** Option 1. `write-metric.sh` is production-ready and
already `flock`-safe; `stop-watcher.sh` already reads `taskIndex`, `taskIteration`
and can `git log -1 --format=%H`. Moving the call from prompt to hook is the fix.

### Point 5 — `_unmark_task.py` empty placeholder (diagnostic §4.3)

**(a) Current behavior.**
- `_unmark_task.py` is **NOT referenced anywhere in the plugin** — a repo-wide
  grep of `plugins/ralphharness/` finds zero hits. It was a spec-*local* artifact
  invented inside the `mutation-score-ramp` spec directory and never wired in. It
  is not plugin machinery; the plugin has no such script.
- Legitimate un-marking IS a real plugin operation: external-reviewer un-marks
  `[x]`→`[ ]` on FAIL (`external-reviewer.md:536-576`, `channel-map.md:21`),
  using `flock -e 201` on `tasks.md.lock`, and increments
  `.ralph-state.json → external_unmarks[taskId]`.
- The §2.2 violation: the *coordinator* un-marked already-verified tasks (1.3,
  1.4) — coordinator has no authority to un-mark, only the reviewer does
  (`role-contracts.md:28`). There is **no integrity guard** that enforces this:
  `implement.md:290-292` merely *logs a warning* when `taskIndex > completed`.
- `task_review.md` records PASS/FAIL per task (template + external-reviewer).
  Nothing cross-checks an un-mark against a PASS entry there.

**(b) Root cause.** Two gaps: (1) the placeholder script was never plugin code,
so "implement `_unmark_task.py`" really means "design an integrity guard the
plugin currently lacks"; (2) write authority on `tasks.md` `[x]` marks is
documented in prose (`role-contracts.md`) but never enforced — any agent can
flip a checkbox.

**(c) Enforcement options.**
1. **Integrity guard in `stop-watcher.sh`.** Each invocation, snapshot the set of
   `[x]` task IDs; on the next invocation, if a task that was `[x]` is now `[ ]`
   AND it has a `status=PASS`/`PASS` entry in `task_review.md` AND
   `external_unmarks` for it did NOT increase, flag an illegitimate un-mark:
   re-mark `[x]` (under `flock 201`) or escalate DEADLOCK. Tradeoff: needs a
   persisted snapshot (e.g. `.task-marks.prev` or a state field).
2. **`validate-task-marks.sh` helper** (the real form of `_unmark_task.py`):
   given a proposed un-mark, return non-zero if the task has a PASS in
   `task_review.md` and the actor is not the external-reviewer. Wired into the
   coordinator's State Update / drift detection. Tradeoff: coordinator must call
   it; weaker than (1) which is unconditional.
3. **Reconcile via `external_unmarks`.** Treat a `[x]`→`[ ]` transition as legal
   ONLY if `external_unmarks[taskId]` incremented in the same interval; otherwise
   auto-revert. Tradeoff: precise and mechanical; depends on the reviewer always
   incrementing the counter (it is already required to, `external-reviewer.md:470`).

**(d) Feasibility: HIGH for a guard, MEDIUM for full auto-revert.** Detection
(option 1+3) is straightforward and mechanical. Auto-*revert* is riskier (a
two-writer file under lock) — safer first step is detect + escalate, with
auto-revert as a follow-up.

### Existing Patterns (reusable machinery)

- **PRE-EXEC-GATE** (`implement.md:560-637`) — established pattern for a
  deterministic shell gate that runs before delegation and routes on exit code.
  New gates (Points 1, 3) can follow this exact shape.
- **HOLD-GATE** (`implement.md:639-661`, `stop-watcher.sh:688-707`) — mechanical
  `signals.jsonl` block; routing reviewer DEADLOCK here makes it bite (Point 1).
- **`flock` locks** — `tasks.md.lock` (fd 201), `signals.jsonl.lock` (fd 202),
  `chat.md.lock` (fd 200), `.metrics.lock` (fd 200 in write-metric.sh). All
  integrity writes must reuse these (Point 5).
- **`write-metric.sh`** — complete, `flock`-safe per-task JSONL writer (Point 4).
- **Circuit breaker** (`implement.md:709-731`, `loop-safety.md`) — precedent for
  hook-side mechanical enforcement with state fields.
- **`replay-signals.sh`** — deterministic incident replay; a model for any new
  audit tooling.

### Constraints

- `stop-watcher.sh` is **append-only** by policy (loop-safety.md Decision 3).
- `tasks.md` is a two-writer file — `flock -e 201` mandatory.
- Circuit breaker has **no auto-reset** (Decision 5) — any auto-recovery for the
  coordinator must respect that human-in-the-loop philosophy.
- Coordinator owns all `.ralph-state.json` fields except `chat.*`,
  `external_unmarks`, `awaitingApproval` (`channel-map.md:24`).
- Version bump required in `plugin.json` + `marketplace.json` for any change.

## Cross-Cutting Themes

1. **Prose-as-enforcement is the master root cause.** All 5 points are rules that
   exist only as English in agent/reference markdown. The fix pattern is uniform:
   move the rule into a deterministic shell gate (`stop-watcher.sh` append-only
   fn, or a PRE-EXEC-GATE-style block, or a helper script).
2. **The coordinator's only advancement gate is `taskIndex < totalTasks`.**
   Points 1 and 3 are both "missing precondition on advancement". One scan
   (preceding-unsatisfied-`[VERIFY]`) solves both.
3. **`signals.jsonl` is mechanically enforced; `chat.md` is not.** Reviewer
   escalations that land in `chat.md` (DEADLOCK in §2.3) have no mechanical
   teeth. Routing control escalations to `signals.jsonl` makes the existing
   HOLD-GATE enforce them for free.
4. **Hook vs prompt.** Anything placed in a coordinator *prompt* (metrics
   emission, integrity warnings) is LLM-discretionary and will be skipped under
   load. Anything in `stop-watcher.sh` runs unconditionally. Point 4 is the
   clearest case; Points 1/3/5 benefit from the same migration.

## Feasibility Assessment

| Point | Aspect | Verdict | Notes |
|-------|--------|---------|-------|
| 1 Sequential VERIFY gate | Technical / Effort | **HIGH** / S | awk scan in stop-watcher + route DEADLOCK to signals.jsonl |
| 2 Robust fix verification | Technical / Effort | **HIGH** / S | `merge-base` three-state diff; helper script |
| 3 Phase exit gate | Technical / Effort | **MEDIUM** / M | Needs a gate data source; Option 2 (gate task) lowest risk |
| 4 Metrics emission | Technical / Effort | **HIGH** / S | Move `write_metric` call from prompt to hook |
| 5 Un-mark integrity guard | Technical / Effort | **HIGH detect / MEDIUM revert** / M | Snapshot+compare; auto-revert is a follow-up |
| Overall | Risk | **LOW–MEDIUM** | Append-only hook changes; reuses existing locks/patterns |

## Related Specs

| Spec | Relationship | Severity | mayNeedUpdate |
|------|--------------|----------|---------------|
| `loop-safety-infra` | Owns circuit breaker, heartbeat, `write-metric.sh`, append-only `stop-watcher.sh` convention. New gates extend this directly. | High | No (extended, not changed) |
| `signal-log-and-ci-autodetect` | Owns `signals.jsonl`, `lib-signals.sh`, `ciSnapshot`. Point 1 (route DEADLOCK) and Point 3 (gate via ciSnapshot) build on it. | High | Possibly — DEADLOCK signal semantics |
| `collaboration-resolution` | Owns external-reviewer FAIL/un-mark + `chat.md` DEADLOCK protocol. Point 1 and Point 5 touch reviewer escalation + `external_unmarks`. | High | Likely — DEADLOCK routing, un-mark authority |
| `reviewer-warmup` | Owns the liveness heartbeat + convergence detection (recently merged). Relevant if Point 1 adds coordinator auto-recovery. | Medium | No |
| `engine-state-hardening` | Owns `.ralph-state.json` field hardening. New fields (`phaseGate`, mark snapshot) should follow its conventions. | Medium | No |
| `reality-verification-principle` / `qa-verification` | Own anti-fabrication / VF reality-check. Point 2 (robust diff) overlaps the anti-fabrication Layer 3. | Medium | Possibly |

## Recommendations for Requirements

1. **FR — Sequential VERIFY blocking gate**: `stop-watcher.sh` MUST NOT emit a
   continuation prompt while any `[VERIFY]` task at an index below `taskIndex` is
   `[ ]`; on detection, append a DEADLOCK `control` signal to `signals.jsonl` and
   halt. (Point 1)
2. **FR — Reviewer DEADLOCK routed to `signals.jsonl`**: external-reviewer MUST
   emit DEADLOCK as an `active` `control` signal so the existing HOLD-GATE blocks
   the loop mechanically. (Point 1)
3. **FR — Robust fix-presence verification**: provide `verify-fix-present.sh`
   using `git merge-base HEAD origin/main` + three-state diff (committed ∪
   staged ∪ working-tree); spec-executor's post-commit check and coordinator
   Layer 3 MUST use it instead of bare `git diff HEAD` / `git diff HEAD~1`. (Point 2)
4. **FR — Phase exit gate**: task-planner emits a `[VERIFY] Phase X exit gate`
   as the final task of each phase; combined with FR-1 this mechanically blocks
   phase advancement until the outgoing phase's gates are green. (Point 3)
5. **FR — Deterministic per-task metrics**: `stop-watcher.sh` MUST call
   `write_metric()` on every task advancement; remove the LLM-discretionary
   prompt block (or keep it only as a documented fallback). (Point 4)
6. **FR — Task-mark integrity guard**: detect illegitimate `[x]`→`[ ]`
   transitions (un-mark of a task with a PASS in `task_review.md` without a
   matching `external_unmarks` increment) and escalate DEADLOCK; auto-revert is
   a stretch goal. Replaces the never-implemented `_unmark_task.py`. (Point 5)
7. **NFR — Enforcement-as-shell**: every new gate MUST be a deterministic shell
   gate (hook function or helper script), never coordinator prose. Append-only
   to `stop-watcher.sh`; reuse existing `flock` fds.
8. **NFR — Backwards compatibility**: missing new state fields default safely;
   legacy specs without `signals.jsonl` / `task_review.md` degrade gracefully
   (skip the gate, log a WARN).

## Open Questions

- For Point 1, should a *legitimately* deferred `[VERIFY]` ever be allowed (e.g.
  a checkpoint waiting on a later artifact)? Current plugin has no notion of
  this — recommend treating ALL preceding unsatisfied `[VERIFY]` as blocking
  unless requirements explicitly introduce a `deferred` marker.
- For Point 3, which data source proves a phase gate is "green" —
  `ciSnapshot`, `.metrics.jsonl`, or a dedicated gate task? Recommend the gate
  *task* (Option 2) to avoid coupling to metric semantics.
- For Point 5, should the guard *auto-revert* an illegitimate un-mark, or only
  detect + escalate? Auto-revert mutates a two-writer file — recommend
  detect+escalate first, auto-revert as a separate hardening task.
- Is coordinator *auto-recovery* (diagnostic §3.2, the 4 DEADLOCKs) in scope?
  The goal lists 5 points and §3.2 is not one of them; recommend keeping it OUT
  of this spec (it conflicts with circuit-breaker Decision 5 "manual reset only"
  and deserves its own spec).

## Sources

- `plans/mutation-score-ramp-diagnostic.md` (forensic diagnostic, §2.3, §3.1, §3.3, §4.2, §4.3)
- `plugins/ralphharness/commands/implement.md` (lines 162, 280-292, 560-661, 680-731)
- `plugins/ralphharness/references/coordinator-pattern.md` (lines 44-50, 242, 356, 399-408, 690-751)
- `plugins/ralphharness/references/phase-rules.md` (lines 372-421)
- `plugins/ralphharness/references/loop-safety.md` (Decisions 3, 5; metrics)
- `plugins/ralphharness/references/test-integrity.md` (False-Complete problem)
- `plugins/ralphharness/references/channel-map.md` (lines 21, 24, 36-40)
- `plugins/ralphharness/references/role-contracts.md` (lines 28, 51)
- `plugins/ralphharness/agents/spec-executor.md` (lines 73, 179-235)
- `plugins/ralphharness/agents/external-reviewer.md` (lines 470, 536-576)
- `plugins/ralphharness/hooks/scripts/stop-watcher.sh` (lines 675-758)
- `plugins/ralphharness/hooks/scripts/write-metric.sh` (full file)
- `plugins/ralphharness/skills/reviewer-warmup/SKILL.md` (heartbeat gate)
- repo grep: `_unmark_task` — zero hits in `plugins/ralphharness/`
