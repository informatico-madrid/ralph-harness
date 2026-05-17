# Tasks: Context Middleware (Spec 10)

## Phase 1: Make It Work (POC)

Focus: Create middleware scripts, wire hooks, prove condensation works end-to-end. Skip tests. Accept hardcoded values.

- [x] 1.1 [P] Create lib-context.sh with shared helpers
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/lib-context.sh` (parallel to `lib-signals.sh`)
    2. Implement `combined_line_count <spec_path>`: `wc -l chat.md .progress.md`, handle missing files as 0
    3. Implement `transcript_usage_pct <transcript_path>`: tail JSONL, find last assistant `message.usage`, compute `(input + cache_creation + cache_read) / 200000 * 100`, echo integer pct
    4. Implement `spec_dir_writable <spec_path>`: return 0 if writable, 1 if not
    5. Implement `context_window_size`: echo 200000
    6. Implement `write_condensation_metric <spec_path> <mode> <linesBefore> <linesAfter> <tokensPct> <archivePath>`: append JSONL event to `.metrics.jsonl` using fd 201 for `.metrics.lock` (distinct from fd 200 chat-lock and fd 202 signals-lock)
  - **Files**: `plugins/ralphharness/hooks/scripts/lib-context.sh`
  - **Done when**: All 5 functions defined, sourced correctly, fd 201 used for metrics lock
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/lib-context.sh && echo 1.1_PASS`
  - **Commit**: `feat(context): create lib-context.sh helper library`
  - _Requirements: FR-1, FR-14, FR-18, FR-9_
  - _Design: lib-context.sh, fd-201 isolation_

- [ ] 1.2 [P] Extend spec.schema.json with executionPhase and 3 chat pointers
  - **Do**:
    1. Add `"executionPhase"` property under `state.properties`: enum `["poc", "refactor", "test", "quality"]`, optional
    2. Extend `chat` object properties to add `coordinator` and `reviewer` objects (same shape as existing `executor`: `lastReadLine` integer)
  - **Files**: `plugins/ralphharness/schemas/spec.schema.json`
  - **Done when**: `jq .definitions.state.properties.executionPhase` returns the enum; `jq .definitions.state.properties.chat.properties` shows 3 entries (executor, coordinator, reviewer)
  - **Verify**: `jq '.definitions.state.properties.executionPhase.enum' plugins/ralphharness/schemas/spec.schema.json && jq '.definitions.state.properties.chat.properties | keys' plugins/ralphharness/schemas/spec.schema.json`
  - **Commit**: `feat(context): add executionPhase and chat pointer objects to schema`
  - _Requirements: FR-19, AC-4.1, AC-4.2_
  - _Design: spec.schema.json modifications_

- [ ] 1.3 [P] Create condense-context.sh: arg parsing, degradation check, archive, gate
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/condense-context.sh`
    2. Parse args: `<spec_path> --mode <proactive|reactive|emergency>`
    3. Implement degradation check: `spec_dir_writable` → skip + log, exit 0
    4. Gate re-check (proactive mode only): if `combined_line_count <= 2000` → no-op, exit 0
    5. Archive first: concatenate `chat.md` + `.progress.md` with section delimiters into `.archive.<date -u +%Y%m%dT%H%M%SZ>.md`
  - **Files**: `plugins/ralphharness/hooks/scripts/condense-context.sh`
  - **Done when**: Script parses args, degradation check works, gate re-check skips when below threshold, archive written before any mutation
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/condense-context.sh && echo 1.3_PASS`
  - **Commit**: `feat(context): create condense-context.sh arg parsing, degradation, archive`
  - _Requirements: FR-1, FR-3_
  - _Design: Condensation Algorithm steps 1-4_

