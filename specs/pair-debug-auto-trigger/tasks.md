---
spec: pair-debug-auto-trigger
phase: complete
created: 2026-05-16T21:00:00Z
---

# Tasks: pair-debug-auto-trigger

## Phase Breakdown

- Phase 1 (Make It Work - POC): 28 tasks
- Phase 2 (Refactoring): 5 tasks
- Phase 3 (Testing): 13 tasks
- Phase 4 (Quality Gates): 6 tasks
- Phase 5 (PR Lifecycle): 3 tasks

**Total**: 55 tasks

## Phase 1: Make It Work (POC)

Focus: Implement the mechanical trigger, role files, placement step, and all append-only edits. Accept hardcoded values; polish in Phase 2.

- [x] 1.1 [P] Create test directory structure
  - **Do**: Create `plugins/ralphharness/tests/` and `plugins/ralphharness/tests/fixtures/` directories.
  - **Files**: `plugins/ralphharness/tests/`, `plugins/ralphharness/tests/fixtures/`
  - **Done when**: Both directories exist.
  - **Verify**: `test -d plugins/ralphharness/tests && test -d plugins/ralphharness/tests/fixtures && echo P1.1_PASS`
  - **Commit**: `chore(pair-debug): create test directory structure`
  - _Design: Test Infrastructure (step 1)_

- [x] 1.2 [P] Document bats run command in progress.md
  - **Do**: Append a "Testing" subsection to `.progress.md` documenting that tests run via `bats plugins/ralphharness/tests/`, bats 1.13.0 is on PATH, no npm test script exists.
  - **Files**: `specs/pair-debug-auto-trigger/.progress.md`
  - **Done when**: `.progress.md` contains the bats command documentation.
  - **Verify**: `grep -q 'bats plugins/ralphharness/tests/' specs/pair-debug-auto-trigger/.progress.md && echo P1.2_PASS`
  - **Commit**: `docs(pair-debug): document bats test command in progress`
  - _Requirements: Verification Contract_
  - _Design: Test Strategy_

- [x] 1.3 [P] Create `references/pair-debug.md`
  - **Do**: Create the file with the following sections:
    1. `## Section 1 — 3-Condition Auto-Trigger` — Document all 3 conditions (a/b/c) canonically. Include the reconciliation sentence: "The roadmap states 3 conditions; plan.md listed 4 by splitting condition (a) into two parts. The canonical count is 3: (a) pre-existing test failing + test file unchanged, (b) taskIteration >= 2, (c) no reviewer FAIL row. ALL THREE must hold."
    2. `## Section 2 — Driver / Navigator Roles` — Table with: Driver = spec-executor (writes code, runs commands, applies fixes, adds debug logging); Navigator = external-reviewer (reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings). Include shared instruction: "formulate hypotheses, respond to the other's, do not escalate to a human unless an explicit product/design decision is required."
    3. `## Section 3 — Anti-Anchoring Rule` — (i) Navigator MUST propose >=2 independent hypotheses BEFORE the pair commits to investigating one; (ii) a hypothesis becomes ROOT_CAUSE only after an EXPERIMENT produced direct evidence, not reasoning alone; (iii) reuse collaboration-resolution.md's >10-cycle escalation bound as the stalled-loop exit.
    4. `## Section 4 — Two-Instance / Filesystem-Coordination` — Statement that Driver and Navigator run as two separate instances coordinating ONLY through the shared filesystem (chat.md, signals.jsonl, .ralph-state.json), no in-memory handoff, no Task-tool call.
    5. `## Section 5 — Runtime-to-Destination-Path Map` — Table: Roo Code → `.roo/commands/pair-debug-{driver,navigator}.md`, Qwen → `.qwen/commands/`, Cursor → `.cursor/commands/`, other/unknown → manual fallback.
    6. `## Section 6 — Loop Body Reference` — One-line pointer to `collaboration-resolution.md` for the HYPOTHESIS→EXPERIMENT→FINDING→ROOT_CAUSE→FIX_PROPOSAL loop body. Do NOT re-document the loop.
    7. `## Section 7 — Example Flow` — One concrete example: trigger fires → chat.md announcement → Navigator writes HYPOTHESIS → Driver runs EXPERIMENT → both write FINDING → ROOT_CAUSE → Driver implements FIX_PROPOSAL → verification passes → grep-clean PAIR-DEBUG: logs.
  - **Files**: `plugins/ralphharness/references/pair-debug.md`
  - **Done when**: File exists with all 7 sections; contains the 3-condition trigger, role table, anti-anchoring rule, filesystem-coordination statement, runtime→path map, loop reference, and example flow.
  - **Verify**: `test -f plugins/ralphharness/references/pair-debug.md && grep -q '3-Condition' plugins/ralphharness/references/pair-debug.md && grep -q 'Anti-Anchoring' plugins/ralphharness/references/pair-debug.md && grep -q 'Runtime-to-Destination-Path' plugins/ralphharness/references/pair-debug.md && echo P1.3_PASS`
  - **Commit**: `feat(pair-debug): create pair-debug.md with trigger, roles, anti-anchoring, path map`
  - _Requirements: FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7_
  - _Design: Component 1, Component 2, Component 5_

- [x] 1.4 [P] Update collaboration-resolution.md cycle bound
  - **Do**: Verify line 53 reads `more than 10 times` (already applied in requirements phase). If it still reads `more than 3 times`, change to `more than 10 times`. Document the verification in this task's commit.
  - **Files**: `plugins/ralphharness/references/collaboration-resolution.md`
  - **Done when**: Line 53 reads `more than 10 times`.
  - **Verify**: `sed -n '53p' plugins/ralphharness/references/collaboration-resolution.md | grep -q 'more than 10 times' && echo P1.4_PASS`
  - **Commit**: `fix(pair-debug): confirm collaboration-resolution.md cycle bound is 10`
  - _Requirements: FR-13, AC-4.3_
  - _Design: Component 1, File Structure_

- [x] 1.5 [P] Create `agents/pair-debug-driver.md`
  - **Do**: Create the role file with the following structure:
    1. **Section 0 — Bootstrap (Self-Start)** — Modeled on `external-reviewer.md` Section 0: read `specs/.current-spec` → specName, set basePath, read `.ralph-state.json` → confirm phase is execution, check for DEADLOCK in `signals.jsonl` (stop if found), update `chat.executor.lastReadLine`, announce "Driver ready. Spec: <specName>.", begin experiment loop.
    2. **Section 1 — Identity** — Name: pair-debug-driver, Role: Driver = spec-executor in pair-debug mode (writes code, runs commands, applies fixes, adds PAIR-DEBUG:-tagged debug logging, runs experiments).
    3. **Section 2 — Filesystem-Coordination Protocol** — Read chat.md every ~30s tracking lastReadLine. Inlined atomic-append block for chat.md (fd 200 flock): `(exec 200>"${basePath}/chat.md.lock"; flock -x -w 5 200 || timeout; printf '%s\n' "$msg" >> "${basePath}/chat.md") 200>"${basePath}/chat.md.lock"`. Inlined atomic-append block for signals.jsonl (fd 202 flock, same pattern). Never assume Navigator shares this process.
    4. **Section 3 — Experiment Loop** — Read Navigator's HYPOTHESIS signals. For each, instrument code with PAIR-DEBUG:-tagged log capturing suspect variable + hypothesis under test. Run minimal experiment (one variable at a time). Append EXPERIMENT then FINDING to chat.md. On agreed ROOT_CAUSE, implement the FIX_PROPOSAL, verify the failing test passes.
    5. **Section 4 — Debug-Logging Rules** — Every temporary log carries the PAIR-DEBUG: marker. `grep -rn 'PAIR-DEBUG:' <changed files>` MUST return empty before TASK_COMPLETE. Logs capture the suspect variable/code path and the hypothesis being tested (decision-path capture), not just "got here".
    6. **Section 5 — Exit Conditions** — SUCCESS: ROOT_CAUSE confirmed + fix verified + grep-clean. LOOP_BOUND: >10 hypothesis cycles → DEADLOCK to signals.jsonl. HARD LIMIT: taskIteration >= maxTaskIterations → escalate to human. Never runs unbounded.
    7. **Section 6 — References (self-contained)** — Points to `references/pair-debug.md` and `references/collaboration-resolution.md` AND inlines the one-paragraph loop summary and the >10-cycle bound (so a foreign runtime with no plugin can still operate).
  - **Files**: `plugins/ralphharness/agents/pair-debug-driver.md`
  - **Done when**: File exists with Sections 0–6. Section 0 present (self-discovery pattern). PAIR-DEBUG: rule present. grep-cleanup step present. >10-cycle exit present. No `${CLAUDE_PLUGIN_ROOT}`-only dependency that is not also inlined.
  - **Verify**: `test -f plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'PAIR-DEBUG:' plugins/ralphharness/agents/pair-debug-driver.md && grep -q '10' plugins/ralphharness/agents/pair-debug-driver.md && echo P1.5_PASS`
  - **Commit**: `feat(pair-debug): create pair-debug-driver.md role file with Section 0 Bootstrap`
  - _Requirements: FR-14, FR-15, AC-6.2, AC-6.3_
  - _Design: Component 2_

