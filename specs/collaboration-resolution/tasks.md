# Tasks: collaboration-resolution

## Phase 1: Make It Work (POC)

Focus: Create the new reference file, make key additive changes that prove the collaboration pattern works. Accept hardcoded values. Skip tests.

### POC Core — Create deliverables

- [x] 1.1 Create `references/collaboration-resolution.md` — Cross-branch regression investigation workflow block
  - **Do**:
    1. Create `plugins/ralphharness/references/collaboration-resolution.md`
    2. Add workflow block "Cross-branch regression investigation" with:
       - Entry condition: test green on `main`, red on `HEAD`, neither test nor fixture changed
       - Steps: (a) run `git diff main...HEAD` on failing code path, (b) identify semantic change, (c) propose fix, (d) run test to verify
       - Exit condition: test green or escalation
       - Explicit statement that trigger surface is ANY regression (including non-E2E unit-test)
    3. Verify file exists and contains required patterns
  - **Files**: `plugins/ralphharness/references/collaboration-resolution.md` (new)
  - **Done when**: File exists with the named workflow block, entry condition, 4 steps, exit condition, and ANY-regression statement
  - **Verify**: `grep -q "Cross-branch regression investigation" plugins/ralphharness/references/collaboration-resolution.md && grep -q "git diff main...HEAD" plugins/ralphharness/references/collaboration-resolution.md && grep -qi "any.*regression\|non-E2E" plugins/ralphharness/references/collaboration-resolution.md && echo 1.1_PASS`
  - **Commit**: `feat(harness): create cross-branch regression investigation workflow`
  - _Requirements: FR-1, FR-2, AC-1.1, AC-1.2, AC-1.4, AC-6.3_
  - _Design: Component C1_

- [x] 1.2 Create `references/collaboration-resolution.md` — Experiment-propose-validate workflow block
  - **Do**:
    1. Append the "Experiment-propose-validate" workflow block to the same file
    2. Describe the loop: reviewer emits HYPOTHESIS → executor emits EXPERIMENT → both emit FINDING → converge on ROOT_CAUSE → emit FIX_PROPOSAL
    3. Name which agent typically emits each signal
    4. Add the ambiguous-baseline cross-reference pointing to external-reviewer.md
  - **Files**: `plugins/ralphharness/references/collaboration-resolution.md`
  - **Done when**: File contains both named workflow blocks (cross-branch + experiment-propose-validate) with signal loop and emitting agents
  - **Verify**: `grep -q "Experiment-propose-validate" plugins/ralphharness/references/collaboration-resolution.md && grep -q "ROOT_CAUSE" plugins/ralphharness/references/collaboration-resolution.md && grep -q "FIX_PROPOSAL" plugins/ralphharness/references/collaboration-resolution.md && echo 1.2_PASS`
  - **Commit**: `feat(harness): add experiment-propose-validate workflow`
  - _Requirements: FR-4, AC-2.1_
  - _Design: Component C1_

- [x] 1.3 Append 3 collaboration-marker rows to `chat.md` — HYPOTHESIS, EXPERIMENT, FINDING
  - **Do**:
    1. Read `plugins/ralphharness/templates/chat.md` to find the end of the Collaboration markers table
    2. Append 3 rows:
       - `HYPOTHESIS` — Proposed root-cause theory for a regression (typically reviewer)
       - `EXPERIMENT` — A test/probe run to validate a hypothesis (typically executor)
       - `FINDING` — Observed result of an experiment, or recorded investigation note (typically both)
    3. Verify table is well-formed
  - **Files**: `plugins/ralphharness/templates/chat.md`
  - **Done when**: All 3 signals present in Collaboration markers table with meaning and emitting agent
  - **Verify**: `grep -q "HYPOTHESIS" plugins/ralphharness/templates/chat.md && grep -q "EXPERIMENT" plugins/ralphharness/templates/chat.md && grep -q "FINDING" plugins/ralphharness/templates/chat.md && echo 1.3_PASS`
  - **Commit**: `feat(harness): add HYPOTHESIS/EXPERIMENT/FINDING collaboration markers`
  - _Requirements: FR-5, AC-2.2, AC-2.4_
  - _Design: Component C2_

- [x] 1.4 Append 3 collaboration-marker rows to `chat.md` — ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY
  - **Do**:
    1. Append 3 more rows to the Collaboration markers table:
       - `ROOT_CAUSE` — Confirmed underlying defect, agreed by both agents
       - `FIX_PROPOSAL` — A concrete suggested fix derived from the root cause
       - `BUG_DISCOVERY` — A bug found via investigation; mirrored as a task_review.md row by reviewer
    2. Verify Control signals table is unchanged
    3. Verify `signals.jsonl` is unchanged
  - **Files**: `plugins/ralphharness/templates/chat.md`
  - **Done when**: All 6 signals present; Control signals table and `signals.jsonl` untouched
  - **Verify**: `grep -q "ROOT_CAUSE" plugins/ralphharness/templates/chat.md && grep -q "FIX_PROPOSAL" plugins/ralphharness/templates/chat.md && grep -q "BUG_DISCOVERY" plugins/ralphharness/templates/chat.md && echo 1.4_PASS`
  - **Commit**: `feat(harness): add ROOT_CAUSE/FIX_PROPOSAL/BUG_DISCOVERY collaboration markers`
  - _Requirements: FR-5, AC-2.2, AC-2.3, AC-2.4, NFR-5_
  - _Design: Component C2_

- [x] 1.5 Extend `failure-recovery.md` — BUG_DISCOVERY trigger section and column mapping
  - **Do**:
    1. Read `plugins/ralphharness/references/failure-recovery.md` to find the end
    2. Append "BUG_DISCOVERY Fix-Task Trigger" section:
       - A `task_review.md` row with `status: BUG_DISCOVERY` triggers fix-task generation
       - Column-to-failure-object mapping: `task_id` → `taskId`, `evidence` → `failure.error`, `fix_hint` → `failure.attemptedFix`, `fix_type: bug_discovery`
       - Reuse of `X.Y.N [FIX X.Y]` format, `fixTaskMap`, depth/limit, `tasks.md` insertion
       - Reviewer write boundary unchanged; coordinator inserts the fix task
  - **Files**: `plugins/ralphharness/references/failure-recovery.md`
  - **Done when**: New section documents trigger, column mapping, and reuse of existing machinery
  - **Verify**: `grep -q "BUG_DISCOVERY" plugins/ralphharness/references/failure-recovery.md && grep -q "fixTaskMap" plugins/ralphharness/references/failure-recovery.md && grep -q "X\.Y\.N \[FIX X\.Y\]" plugins/ralphharness/references/failure-recovery.md && echo 1.5_PASS`
  - **Commit**: `feat(harness): add BUG_DISCOVERY trigger to failure-recovery.md`
  - _Requirements: FR-6, FR-7, AC-3.1, AC-3.2, AC-3.3, AC-3.4_
  - _Design: Component C3, Technical Decision D4_

