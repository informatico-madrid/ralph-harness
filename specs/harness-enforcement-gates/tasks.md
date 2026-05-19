---
spec: harness-enforcement-gates
basePath: specs/harness-enforcement-gates
phase: tasks
created: 2026-05-19
granularity: fine
---

# Tasks: harness-enforcement-gates

Replace 5 prose-only execution rules with deterministic shell enforcement gates.
POC-first 5-phase plan. All gates are append-only to `stop-watcher.sh` (loop-safety.md
Decision 3) plus one standalone helper script. Project type `cli` — verification via
`bats` + direct shell, no UI/Playwright. Each phase ends with a `[VERIFY] Phase X exit gate`.

## Phase 1: Make It Work (POC)

Focus: wire all 5 gates to a working state. Skip dedicated bats suites (Phase 3),
verify with direct shell invocation against ad-hoc fixtures.

  - [x] 1.1 Create `verify-fix-present.sh` helper script skeleton
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/verify-fix-present.sh` with shebang `#!/usr/bin/env bash`, `set -euo pipefail`, arg parse `file=$1 pattern=${2:-}`, exit-code contract header comment (0 present / 1 unchanged / 2 pattern absent / 3 base unresolvable).
    2. `chmod +x` the file.
  - **Files**: `plugins/ralphharness/hooks/scripts/verify-fix-present.sh`
  - **Done when**: Script exists, executable, prints usage on missing `$1`.
  - **Verify**: `test -x plugins/ralphharness/hooks/scripts/verify-fix-present.sh && bash plugins/ralphharness/hooks/scripts/verify-fix-present.sh 2>&1 | grep -qi usage && echo PASS`
  - **Commit**: `feat(verify-fix): scaffold verify-fix-present.sh helper`
  - _Requirements: FR-5, AC-2.1_
  - _Design: Component 2, Implementation Step 1_

- [x] 1.2 Implement base-ref resolution in `verify-fix-present.sh`
  - **Do**:
    1. Compute `base=$(git merge-base HEAD origin/main)`.
    2. On failure, fall back to `.checkpoint.sha` from `<spec>/.ralph-state.json` (resolve spec via `RALPH_CWD`/current-spec); log WARN `origin/main unreachable, base=<sha>` to stderr.
    3. If no checkpoint SHA either, `exit 3` with diagnostic `cannot resolve base ref`.
  - **Files**: `plugins/ralphharness/hooks/scripts/verify-fix-present.sh`
  - **Done when**: Base ref resolves via merge-base, then checkpoint fallback, then exit 3.
  - **Verify**: `cd /tmp && rm -rf vfp1 && git init -q vfp1 && cd vfp1 && git commit -q --allow-empty -m x && bash "$OLDPWD"/plugins/ralphharness/hooks/scripts/verify-fix-present.sh nofile.txt; test $? -eq 3 && echo PASS`
  - **Commit**: `feat(verify-fix): add merge-base + checkpoint-SHA fallback`
  - _Requirements: FR-5, AC-2.7_
  - _Design: Component 2, Implementation Step 1_

- [x] 1.3 Implement three-state diff + pattern check in `verify-fix-present.sh`
  - **Do**:
    1. Compute `changed` = ANY non-empty of `git diff --quiet "$base" HEAD -- "$file"`, `git diff --cached --quiet -- "$file"`, `git diff --quiet -- "$file"`.
    2. If not changed: `exit 1`, stderr `FIX ABSENT: <file> unchanged since <base> in all 3 states`.
    3. If `pattern` supplied: `git show HEAD:"$file" | grep -qF -- "$pattern"`; absent ⇒ `exit 2`, stderr `FIX PATTERN ABSENT`.
    4. Else `exit 0`.
  - **Files**: `plugins/ralphharness/hooks/scripts/verify-fix-present.sh`
  - **Done when**: Returns 0/1/2 correctly for committed/absent/pattern cases.
  - **Verify**: `cd /tmp && rm -rf vfp2 && git init -q vfp2 && cd vfp2 && git commit -q --allow-empty -m base && git checkout -q -b feat && echo new > f.txt && git add f.txt && git commit -q -m fix && git branch -f origin/main main 2>/dev/null; git update-ref refs/remotes/origin/main main; bash "$OLDPWD"/plugins/ralphharness/hooks/scripts/verify-fix-present.sh f.txt; test $? -eq 0 && echo PASS`
  - **Commit**: `feat(verify-fix): three-state diff + optional pattern check`
  - _Requirements: FR-5, FR-6, AC-2.2, AC-2.3, AC-2.4_
  - _Design: Component 2, Implementation Step 1_

- [x] 1.4 [VERIFY] Quality checkpoint: verify-fix-present.sh shellcheck + smoke
  - **Do**: Run `shellcheck` (if available) and a direct-shell smoke of all three exit paths against a throwaway git fixture.
  - **Verify**: `command -v shellcheck >/dev/null && shellcheck plugins/ralphharness/hooks/scripts/verify-fix-present.sh || true; bash -n plugins/ralphharness/hooks/scripts/verify-fix-present.sh && echo PASS`
  - **Done when**: No syntax errors; smoke paths return expected codes.
  - **Commit**: `chore(verify-fix): pass quality checkpoint` (only if fixes needed)