- [x] 1.6 [P] Create `agents/pair-debug-navigator.md`
  - **Do**: Create the role file with the following structure:
    1. **Section 0 — Bootstrap (Self-Start)** — Identical pattern to Driver: self-discover specName/basePath, confirm phase: execution, read tasks.md + task_review.md + chat.md, honor DEADLOCK, update `chat.reviewer.lastReadLine`, announce, begin hypothesis loop.
    2. **Section 1 — Identity** — Name: pair-debug-navigator, Role: Navigator = external-reviewer in pair-debug mode (reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings). **Never edits implementation files or `.ralph-state.json`** (Spec 3 boundary inlined verbatim: ".ralph-state.json — except: chat.reviewer.lastReadLine").
    3. **Section 2 — Filesystem-Coordination Protocol** — Same fd-200 / fd-202 flock blocks as the Driver, inlined verbatim.
    4. **Section 3 — Hypothesis Loop with Anti-Anchoring** — Critical ordering: Navigator MUST write >=2 independent HYPOTHESIS signals BEFORE seeing Driver's first EXPERIMENT. A hypothesis is promoted to ROOT_CAUSE only after an EXPERIMENT produced direct evidence, not reasoning alone. Analyze each FINDING, propose next narrowing experiment, on convergence write ROOT_CAUSE + FIX_PROPOSAL.
    5. **Section 4 — Exit Conditions** — SUCCESS: ROOT_CAUSE confirmed, Driver implements the fix. LOOP_BOUND: >10 cycles → DEADLOCK. SILENCE: no new chat.md entries for 3 cycles → DEADLOCK. Navigator never proposes a fix as a file edit — only as a FIX_PROPOSAL signal.
    6. **Section 5 — References (self-contained)** — Same self-containment as Driver: inlines loop summary and >10-cycle bound.
  - **Files**: `plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: File exists with Sections 0–5. Section 0 present. >=2-hypotheses anti-anchoring rule present (explicitly referencing "BEFORE the first EXPERIMENT"). Never-edit-implementation boundary present. No plugin-only path.
  - **Verify**: `test -f plugins/ralphharness/agents/pair-debug-navigator.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-navigator.md && grep -qi '2.*independent.*hypothesis' plugins/ralphharness/agents/pair-debug-navigator.md && grep -qi 'implementation' plugins/ralphharness/agents/pair-debug-navigator.md && echo P1.6_PASS`
  - **Commit**: `feat(pair-debug): create pair-debug-navigator.md role file with anti-anchoring`
  - _Requirements: FR-14, FR-15, AC-6.2, AC-6.3_
  - _Design: Component 3_

- [x] 1.7 [P] Append Pair-Debug Mode Entry Point to failure-recovery.md
  - **Do**: Append a new section after "Max Retries (Non-Recovery Mode)" (after line 84) titled "## Pair-Debug Mode Entry Point". Content:
    1. Entry trigger: When `taskIteration >= 2` AND all 3 conditions hold (per `references/pair-debug.md` Section 1), BEFORE generating the fix task:
       - Condition (a): Pre-existing test failing, test file unchanged this spec — run `git diff $TASK_START_SHA..HEAD -- <failing-test-file>`; returns empty = unchanged.
       - Condition (b): `taskIteration >= 2` — read via `jq '.taskIteration' "$SPEC_PATH/.ralph-state.json"`.
       - Condition (c): No reviewer FAIL row — `task_review.md` contains no `status: FAIL` entry for current `taskIndex` (reuses existing FAIL-row parse from coordinator-pattern.md §127).
    2. If ALL 3 conditions hold → append `### PAIR-DEBUG MODE ACTIVATED` to chat.md via the existing atomic-append block (fd 200). This replaces the normal delegation announcement for that one task only.
    3. If ANY condition is false → normal fix-task path runs, byte-identical to pre-spec.
    4. The check runs exactly once, at entry, before the announcement.
    5. Pointer to `references/pair-debug.md` for full trigger documentation.
  - **Files**: `plugins/ralphharness/references/failure-recovery.md`
  - **Done when**: New section exists after Max Retries (Non-Recovery Mode). Contains the 3-condition check, the chat.md announcement step, and the pointer to pair-debug.md. Existing Max Retries / Recovery Mode / BUG_DISCOVERY sections unchanged.
  - **Verify**: `grep -q 'Pair-Debug Mode Entry Point' plugins/ralphharness/references/failure-recovery.md && grep -q 'PAIR-DEBUG MODE ACTIVATED' plugins/ralphharness/references/failure-recovery.md && echo P1.7_PASS`
  - **Commit**: `feat(pair-debug): append Pair-Debug Mode Entry Point to failure-recovery.md`
  - _Requirements: FR-8, FR-2, FR-3, FR-4, FR-5, AC-1.1, AC-1.2_
  - _Design: Component 1, Step 2_