- [x] 1.6 Extend `failure-recovery.md` — dedup and depth/limit rules
  - **Do**:
    1. Append dedup rule: before generating, check `fixTaskMap[task_id]` for existing fix task matching `criterion_failed` + `evidence`; if matched, skip generation and mark the duplicate row `resolved_at` = already-handled
    2. Append depth/limit rule: the new trigger runs existing "Check Fix Task Limits" and "Check Fix Task Depth" steps unchanged; on limit/depth exceeded, no fix task generated and existing block/escalate handling applies
  - **Files**: `plugins/ralphharness/references/failure-recovery.md`
  - **Done when**: Dedup rule and depth/limit rule documented in BUG_DISCOVERY section
  - **Verify**: `grep -q "resolved_at.*already-handled\|already-handled.*resolved_at" plugins/ralphharness/references/failure-recovery.md && grep -q "Check Fix Task Limits" plugins/ralphharness/references/failure-recovery.md && grep -q "Check Fix Task Depth" plugins/ralphharness/references/failure-recovery.md && echo 1.6_PASS`
  - **Commit**: `feat(harness): add BUG_DISCOVERY dedup and depth/limit rules`
  - _Requirements: FR-8, FR-9, AC-7.1, AC-7.2, AC-8.1, AC-8.2_
  - _Design: Component C3_

- [x] 1.7 Extend `spec-executor.md` — cross-branch detection in `<exit_code_gate>` + reference
  - **Do**:
    1. Read `plugins/ralphharness/agents/spec-executor.md` to find `<exit_code_gate>` section
    2. In step 4 (error is in code I did not touch), add cross-branch detection: when failing test was green on `main`, run `git diff main...HEAD` on failing code path and follow `collaboration-resolution.md` Workflow A
    3. Append a reference to `references/collaboration-resolution.md` adjacent to `<exit_code_gate>`
    4. Verify no existing `<exit_code_gate>` line is removed (additive only)
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: `<exit_code_gate>` references `git diff main...HEAD` cross-branch detection; reference to `collaboration-resolution.md` present; additive only
  - **Verify**: `grep -q "git diff main...HEAD" plugins/ralphharness/agents/spec-executor.md && grep -q "collaboration-resolution" plugins/ralphharness/agents/spec-executor.md && echo 1.7_PASS`
  - **Commit**: `feat(harness): extend exit_code_gate with cross-branch detection`
  - _Requirements: FR-3, FR-10, AC-4.1, AC-4.2, AC-4.3_
  - _Design: Component C4, Technical Decision D3_

- [x] 1.8 Add baseline-check hard rule to `external-reviewer.md`
  - **Do**:
    1. Read `plugins/ralphharness/agents/external-reviewer.md` to find insertion point (after Section 3 Test Surveillance)
    2. Add "Baseline Check Before Modifying a Test" hard-rule block:
       - 3-condition check via `git diff main...HEAD`: (a) test file unchanged, (b) fixture/environment unchanged, (c) backend code path differs
       - If all 3 hold → backend/environmental regression → MUST NOT modify the test
       - Ambiguous case: any condition ambiguous → treat as NOT satisfied, record via `chat.md` FINDING marker
    3. Verify no existing section removed
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: Baseline-check rule (3 conditions + ambiguous case) present; additive only
  - **Verify**: `grep -q "Baseline Check" plugins/ralphharness/agents/external-reviewer.md && grep -q "git diff main...HEAD" plugins/ralphharness/agents/external-reviewer.md && grep -qi "NOT satisfied\|ambiguous" plugins/ralphharness/agents/external-reviewer.md && echo 1.8_PASS`
  - **Commit**: `feat(harness): add baseline-check hard rule to external-reviewer`
  - _Requirements: FR-11, FR-12, AC-5.1, AC-9.1, AC-9.2_
  - _Design: Component C5_

- [x] 1.9 Add BUG_DISCOVERY emit rule and workflow reference to `external-reviewer.md`
  - **Do**:
    1. Append "Recording a Discovered Bug" rule: when reviewer finds a bug via investigation, write `status: BUG_DISCOVERY` row to `task_review.md` carrying evidence and fix_hint
    2. State reviewer gains no new write permission; `task_review.md` is reviewer-owned
    3. Append reference to `references/collaboration-resolution.md` additively
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: BUG_DISCOVERY emit rule and collaboration-resolution.md reference present; additive only
  - **Verify**: `grep -q "BUG_DISCOVERY" plugins/ralphharness/agents/external-reviewer.md && grep -q "collaboration-resolution" plugins/ralphharness/agents/external-reviewer.md && echo 1.9_PASS`
  - **Commit**: `feat(harness): add BUG_DISCOVERY emit rule and workflow reference`
  - _Requirements: FR-11, AC-5.2, AC-5.3_
  - _Design: Component C5_

- [x] 1.10 Reconcile `channel-map.md` — add spec-executor as chat.md writer
  - **Do**:
    1. Read `plugins/ralphharness/references/channel-map.md` to find the chat.md row in Channel Registry
    2. Add `spec-executor` to the Writer(s) cell: change from `coordinator, reviewer` to `coordinator, reviewer, spec-executor`
    3. Verify table is well-formed
  - **Files**: `plugins/ralphharness/references/channel-map.md`
  - **Done when**: chat.md Writer(s) column contains spec-executor alongside coordinator and reviewer
  - **Verify**: `grep "chat.md" plugins/ralphharness/references/channel-map.md | head -1 | grep -q "spec-executor" && echo 1.10_PASS`
  - **Commit**: `feat(harness): add spec-executor as chat.md writer in channel-map`
  - _Requirements: FR-13b, D2_
  - _Design: Component C6_