- [ ] 1.4 [P] Create condense-context.sh: min-pointer prefix condensation under flock
  - **Do**:
    1. Compute min pointer: `jq -r '[.chat.coordinator.lastReadLine // 0, .chat.executor.lastReadLine // 0, .chat.reviewer.lastReadLine // 0] | min'` from `.ralph-state.json`
    2. Under `flock` on `chat.md.lock` (fd 200): split chat.md into condensable prefix (lines 1..minPtr) and protected suffix (minPtr+1..EOF)
    3. From prefix, extract preserved markers: control signals `[HOLD]|[PENDING]|[DEADLOCK]|[URGENT]|[ACK]|[CONTINUE]`, collaboration signals `HYPOTHESIS|ROOT_CAUSE|FIX_PROPOSAL|BUG_DISCOVERY`, pair-debug `PAIR-DEBUG|^Driver:|^Navigator:`
    4. Keep last 15 message blocks from prefix (`## ` header + body)
    5. Build new chat.md = preserved markers + last 15 messages + protected suffix verbatim
  - **Files**: `plugins/ralphharness/hooks/scripts/condense-context.sh`
  - **Done when**: fd 200 flock acquired, min pointer computed, prefix condensation with preserved signals, last 15 messages kept, protected suffix verbatim
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/condense-context.sh && echo 1.4_PASS`
  - **Commit**: `feat(context): condense-context.sh min-pointer prefix condensation under flock`
  - _Requirements: FR-5, FR-7, FR-8_
  - _Design: Condensation Algorithm step 5_

- [ ] 1.5 [P] Create condense-context.sh: pointer atomicity, progress.md, metrics, prune
  - **Do**:
    1. Under same flock: rewrite 3 pointers in `.ralph-state.json` atomically via temp file + `mv`. Compute `removed = oldPrefixLines - newPrefixLines`. Each pointer `p` → `max(0, p - removed)`
    2. Condense `.progress.md`: keep `## Goal` + `## Learnings` sections verbatim, keep last 3 task entries from volatile section. Rewrite via temp file + `mv`.
    3. After flock subshell closes: call `write_condensation_metric` (fd 201 for metrics lock) to append condensation event to `.metrics.jsonl`
    4. Prune archives: `ls -t .archive.*.md | tail -n +4 | xargs rm -f` (keep newest 3)
    5. Emit one-line summary to stdout: `"condensed: chat <N1>-><N2>, progress <N3>-><N4>"`
  - **Files**: `plugins/ralphharness/hooks/scripts/condense-context.sh`
  - **Done when**: Atomic pointer updates, stable/volatile split in progress.md, metrics logged, archive prune to 3
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/condense-context.sh && echo 1.5_PASS`
  - **Commit**: `feat(context): condense-context.sh pointer atomicity, progress.md, metrics, prune`
  - _Requirements: FR-6, FR-7, FR-8, FR-14, FR-15_
  - _Design: Condensation Algorithm steps 5-8_

- [ ] 1.6 [P] Create evict-tool-result.sh with per-kind thresholds
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/evict-tool-result.sh`
    2. Parse args: read stdin, `<spec_path> <tool_kind> [--pair-debug]` where tool_kind in `grep|gitdiff|fileread|lsfind`
    3. Define thresholds: grep=100, gitdiff=200, fileread=500, lsfind=300 lines
    4. If input line count ≤ threshold → pass input through unchanged
    5. If above threshold: create `.tool-results/` dir, write full content to `.tool-results/<kind>-<timestamp>.txt`, emit first 50 lines + summary `"[evicted] <N> lines total, full output: .tool-results/<kind>-<ts>.txt"`
    6. If `--pair-debug` flag → pass through unchanged, never evict
    7. If spec dir not writable → pass through unchanged + degradation note
  - **Files**: `plugins/ralphharness/hooks/scripts/evict-tool-result.sh`
  - **Done when**: 4 per-kind thresholds, pass-through, `.tool-results/` write, preview emit, pair-debug exclusion, read-only degradation
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/evict-tool-result.sh && echo 1.6_PASS`
  - **Commit**: `feat(context): create evict-tool-result.sh`
  - _Requirements: FR-10, FR-11, AC-3.1, AC-3.2, AC-3.3, AC-3.4_
  - _Design: evict-tool-result.sh interface_

- [ ] 1.7 [P] Create precompact-condense.sh and wire PreCompact hook
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/precompact-condense.sh`: resolve active spec via `ralph_resolve_current`, call `condense-context.sh <spec> --mode emergency`
    2. Always exit 0 (never blocks compaction)
    3. Modify `plugins/ralphharness/hooks/hooks.json`: add `PreCompact` hook entry pointing to `precompact-condense.sh` (same structure as existing Stop/SessionStart entries)
  - **Files**: `plugins/ralphharness/hooks/scripts/precompact-condense.sh`, `plugins/ralphharness/hooks/hooks.json`
  - **Done when**: `hooks.json` has `PreCompact` entry with command path to `precompact-condense.sh`; script resolves spec and calls condense `--mode emergency`
  - **Verify**: `jq '.hooks.PreCompact' plugins/ralphharness/hooks/hooks.json && bash -n plugins/ralphharness/hooks/scripts/precompact-condense.sh && echo 1.7_PASS`
  - **Commit**: `feat(context): wire PreCompact hook for emergency condensation`
  - _Requirements: FR-9, AC-2.5_
  - _Design: PreCompact hook_