- [x] 1.5 Append `gate_verify_sequential()` function to `stop-watcher.sh`
  - **Do**:
    1. **Append** (end of file) a new function `gate_verify_sequential <spec_path> <tasks_file> <task_index>`.
    2. Body: if `tasks_file` absent ⇒ return 0; `awk` scan `^- \[[ x]\]` lines with 0-based counter; for each line at index `< task_index` matching `\[VERIFY\]` with mark `\[ \]` collect index; if none ⇒ return 0; else log `BLOCKED: preceding VERIFY task N unsatisfied` to stderr and return 1.
    3. Do NOT edit any existing line.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Function defined at end of file; existing lines untouched.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'gate_verify_sequential()' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `feat(stop-watcher): append gate_verify_sequential function`
  - _Requirements: FR-1, FR-3, AC-1.1, AC-1.3, AC-1.4, AC-1.5_
  - _Design: Component 1, Implementation Step 2_

- [x] 1.6 Add DEADLOCK signal emission to `gate_verify_sequential()`
  - **Do**:
    1. In `gate_verify_sequential`, before `return 1`: ensure `signals.jsonl` exists (idempotent `cp` of template, mirroring HOLD-GATE); `source lib-signals.sh`; `append_signal` a DEADLOCK control payload (`source:"gate_verify_sequential"`, `reason:"preceding VERIFY task <N> unsatisfied"`, `taskIndex`, `status:"active"`).
    2. If `signals.jsonl` cannot be created (read-only fs) ⇒ log WARN to `.progress.md`, skip append, `return 0`.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Block path appends an active DEADLOCK control signal; read-only fs degrades to WARN+return 0.
  - **Verify**: `grep -q 'append_signal' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'DEADLOCK' plugins/ralphharness/hooks/scripts/stop-watcher.sh && bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `feat(stop-watcher): emit DEADLOCK signal in sequential VERIFY gate`
  - _Requirements: FR-2, AC-1.2, AC-1.7_
  - _Design: Component 1, Implementation Step 2_

- [x] 1.7 Add `gate_verify_sequential` call line inside loop-control block
  - **Do**:
    1. Add **one** call line inside the existing loop-control `if`-body, immediately before the BEGIN HOLD-GATE block: invoke `gate_verify_sequential`; on non-zero, `exit 0` (same shape as HOLD-GATE `exit 0`) — no continuation prompt.
    2. This is the only added line in existing flow; mirrors the existing in-block `source lib-signals.sh` precedent. Do not edit any other line.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Call inserted before HOLD-GATE; non-zero return short-circuits to `exit 0`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -n 'gate_verify_sequential' plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -qv '()' && echo PASS`
  - **Commit**: `feat(stop-watcher): wire gate_verify_sequential call before HOLD-GATE`
  - _Requirements: FR-1, AC-1.1, AC-6.2_
  - _Design: Component 1, Implementation Step 2_

- [x] 1.8 [VERIFY] Quality checkpoint: stop-watcher.sh syntax + append-only spot check
  - **Do**: `bash -n` the modified `stop-watcher.sh`; `git diff` it and confirm only appended function lines + the single call line are added.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && git diff plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -c '^-' | grep -qx 0 && echo PASS`
  - **Done when**: No syntax errors; zero deleted lines in the diff.
  - **Commit**: `chore(stop-watcher): pass quality checkpoint` (only if fixes needed)

- [x] 1.9 Modify `external-reviewer.md` — route DEADLOCK to `signals.jsonl`
  - **Do**:
    1. In the DEADLOCK escalation section, add an instruction that the reviewer also appends a DEADLOCK `control` signal (`status:"active"`) to `signals.jsonl` via `append_signal`, not only to `chat.md`.
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: External-reviewer DEADLOCK path documents the `append_signal` to `signals.jsonl`.
  - **Verify**: `grep -q 'signals.jsonl' plugins/ralphharness/agents/external-reviewer.md && grep -qi 'append_signal' plugins/ralphharness/agents/external-reviewer.md && echo PASS`
  - **Commit**: `feat(external-reviewer): route DEADLOCK to signals.jsonl`
  - _Requirements: FR-4, AC-1.6_
  - _Design: external-reviewer DEADLOCK→signals, Implementation Step 3_

- [x] 1.10 Modify `task-planner.md` — add phase exit-gate emission rule
  - **Do**:
    1. Add a mandatory rule: as the FINAL task of every phase block, task-planner ALWAYS appends exactly one `[VERIFY] Phase X exit gate` task, even when the phase already ends with a `[VERIFY]` checkpoint.
    2. Include the canonical task template (Do/Verify/Done when) from design Component 3.
  - **Files**: `plugins/ralphharness/agents/task-planner.md`
  - **Done when**: task-planner.md documents the exit-gate emission rule with the template.
  - **Verify**: `grep -qi 'Phase X exit gate' plugins/ralphharness/agents/task-planner.md && echo PASS`
  - **Commit**: `feat(task-planner): always emit Phase X exit-gate task`
  - _Requirements: FR-9, FR-10, AC-3.1, AC-3.4_
  - _Design: Component 3, Implementation Step 4_

- [x] 1.11 [VERIFY] Quality checkpoint: agent-file edits well-formed
  - **Do**: Confirm `external-reviewer.md` and `task-planner.md` edits are syntactically valid markdown and reference real artifacts (`signals.jsonl`, `append_signal`, `[VERIFY]`).
  - **Verify**: `grep -q 'signals.jsonl' plugins/ralphharness/agents/external-reviewer.md && grep -qi 'exit gate' plugins/ralphharness/agents/task-planner.md && echo PASS`
  - **Done when**: Both edits present and consistent with design.
  - **Commit**: `chore(agents): pass quality checkpoint` (only if fixes needed)

- [x] 1.12 Append `emit_task_metric()` function to `stop-watcher.sh`
  - **Do**:
    1. **Append** (end of file) `emit_task_metric <spec_path> <state_file>`.
    2. Body: read `taskIndex`, `taskIteration`, `lastMetricTaskIndex` (`// -1`), `lastMetricIteration` from state; advancement detection — `taskIndex > lastMetricTaskIndex` ⇒ `pass` for index `taskIndex-1`; `taskIndex == lastMetricTaskIndex` and `taskIteration` increased ⇒ `fail` for current index; `source write-metric.sh`; derive `commit_sha` via `git -C "$CWD" log -1 --format=%H`; call `write_metric ...`; then `jq` + atomic `mv` to set `lastMetricTaskIndex`/`lastMetricIteration`.
    3. Always `return 0` (best-effort; `write_metric` failure ⇒ WARN + return 0).
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Function appended; advancement logic + idempotency guard present.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'emit_task_metric()' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'lastMetricTaskIndex' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `feat(stop-watcher): append emit_task_metric function`
  - _Requirements: FR-11, AC-4.1, AC-4.2, AC-4.4, AC-4.5_
  - _Design: Component 4, Implementation Step 5_