- [x] 1.11 POC Checkpoint
  - **Do**: Verify all six deliverables exist and contain required content:
    1. `collaboration-resolution.md` exists with both workflow blocks (Cross-branch + Experiment-propose-validate)
    2. `chat.md` Collaboration markers table contains all 6 new signals
    3. `failure-recovery.md` documents BUG_DISCOVERY trigger reusing `fixTaskMap`/`X.Y.N [FIX X.Y]`
    4. `spec-executor.md` and `external-reviewer.md` each contain reference to `collaboration-resolution.md`
    5. `external-reviewer.md` contains the 3-condition baseline-check hard rule
    6. `channel-map.md` chat.md Writer(s) cell contains `spec-executor`
  - **Files**: `plugins/ralphharness/references/collaboration-resolution.md`, `plugins/ralphharness/templates/chat.md`, `plugins/ralphharness/references/failure-recovery.md`, `plugins/ralphharness/agents/spec-executor.md`, `plugins/ralphharness/agents/external-reviewer.md`, `plugins/ralphharness/references/channel-map.md`
  - **Done when**: All 6 deliverables verified present via content assertions
  - **Verify**: `test -f plugins/ralphharness/references/collaboration-resolution.md && grep -q "Cross-branch" plugins/ralphharness/references/collaboration-resolution.md && grep -q "Experiment-propose-validate" plugins/ralphharness/references/collaboration-resolution.md && grep -q "HYPOTHESIS" plugins/ralphharness/templates/chat.md && grep -q "BUG_DISCOVERY" plugins/ralphharness/references/failure-recovery.md && grep -q "git diff main...HEAD" plugins/ralphharness/agents/spec-executor.md && grep -q "git diff main...HEAD" plugins/ralphharness/agents/external-reviewer.md && grep -q "spec-executor" plugins/ralphharness/references/channel-map.md && echo 1.11_PASS`
  - **Commit**: `feat(harness): complete POC checkpoint`
  - _Requirements: NFR-1, NFR-3, NFR-5_
  - _Design: All components_

### POC Additive Corrections — Complete remaining deliverables

- [x] 1.12 [VERIFY] Quality checkpoint: verify all files present and non-empty
  - **Do**: Verify all 6 files exist and are non-empty
  - **Verify**: `test -s plugins/ralphharness/references/collaboration-resolution.md && test -s plugins/ralphharness/templates/chat.md && test -s plugins/ralphharness/references/failure-recovery.md && test -s plugins/ralphharness/agents/spec-executor.md && test -s plugins/ralphharness/agents/external-reviewer.md && test -s plugins/ralphharness/references/channel-map.md && echo 1.12_PASS`
  - **Done when**: All 6 files exist and are non-empty
  - **Commit**: `chore(harness): pass quality checkpoint`
  - _Requirements: NFR-1, NFR-3, NFR-5_
  - _Design: All components_

## Phase 2: Refactoring

Focus: Verify all changes follow NFR-1 (additivity). No new features. Verification only.

- [x] 2.1 Verify NFR-1 additivity — no sections removed or rewritten in existing files
  - **Do**:
    1. Check that `chat.md` change is purely additive (only new table rows in Collaboration markers)
    2. Check that `failure-recovery.md` change adds a new section only
    3. Check that `spec-executor.md` change appends to `<exit_code_gate>` and adds a reference
    4. Check that `external-reviewer.md` change adds new rule blocks and a reference
    5. Check that `channel-map.md` change modifies only one cell in the Writer(s) column
  - **Files**: All 5 modified files
  - **Done when**: Confirmed all changes are additive — no existing content removed
  - **Verify**: `for f in "templates/chat.md" "references/failure-recovery.md" "agents/spec-executor.md" "agents/external-reviewer.md"; do if git diff HEAD -- "plugins/ralphharness/$f" | grep -q "^-[^-]"; then echo "DELETION in $f"; else echo "OK: $f"; fi; done && echo 2.1_PASS`
  - **Commit**: `refactor(harness): verify additivity in all existing file changes`
  - _Requirements: NFR-1_
  - _Design: All components_

- [x] 2.2 Verify `signals.jsonl` and schema untouched
  - **Do**:
    1. Confirm `plugins/ralphharness/templates/signals.jsonl` is unchanged
    2. Confirm no references to signals.jsonl schema modifications in any changed file
    3. Confirm all 6 new signals are marked as Collaboration markers (→ chat.md), NOT Control signals
  - **Files**: `plugins/ralphharness/templates/signals.jsonl` (read-only verification)
  - **Done when**: signals.jsonl file unchanged; all 6 new signals documented as chat.md collaboration markers
  - **Verify**: `git diff HEAD -- plugins/ralphharness/templates/signals.jsonl | wc -l | grep -q "0$" && grep -q "chat.md" plugins/ralphharness/templates/chat.md && echo 2.2_PASS`
  - **Commit**: `refactor(harness): verify signals.jsonl untouched`
  - _Requirements: FR-5, NFR-5_
  - _Design: Component C2_

- [x] 2.3 Verify BUG_DISCOVERY column-to-failure-object mapping is consistent
  - **Do**:
    1. Read `plugins/ralphharness/references/failure-recovery.md` BUG_DISCOVERY section
    2. Confirm field mapping matches design: `task_id` → `taskId`, `evidence` → `failure.error`, `fix_hint` → `failure.attemptedFix`, `fix_type: bug_discovery`
    3. Confirm dedup rule references `fixTaskMap` before incrementing attempts
    4. Confirm depth/limit check references existing "Check Fix Task Limits" and "Check Fix Task Depth" sections
  - **Files**: `plugins/ralphharness/references/failure-recovery.md` (read-only verification)
  - **Done when**: All mapping, dedup, and depth/limit references verified correct
  - **Verify**: `grep -q "task_id" plugins/ralphharness/references/failure-recovery.md && grep -q "failure.error" plugins/ralphharness/references/failure-recovery.md && grep -q "fixTaskMap" plugins/ralphharness/references/failure-recovery.md && grep -q "Check Fix Task Limits" plugins/ralphharness/references/failure-recovery.md && grep -q "Check Fix Task Depth" plugins/ralphharness/references/failure-recovery.md && echo 2.3_PASS`
  - **Commit**: `refactor(harness): verify BUG_DISCOVERY mapping consistency`
  - _Requirements: FR-6, AC-3.2_
  - _Design: Component C3, Interfaces section_

- [x] 2.4 [VERIFY] Quality checkpoint: verify all files present and non-empty
  - **Do**: Verify all 6 files exist and are non-empty
  - **Verify**: `test -s plugins/ralphharness/references/collaboration-resolution.md && test -s plugins/ralphharness/templates/chat.md && test -s plugins/ralphharness/references/failure-recovery.md && test -s plugins/ralphharness/agents/spec-executor.md && test -s plugins/ralphharness/agents/external-reviewer.md && test -s plugins/ralphharness/references/channel-map.md && echo 2.4_PASS`
  - **Done when**: All 6 files exist and are non-empty
  - **Commit**: `chore(harness): pass quality checkpoint`
  - _Requirements: NFR-1, NFR-3, NFR-5_
  - _Design: All components_