- [ ] 1.8 [P] Modify stop-watcher.sh: source lib-context.sh, two-gate check, condensation call
  - **Do**:
    1. In the execution-phase block of `stop-watcher.sh` (after HOLD-GATE, before continuation prompt), add:
    2. Source `lib-context.sh`
    3. Gate 1: `combined_line_count "$SPEC_PATH" > 2000` → call `condense-context.sh "$SPEC_PATH" --mode proactive`
    4. Gate 2: `transcript_usage_pct "$TRANSCRIPT_PATH" > 85` → call `condense-context.sh "$SPEC_PATH" --mode reactive`
    5. Wrap all middleware calls in `|| true` so failures never abort the hook
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: Two-gate check fires before continuation prompt; Gate 1 calls `--mode proactive`, Gate 2 calls `--mode reactive`; all calls wrapped in `|| true`
  - **Verify**: `grep -c 'condense-context' plugins/ralphharness/hooks/scripts/stop-watcher.sh && grep -c 'lib-context.sh' plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo 1.8_PASS`
  - **Commit**: `feat(context): add two-gate condensation check to stop-watcher.sh`
  - _Requirements: FR-1, FR-9, AC-2.1, AC-2.3, AC-2.6_
  - _Design: stop-watcher.sh modifications, Two-gate trigger model_

- [ ] 1.9 [P] Modify implement.md: phase-conditional reference loading + eviction prompt-rule
  - **Do**:
    1. Replace the static "Read these references" section (lines 374-389) with a `case` statement keyed off `executionPhase` from `.ralph-state.json`
    2. `executionPhase: poc` → load coordinator-pattern.md + failure-recovery.md
    3. `executionPhase: refactor` → + commit-discipline.md
    4. `executionPhase: test`/`quality` → + commit-discipline.md + verification-layers.md
    5. `phase-rules.md` loaded only for `test`/`quality`
    6. `pair-debug.md` loaded when `chat.md` contains `PAIR-DEBUG` marker
    7. Default (no `executionPhase` field) → load all references (safe fallback)
    8. Document the eviction prompt-rule: oversized tool output → route through `evict-tool-result.sh`
    9. Ensure always-relevant refs (coordinator-pattern.md + failure-recovery.md) loaded in every phase (AC-4.5)
    10. Ensure scoping is implement.md only — no reference file split/rename/move (AC-4.4)
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: `case` statement replaces static reference list; `phase-rules.md` gated to test/quality; `pair-debug.md` gated on `PAIR-DEBUG`; eviction prompt-rule documented; always-relevant refs loaded in all phases
  - **Verify**: `grep -A 20 'case.*executionPhase' plugins/ralphharness/commands/implement.md | head -25 && grep -c 'evict-tool-result' plugins/ralphharness/commands/implement.md && echo 1.9_PASS`
  - **Commit**: `feat(context): phase-conditional reference loading and eviction prompt-rule in implement.md`
  - _Requirements: FR-12, FR-13, FR-17, AC-3.5, AC-4.1, AC-4.2, AC-4.3, AC-4.4, AC-4.5, AC-4.7_
  - _Design: implement.md modifications_