- [x] 1.13 Add `emit_task_metric` call line inside loop-control block
  - **Do**:
    1. Add **one** call line inside the existing loop-control `if`-body, after the continuation prompt is built, invoking `emit_task_metric`. Do not edit any other line.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Call inserted after continuation build; existing lines untouched.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -n 'emit_task_metric' plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -qv '()' && echo PASS`
  - **Commit**: `feat(stop-watcher): wire emit_task_metric call after continuation build`
  - _Requirements: FR-11, AC-4.1, AC-6.2_
  - _Design: Component 4, Implementation Step 5_

- [x] 1.14 Remove LLM-discretionary metrics block from `implement.md`
  - **Do**:
    1. Delete the LLM-discretionary metrics prompt block (~lines 680-708, "After TASK_COMPLETE — write metrics"). No fallback kept (a kept fallback risks the duplicate line FR-12 forbids).
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: The metrics prompt block is gone; hook is the sole authoritative writer.
  - **Verify**: `! grep -qi 'write metrics' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `refactor(implement): remove LLM-discretionary metrics block`
  - _Requirements: FR-12, AC-4.3_
  - _Design: Component 4 FR-12, Implementation Step 5_

- [x] 1.15 [VERIFY] Quality checkpoint: metrics wiring syntax + smoke
  - **Do**: `bash -n stop-watcher.sh`; smoke `emit_task_metric` against a throwaway fixture spec dir + state file, assert one `.metrics.jsonl` line written.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Done when**: No syntax errors; metric line appears on a smoke run.
  - **Commit**: `chore(stop-watcher): pass quality checkpoint` (only if fixes needed)

- [x] 1.16 Append `gate_task_mark_integrity()` — snapshot + detection
  - **Do**:
    1. **Append** (end of file) `gate_task_mark_integrity <spec_path> <state_file>`.
    2. If `task_review.md` absent ⇒ WARN to `.progress.md`, return 0; read `taskMarkSnapshot` (`// null`) — on `null` take fresh snapshot, return 0.
    3. Under `flock -e 201` on `tasks.md.lock`: read current `[x]` task IDs; `unmarked = prior.checkedTaskIds \ current`; classify each — `hasPass` (PASS in `task_review.md`), `extInc` (`external_unmarks` increased vs snapshot); LEGITIMATE if `extInc`, ILLEGITIMATE if `hasPass && !extInc`.
    4. Refresh `taskMarkSnapshot` under the same lock. Never write `external_unmarks`, never re-mark.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Function appended; detection + `flock -e 201` + snapshot refresh present; no auto-revert.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'gate_task_mark_integrity()' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'flock -e 201' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `feat(stop-watcher): append gate_task_mark_integrity detection`
  - _Requirements: FR-13, FR-14, FR-18, AC-5.1, AC-5.2, AC-5.6, AC-5.7, AC-5.8, AC-5.9_
  - _Design: Component 5 (snapshot+detect), Implementation Step 6_

  - [x] 1.17 Add Tier 1 DEADLOCK emission to `gate_task_mark_integrity()`
  - **Do**:
    1. On ≥1 illegitimate un-mark: `append_signal` a DEADLOCK control payload (`source:"gate_task_mark_integrity"`, `reason:"illegitimate un-mark of task <id>"`, `taskId`, `status:"active"`); `return 1`.
    2. Clean / legitimate ⇒ `return 0`.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Illegitimate detection appends an active DEADLOCK signal and returns 1.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -A30 'gate_task_mark_integrity()' plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -q 'gate_task_mark_integrity' && grep -q 'illegitimate un-mark' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `feat(stop-watcher): emit Tier-1 DEADLOCK on illegitimate un-mark`
  - _Requirements: FR-15, AC-5.3_
  - _Design: Component 5 Tier 1, Implementation Step 6_