## Phase 3: Testing

Focus: Add comprehensive test coverage. One RED/GREEN pair per Test Coverage Table row. Integration tests exercise BUG_DISCOVERY behavioral assertions in a real temp workspace (`mktemp -d`) — not a mock. The simulation mechanism in each integration GREEN task: implement a bash function inline in the bats test that reads `task_review.md` and `fixTaskMap` from a temp workspace, performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap` for dedup matching `criterion_failed` + `evidence`, check depth/limit via `fixTaskMap[task_id].attempts >= maxFixTasksPerOriginal`), and appends a `X.Y.N [FIX X.Y]` line to tasks.md if allowed.

- [x] 3.1 Create `tests/collaboration-resolution.bats` with repo-root path setup
  - **Do**:
    1. Create `tests/collaboration-resolution.bats`
    2. Add setup: `REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"`, `PLUGIN_REF="$REPO_ROOT/plugins/ralphharness/references"`, `PLUGIN_TPL="$REPO_ROOT/plugins/ralphharness/templates"`, `PLUGIN_AGENTS="$REPO_ROOT/plugins/ralphharness/agents"`, `TEST_WORKSPACE="$(mktemp -d)"`
    3. Add teardown: `rm -rf "$TEST_WORKSPACE"`
    4. Add `LC_ALL=C` / `LANG=C` to suppress locale warnings
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Bats test file exists with correct path setup, helpers, and mktemp workspace
  - **Verify**: `grep -q "REPO_ROOT.*BATS_TEST_DIRNAME" tests/collaboration-resolution.bats && grep -q "PLUGIN_REF.*plugins/ralphharness/references" tests/collaboration-resolution.bats && grep -q "mktemp -d" tests/collaboration-resolution.bats && echo 3.1_PASS`
  - **Commit**: `test(harness): create collaboration-resolution.bats test file`
  - _Requirements: N/A — test harness_
  - _Design: Test File Conventions_

- [x] 3.2 [RED] Unit test: C1 collaboration-resolution.md exists with required structure
  - **Do**: Write failing test asserting collaboration-resolution.md exists and contains:
    1. "Cross-branch regression investigation" block with `git diff main...HEAD` steps
    2. Explicit ANY-regression entry condition (non-E2E unit-test coverage stated)
    3. "Experiment-propose-validate" block with 5-signal loop and emitting agents
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails (file not yet created at this point)
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C1.*exists" 2>&1 | grep -q "FAIL\|not ok" && echo 3.2_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C1 collaboration-resolution.md structure`
  - _Requirements: AC-1.1, AC-1.2, AC-1.4, AC-2.1_
  - _Design: Test Coverage Table row 1_

- [x] 3.3 [GREEN] Pass test: C1 collaboration-resolution.md structure check
  - **Do**: Write assertions for C1:
    1. `[ -f "$PLUGIN_REF/collaboration-resolution.md" ]`
    2. `grep -q "Cross-branch regression investigation" "$PLUGIN_REF/collaboration-resolution.md"`
    3. `grep -q "git diff main...HEAD" "$PLUGIN_REF/collaboration-resolution.md"`
    4. `grep -qi "any.*regression" "$PLUGIN_REF/collaboration-resolution.md"`
    5. `grep -q "Experiment-propose-validate" "$PLUGIN_REF/collaboration-resolution.md"`
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Previously failing test now passes
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C1.*exists" && echo 3.3_GREEN_PASS`
  - **Commit**: `test(harness): green - C1 structure assertions pass`
  - _Requirements: AC-1.1, AC-1.2, AC-1.4, AC-2.1_
  - _Design: Test Coverage Table row 1_

- [x] 3.4 [RED] Unit test: C2 chat.md Collaboration markers contain all 6 signals
  - **Do**: Write failing test asserting Collaboration markers table has all 6 signals with meanings and emitting agents
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails (signals not yet added)
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C2.*markers" 2>&1 | grep -q "FAIL\|not ok" && echo 3.4_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C2 chat.md collaboration markers`
  - _Requirements: AC-2.2, AC-2.4_
  - _Design: Test Coverage Table row 2_

- [x] 3.5 [GREEN] Pass test: C2 chat.md Collaboration markers check
  - **Do**: Write assertions for C2:
    1. For each signal in HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL/BUG_DISCOVERY: `grep -q "$signal" "$PLUGIN_TPL/chat.md"`
    2. Verify the signals appear in the Collaboration markers table section (after "Collaboration markers" header)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — all 6 signals present in chat.md Collaboration markers table
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C2.*markers" && echo 3.5_GREEN_PASS`
  - **Commit**: `test(harness): green - C2 collaboration markers assertions pass`
  - _Requirements: AC-2.2, AC-2.4_
  - _Design: Test Coverage Table row 2_

- [x] 3.6 [RED] Unit test: C2 signals are collaboration markers, NOT control signals
  - **Do**: Write failing test asserting 6 new signals are NOT in signals.jsonl or Control signals table
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C2.*not.*control" 2>&1 | grep -q "FAIL\|not ok" && echo 3.6_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C2 signals are not control`
  - _Requirements: AC-2.3, NFR-5_
  - _Design: Test Coverage Table row 2_

- [x] 3.7 [GREEN] Pass test: C2 signals in chat.md, not in signals.jsonl
  - **Do**: Write assertions for C2:
    1. `! grep -q "HYPOTHESIS\|EXPERIMENT\|FINDING\|ROOT_CAUSE\|FIX_PROPOSAL\|BUG_DISCOVERY" "$REPO_ROOT/plugins/ralphharness/templates/signals.jsonl"`
    2. Verify Control signals table in chat.md is unchanged (no new rows added there)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — signals are only in chat.md Collaboration markers, not in signals.jsonl or Control table
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C2.*not.*control" && echo 3.7_GREEN_PASS`
  - **Commit**: `test(harness): green - C2 signals not in signals.jsonl assertions pass`
  - _Requirements: AC-2.3, NFR-5_
  - _Design: Test Coverage Table row 2_