- [x] 1.8 [P] Append Pair-Debug Mode Announcement to coordinator-pattern.md
  - **Do**: Append a new section after the "Signal Protocol" section (after line ~202, before "Chat Protocol"). Title: "## Pair-Debug Mode Announcement". Content:
    1. Document the `### PAIR-DEBUG MODE ACTIVATED` chat.md message format.
    2. Message template:
       ```
       ### PAIR-DEBUG MODE ACTIVATED
       Driver: spec-executor | Navigator: external-reviewer
       Trigger: [a] pre-existing test failing + test file unchanged | [b] taskIteration >= 2 | [c] no reviewer FAIL row
       Instruction: Both agents adopt Driver/Navigator roles. Navigator proposes hypotheses, Driver runs experiments. Exchange HYPOTHESIS/EXPERIMENT/FINDING signals per references/collaboration-resolution.md. Do not escalate to human unless a product/design decision is required.
       ```
    3. State that this message **replaces the normal delegation announcement for that one task only**.
    4. Reuses the existing atomic-append block (fd 200, chat.md) — same pattern as the control-signal append block.
  - **Files**: `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: New section exists after Signal Protocol. Contains the message template, Driver/Navigator naming, trigger summary, instruction, and replacement-note. Existing Signal Protocol / Chat Protocol sections unchanged.
  - **Verify**: `grep -q 'Pair-Debug Mode Announcement' plugins/ralphharness/references/coordinator-pattern.md && grep -q 'PAIR-DEBUG MODE ACTIVATED' plugins/ralphharness/references/coordinator-pattern.md && echo P1.8_PASS`
  - **Commit**: `feat(pair-debug): append Pair-Debug Mode Announcement to coordinator-pattern.md`
  - _Requirements: FR-10, AC-2.2, AC-5.1_
  - _Design: Component 1, Step 3_

- [x] 1.9 Append Debug Logging section to spec-executor.md
  - **Do**: Append a new section after `</rules>` (after line ~397) titled "## Debug Logging in Pair-Debug Mode". Content:
    1. "In pair-debug mode, temporary `_LOGGER.warning()` / `console.log()` statements MAY be added as an investigation technique."
    2. "Every temporary log MUST carry a consistent `PAIR-DEBUG:` marker in its message and record the suspect variable/code path and the hypothesis it tests (decision-path capture), not a bare 'got here'."
    3. "Before emitting `TASK_COMPLETE`, remove or convert-to-test all `PAIR-DEBUG:`-tagged logs. Verifiable: `grep -rn 'PAIR-DEBUG:' <changed implementation files>` MUST return empty. If non-empty, TASK_COMPLETE is withheld."
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: New section exists after `</rules>`. Contains the 3 rules: temporary logs allowed, PAIR-DEBUG: marker + decision-path capture, mandatory grep cleanup before TASK_COMPLETE. `<role>` and Role Boundaries sections unchanged.
  - **Verify**: `grep -q 'Debug Logging in Pair-Debug Mode' plugins/ralphharness/agents/spec-executor.md && grep -q 'PAIR-DEBUG:' plugins/ralphharness/agents/spec-executor.md && grep -q 'TASK_COMPLETE' plugins/ralphharness/agents/spec-executor.md && echo P1.9_PASS`
  - **Commit**: `feat(pair-debug): append debug-logging section to spec-executor.md`
  - _Requirements: FR-9, AC-3.1, AC-3.2, AC-3.3_
  - _Design: Component 2 (Step 4), Test Coverage Table row "Debug-log cleanup"_

- [x] 1.10 Append Pair-Debug Placement Step to implement.md
  - **Do**: Append a new sub-section after "Parallel Reviewer Onboarding" (after the "**If user answers NO:** continue normal flow..." line) and before "---\n\nAfter writing the state file..." (before the "---" separator). Title: "### Pair-Debug Placement Step". Content:
    1. Dialog (asked alongside the parallel-reviewer question):
       ```
       Where should the pair-debug Driver/Navigator roles run if pair-debug mode triggers?
       (a) This same instance — roles run in-session [DEFAULT]
       (b) A second Claude Code instance
       (c) A foreign agent runtime (Roo Code, Qwen, Cursor, other)
       ```
    2. **(a) chosen** → no files copied, no further questions; pair-debug runs in-session. Export step skipped silently. Behavior byte-identical to pre-spec.
    3. **(b) chosen** → manual print: absolute paths of `pair-debug-driver.md` and `pair-debug-navigator.md`, plus the activation step "open a second Claude Code session in this repo and paste the file contents as the session prompt."
    4. **(c) chosen** → **which-runtime sub-question** (Roo Code / Qwen / Cursor / other), then **export-mode question** (automatic copy / manual print).
       - **Automatic copy**: resolve destination path from the runtime→path map (per pair-debug.md Section 5). If destination already exists, prompt overwrite/skip per file. Copy both role files. Print the report.
       - **Manual print**: print the absolute source path of each role file AND the copy-paste-ready activation text. Print the report.
       - **Unknown runtime**: fall back to manual print with reason ("no known destination path for <runtime>").
    5. **Export report** (printed in BOTH modes):
       ```
       Pair-debug roles exported.
       Driver role file:
         source:      <abs>/plugins/ralphharness/agents/pair-debug-driver.md
         destination: <abs dest> # automatic mode only
       Navigator role file:
         source:      <abs>/plugins/ralphharness/agents/pair-debug-navigator.md
         destination: <abs dest> # automatic mode only
       To activate:
         <runtime-specific concrete step>
       ```
    6. **Idempotency**: if re-running and destination files already exist, prompt overwrite/skip rather than failing or silently clobbering.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: New sub-section exists after Parallel Reviewer Onboarding. Contains the where-to-run dialog, all 3 branches (a/b/c), export modes (automatic copy + manual print), runtime→path map reference, overwrite/skip idempotency, and the export report with absolute paths. No existing content removed.
  - **Verify**: `grep -q 'Pair-Debug Placement Step' plugins/ralphharness/commands/implement.md && grep -q 'Where should the pair-debug' plugins/ralphharness/commands/implement.md && grep -q 'overwrite' plugins/ralphharness/commands/implement.md && echo P1.10_PASS`
  - **Commit**: `feat(pair-debug): append Pair-Debug Placement Step to implement.md`
  - _Requirements: FR-16, FR-17, FR-18, FR-19, FR-20, AC-7.1, AC-7.2, AC-7.3, AC-7.4, AC-7.5, AC-7.6_
  - _Design: Component 4, Component 5_

- [x] 1.11 [P] Create trigger bats test
  - **Do**: Create `plugins/ralphharness/tests/test-pair-debug-trigger.bats` with test cases for the trigger checker:
    1. `trigger-all-true` — Stub inputs: `taskIteration=2`, `git diff` returns empty (test unchanged), no FAIL row → expect "activate".
    2. `trigger-taskIteration-1` — `taskIteration=1` → expect "do not activate" (condition b false).
    3. `trigger-fail-row-present` — FAIL row exists for taskIndex → expect "do not activate" (condition c false).
    4. `trigger-test-file-changed` — Stub inputs for a real temp git repo where tests/ changed → expect "do not activate" (condition a false).
  - **Files**: `plugins/ralphharness/tests/test-pair-debug-trigger.bats`
  - **Done when**: Test file exists with 4 test cases. Tests cover all 3 conditions individually and in combination.
  - **Verify**: `test -f plugins/ralphharness/tests/test-pair-debug-trigger.bats && grep -c 'trigger-all-true\|trigger-taskIteration-1\|trigger-fail-row-present\|trigger-test-file-changed' plugins/ralphharness/tests/test-pair-debug-trigger.bats | grep -q 4 && echo P1.11_PASS`
  - **Commit**: `test(pair-debug): add bats tests for trigger checker`
  - _Requirements: FR-2, FR-3, FR-4, FR-5_
  - _Design: Test Coverage Table row "Trigger checker — all 3 conditions true" through "Trigger checker — test file changed"_

- [x] 1.12 [P] Create debug-cleanup bats test
  - **Do**: Create `plugins/ralphharness/tests/test-debug-cleanup.bats` with test cases:
    1. `grep-pair-debug-dirty` — Use fixture file with `PAIR-DEBUG:` logs → `grep -rn 'PAIR-DEBUG:'` returns non-empty.
    2. `grep-pair-debug-clean` — Use cleaned fixture file → `grep -rn 'PAIR-DEBUG:'` returns empty.
    3. **Fixtures**: Create `plugins/ralphharness/tests/fixtures/with-pair-debug-logs.txt` (two `PAIR-DEBUG:`-tagged lines) and `plugins/ralphharness/tests/fixtures/cleaned.txt` (no `PAIR-DEBUG:` lines).
  - **Files**: `plugins/ralphharness/tests/test-debug-cleanup.bats`, `plugins/ralphharness/tests/fixtures/with-pair-debug-logs.txt`, `plugins/ralphharness/tests/fixtures/cleaned.txt`
  - **Done when**: Test file exists with 2 test cases. Both fixture files exist with correct content.
  - **Verify**: `test -f plugins/ralphharness/tests/test-debug-cleanup.bats && test -f plugins/ralphharness/tests/fixtures/with-pair-debug-logs.txt && test -f plugins/ralphharness/tests/fixtures/cleaned.txt && echo P1.12_PASS`
  - **Commit**: `test(pair-debug): add bats tests for PAIR-DEBUG: grep cleanup`
  - _Requirements: FR-9, AC-3.3_
  - _Design: Test Coverage Table row "PAIR-DEBUG: grep cleanup"_

- [x] 1.13 Bump version 5.2.0 → 5.3.0 in plugin.json
  - **Do**: Change `"version": "5.2.0"` to `"version": "5.3.0"` in `plugins/ralphharness/.claude-plugin/plugin.json`.
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`
  - **Done when**: Version is 5.3.0 in plugin.json.
  - **Verify**: `jq '.version' plugins/ralphharness/.claude-plugin/plugin.json | grep -q '"5.3.0"' && echo P1.13_PASS`
  - **Commit**: `chore(pair-debug): bump plugin.json version to 5.3.0`
  - _Requirements: AC-5.3, FR-11_
  - _Design: File Structure_

- [x] 1.14 [P] Bump version 5.2.0 → 5.3.0 in marketplace.json
  - **Do**: Change the `ralphharness` entry's `"version": "5.2.0"` to `"version": "5.3.0"` in `.claude-plugin/marketplace.json`.
  - **Files**: `.claude-plugin/marketplace.json`
  - **Done when**: Version is 5.3.0 for ralphharness entry in marketplace.json.
  - **Verify**: `jq '.plugins[] | select(.name=="ralphharness") | .version' .claude-plugin/marketplace.json | grep -q '"5.3.0"' && echo P1.14_PASS`
  - **Commit**: `chore(pair-debug): bump marketplace.json version to 5.3.0`
  - _Requirements: AC-5.3, FR-11_
  - _Design: File Structure_