- [ ] 1.12 [P] Create POC fixture: oversized spec with all preserved markers
  - **Do**:
    1. Create temp spec dir with oversized chat.md (1200 lines) + .progress.md (900 lines)
    2. Seed: control signals [HOLD], collaboration signals HYPOTHESIS/BUG_DISCOVERY, pair-debug markers PAIR-DEBUG/Driver:/Navigator:
    3. Seed .ralph-state.json with 3 chat pointers, signals.jsonl, stable/volatile progress.md sections
  - **Files**: Temp fixture created inline in bats/verification step
  - **Done when**: Temp spec dir contains all required fixture data ready for condensation testing
  - **Verify**: `[N/A] fixture only — no script to check`
  - **Commit**: None
  - _Design: Test Coverage Table — fixture for condense-context.sh proactive_

- [ ] 1.13 [VERIFY] POC Checkpoint: end-to-end condensation on oversized fixture
  - **Do**:
    1. Run `condense-context.sh <temp_spec> --mode proactive` against a temp fixture with >2000 combined lines
    2. Verify: archive exists; chat.md condensed below threshold; signals preserved; metrics logged
  - **Done when**: condense-context.sh runs successfully on oversized fixture, archive created, files condensed below threshold
  - **Verify**: `TMP=$(mktemp -d) && cp "$REPO_ROOT/plugins/ralphharness/hooks/scripts/condense-context.sh" "$TMP/" && cp "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-context.sh" "$TMP/" && seq 1 1200 > "$TMP/chat.md" && seq 1 900 > "$TMP/.progress.md" && echo '{"phase":"execution","chat":{"coordinator":{"lastReadLine":500},"executor":{"lastReadLine":1000},"reviewer":{"lastReadLine":700}}}' > "$TMP/.ralph-state.json" && bash "$TMP/condense-context.sh" "$TMP" --mode proactive && ls "$TMP/.archive."*.md > /dev/null 2>&1 && echo POC_CHECKPOINT_PASS`
  - **Commit**: `feat(context): complete POC end-to-end condensation`
  - _Requirements: AC-1.1, AC-1.2, AC-1.3, AC-1.4, AC-1.5, AC-1.6, FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8_
  - _Design: Condensation Algorithm steps 1-8_

## Phase 2: Refactoring

Focus: Add error handling, improve robustness, version bump in implement.md completion.

- [ ] 2.1 Add flock timeout and validation error handling to condense-context.sh
  - **Do**:
    1. Add `flock -w 10 -x 200` (10s timeout instead of infinite block) with graceful skip on contention
    2. Validate temp `chat.md` non-empty and contains protected suffix before `mv` — on failure, discard temp, keep original
    3. Add error logging to stderr for all failure paths (flock timeout, validation failure, jq parse error)
  - **Files**: `plugins/ralphharness/hooks/scripts/condense-context.sh`
  - **Done when**: All flock/jq/validate failures log and degrade gracefully; original files preserved on failure
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/condense-context.sh && echo 2.1_PASS`
  - **Commit**: `refactor(context): add flock timeout and validation to condense-context.sh`
  - _Requirements: NFR-4, FR-18_
  - _Design: Error Handling / Failure Modes_

- [ ] 2.2 Improve error handling in lib-context.sh
  - **Do**:
    1. In `transcript_usage_pct`: add `set -o pipefail`, handle jq parse errors gracefully (return 0 on parse failure)
    2. In `write_condensation_metric`: add flock timeout on fd 201, validate JSONL format before append
  - **Files**: `plugins/ralphharness/hooks/scripts/lib-context.sh`
  - **Done when**: lib-context.sh has pipefail, flock timeouts, graceful degradation on all failure paths
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/lib-context.sh && echo 2.2_PASS`
  - **Commit**: `refactor(context): improve error handling in lib-context.sh`
  - _Requirements: NFR-4_
  - _Design: Error Handling / Failure Modes_