- [x] 1.18 Add `gate_task_mark_integrity` call line inside loop-control block
  - **Do**:
    1. Add **one** call line inside the existing loop-control `if`-body, after the HOLD-GATE block and before continuation emission, invoking `gate_task_mark_integrity`; on non-zero ⇒ `exit 0` (halt, no continuation). Do not edit any other line.
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Call inserted after HOLD-GATE; non-zero short-circuits to `exit 0`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -n 'gate_task_mark_integrity' plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -qv '()' && echo PASS`
  - **Commit**: `feat(stop-watcher): wire gate_task_mark_integrity call after HOLD-GATE`
  - _Requirements: FR-15, AC-5.3, AC-6.2_
  - _Design: Component 5, Implementation Step 6_

- [x] 1.19 [VERIFY] Quality checkpoint: integrity gate syntax + append-only diff
  - **Do**: `bash -n stop-watcher.sh`; `git diff` it and confirm zero deleted lines.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && git diff plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -c '^-' | grep -qx 0 && echo PASS`
  - **Done when**: No syntax errors; append-only invariant holds in the diff.
  - **Commit**: `chore(stop-watcher): pass integrity gate quality checkpoint` (only if fixes needed)

- [x] 1.20 Add Tier 2 integrity-triage DEADLOCK handler to `implement.md`
  - **Do**:
    1. Add a DEADLOCK handler dispatch keyed on `source:"gate_task_mark_integrity"` to the integrity-triage path.
    2. Primary: invoke `bmad-consensus-party` SKILL via the Skill tool; fallback when `[ -f .claude/skills/bmad-consensus-party/SKILL.md ]` is false: invoke 2-3 consensus subagents (external-reviewer + qa-engineer) via Task tool, take majority verdict.
    3. Document the triage input contract and the `VERDICT: FALSE_POSITIVE | GENUINE_CONFLICT` output contract.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: implement.md has the integrity-triage handler with skill + subagent fallback and the verdict contracts.
  - **Verify**: `grep -q 'gate_task_mark_integrity' plugins/ralphharness/commands/implement.md && grep -q 'bmad-consensus-party' plugins/ralphharness/commands/implement.md && grep -q 'FALSE_POSITIVE' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `feat(implement): add Tier-2 integrity-triage DEADLOCK handler`
  - _Requirements: FR-16, AC-5.4_
  - _Design: Component 5 Tier 2, Implementation Step 7_

- [x] 1.21 Wire Tier 2 resume + Tier 3 human escalation in `implement.md`
  - **Do**:
    1. On `FALSE_POSITIVE`: coordinator marks the DEADLOCK signal `status:"resolved"`, logs resolution to `.progress.md`, loop resumes.
    2. On `GENUINE_CONFLICT`: DEADLOCK stays `active`; emit a human-facing escalation block (same shape as existing ESCALATE blocks) describing the un-marked task, its PASS entry, and triage rationale; set `awaitingApproval=true`.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: implement.md documents the FALSE_POSITIVE resume path and the GENUINE_CONFLICT Tier-3 escalation.
  - **Verify**: `grep -q 'GENUINE_CONFLICT' plugins/ralphharness/commands/implement.md && grep -q 'awaitingApproval' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `feat(implement): wire Tier-2 resume and Tier-3 escalation`
  - _Requirements: FR-17, AC-5.4, AC-5.5_
  - _Design: Component 5 Tier 2/3, Implementation Step 7_

- [x] 1.22 Re-point `spec-executor.md` post-commit check to `verify-fix-present.sh`
  - **Do**:
    1. At the post-commit check (~line 73), replace `git diff HEAD~1 --stat` with a call to `verify-fix-present.sh` for each file in the task's Files list; non-zero ⇒ investigate before `TASK_COMPLETE`.
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: Post-commit check invokes `verify-fix-present.sh`; bare `git diff HEAD~1 --stat` removed.
  - **Verify**: `grep -q 'verify-fix-present.sh' plugins/ralphharness/agents/spec-executor.md && ! grep -q 'git diff HEAD~1 --stat' plugins/ralphharness/agents/spec-executor.md && echo PASS`
  - **Commit**: `feat(spec-executor): use verify-fix-present.sh in post-commit check`
  - _Requirements: FR-7, AC-2.5_
  - _Design: Component 2 callers, Implementation Step 8_

- [x] 1.23 Re-point `implement.md` Layer 3 review to `verify-fix-present.sh`
  - **Do**:
    1. In the Layer 3 anti-fabrication review, replace bare `git diff HEAD` with `verify-fix-present.sh <file> [<pattern>]`; non-zero ⇒ FABRICATION → REJECT.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: Layer 3 review invokes `verify-fix-present.sh`; bare `git diff HEAD` removed from Layer 3.
  - **Verify**: `grep -q 'verify-fix-present.sh' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `feat(implement): use verify-fix-present.sh in Layer 3 review`
  - _Requirements: FR-8, AC-2.6_
  - _Design: Component 2 callers, Implementation Step 8_

- [x] 1.24 POC milestone — all 5 gates wired end-to-end
  - **Do**:
    1. Build a throwaway fixture spec dir with `tasks.md` (a skipped preceding `[VERIFY]`), `signals.jsonl`, `task_review.md`, `.ralph-state.json`.
    2. Run `stop-watcher.sh` against it; confirm `gate_verify_sequential` blocks (no continuation, DEADLOCK appended).
    3. Confirm `verify-fix-present.sh`, `emit_task_metric`, `gate_task_mark_integrity` each execute without shell error on the fixture.
  - **Files**: (none — verification only; fixture in a temp dir)
  - **Done when**: All 5 gates are reachable and fire on the fixture; POC proven.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && bash -n plugins/ralphharness/hooks/scripts/verify-fix-present.sh && grep -q 'gate_verify_sequential\|emit_task_metric\|gate_task_mark_integrity' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo POC_PASS`
  - **Commit**: `feat(harness): complete POC — all 5 enforcement gates wired`
  - _Requirements: US-1..US-6_
  - _Design: Implementation Steps 1-8_