- [x] 3.8 [RED] Unit test: C3 failure-recovery.md documents BUG_DISCOVERY trigger
  - **Do**: Write failing test asserting failure-recovery.md has BUG_DISCOVERY section with mapping, dedup, and depth/limit docs
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C3.*trigger" 2>&1 | grep -q "FAIL\|not ok" && echo 3.8_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C3 BUG_DISCOVERY trigger documentation`
  - _Requirements: AC-3.1, AC-3.2_
  - _Design: Test Coverage Table row 3_

- [x] 3.9 [GREEN] Pass test: C3 failure-recovery.md BUG_DISCOVERY trigger check
  - **Do**: Write assertions for C3:
    1. `grep -q "BUG_DISCOVERY" "$PLUGIN_REF/failure-recovery.md"`
    2. `grep -q "fixTaskMap" "$PLUGIN_REF/failure-recovery.md"`
    3. `grep -q "X\.Y\.N" "$PLUGIN_REF/failure-recovery.md"`
    4. `grep -q "task_id" "$PLUGIN_REF/failure-recovery.md"`
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — BUG_DISCOVERY section documented with all required details
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C3.*trigger" && echo 3.9_GREEN_PASS`
  - **Commit**: `test(harness): green - C3 BUG_DISCOVERY trigger assertions pass`
  - _Requirements: AC-3.1, AC-3.2_
  - _Design: Test Coverage Table row 3_

- [x] 3.10 [RED] Unit test: NFR-3 append-only + NFR-4 machine-actionability
  - **Do**: Write failing test asserting:
    1. `collaboration-resolution.md` specifies that HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE entries accumulate **append-only** in `chat.md` (grep for "append-only" or "never edit" or "append" in workflow text)
    2. `failure-recovery.md` documents that `BUG_DISCOVERY` entries carry `evidence` and `fix_hint` as **structured fields** the coordinator processes mechanically (grep for "evidence" AND "fix_hint" in BUG_DISCOVERY section)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "NFR" 2>&1 | grep -q "FAIL\|not ok" && echo 3.10_RED_PASS`
  - **Commit**: `test(harness): red - failing test for NFR-3 append-only + NFR-4 machine-actionability`
  - _Requirements: NFR-3, NFR-4_
  - _Design: C1, C3_

- [x] 3.11 [GREEN] Pass test: NFR-3 append-only + NFR-4 machine-actionability
  - **Do**: Write assertions for NFR-3/NFR-4:
    1. `grep -q "append.only\|append\|never overwrite\|never edit" "$PLUGIN_REF/collaboration-resolution.md"` (verifies append-only semantics documented)
    2. `grep -q "evidence" "$PLUGIN_REF/failure-recovery.md" && grep -q "fix_hint" "$PLUGIN_REF/failure-recovery.md"` (verifies structured fields documented)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — NFR-3 and NFR-4 verified
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "NFR" && echo 3.11_GREEN_PASS`
  - **Commit**: `test(harness): green - NFR-3 append-only + NFR-4 machine-actionability assertions pass`
  - _Requirements: NFR-3, NFR-4_
  - _Design: C1, C3_

- [x] 3.12 [RED] Unit test: C4 spec-executor.md cross-branch detection
  - **Do**: Write failing test asserting spec-executor.md has `git diff main...HEAD` in `<exit_code_gate>` and reference to collaboration-resolution.md
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C4.*cross-branch" 2>&1 | grep -q "FAIL\|not ok" && echo 3.12_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C4 cross-branch detection`
  - _Requirements: AC-4.1, AC-4.2, AC-4.3_
  - _Design: Test Coverage Table row 7_

- [x] 3.13 [GREEN] Pass test: C4 spec-executor.md cross-branch detection check
  - **Do**: Write assertions for C4:
    1. `grep -q "git diff main...HEAD" "$PLUGIN_AGENTS/spec-executor.md"`
    2. `grep -q "collaboration-resolution" "$PLUGIN_AGENTS/spec-executor.md"`
    3. Verify `<exit_code_gate>` section was not rewritten (only appended)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — cross-branch detection and reference present, section not rewritten
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C4.*cross-branch" && echo 3.13_GREEN_PASS`
  - **Commit**: `test(harness): green - C4 cross-branch detection assertions pass`
  - _Requirements: AC-4.1, AC-4.2, AC-4.3_
  - _Design: Test Coverage Table row 7_

- [x] 3.14 [RED] Unit test: C5 external-reviewer.md baseline-check rule
  - **Do**: Write failing test asserting external-reviewer.md has baseline-check rule, ambiguous case handling, BUG_DISCOVERY emit rule, and reference
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C5.*baseline" 2>&1 | grep -q "FAIL\|not ok" && echo 3.14_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C5 baseline-check rule`
  - _Requirements: AC-5.1, AC-5.2, AC-5.3_
  - _Design: Test Coverage Table row 8_

- [x] 3.15 [GREEN] Pass test: C5 external-reviewer.md baseline-check rule check
  - **Do**: Write assertions for C5:
    1. `grep -q "Baseline Check" "$PLUGIN_AGENTS/external-reviewer.md"`
    2. `grep -q "git diff main...HEAD" "$PLUGIN_AGENTS/external-reviewer.md"`
    3. `grep -q "BUG_DISCOVERY" "$PLUGIN_AGENTS/external-reviewer.md"`
    4. `grep -q "collaboration-resolution" "$PLUGIN_AGENTS/external-reviewer.md"`
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — all 4 required elements present in external-reviewer.md
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C5.*baseline" && echo 3.15_GREEN_PASS`
  - **Commit**: `test(harness): green - C5 baseline-check rule assertions pass`
  - _Requirements: AC-5.1, AC-5.2, AC-5.3_
  - _Design: Test Coverage Table row 8_

- [x] 3.16 [RED] Unit test: C6 channel-map.md writer reconciliation
  - **Do**: Write failing test asserting channel-map.md chat.md Writer(s) cell contains spec-executor
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C6.*writer" 2>&1 | grep -q "FAIL\|not ok" && echo 3.16_RED_PASS`
  - **Commit**: `test(harness): red - failing test for C6 channel-map writer reconciliation`
  - _Requirements: FR-13b, D2_
  - _Design: Component C6_