- [ ] 2.3 Improve error handling in evict-tool-result.sh
  - **Do**:
    1. Validate `tool_kind` is one of the 4 allowed values (`grep|gitdiff|fileread|lsfind`)
    2. Add `set -o pipefail`
  - **Files**: `plugins/ralphharness/hooks/scripts/evict-tool-result.sh`
  - **Done when**: Tool kind validated, pipefail set, graceful degradation on all paths
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/evict-tool-result.sh && echo 2.3_PASS`
  - **Commit**: `refactor(context): improve error handling in evict-tool-result.sh`
  - _Requirements: NFR-4_
  - _Design: Error Handling / Failure Modes_

- [ ] 2.4 Add spec-completion cleanup to implement.md (AC-5.3)
  - **Do**:
    1. In implement.md Step 5 (Completion), after taskIndex verification and before the existing cleanup step, add:
    2. `rm -f "$SPEC_PATH"/.archive.*.md` — delete all archive files
    3. `rm -rf "$SPEC_PATH/.tool-results/"` — delete tool-results directory
    4. Log cleanup to stderr
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: implement.md Step 5 includes archive + tool-results cleanup before ALL_TASKS_COMPLETE
  - **Verify**: `grep -A 3 'Step 5' plugins/ralphharness/commands/implement.md | grep -c 'archive\|tool-results' && echo 2.4_PASS`
  - **Commit**: `feat(context): add spec-completion cleanup for archives and tool-results`
  - _Requirements: FR-15, AC-5.3_
  - _Design: Architecture → Cleanup_

- [ ] 2.5 Modify coordinator-pattern.md: document executionPhase writes + eviction prompt-rule
  - **Do**:
    1. Add a section documenting that the coordinator writes `executionPhase` field to `.ralph-state.json` at each phase transition (poc→refactor→test→quality)
    2. Add the eviction prompt-rule: "When a tool produces output exceeding its threshold (grep/rg >100 lines, git diff >200, file read >500, ls/find >300), route the full output through `evict-tool-result.sh` and use only the returned preview"
    3. Add note: "Never route pair-debug debug-logging output through eviction"
  - **Files**: `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: coordinator-pattern.md documents executionPhase writes and eviction prompt-rule
  - **Verify**: `grep -c 'executionPhase' plugins/ralphharness/references/coordinator-pattern.md && grep -c 'evict-tool-result' plugins/ralphharness/references/coordinator-pattern.md && echo 2.5_PASS`
  - **Commit**: `refactor(context): document executionPhase writes and eviction rule in coordinator-pattern.md`
  - _Requirements: FR-12, FR-19, FR-17, AC-4.7, AC-5.4_
  - _Design: coordinator-pattern.md modifications_

## Phase 3: Testing

Focus: Comprehensive test coverage. One task per Test Coverage Table row. Real temp dirs via `mktemp -d`. No stubs/mocks.