- [x] 1.G [VERIFY] Phase 1 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 1 are complete and green.
  - **Verify**: All Phase 1 `[VERIFY]` tasks above are `[x]`; `bash -n` passes on both scripts.
  - **Done when**: Phase 1 is fully satisfied; safe to advance to Phase 2.
  - **Commit**: `chore(harness): Phase 1 exit gate`

## Phase 2: Refactoring

Focus: clean up the POC code — extract shared helpers, consistent error handling,
match existing `stop-watcher.sh` / helper-script style. No behavior change.

- [x] 2.1 Normalize WARN/diagnostic logging across the 3 appended functions
  - **Do**:
    1. Unify stderr/`.progress.md` WARN message format across `gate_verify_sequential`, `emit_task_metric`, `gate_task_mark_integrity` (consistent prefix, no duplicated literals).
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: All three functions log via a consistent pattern; no behavior change.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo PASS`
  - **Commit**: `refactor(stop-watcher): normalize gate WARN logging`
  - _Design: Existing Patterns to Follow_

- [x] 2.2 Tidy `verify-fix-present.sh` — clarify exit-code paths and diagnostics
  - **Do**:
    1. Consolidate the three-state diff into a clear helper-local block; ensure each exit (0/1/2/3) has a single unambiguous diagnostic; stdout stays silent (composable).
  - **Files**: `plugins/ralphharness/hooks/scripts/verify-fix-present.sh`
  - **Done when**: Exit paths are clean and documented; stdout silent; no behavior change.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/verify-fix-present.sh && echo PASS`
  - **Commit**: `refactor(verify-fix): clarify exit-code paths`
  - _Design: Component 2_

- [x] 2.3 [VERIFY] Quality checkpoint: post-refactor syntax + append-only diff
  - **Do**: `bash -n` both scripts; `git diff stop-watcher.sh` confirms zero deleted pre-existing lines.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && bash -n plugins/ralphharness/hooks/scripts/verify-fix-present.sh && echo PASS`
  - **Done when**: No syntax errors; append-only invariant intact.
  - **Commit**: `chore(harness): pass quality checkpoint` (only if fixes needed)

  - [x] 2.4 Review `implement.md` edits for consistency and dead prose
  - **Do**:
    1. Confirm the removed metrics block left no orphan references; the Tier-2/3 handler and Layer-3 re-point read consistently with surrounding coordinator prose; remove only dead prose this spec's changes created.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: No orphan metrics references; integrity-triage and Layer-3 sections coherent.
  - **Verify**: `! grep -qi 'write metrics' plugins/ralphharness/commands/implement.md && grep -q 'verify-fix-present.sh' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `refactor(implement): clean up coordinator prose after gate wiring`
  - _Design: Component 4 FR-12, Component 5_

- [x] 2.5 [VERIFY] Phase 2 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 2 are complete and green.
  - **Verify**: All Phase 2 `[VERIFY]` tasks above are `[x]`; both scripts pass `bash -n`.
  - **Done when**: Phase 2 is fully satisfied; safe to advance to Phase 3.
  - **Commit**: `chore(harness): Phase 2 exit gate`

## Phase 3: Testing

Focus: the 5 bats suites. One suite per gate, each covering pass / block /
legacy-degradation per the design Test Coverage Table. Plus the append-only
git-diff assertion and the E2E gate-integration task.

- [x] 3.1 Create `test-verify-fix-present.bats` — committed/staged/working-tree
  - **Do**:
    1. Create the bats file; `setup()` shell-builds a `fixture-git-fix` repo (`git init`, branch diverged from a local fake `origin/main`).
    2. Cases: fix committed ⇒ exit 0; fix staged not committed ⇒ exit 0; fix unstaged ⇒ exit 0.
  - **Files**: `plugins/ralphharness/tests/test-verify-fix-present.bats`
  - **Done when**: 3 git-state cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-fix-present.bats`
  - **Commit**: `test(verify-fix): bats for three git-state diffs`
  - _Requirements: FR-5, AC-2.2, NFR-6_
  - _Design: Test Coverage Table rows 4-6_

- [x] 3.2 Extend `test-verify-fix-present.bats` — absent + pattern + fallback
  - **Do**:
    1. Add cases: file unchanged ⇒ exit 1 + `FIX ABSENT` stderr; pattern present ⇒ 0, pattern absent ⇒ exit 2; `origin/main` removed ⇒ checkpoint SHA used + WARN + correct verdict; no SHA ⇒ exit 3.
  - **Files**: `plugins/ralphharness/tests/test-verify-fix-present.bats`
  - **Done when**: absent, pattern, and fallback cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-fix-present.bats`
  - **Commit**: `test(verify-fix): bats for absent, pattern, base-ref fallback`
  - _Requirements: FR-5, FR-6, AC-2.3, AC-2.4, AC-2.7, NFR-6_
  - _Design: Test Coverage Table rows 7-9_