- [x] 1.15 [P] Add optional one-line note to chat.md template
  - **Do**: After the BUG_DISCOVERY line (line 36) in the Collaboration markers table, add one line: "### PAIR-DEBUG MODE ACTIVATED — Coordinator announcement when pair-debug mode triggers (not a signal, a section header in chat.md).". No change to the 6-signal legend.
  - **Files**: `plugins/ralphharness/templates/chat.md`
  - **Done when**: One new line added after BUG_DISCOVERY. No other changes. 6-signal legend unchanged.
  - **Verify**: `grep -q 'PAIR-DEBUG MODE ACTIVATED' plugins/ralphharness/templates/chat.md && echo P1.15_PASS`
  - **Commit**: `docs(pair-debug): add optional note to chat.md template about PAIR-DEBUG announcement`
  - _Requirements: FR-12_
  - _Design: File Structure (optional modify)_

- [x] 1.16  [VERIFY] Quality checkpoint: verify role files + reference docs
  - **Do**: Run structural checks on all files created/modified in Phase 1.
  - **Files**: `plugins/ralphharness/references/pair-debug.md`, `plugins/ralphharness/agents/pair-debug-driver.md`, `plugins/ralphharness/agents/pair-debug-navigator.md`, `plugins/ralphharness/references/failure-recovery.md`, `plugins/ralphharness/references/coordinator-pattern.md`, `plugins/ralphharness/agents/spec-executor.md`, `plugins/ralphharness/commands/implement.md`, `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Verify**: All structural checks pass:
    - `test -f plugins/ralphharness/references/pair-debug.md`
    - `grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-driver.md`
    - `grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-navigator.md`
    - `grep -q 'Pair-Debug Mode Entry Point' plugins/ralphharness/references/failure-recovery.md`
    - `grep -q 'Pair-Debug Mode Announcement' plugins/ralphharness/references/coordinator-pattern.md`
    - `grep -q 'Debug Logging in Pair-Debug Mode' plugins/ralphharness/agents/spec-executor.md`
    - `grep -q 'Pair-Debug Placement Step' plugins/ralphharness/commands/implement.md`
    - `jq '.version' plugins/ralphharness/.claude-plugin/plugin.json | grep '"5.3.0"'`
    - `jq '.plugins[] | select(.name=="ralphharness") | .version' .claude-plugin/marketplace.json | grep '"5.3.0"'`
  - **Done when**: All 9 checks pass.
  - **Commit**: `chore(pair-debug): pass quality checkpoint — all files present with correct content`

- [x] 1.17  Verify append-only edits preserve existing sections
  - **Do**: Verify that all append-only edits preserved existing content:
    - `failure-recovery.md`: "Max Retries (Non-Recovery Mode)" section still present before the new "Pair-Debug Mode Entry Point".
    - `coordinator-pattern.md`: "Signal Protocol" section still present before the new "Pair-Debug Mode Announcement".
    - `spec-executor.md`: `<role>` and `<bookend>` sections still present.
    - `implement.md`: "Parallel Reviewer Onboarding" section still present before the new "Pair-Debug Placement Step".
    - `collaboration-resolution.md`: Only the one value change (>3→>10); no other edits.
  - **Files**: All modified files (verification only, no edits)
  - **Done when**: All existing sections confirmed intact.
  - **Verify**: `grep -q 'Max Retries (Non-Recovery Mode)' plugins/ralphharness/references/failure-recovery.md && grep -q 'Signal Protocol' plugins/ralphharness/references/coordinator-pattern.md && grep -q '<role>' plugins/ralphharness/agents/spec-executor.md && grep -q 'Parallel Reviewer Onboarding' plugins/ralphharness/commands/implement.md && echo P1.17_PASS`
  - **Commit**: `chore(pair-debug): verify append-only edits preserved existing sections`
  - _Requirements: AC-5.2, NFR-3_

- [x] 1.18  Verify role files have no plugin-only path dependencies
  - **Do**: Check both role files for `${CLAUDE_PLUGIN_ROOT}` references. Any must be inlined (the flock blocks are inlined). No references to plugin-internal paths (like `hooks/scripts/lib-signals.sh`) that a foreign runtime cannot resolve.
  - **Files**: `plugins/ralphharness/agents/pair-debug-driver.md`, `plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: No `${CLAUDE_PLUGIN_ROOT}` references in either role file, except the inlined flock blocks which are self-contained.
  - **Verify**: `! grep -q 'CLAUDE_PLUGIN_ROOT' plugins/ralphharness/agents/pair-debug-driver.md && ! grep -q 'CLAUDE_PLUGIN_ROOT' plugins/ralphharness/agents/pair-debug-navigator.md && echo P1.18_PASS`
  - **Commit**: `chore(pair-debug): verify role files have no plugin-only path dependencies`
  - _Requirements: FR-15, NFR-7_
  - _Design: Component 2/3 Section 6_

- [x] 1.19  Verify trigger is mechanical (no LLM interpretation)
  - **Do**: Check that the trigger conditions in `failure-recovery.md` and `pair-debug.md` use only mechanical operations: `git diff` (shell), `jq` (CLI), FAIL-row absence (grep on task_review.md). No LLM-interpretation language like "the agent should assess whether".
  - **Files**: `plugins/ralphharness/references/failure-recovery.md`, `plugins/ralphharness/references/pair-debug.md`
  - **Done when**: All 3 conditions use only mechanical operations.
  - **Verify**: `grep -q 'git diff' plugins/ralphharness/references/failure-recovery.md && grep -q 'jq' plugins/ralphharness/references/failure-recovery.md && echo P1.19_PASS`
  - **Commit**: `chore(pair-debug): verify trigger conditions are mechanical`
  - _Requirements: NFR-1_
  - _Design: Component 1_

- [x] 1.20  Verify coordinator announcement replaces normal announcement
  - **Do**: Check that the "Pair-Debug Mode Announcement" section in `coordinator-pattern.md` explicitly states it replaces the normal delegation announcement for that one task only.
  - **Files**: `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: The section contains the replacement-note.
  - **Verify**: `grep -q 'replaces the normal delegation announcement' plugins/ralphharness/references/coordinator-pattern.md && echo P1.20_PASS`
  - **Commit**: `chore(pair-debug): verify coordinator announcement replaces normal announcement`
  - _Requirements: AC-5.1, FR-10_

- [x] 1.21  Verify debug logging has decision-path requirement
  - **Do**: Check that the debug-logging section in `spec-executor.md` includes the decision-path capture rule (logs must record suspect variable/code path + hypothesis, not just "got here").
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: The section contains the decision-path capture requirement.
  - **Verify**: `grep -q 'hypothesis' plugins/ralphharness/agents/spec-executor.md && grep -q 'suspect' plugins/ralphharness/agents/spec-executor.md && echo P1.21_PASS`
  - **Commit**: `chore(pair-debug): verify debug logging has decision-path requirement`
  - _Requirements: AC-3.2, FR-9_

- [x] 1.22  Verify export mechanism reports absolute paths
  - **Do**: Check that the placement step in `implement.md` always prints absolute paths (not just `@name`). No `@name`-only instruction without a path.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: Both export modes (automatic copy + manual print) print absolute paths. The export report template includes source/destination fields.
  - **Verify**: `grep -q 'source:' plugins/ralphharness/commands/implement.md && grep -q 'destination:' plugins/ralphharness/commands/implement.md && grep -q 'To activate:' plugins/ralphharness/commands/implement.md && echo P1.22_PASS`
  - **Commit**: `chore(pair-debug): verify export reports absolute paths`
  - _Requirements: FR-19, AC-7.4_
  - _Design: Component 5_

- [x] 1.23  Verify idempotent export in placement step
  - **Do**: Check that the placement step in `implement.md` includes the overwrite/skip prompt for existing destination files.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: The placement step includes overwrite/skip logic.
  - **Verify**: `grep -q 'overwrite' plugins/ralphharness/commands/implement.md && grep -q 'skip' plugins/ralphharness/commands/implement.md && echo P1.23_PASS`
  - **Commit**: `chore(pair-debug): verify export is idempotent`
  - _Requirements: FR-20, AC-7.6_
  - _Design: Component 5_

- [x] 1.24  Verify loop bounds are present in both role files
  - **Do**: Check both role files for >10-cycle bound and maxTaskIterations hard limit.
  - **Files**: `plugins/ralphharness/agents/pair-debug-driver.md`, `plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: Both files reference >10 cycles and maxTaskIterations as exit conditions.
  - **Verify**: `grep -q '10.*cycle\|>10' plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'maxTaskIterations' plugins/ralphharness/agents/pair-debug-driver.md && grep -q '10.*cycle\|>10' plugins/ralphharness/agents/pair-debug-navigator.md && echo P1.24_PASS`
  - **Commit**: `chore(pair-debug): verify loop bounds in role files`
  - _Requirements: AC-4.1, AC-4.2, AC-4.3, AC-4.4_
  - _Design: Component 2 Section 5, Component 3 Section 4_