- [ ] 3.1 [P] Create test-lib-context.bats: all lib-context.sh functions
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-lib-context.bats`
    2. `combined_line_count`: correct sum; missing .progress.md; both missing
    3. `transcript_usage_pct`: >85% fixture (175k tokens → 87); <85% (150k → 75); empty file; missing file; malformed JSONL
    4. `spec_dir_writable`: writable dir → 0; read-only dir → 1
    5. `context_window_size`: echoes 200000
    6. `write_condensation_metric`: appends valid JSONL to `.metrics.jsonl`; uses fd 201 lock; does not touch fd 200
  - **Files**: `plugins/ralphharness/tests/test-lib-context.bats`
  - **Done when**: 12 tests pass across all 5 functions
  - **Verify**: `bats plugins/ralphharness/tests/test-lib-context.bats`
  - **Commit**: `test(context): unit tests for lib-context.sh helper functions`
  - _Requirements: FR-1, FR-9, NFR-4_
  - _Design: Test Coverage Table — lib-context.sh all functions_

- [ ] 3.2 [P] Create test-condense-context.bats: proactive condensation
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-condense-context.bats`
    2. `setup()`: `build_oversized_spec()` creates temp dir with chat.md (1200 lines + HOLD signal), .progress.md (900 lines + Goal/Learnings + 5 task entries), .ralph-state.json with 3 pointers, signals.jsonl
    3. Test proactive: combined lines < 2000 post-run; archive exists; diff archive vs pre-snapshot empty
    4. Test signal preservation: grep for `[HOLD]`, `[PENDING]`, `HYPOTHESIS`, `PAIR-DEBUG`, `Driver:`, `Navigator:` — all present
    5. Test message count: ≤15 `## Message` headers in condensed chat.md
    6. Test signals.jsonl exclusion: md5sum identical before/after
    7. Test three-pointer reconciliation: pointers in-bounds; lagging reviewer protects content
    8. Test progress.md stable/volatile: Goal/Learnings intact; exactly 3 task entries
    9. Test archive prune: run 4 times → exactly 3 `.archive.*.md` remain
    10. Test metrics: `.metrics.jsonl` has valid condensation event with correct mode
    11. Test read-only degradation: exit 0, no files mutated, degradation logged
  - **Files**: `plugins/ralphharness/tests/test-condense-context.bats`
  - **Done when**: 11 tests pass covering all condensation behaviors
  - **Verify**: `bats plugins/ralphharness/tests/test-condense-context.bats`
  - **Commit**: `test(context): integration tests for condense-context.sh`
  - _Requirements: AC-1.1, AC-1.2, AC-1.3, AC-1.4, AC-1.5, AC-1.6, AC-1.8, FR-1, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-14, FR-15, FR-16, FR-18_
  - _Design: Test Coverage Table — condense-context.sh_

- [ ] 3.3 [P] Create test-evict-tool-result.bats: eviction + pair-debug + read-only
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-evict-tool-result.bats`
    2. Test each kind (grep >100, gitdiff >200, fileread >500, lsfind >300) → evicted with preview + path
    3. Test below-threshold → passes through unchanged
    4. Test pair-debug: oversized input → pass through, no `.tool-results/`
    5. Test read-only: pass through + degradation note
  - **Files**: `plugins/ralphharness/tests/test-evict-tool-result.bats`
  - **Done when**: 8 tests pass: 4 evict + 4 below-threshold + pair-debug + read-only
  - **Verify**: `bats plugins/ralphharness/tests/test-evict-tool-result.bats`
  - **Commit**: `test(context): integration tests for evict-tool-result.sh`
  - _Requirements: AC-3.1, AC-3.2, AC-3.3, AC-3.4, AC-5.1, FR-10, FR-11_
  - _Design: Test Coverage Table — evict-tool-result.sh_

- [ ] 3.4 [P] Create test-context-scoping.bats: precompact + stop-watcher + implement.md + schema + hooks
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-context-scoping.bats`
    2. precompact-condense.sh: resolves spec, calls `--mode emergency`, exits 0 unconditionally
    3. stop-watcher.sh two-gate: Gate 1 → proactive; Gate 2 → reactive; neither → no trigger
    4. implement.md phase scoping: `case` present; `phase-rules.md` gated; `pair-debug.md` gated; default loads all
    5. spec.schema.json: valid sample passes; bad enum rejected via schema validation
    6. hooks.json: PreCompact entry present; command points to `precompact-condense.sh`
  - **Files**: `plugins/ralphharness/tests/test-context-scoping.bats`
  - **Done when**: 9 tests pass across all 5 components
  - **Verify**: `bats plugins/ralphharness/tests/test-context-scoping.bats`
  - **Commit**: `test(context): integration tests for precompact, two-gate, scoping, schema, hooks`
  - _Requirements: AC-2.5, AC-2.6, AC-4.1, AC-4.2, AC-4.3, AC-4.7, FR-1, FR-9, FR-19_
  - _Design: Test Coverage Table — precompact, two-gate, implement.md, schema, hooks_

- [ ] 3.5 [VERIFY] Quality checkpoint: all bats tests pass
  - **Do**: Run the full bats test suite
  - **Verify**: `bats plugins/ralphharness/tests/ 2>&1 | tail -5`
  - **Done when**: All test files pass with zero failures
  - **Commit**: `chore(context): pass quality checkpoint — all bats tests`