- [x] 3.3 [VERIFY] Quality checkpoint: verify-fix-present suite green
  - **Do**: Run the full `test-verify-fix-present.bats` suite.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-fix-present.bats`
  - **Done when**: All US-2 cases pass.
  - **Commit**: `chore(tests): pass quality checkpoint` (only if fixes needed)

- [x] 3.4 Create `test-verify-sequential-gate.bats` — pass / block / legacy — c1ff5c6
  - **Do**:
    1. Create the bats file; `setup()` writes a `fixture-multiphase` spec dir into `$BATS_TMPDIR`.
    2. Cases: preceding `[VERIFY]` `[ ]` ⇒ rc=1 + `BLOCKED:` stderr + DEADLOCK line in `signals.jsonl`; all preceding `[VERIFY]` `[x]` ⇒ rc=0, no signal; no `[VERIFY]` tasks ⇒ rc=0; read-only fs `signals.jsonl` ⇒ WARN + rc=0.
  - **Files**: `plugins/ralphharness/tests/test-verify-sequential-gate.bats`
  - **Done when**: block, pass, and 2 legacy cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-sequential-gate.bats`
  - **Commit**: `test(stop-watcher): bats for sequential VERIFY gate`
  - _Requirements: FR-1, FR-2, FR-3, AC-1.1..1.5, AC-1.7, NFR-6_
  - _Design: Test Coverage Table rows 1-3_

- [x] 3.5 Create `test-phase-exit-gate.bats` — task-planner emission — 72c09eb
  - **Do**:
    1. Create the bats file; assert a generated multi-phase `tasks.md` fixture has exactly one `[VERIFY] Phase X exit gate` as the last task of each phase block.
  - **Files**: `plugins/ralphharness/tests/test-phase-exit-gate.bats`
  - **Done when**: Emission assertion passes for a 2-phase fixture.
  - **Verify**: `bats plugins/ralphharness/tests/test-phase-exit-gate.bats`
  - **Commit**: `test(task-planner): bats for phase exit-gate emission`
  - _Requirements: FR-9, FR-10, AC-3.1..3.5, NFR-6_
  - _Design: Test Coverage Table row 10_

- [x] 3.6 [VERIFY] Quality checkpoint: sequential-gate + exit-gate suites green
  - **Do**: Run `test-verify-sequential-gate.bats` and `test-phase-exit-gate.bats`.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-sequential-gate.bats && bats plugins/ralphharness/tests/test-phase-exit-gate.bats`
  - **Done when**: Both suites pass.
  - **Commit**: `chore(tests): pass quality checkpoint` (only if fixes needed)

- [x] 3.7 Create `test-task-metrics.bats` — pass / fail / count
  - **Do**:
    1. Create the bats file; `setup()` writes a `fixture-multiphase` spec dir + state file.
    2. Cases: `taskIndex` advanced ⇒ one `pass` line for index-1 + `lastMetricTaskIndex` updated; `taskIteration` up no advance ⇒ one `fail` line for current index; N advancements ⇒ N lines, zero empty lines.
  - **Files**: `plugins/ralphharness/tests/test-task-metrics.bats`
  - **Done when**: pass, fail, and count cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-task-metrics.bats`
  - **Commit**: `test(stop-watcher): bats for emit_task_metric`
  - _Requirements: FR-11, AC-4.1, AC-4.2, AC-4.4, AC-4.5, NFR-6_
  - _Design: Test Coverage Table rows 11-13_

- [x] 3.8 Create `test-mark-integrity-gate.bats` — illegitimate / legitimate / no-revert
  - **Do**:
    1. Create the bats file; `setup()` writes `fixture-multiphase` with `tasks.md`/`task_review.md`/state.
    2. Cases: `[x]`→`[ ]` w/ PASS entry + no `external_unmarks` increment ⇒ rc=1 + DEADLOCK signal; `[x]`→`[ ]` w/ matching `external_unmarks` increment ⇒ rc=0 no signal; after detection `tasks.md` mark unchanged + `external_unmarks` untouched.
  - **Files**: `plugins/ralphharness/tests/test-mark-integrity-gate.bats`
  - **Done when**: illegitimate, legitimate, and no-revert cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-mark-integrity-gate.bats`
  - **Commit**: `test(stop-watcher): bats for mark-integrity detection`
  - _Requirements: FR-13, FR-14, FR-15, FR-18, AC-5.1..5.3, AC-5.6, AC-5.7, NFR-6_
  - _Design: Test Coverage Table rows 14-16_

- [x] 3.9 Extend `test-mark-integrity-gate.bats` — flock + legacy degradation
  - **Do**:
    1. Add cases: grep the script source confirms `tasks.md` access uses `flock -e 201`; missing `task_review.md` ⇒ rc=0 + WARN; missing `taskMarkSnapshot` ⇒ fresh snapshot + rc=0.
  - **Files**: `plugins/ralphharness/tests/test-mark-integrity-gate.bats`
  - **Done when**: flock and 2 legacy cases pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-mark-integrity-gate.bats`
  - **Commit**: `test(stop-watcher): bats for integrity gate flock + legacy`
  - _Requirements: FR-18, AC-5.8, AC-5.9, NFR-3, NFR-4, NFR-6_
  - _Design: Test Coverage Table rows 17-18_