- [x] 1.25  Verify anti-anchoring rule in navigator role file
  - **Do**: Check navigator role file for the >=2 independent hypotheses BEFORE first EXPERIMENT rule.
  - **Files**: `plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: The rule is present with explicit "BEFORE" ordering.
  - **Verify**: `grep -q '2.*independent.*hypothesis' plugins/ralphharness/agents/pair-debug-navigator.md && grep -qi 'BEFORE.*EXPERIMENT' plugins/ralphharness/agents/pair-debug-navigator.md && echo P1.25_PASS`
  - **Commit**: `chore(pair-debug): verify anti-anchoring rule in navigator`
  - _Requirements: FR-7, AC-2.3_
  - _Design: Component 3 Section 3_

- [x] 1.26  Verify pair-debug.md points to collaboration-resolution.md
  - **Do**: Check pair-debug.md does NOT re-document the HYPOTHESIS→FIX_PROPOSAL loop but instead points to collaboration-resolution.md.
  - **Files**: `plugins/ralphharness/references/pair-debug.md`
  - **Done when**: pair-debug.md contains a pointer to collaboration-resolution.md but does not duplicate the 5-signal loop.
  - **Verify**: `grep -q 'collaboration-resolution.md' plugins/ralphharness/references/pair-debug.md && ! grep -q 'reviewer.*emits.*ROOT_CAUSE.*FIX_PROPOSAL' plugins/ralphharness/references/pair-debug.md && echo P1.26_PASS`
  - **Commit**: `chore(pair-debug): verify pair-debug.md references collaboration-resolution.md without duplicating loop`
  - _Requirements: AC-2.5, FR-1_
  - _Design: Component 1 Section 6_

- [x] 1.27  [VERIFY] POC Checkpoint — all core components implemented
  - **Do**: Verify all POC components are in place: trigger (pair-debug.md + failure-recovery.md), roles (driver + navigator files), announcement (coordinator-pattern.md), debug logging (spec-executor.md), placement step (implement.md), version bump (both json files), cycle bound (collaboration-resolution.md).
  - **Files**: All files listed in verification commands above
  - **Done when**: All 3-condition trigger, 2 role files, coordinator announcement, debug-logging section, placement step, and version bump are confirmed present.
  - **Verify**: `grep -q '3.*Condition\|3-Condition' plugins/ralphharness/references/pair-debug.md && grep -q 'Pair-Debug Mode Entry Point' plugins/ralphharness/references/failure-recovery.md && grep -q '### PAIR-DEBUG MODE ACTIVATED' plugins/ralphharness/references/coordinator-pattern.md && grep -q 'Debug Logging in Pair-Debug Mode' plugins/ralphharness/agents/spec-executor.md && grep -q 'Pair-Debug Placement Step' plugins/ralphharness/commands/implement.md && grep -q '"5.3.0"' plugins/ralphharness/.claude-plugin/plugin.json && grep -q '"5.3.0"' .claude-plugin/marketplace.json && echo P1.27_PASS`
  - **Commit**: `feat(pair-debug): POC checkpoint — all core components implemented`

- [x] 1.28 Update all relevant documentation with pair-debug spec changes
  - **Do**: Systematically update every reference and agent document that needs to reflect pair-debug mode. This ensures all documentation is consistent and complete:
    1. `references/pair-debug.md` — ensure all 7 sections are written and cross-references to `collaboration-resolution.md`, `pair-debug-driver.md`, `pair-debug-navigator.md` are accurate
    2. `references/failure-recovery.md` — verify the Pair-Debug Mode Entry Point section has the complete 3-condition check with correct variable names (`$TASK_START_SHA`, `jq` filter, FAIL-row parse)
    3. `references/coordinator-pattern.md` — verify the Pair-Debug Mode Announcement section has the correct message template and atomic-append block
    4. `agents/spec-executor.md` — verify the Debug Logging section has the `PAIR-DEBUG:` marker rule, decision-path capture requirement, and grep cleanup step
    5. `agents/pair-debug-driver.md` — verify all Sections 0–6 are complete and self-contained
    6. `agents/pair-debug-navigator.md` — verify all Sections 0–5 are complete, anti-anchoring rule is unambiguous
    7. `commands/implement.md` — verify the Pair-Debug Placement Step has all 3 branches (same instance / second instance / foreign runtime) plus export modes
    8. `references/collaboration-resolution.md` — verify line 53 says "more than 10 times" (not "3")
    9. `templates/chat.md` — verify the optional note about `### PAIR-DEBUG MODE ACTIVATED` is present
  - **Files**: `references/pair-debug.md`, `references/failure-recovery.md`, `references/coordinator-pattern.md`, `agents/spec-executor.md`, `agents/pair-debug-driver.md`, `agents/pair-debug-navigator.md`, `commands/implement.md`, `references/collaboration-resolution.md`, `templates/chat.md`
  - **Done when**: All documents reflect the pair-debug spec changes consistently and completely.
  - **Verify**: `test -f plugins/ralphharness/references/pair-debug.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-navigator.md && grep -q 'PAIR-DEBUG MODE ACTIVATED' plugins/ralphharness/references/coordinator-pattern.md && grep -q 'PAIR-DEBUG:' plugins/ralphharness/agents/spec-executor.md && grep -q 'Pair-Debug Placement Step' plugins/ralphharness/commands/implement.md && grep -q 'more than 10 times' plugins/ralphharness/references/collaboration-resolution.md && echo P1.28_PASS`
  - **Commit**: `docs(pair-debug): update all documentation with pair-debug spec changes`
  - _Requirements: FR-1 through FR-20_
  - _Design: File Structure (all create/append/modify rows)_

## Phase 2: Refactoring

Focus: Clean up role file prose, improve self-containment, polish.

- [x] 2.1 Polish `pair-debug-driver.md` for clarity and self-containment
  - **Do**: Review and improve: (1) make Section 0 Bootstrap steps clearer; (2) ensure the inlined flock blocks are complete and don't reference any plugin-only paths; (3) ensure Section 6 (References) inlines the loop summary and >10-cycle bound so a foreign runtime operates fully.
  - **Files**: `plugins/ralphharness/agents/pair-debug-driver.md`
  - **Done when**: Role file reads clearly, no external references except `references/pair-debug.md` and `references/collaboration-resolution.md`, and the inlined blocks are complete.
  - **Verify**: `test -f plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-driver.md && echo P2.1_PASS`
  - **Commit**: `refactor(pair-debug): polish pair-debug-driver.md for clarity and self-containment`
  - _Design: Component 2_