## Phase 4: Quality Gates

Focus: Full local CI, PR creation, AC verification.

- [ ] 4.1 [VERIFY] Full local CI: bats + script syntax + JSON validation
  - **Do**: Run the complete bats test suite AND verify all scripts parse AND all JSON files are valid
  - **Verify**: `bats plugins/ralphharness/tests/ && bash -n plugins/ralphharness/hooks/scripts/{lib-context,condense-context,evict-tool-result,precompact-condense,stop-watcher}.sh && jq empty plugins/ralphharness/hooks/hooks.json && jq empty plugins/ralphharness/schemas/spec.schema.json && echo FULL_CI_PASS`
  - **Done when**: All tests pass, zero script parse errors, zero JSON validation errors
  - **Commit**: `chore(context): pass full local CI` (if fixes needed)

- [ ] 4.2 [VERIFY] AC checklist: verify all 28 acceptance criteria
  - **Do**:
    1. FR-1/AC-1.1: `grep -q 'combined_line_count' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC11_PASS`
    2. FR-2/AC-1.3: `grep -q 'mv.*chat.md' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC12_PASS`
    3. FR-3/AC-1.2: `grep -q 'archive' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC13_PASS`
    4. FR-5/AC-1.4: `grep -q 'HOLD\|PENDING\|DEADLOCK\|URGENT\|ACK\|CONTINUE\|HYPOTHESIS\|ROOT_CAUSE\|FIX_PROPOSAL\|BUG_DISCOVERY\|PAIR-DEBUG\|Driver:\|Navigator:' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC14_PASS`
    5. FR-8/AC-1.6: `grep -q 'lastReadLine' plugins/ralphharness/hooks/scripts/condense-context.sh && grep -q 'chat.coordinator\|chat.executor\|chat.reviewer' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC16_PASS`
    6. FR-9/AC-2.1: `grep -q 'transcript_usage_pct\|message.usage\|input_tokens' plugins/ralphharness/hooks/scripts/lib-context.sh && echo AC21_PASS`
    7. FR-9/AC-2.5: `grep -q 'PreCompact' plugins/ralphharness/hooks/hooks.json && echo AC25_PASS`
    8. FR-10/AC-3.1: `grep -q 'grep.*100\|gitdiff.*200\|fileread.*500\|lsfind.*300' plugins/ralphharness/hooks/scripts/evict-tool-result.sh && echo AC31_PASS`
    9. FR-10/AC-3.4: `grep -q 'pair-debug' plugins/ralphharness/hooks/scripts/evict-tool-result.sh && echo AC34_PASS`
    10. FR-12/AC-4.1: `grep -q 'executionPhase' plugins/ralphharness/commands/implement.md && echo AC41_PASS`
    11. FR-12/AC-4.7: `grep -q 'executionPhase.*poc.*refactor.*test.*quality' plugins/ralphharness/schemas/spec.schema.json && echo AC47_PASS`
    12. FR-15/AC-5.3: `grep -q 'archive\|tool-results' plugins/ralphharness/commands/implement.md && echo AC53_PASS`
    13. FR-16/AC-5.1: `grep -q 'spec_dir_writable\|read.only\|degrad' plugins/ralphharness/hooks/scripts/condense-context.sh && echo AC51_PASS`
  - **Verify**: All 13 checks above exit 0
  - **Done when**: All grep assertions pass — every AC verified by concrete code presence check
  - **Commit**: `chore(context): AC checklist verified`

- [ ] 4.3 Bump versions: plugin.json + marketplace.json from 5.4.0 to 5.5.0
  - **Do**:
    1. Update `plugins/ralphharness/.claude-plugin/plugin.json`: change `"version": "5.4.0"` to `"version": "5.5.0"`
    2. Update `.claude-plugin/marketplace.json`: change ralphharness entry version from `"5.4.0"` to `"5.5.0"`
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Done when**: Both files show version 5.5.0
  - **Verify**: `jq -r .version plugins/ralphharness/.claude-plugin/plugin.json && jq '.plugins[] | select(.name=="ralphharness") | .version' .claude-plugin/marketplace.json | grep 5.5.0 && echo 4.3_PASS`
  - **Commit**: `chore(context): bump version to 5.5.0`