- [x] 3.10 [VERIFY] Quality checkpoint: metrics + integrity suites green
  - **Do**: Run `test-task-metrics.bats` and `test-mark-integrity-gate.bats`.
  - **Verify**: `bats plugins/ralphharness/tests/test-task-metrics.bats && bats plugins/ralphharness/tests/test-mark-integrity-gate.bats`
  - **Done when**: Both suites pass.
  - **Commit**: `chore(tests): pass quality checkpoint` (only if fixes needed)

- [x] 3.11 Add `stop-watcher.sh` append-only assertion to a bats suite
  - **Do**:
    1. In `test-verify-sequential-gate.bats` (or a small dedicated `@test`), git-diff the changed `stop-watcher.sh`: assert only appended lines + ≤3 in-block call lines; no edited pre-existing logic line (zero `^-` diff lines).
  - **Files**: `plugins/ralphharness/tests/test-verify-sequential-gate.bats`
  - **Done when**: Append-only assertion passes against the working tree.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-sequential-gate.bats`
  - **Commit**: `test(stop-watcher): assert append-only discipline via git-diff`
  - _Requirements: FR-19, AC-6.1, AC-6.2, NFR-2_
  - _Design: Test Coverage Table row 19_

- [x] 3.12 E2E gate-integration test — drive a fixture spec through `stop-watcher.sh`
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-gate-integration-e2e.bats`.
    2. Build a real fixture spec directory (`tasks.md` multi-phase with a skipped preceding `[VERIFY]`, `signals.jsonl`, `task_review.md`, `.ralph-state.json`, `.metrics.jsonl`) in `$BATS_TMPDIR`.
    3. Invoke `stop-watcher.sh` end-to-end with all 5 gates wired; assert: no continuation prompt emitted, an `active` DEADLOCK appended by `gate_verify_sequential`, the loop halts. Then clear the skipped `[VERIFY]`, re-run, assert continuation proceeds and `emit_task_metric` writes a `.metrics.jsonl` line.
  - **Files**: `plugins/ralphharness/tests/test-gate-integration-e2e.bats`
  - **Done when**: The fixture spec is driven through `stop-watcher.sh` and the gates fire/halt/resume as designed.
  - **Verify**: `bats plugins/ralphharness/tests/test-gate-integration-e2e.bats`
  - **Commit**: `test(harness): end-to-end gate-integration bats`
  - _Requirements: US-1..US-6, Success Criteria_
  - _Design: Data Flow, Verification Contract_

- [x] 3.13 [VERIFY] Phase 3 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 3 are complete and green; run all 6 bats suites.
  - **Verify**: `bats plugins/ralphharness/tests/test-verify-fix-present.bats plugins/ralphharness/tests/test-verify-sequential-gate.bats plugins/ralphharness/tests/test-phase-exit-gate.bats plugins/ralphharness/tests/test-task-metrics.bats plugins/ralphharness/tests/test-mark-integrity-gate.bats plugins/ralphharness/tests/test-gate-integration-e2e.bats`
  - **Done when**: Phase 3 fully satisfied; all bats suites green; safe to advance to Phase 4.
  - **Commit**: `chore(harness): Phase 3 exit gate`

## Phase 4: Quality Gates

NEVER push to the default branch. Use the existing feature branch and a PR.

- [x] 4.1 Bump plugin version to 5.7.0
  - **Do**:
    1. Update `plugins/ralphharness/.claude-plugin/plugin.json` version 5.6.0 → 5.7.0.
    2. Update the matching `ralphharness` entry in `.claude-plugin/marketplace.json` to 5.7.0.
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Done when**: Both manifests read 5.7.0.
  - **Verify**: `jq -r .version plugins/ralphharness/.claude-plugin/plugin.json | grep -qx 5.7.0 && grep -q '5.7.0' .claude-plugin/marketplace.json && echo PASS`
  - **Commit**: `chore(ralphharness): bump version to 5.7.0`
  - _Requirements: NFR-5, AC-6.3_
  - _Design: File Structure (plugin.json, marketplace.json), Implementation Step 9_