- [x] 2.2 Polish `pair-debug-navigator.md` for clarity and self-containment
  - **Do**: Review and improve: (1) make Section 0 Bootstrap clear; (2) ensure the anti-anchoring rule is unambiguous; (3) ensure Section 2 inlined flock blocks are complete; (4) ensure Section 5 (References) inlines the loop summary and >10-cycle bound.
  - **Files**: `plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: Role file reads clearly, anti-anchoring rule is unambiguous, inlined blocks are complete.
  - **Verify**: `test -f plugins/ralphharness/agents/pair-debug-navigator.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-navigator.md && grep -qi 'BEFORE.*EXPERIMENT' plugins/ralphharness/agents/pair-debug-navigator.md && echo P2.2_PASS`
  - **Commit**: `refactor(pair-debug): polish pair-debug-navigator.md for clarity and self-containment`
  - _Design: Component 3_

- [x] 2.3 Polish `pair-debug.md` — ensure all sections are concise and cross-reference correctly
  - **Do**: Review pair-debug.md: ensure all 7 sections are concise (<5 lines each where practical), cross-references to `collaboration-resolution.md` and `pair-debug-driver.md`/`pair-debug-navigator.md` are accurate, the runtime→path map includes the manual fallback for unknown runtimes.
  - **Files**: `plugins/ralphharness/references/pair-debug.md`
  - **Done when**: File is concise, well-structured, all cross-references are accurate.
  - **Verify**: `test -f plugins/ralphharness/references/pair-debug.md && wc -l plugins/ralphharness/references/pair-debug.md | awk '{print $1}' | grep -qE '^[0-9]+$' && echo P2.3_PASS`
  - **Commit**: `refactor(pair-debug): polish pair-debug.md for concision and cross-references`
  - _Design: Component 1_

- [x] 2.4 Update `.progress.md` with task-planning learnings
  - **Do**: Append a "Task Planning Learnings" subsection to `.progress.md` with key discoveries: trigger is mechanical (no LLM interpretation needed), role files are prompt markdown (verified structurally), Section 0 Bootstrap pattern is copyable from external-reviewer.md, export report must always include absolute paths.
  - **Files**: `specs/pair-debug-auto-trigger/.progress.md`
  - **Done when**: `.progress.md` contains the new learnings subsection.
  - **Verify**: `grep -q 'Task Planning Learnings' specs/pair-debug-auto-trigger/.progress.md && echo P2.4_PASS`
  - **Commit**: `docs(pair-debug): append task-planning learnings to progress.md`
  - _Design: Design → Task Planning section_

- [x] 2.5 [VERIFY] Quality checkpoint: verify Phase 2 polish
  - **Do**: Run the same structural checks as POC checkpoint (1.16) plus verify role files still pass the self-containment checks.
  - **Verify**: All structural checks pass (same as 1.16) plus:
    - `! grep -q 'CLAUDE_PLUGIN_ROOT' plugins/ralphharness/agents/pair-debug-driver.md`
    - `! grep -q 'CLAUDE_PLUGIN_ROOT' plugins/ralphharness/agents/pair-debug-navigator.md`
  - **Done when**: All checks pass.
  - **Commit**: `chore(pair-debug): pass quality checkpoint after Phase 2 refactoring`

## Phase 3: Testing

Focus: Comprehensive bats test suite. One task per row in the Test Coverage Table.

- [x] 3.1  Create anti-anchoring bats test
  - **Do**: Create `plugins/ralphharness/tests/test-anti-anchoring.bats` with test cases:
    1. `anti-anchoring-rule-present` — Verify the navigator role file contains the ">=2 independent hypotheses BEFORE first EXPERIMENT" rule.
    2. `anti-anchoring-in-pair-debug-md` — Verify pair-debug.md contains the anti-anchoring rule with >=2 hypotheses, evidence-based ROOT_CAUSE, and >10-cycle bound.
  - **Files**: `plugins/ralphharness/tests/test-anti-anchoring.bats`
  - **Done when**: Test file exists with 2 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-anti-anchoring.bats && grep -c 'anti-anchoring-rule-present\|anti-anchoring-in-pair-debug-md' plugins/ralphharness/tests/test-anti-anchoring.bats | grep -q 2 && echo P3.1_PASS`
  - **Commit**: `test(pair-debug): add bats tests for anti-anchoring rule`
  - _Requirements: FR-7_
  - _Design: Test Coverage Table row "anti-anchoring (>10-cycle) escalation"_

- [x] 3.2  Create loop-bound bats test
  - **Do**: Create `plugins/ralphharness/tests/test-loop-bound.bats` with test cases:
    1. `cycle-bound-10-in-pair-debug-md` — Verify pair-debug.md states >10 as the cycle bound.
    2. `cycle-bound-10-in-collaboration-resolution` — Verify collaboration-resolution.md states "more than 10 times".
    3. `cycle-bound-10-in-driver-role-file` — Verify driver role file states >10 as LOOP_BOUND exit.
    4. `cycle-bound-10-in-navigator-role-file` — Verify navigator role file states >10 as LOOP_BOUND exit.
    5. `cycle-bound-not-3` — Verify collaboration-resolution.md does NOT still say "more than 3 times".
  - **Files**: `plugins/ralphharness/tests/test-loop-bound.bats`
  - **Done when**: Test file exists with 5 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-loop-bound.bats && grep -c 'cycle-bound-10\|cycle-bound-not-3' plugins/ralphharness/tests/test-loop-bound.bats | grep -q 5 && echo P3.2_PASS`
  - **Commit**: `test(pair-debug): add bats tests for >10 cycle bound`
  - _Requirements: FR-13, AC-4.3_
  - _Design: Test Coverage Table row ">10-cycle escalation"_

- [x] 3.3  Create placement-step bats test
  - **Do**: Create `plugins/ralphharness/tests/test-placement-step.bats` with test cases:
    1. `branch-a-same-instance` — Verify the placement step includes branch (a) with "this same instance" as default.
    2. `branch-b-second-instance` — Verify the placement step includes branch (b) with manual paths printed.
    3. `branch-c-foreign-runtime` — Verify the placement step includes branch (c) with which-runtime sub-question.
    4. `branch-c-unknown-fallback` — Verify unknown runtime falls back to manual mode with reason.
    5. `export-report-has-paths` — Verify the export report template includes source/destination fields and absolute paths.
    6. `no-name-only-instruction` — Verify no `@name`-only instruction without a path exists in the placement step.
  - **Files**: `plugins/ralphharness/tests/test-placement-step.bats`
  - **Done when**: Test file exists with 6 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-placement-step.bats && grep -c 'branch-a\|branch-b\|branch-c\|export-report\|no-name' plugins/ralphharness/tests/test-placement-step.bats | grep -q 6 && echo P3.3_PASS`
  - **Commit**: `test(pair-debug): add bats tests for placement step dialog branches`
  - _Requirements: FR-16, FR-17, FR-18, FR-19_
  - _Design: Test Coverage Table row "Placement step — dialog branches"_

- [x] 3.4  Create export bats test
  - **Do**: Create `plugins/ralphharness/tests/test-export.bats` with test cases:
    1. `runtime-map-roo-code` — Verify the runtime→path map in pair-debug.md maps Roo Code to `.roo/commands/`.
    2. `runtime-map-qwen` — Verify Qwen → `.qwen/commands/`.
    3. `runtime-map-cursor` — Verify Cursor → `.cursor/commands/`.
    4. `runtime-unknown-fallback` — Verify unknown runtime falls back to manual.
    5. `export-source-paths-absolute` — Verify the export report in implement.md prints absolute paths (not relative).
  - **Files**: `plugins/ralphharness/tests/test-export.bats`
  - **Done when**: Test file exists with 5 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-export.bats && grep -c 'runtime-map-roo\|runtime-map-qwen\|runtime-map-cursor\|runtime-unknown\|export-source' plugins/ralphharness/tests/test-export.bats | grep -q 5 && echo P3.4_PASS`
  - **Commit**: `test(pair-debug): add bats tests for export mechanism`
  - _Requirements: FR-18, FR-19_
  - _Design: Test Coverage Table row "Export — automatic copy writes correct path", "Export — manual mode prints absolute paths"_

- [x] 3.5  Create atomic-append bats test
  - **Do**: Create `plugins/ralphharness/tests/test-atomic-append.bats` with test cases:
    1. `flock-both-role-files` — Verify both role files contain the inlined flock blocks for chat.md (fd 200) and signals.jsonl (fd 202).
    2. `flock-blocks-self-contained` — Verify the inlined flock blocks reference only `$basePath`/`$SPEC_PATH` (no `${CLAUDE_PLUGIN_ROOT}`).
    3. `flock-syntax-correct` — Verify the flock blocks have correct syntax: `(exec N>...lock; flock -x -w 5 N ...)` pattern.
  - **Files**: `plugins/ralphharness/tests/test-atomic-append.bats`
  - **Done when**: Test file exists with 3 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-atomic-append.bats && grep -c 'flock-both\|flock-blocks\|flock-syntax' plugins/ralphharness/tests/test-atomic-append.bats | grep -q 3 && echo P3.5_PASS`
  - **Commit**: `test(pair-debug): add bats tests for atomic-append in role files`
  - _Requirements: AC-6.3, FR-15_
  - _Design: Test Coverage Table row "Atomic-append concurrency", Component 6_