- [ ] 4.4 [VERIFY] PR opened correctly
  - **Do**:
    1. Verify feature branch: `git branch --show-current`
    2. Push: `git push -u origin context-middleware`
    3. Create PR: `gh pr create --title "feat(context-middleware): add context management middleware" --body "Add proactive condensation, reactive fallback, tool result eviction, and phase-based reference scoping. Replaces cancelled Spec 2 (prompt-diet-refactor) with a non-disruptive additive approach."`
    4. Verify: `gh pr view --json url,state | jq -r '.state'` returns `OPEN`
  - **Verify**: `gh pr view --json url,state | jq -r '.state'` returns `OPEN`
  - **Done when**: PR exists on GitHub with a valid URL and state OPEN
  - **Commit**: None

  > **PR Lifecycle Rule (CRITICAL)**: The local agent's responsibility ends
  > when the PR exists on GitHub. The agent MUST NOT wait for CI nor run
  > `gh pr checks --watch`. CI is executed asynchronously by the cloud
  > infrastructure (GitHub Actions).
  >
  > ✅ TASKCOMPLETE when: `gh pr view` returns state OPEN
  > ❌ NEVER: wait for `gh pr checks` to be green before marking [x]

## Phase 5: PR Lifecycle

Focus: Autonomous PR validation, review comment resolution, final E2E verification.

- [ ] 5.1 [VERIFY] CI monitoring: watch for CI completion
  - **Do**: Monitor PR checks via `gh pr checks`. If any check fails, read failure details, fix issues, push fix.
  - **Verify**: `gh pr checks` shows all green
  - **Done when**: All CI checks green

- [ ] 5.2 [VERIFY] Code review: address any review comments
  - **Do**: If review comments appear, address them surgically (no scope creep). Push fixes.
  - **Verify**: `gh pr reviews` — no pending review requests requiring changes
  - **Done when**: All review comments resolved

- [ ] 5.3 [VERIFY] Final verification: all bats tests pass, files exist, scripts parse
  - **Do**:
    1. `bats plugins/ralphharness/tests/` — all tests pass
    2. `bash -n plugins/ralphharness/hooks/scripts/{lib-context,condense-context,evict-tool-result,precompact-condense,stop-watcher}.sh` — all scripts parse
    3. `jq empty plugins/ralphharness/hooks/hooks.json` — hooks.json valid
    4. `jq empty plugins/ralphharness/schemas/spec.schema.json` — schema valid
  - **Verify**: All 4 checks pass
  - **Done when**: Zero test failures, zero parse errors, zero schema errors
  - **Commit**: `chore(context): final verification pass`

- [ ] 5.4 [VERIFY] Goal verification: condensation reduces context, cleanup works
  - **Do**:
    1. Create temp spec dir with oversized chat.md + .progress.md
    2. Run `condense-context.sh` — verify line count reduced below 2000
    3. Verify archive exists, signals preserved, pointers adjusted
    4. Run completion cleanup pattern — verify archives deleted, .tool-results/ deleted
  - **Verify**: Exit code 0 for condensation + cleanup
  - **Done when**: End-to-end condensation + cleanup verified
  - **Commit**: `chore(context): verify goal resolves original issue`

## Notes

- POC shortcuts: hardcoded 200000 window size, no adaptive thresholds, no tool argument truncation (deferred to v0.2), no reference file splitting
- Production TODOs: adaptive thresholds by totalTasks count, context budget accounting, split coordinator-pattern.md into base + extensions
- Test fixtures live inline in bats files via `build_oversized_spec()` builder function — no separate fixture directory needed
- fd isolation: fd 200 for chat.md.lock, fd 201 for .metrics.lock (avoids collision with both fd 200 chat-lock and fd 202 signals-lock from lib-signals.sh)
- Version bump: 5.4.0 → 5.5.0 (minor, new feature)