- [x] 4.2 [VERIFY] Full local CI: bats suites + script syntax
  - **Do**: Run all 6 new bats suites plus the existing suite set; `bash -n` on `stop-watcher.sh` and `verify-fix-present.sh`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && bash -n plugins/ralphharness/hooks/scripts/verify-fix-present.sh && bats plugins/ralphharness/tests/test-verify-fix-present.bats plugins/ralphharness/tests/test-verify-sequential-gate.bats plugins/ralphharness/tests/test-phase-exit-gate.bats plugins/ralphharness/tests/test-task-metrics.bats plugins/ralphharness/tests/test-mark-integrity-gate.bats plugins/ralphharness/tests/test-gate-integration-e2e.bats`
  - **Done when**: All bats suites pass; no syntax errors.
  - **Commit**: `chore(harness): pass local CI` (only if fixes needed)

- [x] 4.3 [VERIFY] AC checklist verification
  - **Do**: Read requirements.md; programmatically confirm each AC-* is satisfied — grep the codebase for each gate's implementation and run the relevant bats case.
  - **Verify**: `grep -q 'gate_verify_sequential' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'emit_task_metric' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -q 'gate_task_mark_integrity' plugins/ralphharness/hooks/scripts/stop-watcher.sh && test -x plugins/ralphharness/hooks/scripts/verify-fix-present.sh && grep -qi 'Phase X exit gate' plugins/ralphharness/agents/task-planner.md && echo AC_PASS`
  - **Done when**: All 36 ACs confirmed met via automated checks.
  - **Commit**: None

- [x] 4.4 Create PR and verify CI
  - **Do**:
    1. Verify current branch is a feature branch: `git branch --show-current`. If on default branch, STOP and alert user.
    2. Push branch: `git push -u origin <branch-name>`.
    3. Create PR: `gh pr create --title "harness-enforcement-gates: deterministic shell enforcement gates" --body "<summary>"`.
  - **Files**: (none — git/PR operation)
  - **Done when**: PR open; CI checks green.
  - **Verify**: `gh pr checks` shows all checks passing.
  - **Commit**: None

- [x] 4.G [VERIFY] Phase 4 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 4 are complete and green; PR open, CI green, version bumped.
  - **Verify**: All Phase 4 `[VERIFY]` tasks above are `[x]`; `gh pr checks` green; `jq -r .version plugins/ralphharness/.claude-plugin/plugin.json` is `5.7.0`.
  - **Done when**: Phase 4 fully satisfied; safe to advance to Phase 5.
  - **Commit**: `chore(harness): Phase 4 exit gate`

## Phase 5: PR Lifecycle

Continuous PR validation — CI monitoring, review-comment resolution, final verification.

- [x] 5.1 Monitor CI and resolve failures
  - **Do**:
    1. `gh pr checks --watch` until CI completes.
    2. On any failure: read `gh pr checks`, fix locally, `git push`, re-verify.
  - **Files**: (varies — fix files as needed)
  - **Done when**: All CI checks green.
  - **Verify**: `gh pr checks` shows all checks passing.
  - **Commit**: `fix(harness): resolve CI failure` (only if fixes needed)

- [x] 5.2 Resolve code-review comments
  - **Do**:
    1. Fetch review comments: `gh api repos/<owner>/<repo>/pulls/<n>/comments`.
    2. Address each actionable comment with a surgical fix; reply/resolve.
  - **Files**: (varies — fix files as needed)
  - **Done when**: All review comments addressed; no unresolved threads.
  - **Verify**: `gh pr view --json reviewDecision -q .reviewDecision` is not `CHANGES_REQUESTED`.
  - **Commit**: `fix(harness): address review comments` (only if fixes needed)

- [x] 5.3 [VERIFY] Final validation — zero regressions, all gates green
  - **Do**: Re-run all 6 bats suites and the existing suite set; confirm append-only invariant on `stop-watcher.sh`; confirm no test regressions.
  - **Verify**: `git diff origin/main...HEAD -- plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -c '^-' | grep -qx 0 && bats plugins/ralphharness/tests/test-verify-fix-present.bats plugins/ralphharness/tests/test-verify-sequential-gate.bats plugins/ralphharness/tests/test-phase-exit-gate.bats plugins/ralphharness/tests/test-task-metrics.bats plugins/ralphharness/tests/test-mark-integrity-gate.bats plugins/ralphharness/tests/test-gate-integration-e2e.bats`
  - **Done when**: All suites green; zero deleted lines in `stop-watcher.sh`; no regressions.
  - **Commit**: None

- [x] 5.G [VERIFY] Phase 5 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 5 are complete and green; PR is mergeable, CI green, reviews resolved.
  - **Verify**: All Phase 5 `[VERIFY]` tasks above are `[x]`; `gh pr checks` green; `gh pr view --json mergeable -q .mergeable` is `MERGEABLE`.
  - **Done when**: Phase 5 fully satisfied; PR ready for merge (merge requires explicit user permission).
  - **Commit**: `chore(harness): Phase 5 exit gate`

## Notes

- **POC shortcuts**: Phase 1 verifies gates via direct shell against ad-hoc temp
  fixtures; the 5 dedicated bats suites land in Phase 3.
- **Append-only discipline**: every `stop-watcher.sh` task is "append function" or
  "add one call line" — NEVER edit existing logic. Tasks 1.8 / 1.19 / 2.3 / 5.3
  assert zero deleted lines via `git diff`. If a strict reading of loop-safety.md
  Decision 3 forbids even the in-block call insertion, ESCALATE before implementing
  (the existing HOLD-GATE / `source lib-signals.sh` precedent confirms in-block
  calls are within policy — see design Unresolved Questions).
- **Self-referential change**: task 1.10 modifies `task-planner.md` (this agent's
  own definition) to add the exit-gate emission rule. This tasks.md already applies
  that rule — each phase ends with a `[VERIFY] Phase X exit gate` (1.G, 2.5, 3.13,
  4.G, 5.G).
- **`flock` fds**: 200 (`.metrics.lock`), 201 (`tasks.md.lock`), 202
  (`signals.jsonl.lock`) — reused exactly, never re-invented.
- **Production TODOs**: none deferred — the spec is fully implemented within these
  5 phases.