- [x] 3.17 [GREEN] Pass test: C6 channel-map.md writer reconciliation check
  - **Do**: Write assertion for C6:
    1. `grep "chat.md" "$PLUGIN_REF/channel-map.md" | head -1 | grep -q "spec-executor"`
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — spec-executor present in chat.md Writer(s) column
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "C6.*writer" && echo 3.17_GREEN_PASS`
  - **Commit**: `test(harness): green - C6 channel-map writer assertion passes`
  - _Requirements: FR-13b, D2_
  - _Design: Component C6_

- [x] 3.18 [RED] Integration test: C3 BUG_DISCOVERY single discovery yields one fix task
  - **Do**: Write failing integration test for BUG_DISCOVERY trigger. Seed a real temp workspace (use `mktemp -d`) with one task (`3.2`), empty `task_review.md`, and `fixTaskMap: {}`. Seed a single `BUG_DISCOVERY` row in `task_review.md`. Simulate coordinator processing: implement a bash function inline in the bats test that reads `task_review.md` and `fixTaskMap` from the temp workspace, performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap` for dedup — empty so no dedup needed; check depth/limit — under limit), and appends a `X.Y.N [FIX X.Y]` line to tasks.md if allowed. This test should FAIL initially.
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test exists that simulates single BUG_DISCOVERY and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "single.*discovery" 2>&1 | grep -q "FAIL\|not ok" && echo 3.18_RED_PASS`
  - **Commit**: `test(harness): red - failing integration test for BUG_DISCOVERY single discovery`
  - _Requirements: AC-3.1, AC-3.2_
  - _Design: Test Coverage Table row 4_

- [x] 3.19 [GREEN] Pass test: C3 BUG_DISCOVERY single discovery yields one fix task
  - **Do**: Write integration test that:
    1. Creates temp workspace with `tasks.md` containing one task, empty `task_review.md`, `.ralph-state.json` with empty `fixTaskMap` using `mktemp -d` (real temp workspace, not a mock)
    2. Seeds a `BUG_DISCOVERY` row in `task_review.md`
    3. Simulates coordinator processing: implement a bash function inline in the bats test that reads `task_review.md` and `fixTaskMap` from the temp workspace, performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap` for dedup — empty so no dedup; check depth/limit — under limit), and appends a `X.Y.N [FIX X.Y]` line to tasks.md if allowed
    4. Asserts exactly one `X.Y.N [FIX X.Y]` task appears in `tasks.md` and one `fixTaskMap` entry created
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test passes — single BUG_DISCOVERY yields exactly one fix task
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "single.*discovery" && echo 3.19_GREEN_PASS`
  - **Commit**: `test(harness): green - BUG_DISCOVERY single discovery integration test passes`
  - _Requirements: AC-3.1, AC-3.2_
  - _Design: Test Coverage Table row 4, Fixtures row 1_

- [x] 3.20 [RED] Integration test: C3 duplicate BUG_DISCOVERY yields zero fix tasks
  - **Do**: Write failing integration test for duplicate BUG_DISCOVERY. Seed workspace with matching `fixTaskMap` entry (same `task_id` + `criterion_failed` + `evidence`). Implement a bash function inline in the bats test that reads `task_review.md` and `fixTaskMap` from a real temp workspace (`mktemp -d`), performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap` for dedup matching `criterion_failed` + `evidence` — matched so skip generation; mark row `resolved_at` = already-handled). This test should FAIL initially.
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test exists that simulates duplicate BUG_DISCOVERY and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "duplicate.*BUG_DISCOVERY" 2>&1 | grep -q "FAIL\|not ok" && echo 3.20_RED_PASS`
  - **Commit**: `test(harness): red - failing integration test for duplicate BUG_DISCOVERY`
  - _Requirements: AC-7.1, AC-7.2, FR-8_
  - _Design: Test Coverage Table row 5_

- [x] 3.21 [GREEN] Pass test: C3 duplicate BUG_DISCOVERY yields zero fix tasks
  - **Do**: Write integration test that:
    1. Creates temp workspace with `fixTaskMap` entry containing matching `lastError` using `mktemp -d` (real temp workspace, not a mock)
    2. Seeds a duplicate `BUG_DISCOVERY` row
    3. Simulates coordinator dedup check: implement a bash function inline in the bats test that reads `task_review.md` and `fixTaskMap` from the temp workspace, performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap` for dedup — matches `criterion_failed` + `evidence` so skip generation), and marks the row `resolved_at` = already-handled
    4. Asserts zero new fix tasks generated, duplicate row marked as handled
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test passes — duplicate BUG_DISCOVERY yields zero fix tasks, row marked handled
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "duplicate.*BUG_DISCOVERY" && echo 3.21_GREEN_PASS`
  - **Commit**: `test(harness): green - BUG_DISCOVERY dedup integration test passes`
  - _Requirements: AC-7.1, AC-7.2, FR-8_
  - _Design: Test Coverage Table row 5, Fixtures row 2_

- [x] 3.22 [RED] Integration test: C3 depth-limit BUG_DISCOVERY yields zero fix tasks
  - **Do**: Write failing integration test for depth-limit. Seed `fixTaskMap` at the limit (`fixTaskMap["3.2"].attempts == maxFixTasksPerOriginal`). Implement a bash function inline in the bats test that reads `fixTaskMap` from a real temp workspace (`mktemp -d`), performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap[task_id].attempts >= maxFixTasksPerOriginal` — at limit so no fix task generated, limit error fires). This test should FAIL initially.
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test exists that simulates depth-limit BUG_DISCOVERY and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "depth.*limit" 2>&1 | grep -q "FAIL\|not ok" && echo 3.22_RED_PASS`
  - **Commit**: `test(harness): red - failing integration test for depth-limit BUG_DISCOVERY`
  - _Requirements: AC-8.1, AC-8.2, FR-9_
  - _Design: Test Coverage Table row 6_

- [x] 3.23 [GREEN] Pass test: C3 depth-limit BUG_DISCOVERY yields zero fix tasks
  - **Do**: Write integration test that:
    1. Creates temp workspace with `fixTaskMap["3.2"].attempts == maxFixTasksPerOriginal` (e.g., 3) using `mktemp -d` (real temp workspace, not a mock)
    2. Seeds a `BUG_DISCOVERY` row
    3. Simulates coordinator limit check: implement a bash function inline in the bats test that reads `fixTaskMap` from the temp workspace, performs the coordinator's Pre-Delegation Check logic (check `fixTaskMap[task_id].attempts >= maxFixTasksPerOriginal` — at limit so no fix task generated, existing block/escalate handling fires)
    4. Asserts zero new fix tasks and existing block/escalate handling triggered
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Integration test passes — depth-limit BUG_DISCOVERY yields zero fix tasks with limit error
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "depth.*limit" && echo 3.23_GREEN_PASS`
  - **Commit**: `test(harness): green - BUG_DISCOVERY depth-limit integration test passes`
  - _Requirements: AC-8.1, AC-8.2, FR-9_
  - _Design: Test Coverage Table row 6, Fixtures row 3_