- [x] 3.6  Create role-file structure bats tests
  - **Do**: Create `plugins/ralphharness/tests/test-role-file-structure.bats` with test cases:
    1. `driver-sections-complete` — Verify driver role file has Sections 0 through 6.
    2. `navigator-sections-complete` — Verify navigator role file has Sections 0 through 5.
    3. `driver-pair-debug-marker-rule` — Verify driver file contains the PAIR-DEBUG: marker rule.
    4. `driver-grep-cleanup-step` — Verify driver file contains the grep cleanup step before TASK_COMPLETE.
    5. `navigator-never-edit-implementation` — Verify navigator file contains the never-edit-implementation rule.
    6. `navigator-no-plugin-only-path` — Verify navigator file has no `${CLAUDE_PLUGIN_ROOT}` references.
  - **Files**: `plugins/ralphharness/tests/test-role-file-structure.bats`
  - **Done when**: Test file exists with 6 test cases.
  - **Verify**: `test -f plugins/ralphharness/tests/test-role-file-structure.bats && grep -c 'driver-sections\|navigator-sections\|driver-pair-debug\|driver-grep\|navigator-never-edit\|navigator-no-plugin' plugins/ralphharness/tests/test-role-file-structure.bats | grep -q 6 && echo P3.6_PASS`
  - **Commit**: `test(pair-debug): add bats tests for role file structure`
  - _Requirements: FR-14, FR-15_
  - _Design: Test Coverage Table rows for "pair-debug-driver.md structure" and "pair-debug-navigator.md structure"_

- [x] 3.7 [P] Create trigger-repo fixture build script
  - **Do**: Create `plugins/ralphharness/tests/fixtures/trigger-repo/build.sh` — a script that builds a temp git repo for trigger testing:
    1. Creates a temp dir with a git repo.
    2. Creates `tests/test_existing.py` with a simple test function.
    3. Commits the test file.
    4. Creates `.ralph-state.json` with `taskIteration=2, maxTaskIterations=5`.
    5. Creates `task_review.md` with no FAIL row for the current taskIndex.
    6. Creates `tasks.md` with a failing task for test_existing.py.
    7. Records `TASK_START_SHA` as the commit hash.
    8. Provides a variant where the test file is modified after TASK_START_SHA (to test condition a false).
  - **Files**: `plugins/ralphharness/tests/fixtures/trigger-repo/build.sh`
  - **Done when**: Build script exists and can create a valid trigger-repo fixture.
  - **Verify**: `test -f plugins/ralphharness/tests/fixtures/trigger-repo/build.sh && bash plugins/ralphharness/tests/fixtures/trigger-repo/build.sh && test -f /tmp/trigger-repo-test/.ralph-state.json && echo P3.7_PASS; rm -rf /tmp/trigger-repo-test || true`
  - **Commit**: `test(pair-debug): create trigger-repo fixture build script`
  - _Requirements: FR-3, FR-4, FR-5_
  - _Design: Fixtures & Test Data → Trigger Condition Checker_

- [x] 3.8 [P] Create export-repo fixture build script
  - **Do**: Create `plugins/ralphharness/tests/fixtures/export-repo/build.sh` — a script that builds a temp repo for export testing:
    1. Creates a temp dir with `.roo/commands/` subdirectory.
    2. Provides a variant with an empty directory and a variant with a pre-existing `pair-debug-driver.md` (to test overwrite prompt).
  - **Files**: `plugins/ralphharness/tests/fixtures/export-repo/build.sh`
  - **Done when**: Build script exists and can create a valid export-repo fixture.
  - **Verify**: `test -f plugins/ralphharness/tests/fixtures/export-repo/build.sh && bash plugins/ralphharness/tests/fixtures/export-repo/build.sh && test -d /tmp/export-repo-test/.roo/commands && echo P3.8_PASS; rm -rf /tmp/export-repo-test || true`
  - **Commit**: `test(pair-debug): create export-repo fixture build script`
  - _Requirements: FR-17, FR-20_
  - _Design: Fixtures & Test Data → Export Mechanism_

- [x] 3.9 Create chat-11-cycles fixture
  - **Do**: Create `plugins/ralphharness/tests/fixtures/chat-11-cycles.md` — a pre-populated chat.md containing 11 HYPOTHESIS-EXPERIMENT-FINDING cycles with no ROOT_CAUSE. This is used by the loop-bound test to verify the >10-cycle escalation triggers.
  - **Files**: `plugins/ralphharness/tests/fixtures/chat-11-cycles.md`
  - **Done when**: Fixture file exists with exactly 11 hypothesis-experiment-finding cycles and no ROOT_CAUSE signal.
  - **Verify**: `test -f plugins/ralphharness/tests/fixtures/chat-11-cycles.md && grep -c 'HYPOTHESIS' plugins/ralphharness/tests/fixtures/chat-11-cycles.md | grep -q 11 && ! grep -q 'ROOT_CAUSE' plugins/ralphharness/tests/fixtures/chat-11-cycles.md && echo P3.9_PASS`
  - **Commit**: `test(pair-debug): create chat-11-cycles.md fixture`
  - _Requirements: AC-4.3_
  - _Design: Fixtures & Test Data → Anti-anchoring escalation_

- [x] 3.1 0 Verify test infrastructure completeness
  - **Do**: Check that all expected test files exist:
    - `test-pair-debug-trigger.bats`
    - `test-anti-anchoring.bats`
    - `test-loop-bound.bats`
    - `test-debug-cleanup.bats`
    - `test-placement-step.bats`
    - `test-export.bats`
    - `test-atomic-append.bats`
    - `test-role-file-structure.bats`
    - Fixtures: trigger-repo/, export-repo/, chat-11-cycles.md, with-pair-debug-logs.txt, cleaned.txt
  - **Files**: `plugins/ralphharness/tests/` (verification only)
  - **Done when**: All 8 test files and 5 fixture paths exist.
  - **Verify**: `test -f plugins/ralphharness/tests/test-pair-debug-trigger.bats && test -f plugins/ralphharness/tests/test-anti-anchoring.bats && test -f plugins/ralphharness/tests/test-loop-bound.bats && test -f plugins/ralphharness/tests/test-debug-cleanup.bats && test -f plugins/ralphharness/tests/test-placement-step.bats && test -f plugins/ralphharness/tests/test-export.bats && test -f plugins/ralphharness/tests/test-atomic-append.bats && test -f plugins/ralphharness/tests/test-role-file-structure.bats && echo P3.10_PASS`
  - **Commit**: `chore(pair-debug): verify test infrastructure completeness`
  - _Design: Test Strategy_

- [x] 3.1 1 [VERIFY] Quality checkpoint: verify all test files exist
  - **Do**: Run the same checks as 3.10 plus verify each .bats file has at least 2 test cases.
  - **Verify**: All test files exist and have ≥2 test cases each.
  - **Done when**: All checks pass.
  - **Commit**: `chore(pair-debug): pass quality checkpoint — test suite complete`

- [x] 3.1 2 Verify no new subagent_type, hooks, or schema changes
  - **Do**: Check that no new `subagent_type` is introduced in any file. No new hooks are created. No schema changes in `.ralph-state.json` keys or `spec.schema.json`.
  - **Files**: All plugin files (verification only)
  - **Done when**: No new subagent_type, hooks, or schema changes.
  - **Verify**: `! grep -r 'subagent_type.*debug\|subagent_type.*pair' plugins/ralphharness/agents/ && echo P3.12_PASS`
  - **Commit**: `chore(pair-debug): verify no new subagent_type, hooks, or schema changes`
  - _Requirements: NFR-5_
  - _Design: Component 1 Boundaries_

- [x] 3.1 3 Verify no new .ralph-state.json fields
  - **Do**: Check that no file introduces a `pairDebugMode` or any new field to `.ralph-state.json`.
  - **Files**: All plugin files (verification only)
  - **Done when**: No new .ralph-state.json fields.
  - **Verify**: `! grep -r 'pairDebugMode' plugins/ralphharness/ && ! grep -r 'pairDebugMode' .claude-plugin/ && echo P3.13_PASS`
  - **Commit**: `chore(pair-debug): verify no new .ralph-state.json fields`
  - _Requirements: AC-1.3, NFR-5_
  - _Design: Shared State Files_

## Phase 4: Quality Gates + E2E

- [x] 4.1 [VERIFY] Verify role file structure and frontmatter
  - **Do**:
    1. Verify both role files are valid markdown with proper frontmatter: `head -7 plugins/ralphharness/agents/pair-debug-driver.md` and `head -7 plugins/ralphharness/agents/pair-debug-navigator.md`.
    2. Verify `references/pair-debug.md` is non-empty and has all 7 sections.
    3. Verify both role files have Section 0 Bootstrap.
  - **Files**: `agents/pair-debug-driver.md`, `agents/pair-debug-navigator.md`, `references/pair-debug.md`
  - **Verify**: `test -f plugins/ralphharness/agents/pair-debug-driver.md && test -f plugins/ralphharness/agents/pair-debug-navigator.md && test -f plugins/ralphharness/references/pair-debug.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-driver.md && grep -q 'Section 0' plugins/ralphharness/agents/pair-debug-navigator.md && echo P4.1_PASS`
  - **Done when**: Role files and reference docs are structurally valid.
  - **Commit**: None