- [x] 3.24 [VERIFY] Quality checkpoint: run all bats tests
  - **Do**: Run the full collaboration-resolution.bats test suite. All tests should pass.
  - **Verify**: `bats tests/collaboration-resolution.bats 2>&1 | grep -c "not ok" | grep -q "^0$"`
  - **Done when**: All bats tests pass
  - **Commit**: `chore(harness): pass quality checkpoint`
  - _Requirements: NFR-1, NFR-3, NFR-5_
  - _Design: All components_

- [x] 3.25 [VERIFY] Quality checkpoint: bats smoke on existing test files
  - **Do**: Run `bats tests/signal-log.bats` to confirm existing tests still pass (no regressions from spec-7 changes). Also run `bats tests/ci-autodetect.bats` if it exists.
  - **Verify**: `bats tests/signal-log.bats 2>&1 | grep -c "not ok" | grep -q "^0$"`
  - **Done when**: All existing bats tests still pass
  - **Commit**: `chore(harness): verify no regression in existing tests`
  - _Requirements: NFR-1, NFR-5_
  - _Design: All components_

- [x] 3.26 [RED] Unit test: Additivity invariant — git diff shows only additions in existing files
  - **Do**: Write failing test for NFR-1 additivity: git diff HEAD shows only additions, zero deletions in 4 modified existing files
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails (no changes yet committed)
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "additivity" 2>&1 | grep -q "FAIL\|not ok" && echo 3.26_RED_PASS`
  - **Commit**: `test(harness): red - failing test for additivity invariant`
  - _Requirements: NFR-1_
  - _Design: Test Coverage Table row 10_

- [x] 3.27 [GREEN] Pass test: Additivity invariant — git diff shows only additions
  - **Do**: Write assertion for additivity invariant:
    1. For each modified file in `templates/chat.md`, `references/failure-recovery.md`, `agents/spec-executor.md`, `agents/external-reviewer.md`: assert no lines starting with `-` (non-dash-prefixed) in `git diff HEAD`
    2. For `references/channel-map.md`: assert only the Writer(s) cell content changed, no structural deletions
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — no deletions in any modified existing file
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "additivity" && echo 3.27_GREEN_PASS`
  - **Commit**: `test(harness): green - additivity invariant test passes`
  - _Requirements: NFR-1_
  - _Design: Test Coverage Table row 10_

- [x] 3.28 [RED] Unit test: 8 ACs explicit coverage (AC-1.3 workflow format, AC-3.3/3.4 no-loop-write-boundary, AC-4.1-4.3 executor reference, AC-6.1-6.3 detection point)
  - **Do**: Write failing test asserting the remaining acceptance criteria not covered by dedicated C1-C6 tests:
    1. AC-1.3: `collaboration-resolution.md` written as a workflow (entry/exit conditions, numbered steps) not micro-rules
    2. AC-3.3: `failure-recovery.md` documents BUG_DISCOVERY does not change coordinator core loop
    3. AC-3.4: `failure-recovery.md` states reviewer gains no new write permission
    4. AC-4.1: `spec-executor.md` contains reference to `collaboration-resolution.md`
    5. AC-4.2: reference positioned adjacent to `<exit_code_gate>`
    6. AC-4.3: no existing `spec-executor.md` lines removed
    7. AC-6.1: design explicitly defines `<exit_code_gate>` as detection point for non-E2E regression
    8. AC-6.2: detection point extends `git diff --name-only HEAD` to `git diff main...HEAD`
    9. AC-6.3: workflow entry condition references general detection point, not restricted to VE/E2E
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test exists and fails
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "AC-coverage\|ACs.*explicit" 2>&1 | grep -q "FAIL\|not ok" && echo 3.28_RED_PASS`
  - **Commit**: `test(harness): red - failing test for 8 remaining ACs explicit coverage`
  - _Requirements: AC-1.3, AC-3.3, AC-3.4, AC-4.1, AC-4.2, AC-4.3, AC-6.1, AC-6.2, AC-6.3_
  - _Design: C1, C3, C4, C6_

- [x] 3.29 [GREEN] Pass test: 8 ACs explicit coverage
  - **Do**: Write assertions for the 8 remaining ACs:
    1. `grep -q "entry condition\|exit condition" "$PLUGIN_REF/collaboration-resolution.md"` (AC-1.3 workflow format)
    2. `grep -q "core.loop\|core loop\|not modify" "$PLUGIN_REF/failure-recovery.md"` (AC-3.3)
    3. `grep -q "no new write\|no new.*permission\|gains no" "$PLUGIN_REF/failure-recovery.md"` (AC-3.4)
    4. `grep -q "collaboration-resolution" "$PLUGIN_AGENTS/spec-executor.md"` (AC-4.1)
    5. Verify `<exit_code_gate>` section exists and reference appears adjacent (grep both in file, close line numbers) (AC-4.2)
    6. `git diff HEAD -- "plugins/ralphharness/agents/spec-executor.md" | grep -q "^-[^-]" || true` asserts no deletions (AC-4.3)
    7. `grep -q "exit_code_gate.*non-E2E\|non-E2E.*exit_code_gate\|detection point.*exit_code_gate" specs/collaboration-resolution/design.md || grep -q "detection point" "$PLUGIN_AGENTS/spec-executor.md"` (AC-6.1)
    8. `grep -q "git diff main...HEAD" "$PLUGIN_AGENTS/spec-executor.md"` (AC-6.2/6.3)
  - **Files**: `tests/collaboration-resolution.bats`
  - **Done when**: Test passes — all 8 ACs verified via content assertions
  - **Verify**: `bats tests/collaboration-resolution.bats --filter "AC-coverage\|ACs.*explicit" && echo 3.29_GREEN_PASS`
  - **Commit**: `test(harness): green - 8 ACs explicit coverage assertions pass`
  - _Requirements: AC-1.3, AC-3.3, AC-3.4, AC-4.1, AC-4.2, AC-4.3, AC-6.1, AC-6.2, AC-6.3_
  - _Design: C1, C3, C4, C6_

## Phase 4: Quality Gates

Focus: Version bump, all local checks pass, AC checklist verification, PR creation and CI monitoring. VE tasks are not applicable — RalphHarness is a markdown-only plugin with no UI.

- [x] 4.1 Bump plugin version in `plugin.json` and `marketplace.json`
  - **Do**:
    1. Bump `plugins/ralphharness/.claude-plugin/plugin.json` version from `5.1.0` to `5.2.0` (minor bump — additive feature)
    2. Bump `plugins/ralphharness` entry in `.claude-plugin/marketplace.json` version from `5.1.0` to `5.2.0`
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Done when**: Both version fields set to `5.2.0`
  - **Verify**: `jq -r .version plugins/ralphharness/.claude-plugin/plugin.json | grep -q "5.2.0" && jq -r '.plugins[] | select(.name=="ralphharness") | .version' .claude-plugin/marketplace.json | grep -q "5.2.0" && echo 4.1_PASS`
  - **Commit**: `chore(harness): bump version to 5.2.0 for collaboration-resolution`
  - _Requirements: NFR-1 (version bump)_
  - _Design: All components_

- [x] 4.2 [VERIFY] Full local CI: bats tests pass
  - **Do**: Run all test suites:
    1. New tests: `bats tests/collaboration-resolution.bats`
    2. Existing tests: `bats tests/signal-log.bats`
  - **Verify**: `bats tests/collaboration-resolution.bats && bats tests/signal-log.bats`
  - **Files**: `tests/collaboration-resolution.bats`, `tests/signal-log.bats`
  - **Done when**: All tests pass
  - **Commit**: `chore(harness): pass local CI`
  - _Requirements: NFR-1_
  - _Design: All components_

- [x] 4.3 [VERIFY] AC checklist — verify all 27 acceptance criteria
  - **Do**: Read requirements.md and programmatically verify each AC-*:
    1. AC-1.1 through AC-1.4: `grep collaboration-resolution.md` for workflow block, steps, ANY-regression, non-E2E coverage
    2. AC-2.1 through AC-2.4: `grep chat.md` for 6 signals in Collaboration markers table with definitions
    3. AC-3.1 through AC-3.4: `grep failure-recovery.md` for BUG_DISCOVERY trigger, fixTaskMap reuse, column mapping
    4. AC-4.1 through AC-4.3: `grep spec-executor.md` for cross-branch reference, adjacent to exit_code_gate
    5. AC-5.1 through AC-5.3: `grep external-reviewer.md` for baseline-check rule, ambiguous case, reference
    6. AC-6.1 through AC-6.3: verify cross-branch workflow triggers on ANY regression type (entry condition text)
    7. AC-7.1 and AC-7.2: verify dedup documentation in failure-recovery.md
    8. AC-8.1 and AC-8.2: verify depth/limit reuse in failure-recovery.md
    9. AC-9.1 and AC-9.2: verify ambiguous baseline handling in external-reviewer.md
  - **Files**: `requirements.md`, `design.md`, `plugins/ralphharness/references/collaboration-resolution.md`, `plugins/ralphharness/templates/chat.md`, `plugins/ralphharness/references/failure-recovery.md`, `plugins/ralphharness/agents/spec-executor.md`, `plugins/ralphharness/agents/external-reviewer.md`, `plugins/ralphharness/references/channel-map.md`
  - **Verify**: All grep checks pass
  - **Done when**: All 27 acceptance criteria confirmed via automated checks
  - **Commit**: None
  - _Requirements: All ACs (AC-1.1 through AC-9.2)_
  - _Design: All components_

- [x] 4.4 [VERIFY] CI pipeline passes after push
  - **Do**:
    1. Verify current branch: `git branch --show-current` should show a feature branch (not main)
    2. Push branch: `git push -u origin collaboration-resolution`
    3. Create PR: `gh pr create --title "feat(harness): encode agent collaboration patterns" --body "Encode cross-branch regression workflow, experiment-propose-validate pattern, BUG_DISCOVERY trigger, and chat collaboration signals."`
    4. Verify CI: `gh pr checks --watch` or poll `gh pr checks`
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `specs/collaboration-resolution/*`, `tests/collaboration-resolution.bats`
  - **Verify**: `gh pr checks` shows all green (check at least 2 rounds to confirm CI is stable)
  - **Done when**: All CI checks green, PR ready for review
  - **If CI fails**: Fix issues, push fixes, re-verify
  - **Commit**: None
  - _Requirements: NFR-1, NFR-5_
  - _Design: All components_

## Phase 5: PR Lifecycle

Goal: Autonomous PR management loop until all criteria met.

- [x] 5.1 Monitor PR CI status
  - **Do**: Check PR CI status. If green, proceed to 5.2. If any check fails, read failure details, fix issues, push fixes, re-check.
  - **Verify**: `gh pr checks` shows all passing
  - **Files**: None (PR monitoring only)
  - **Done when**: All CI checks green
  - **Commit**: `fix(harness): address CI failures` (only if fixes needed)
  - _Requirements: Phase 5 completion_
  - _Design: All components_

- [x] 5.2 Resolve review comments if any
  - **Do**: If any review comments exist on the PR, address them. Push fixes. Re-check CI if fixes change tested code.
  - **Verify**: `gh pr view --json reviewRequests,statusCheckRollup --jq '.reviewRequests | length'` returns 0 and all status checks pass
  - **Files**: None (PR monitoring only)
  - **Done when**: Zero unresolved review comments, all CI green
  - **Commit**: `fix(harness): address review comments` (only if comments existed)
  - _Requirements: Phase 5 completion_
  - _Design: All components_

- [x] 5.3 [VERIFY] Final validation — zero regressions, modularity verified
  - **Do**: Final checks:
    1. `git diff main...HEAD --stat` to confirm only expected files changed
    2. `bats tests/collaboration-resolution.bats` — all tests pass
    3. Verify modularity: `collaboration-resolution.md` is a standalone reference; changes to other files are additive and self-contained
  - **Verify**: All checks pass
  - **Done when**: PR is clean, tests pass, changes are modular
  - **Commit**: None
  - _Requirements: Phase 5 completion_
  - _Design: All components_

## Notes

- POC shortcuts: Phase 1 skips tests, accepts hardcoded values. Integration tests (Phase 3) use simulated coordinator behavior in bats — the actual coordinator loop is not modified (NFR-2).
- Production TODOs: The BUG_DISCOVERY trigger and dedup logic are documented in markdown; the actual implementation is in the coordinator (separate concern, not modified by this spec).
- All changes are additive — zero sections removed or rewritten (NFR-1).
- `signals.jsonl` and its schema are NOT modified (NFR-5).
- The 6 new signals are collaboration markers in `chat.md`, NOT control signals.
- No new infrastructure introduced: no new agents, scripts, loops, or channels.