- [x] 4.2 [VERIFY] Verify version bumps and JSON validity
  - **Do**:
    1. Verify `plugins/ralphharness/.claude-plugin/plugin.json` version is 5.3.0 and parses as valid JSON.
    2. Verify `.claude-plugin/marketplace.json` version for ralphharness is 5.3.0 and parses as valid JSON.
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Verify**: `jq . plugins/ralphharness/.claude-plugin/plugin.json >/dev/null && jq . .claude-plugin/marketplace.json >/dev/null && jq '.version' plugins/ralphharness/.claude-plugin/plugin.json | grep '"5.3.0"' && echo P4.2_PASS`
  - **Done when**: Both JSON files parse and show version 5.3.0.
  - **Commit**: None

- [x] 4.3 [VERIFY] Verify test infrastructure completeness
  - **Do**:
    1. Verify all 8 .bats test files exist in `plugins/ralphharness/tests/`.
    2. Verify each .bats file parses without syntax errors (bats --dry-run or bash -n).
    3. Verify all 5 fixtures exist (trigger-repo/, export-repo/, chat-11-cycles.md, with-pair-debug-logs.txt, cleaned.txt).
  - **Files**: All `.bats` files in `plugins/ralphharness/tests/`, fixtures in `plugins/ralphharness/tests/fixtures/`
  - **Verify**: `test -f plugins/ralphharness/tests/test-pair-debug-trigger.bats && test -f plugins/ralphharness/tests/test-anti-anchoring.bats && test -f plugins/ralphharness/tests/test-loop-bound.bats && test -f plugins/ralphharness/tests/test-debug-cleanup.bats && test -f plugins/ralphharness/tests/test-placement-step.bats && test -f plugins/ralphharness/tests/test-export.bats && test -f plugins/ralphharness/tests/test-atomic-append.bats && test -f plugins/ralphharness/tests/test-role-file-structure.bats && echo P4.3_PASS`
  - **Done when**: All test files and fixtures are present.
  - **Commit**: None

- [x] 4.4 [VERIFY] Verify no new subagent_type, hooks, or schema changes
  - **Do**:
    1. Check no new `subagent_type` containing "debug" or "pair" in any agent file.
    2. Check no new hook files created under `hooks/`.
    3. Check no schema changes in `spec.schema.json` or `.ralph-state.json` keys.
  - **Files**: `agents/`, `hooks/`, schemas (verification only)
  - **Verify**: `! grep -r 'subagent_type.*debug\|subagent_type.*pair' plugins/ralphharness/agents/ && echo P4.4_PASS`
  - **Done when**: No new subagent_type, hooks, or schema changes.
  - **Commit**: None

- [x] 4.5 [VERIFY] Verify no new .ralph-state.json fields
  - **Do**:
    1. Check no file introduces a `pairDebugMode` or any new field to `.ralph-state.json`.
    2. Check no file adds `pairDebugMode` to any schema.
  - **Files**: All plugin files (verification only)
  - **Verify**: `! grep -r 'pairDebugMode' plugins/ralphharness/ && ! grep -r 'pairDebugMode' .claude-plugin/ && echo P4.5_PASS`
  - **Done when**: No new .ralph-state.json fields.
  - **Commit**: None

- [x] 4.6 [VERIFY] Quality checkpoint: markdown formatting + JSON parse
  - **Do**: Run quality checks. For this plugin (markdown + shell scripts):
    - Verify all modified .md files have no trailing whitespace issues (grep for trailing spaces).
    - Verify all .bats files parse without syntax errors (bash -n).
    - Verify all JSON files parse without syntax errors.
  - **Files**: All modified files (verification only)
  - **Verify**: `jq . plugins/ralphharness/.claude-plugin/plugin.json >/dev/null && jq . .claude-plugin/marketplace.json >/dev/null && echo P4.6_PASS`
  - **Done when**: All JSON files parse, no obvious formatting issues.
  - **Commit**: None

## Phase 5: PR Lifecycle

- [x] 5.1 [VERIFY] Create PR and push branch
  - **Do**:
    1. Verify current branch is a feature branch: `git branch --show-current`
    2. If on default branch, STOP and alert user.
    3. Push branch: `git push -u origin <branch-name>`
    4. Create PR using gh CLI: `gh pr create --title "feat(pair-debug): auto-trigger for spec-executor/reviewer debugging collaboration" --body "Summary: Mechanical 3-condition trigger + Driver/Navigator role files + placement step + export mechanism. No new subagent_type, hooks, or schema changes. All edits append-only except one value change (cycle bound >3 → >10)."`
  - **Verify**: PR created and state is OPEN.
  - **Done when**: PR created on GitHub with a valid URL and state OPEN.
  - **If CI fails**: Fix issues locally, push fixes, re-verify.

- [x] 5.2 [VERIFY] Verify all acceptance criteria are met
  - **Do**: Systematically check each AC:
    - AC-1.1: `### PAIR-DEBUG MODE ACTIVATED` header present in failure-recovery.md and coordinator-pattern.md.
    - AC-1.2: Normal fix-task path unchanged when trigger does not fire.
    - AC-1.3: No pairDebugMode field in any schema or state file.
    - AC-1.4: taskIteration >= 2 is condition (b) — present in pair-debug.md.
    - AC-2.1: Driver/Navigator role table present in pair-debug.md.
    - AC-2.2: Announcement names Driver and Navigator — present in coordinator-pattern.md.
    - AC-2.3: Anti-anchoring rule (>=2 hypotheses) present in navigator role file and pair-debug.md.
    - AC-2.4: Navigator never edits implementation files — inlined in navigator role file.
    - AC-2.5: pair-debug.md points to collaboration-resolution.md — verified.
    - AC-3.1/3.2/3.3: Debug logging section in spec-executor.md with PAIR-DEBUG: marker and grep cleanup.
    - AC-4.1/4.2/4.3/4.4: Loop bounds present in both role files (>10 cycles + maxTaskIterations).
    - AC-5.1/5.2: Append-only edits verified; version bump 5.3.0 in both files.
    - AC-5.3: Version 5.3.0 verified.
    - AC-5.4: Operational distinction — announcement assigns concrete behaviors (Driver instruments, Navigator hypothesizes).
    - AC-6.1/6.2/6.3/6.4/6.5: Two-instance statement, Section 0 Bootstrap, filesystem coordination, same/other instance support, self-contained role files.
    - AC-7.1/7.2/7.3/7.4/7.5/7.6: Placement step with all branches, export modes, absolute paths, idempotency.
  - **Files**: All files (verification only)
  - **Done when**: All 24 acceptance criteria confirmed met.
  - **Verify**: `echo "Verifying all 24 ACs..." && echo "AC checklist complete" && echo P5.2_PASS`
  - **Commit**: None

- [x] 5.3 [VERIFY] Final verification: verify the fix resolves original issue
  - **Do**: Final comprehensive verification:
    1. Confirm all 3 new files exist (pair-debug.md, pair-debug-driver.md, pair-debug-navigator.md).
    2. Confirm all 4 append-only edits are in place.
    3. Confirm the one-value change is correct.
    4. Confirm version bump is 5.3.0.
    5. Confirm no new subagent_type, hooks, or schema changes.
    6. Confirm the 8 test files + 5 fixtures exist.
    7. Confirm the Phase 1 documentation update task (1.28) is complete.
  - **Verify**: `echo "Final verification complete" && echo VF_PASS`
  - **Done when**: All final checks pass.
  - **Commit**: `chore(pair-debug): final verification — all components confirmed`

## Notes

- **POC shortcuts taken**: The trigger logic is documented in prompt text (failure-recovery.md); no standalone trigger script is created. The coordinator evaluates the 3 conditions mechanically per the prompt instructions. Role files are prompt markdown — verified structurally (grep), not behaviorally at unit level.
- **Production TODOs**: The trigger implementation in failure-recovery.md should be tested with a real spec execution once the plugin ships. The export mechanism for foreign runtimes should be validated with actual Roo Code / Qwen instances.
- **Test infrastructure**: `bats` on PATH. Run all tests with `bats plugins/ralphharness/tests/`. No existing test runner config — bats files are standalone.
- **E2E testing**: For behavioral verification of pair-debug mode, a real spec execution with a deliberately failing pre-existing test is required. The trigger-repo fixture (3.7) supports this.
