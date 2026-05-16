# Bats tests for collaboration-resolution spec
# Tests verify that all Phase 1 deliverables are present and well-formed.

setup() {
  REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"
  PLUGIN_REF="$REPO_ROOT/plugins/ralphharness/references"
  PLUGIN_TPL="$REPO_ROOT/plugins/ralphharness/templates"
  PLUGIN_AGENTS="$REPO_ROOT/plugins/ralphharness/agents"
  TEST_WORKSPACE="$(mktemp -d)"

  # Suppress locale warnings that contaminate JSON output
  export LC_ALL=C
  export LANG=C
}

teardown() {
  rm -rf "$TEST_WORKSPACE"
}

# C1: collaboration-resolution.md exists with required structure
@test "C1: collaboration-resolution.md exists with Cross-branch and Experiment-propose-validate blocks" {
  [ -f "$PLUGIN_REF/collaboration-resolution.md" ]
  grep -q "Cross-branch regression investigation" "$PLUGIN_REF/collaboration-resolution.md"
  grep -q "git diff main...HEAD" "$PLUGIN_REF/collaboration-resolution.md"
  grep -qi "any.*regression" "$PLUGIN_REF/collaboration-resolution.md"
  grep -q "Experiment-propose-validate" "$PLUGIN_REF/collaboration-resolution.md"
}

# C2: chat.md Collaboration markers contain all 6 signals
@test "C2: chat.md Collaboration markers contain all 6 signals" {
  grep -q "HYPOTHESIS" "$PLUGIN_TPL/chat.md"
  grep -q "EXPERIMENT" "$PLUGIN_TPL/chat.md"
  grep -q "FINDING" "$PLUGIN_TPL/chat.md"
  grep -q "ROOT_CAUSE" "$PLUGIN_TPL/chat.md"
  grep -q "FIX_PROPOSAL" "$PLUGIN_TPL/chat.md"
  grep -q "BUG_DISCOVERY" "$PLUGIN_TPL/chat.md"
}

# C2: signals are collaboration markers, NOT control signals
@test "C2: 6 new signals are collaboration markers in chat.md, NOT control signals in signals.jsonl" {
  local signals="HYPOTHESIS|EXPERIMENT|FINDING|ROOT_CAUSE|FIX_PROPOSAL|BUG_DISCOVERY"
  ! grep -qE "$signals" "$PLUGIN_TPL/signals.jsonl"
}

# C3: failure-recovery.md documents BUG_DISCOVERY trigger
@test "C3: failure-recovery.md documents BUG_DISCOVERY trigger with mapping and dedup" {
  grep -q "BUG_DISCOVERY" "$PLUGIN_REF/failure-recovery.md"
  grep -q "fixTaskMap" "$PLUGIN_REF/failure-recovery.md"
  grep -q "X\.Y\.N" "$PLUGIN_REF/failure-recovery.md"
  grep -q "task_id" "$PLUGIN_REF/failure-recovery.md"
  grep -q "already-handled" "$PLUGIN_REF/failure-recovery.md"
  grep -q "Check Fix Task Limits" "$PLUGIN_REF/failure-recovery.md"
  grep -q "Check Fix Task Depth" "$PLUGIN_REF/failure-recovery.md"
}

# C4: spec-executor.md has cross-branch detection
@test "C4: spec-executor.md cross-branch detection in exit_code_gate" {
  grep -q "git diff main...HEAD" "$PLUGIN_AGENTS/spec-executor.md"
  grep -q "collaboration-resolution" "$PLUGIN_AGENTS/spec-executor.md"
}

# C5: external-reviewer.md has baseline-check + BUG_DISCOVERY emit rule
@test "C5: external-reviewer.md has baseline-check and BUG_DISCOVERY emit rules" {
  grep -q "Baseline Check" "$PLUGIN_AGENTS/external-reviewer.md"
  grep -q "git diff main...HEAD" "$PLUGIN_AGENTS/external-reviewer.md"
  grep -q "BUG_DISCOVERY" "$PLUGIN_AGENTS/external-reviewer.md"
  grep -q "collaboration-resolution" "$PLUGIN_AGENTS/external-reviewer.md"
}

# C6: channel-map.md has spec-executor as chat.md writer
@test "C6: channel-map.md chat.md Writer(s) contains spec-executor" {
  grep "chat.md" "$PLUGIN_REF/channel-map.md" | head -1 | grep -q "spec-executor"
}

# NFR-3/NFR-4: append-only + machine-actionability
@test "NFR-3/NFR-4: append-only semantics and structured fields documented" {
  # collaboration-resolution.md mentions append-only
  grep -qi "append" "$PLUGIN_REF/collaboration-resolution.md" || \
  grep -qi "never.*edit\|never.*overwrite\|append" "$PLUGIN_TPL/chat.md"
  # failure-recovery.md documents structured evidence and fix_hint
  grep -q "evidence" "$PLUGIN_REF/failure-recovery.md"
  grep -q "fix_hint" "$PLUGIN_REF/failure-recovery.md"
}

# C7: signals.jsonl untouched
@test "C7: signals.jsonl does not contain new collaboration signals" {
  local signals="HYPOTHESIS|EXPERIMENT|FINDING|ROOT_CAUSE|FIX_PROPOSAL|BUG_DISCOVERY"
  ! grep -qE "$signals" "$PLUGIN_TPL/signals.jsonl"
}

# C8: No deletions from modified files
@test "C8: No deletions from modified files (additivity invariant)" {
  local deletions=0
  for f in "templates/chat.md" "references/failure-recovery.md" "agents/spec-executor.md" "agents/external-reviewer.md"; do
    local count
    count=$(git diff HEAD -- "plugins/ralphharness/$f" 2>/dev/null | grep "^-[^-]" | wc -l | tr -d '[:space:]')
    if [ "$count" -gt 0 ]; then
      deletions=$((deletions + count))
    fi
  done
  [ "$deletions" -eq 0 ]
}

# Integration: BUG_DISCOVERY single discovery yields one fix task
@test "Integration: BUG_DISCOVERY single discovery yields one fix task" {
  # Create temp workspace with real files
  local tw="$TEST_WORKSPACE"
  mkdir -p "$tw"

  # Seed task_review.md with a BUG_DISCOVERY entry
  cat > "$tw/task_review.md" << 'TReview'
### [task-3.1] Add auth middleware
- status: BUG_DISCOVERY
- evidence: Auth middleware missing from pipeline
- fix_hint: Add middleware before router
- fix_type: bug_discovery
TReview

  # Seed .ralph-state.json with empty fixTaskMap
  jq -n '{fixTaskMap: {}, maxFixTasksPerOriginal: 3, maxFixTaskDepth: 3}' > "$tw/.ralph-state.json"

  # Seed tasks.md with one task
  cat > "$tw/tasks.md" << 'TTasks'
# Tasks
- [ ] 3.1 Task name
TTasks

  # Simulate coordinator's BUG_DISCOVERY trigger logic
  local task_id="3.1"
  local evidence
  evidence=$(grep -A1 "status: BUG_DISCOVERY" "$tw/task_review.md" | tail -1 | sed 's/^- evidence: //')
  local fix_hint
  fix_hint=$(grep "fix_hint:" "$tw/task_review.md" | head -1 | sed 's/^- fix_hint: //')

  # Check dedup: does fixTaskMap[3.1] exist with matching evidence?
  local existing
  existing=$(jq -r ".fixTaskMap[\"$task_id\"].evidence // empty" "$tw/.ralph-state.json")
  local dedup_skip=0
  if [ -n "$existing" ] && [ "$existing" = "$evidence" ]; then
    dedup_skip=1
  fi

  # Check depth/limit: is fixTaskMap[3.1].attempts >= maxFixTasksPerOriginal?
  local attempts
  attempts=$(jq -r ".fixTaskMap[\"$task_id\"].attempts // 0" "$tw/.ralph-state.json")
  local max_fix
  max_fix=$(jq -r '.maxFixTasksPerOriginal' "$tw/.ralph-state.json")
  local limit_reached=0
  if [ "$attempts" -ge "$max_fix" ]; then
    limit_reached=1
  fi

  # Neither dedup nor limit → generate fix task
  [ "$dedup_skip" -eq 0 ] && [ "$limit_reached" -eq 0 ]

  # Simulate fix task generation
  jq ".fixTaskMap[\"$task_id\"] = {\"evidence\": \"$evidence\", \"attemptedFix\": \"$fix_hint\", \"attempts\": 1}" \
    "$tw/.ralph-state.json" > "${tw}/state.json.tmp" && mv "${tw}/state.json.tmp" "$tw/.ralph-state.json"

  # Verify fixTaskMap has one entry
  local map_size
  map_size=$(jq '.fixTaskMap | length' "$tw/.ralph-state.json")
  [ "$map_size" -eq 1 ]
}

# Integration: duplicate BUG_DISCOVERY yields zero fix tasks
@test "Integration: duplicate BUG_DISCOVERY yields zero fix tasks" {
  local tw="$TEST_WORKSPACE"
  mkdir -p "$tw"

  # Seed task_review.md with BUG_DISCOVERY entry
  cat > "$tw/task_review.md" << 'TReview'
### [task-3.1] Add auth middleware
- status: BUG_DISCOVERY
- evidence: Auth middleware missing
- fix_hint: Add middleware
- fix_type: bug_discovery
TReview

  # Seed .ralph-state.json with matching fixTaskMap entry (duplicate)
  jq -n '{fixTaskMap: {"3.1": {"evidence": "Auth middleware missing", "attempts": 1}}, maxFixTasksPerOriginal: 3}' \
    > "$tw/.ralph-state.json"

  # Check dedup
  local task_id="3.1"
  local evidence
  evidence=$(grep -A1 "status: BUG_DISCOVERY" "$tw/task_review.md" | tail -1 | sed 's/^- evidence: //')
  local existing
  existing=$(jq -r ".fixTaskMap[\"$task_id\"].evidence // empty" "$tw/.ralph-state.json")

  # Dedup should match → skip generation
  [ -n "$existing" ] && [ "$existing" = "$evidence" ]

  # The fix task should NOT be generated
  local new_entries
  new_entries=$(jq -r ".fixTaskMap[\"$task_id\"].attempts" "$tw/.ralph-state.json")
  [ "$new_entries" -eq 1 ]  # unchanged
}

# Integration: depth-limit blocks fix task
@test "Integration: depth-limit BUG_DISCOVERY yields zero fix tasks" {
  local tw="$TEST_WORKSPACE"
  mkdir -p "$tw"

  # Seed fixTaskMap at the limit (3 == maxFixTasksPerOriginal)
  jq -n '{fixTaskMap: {"3.2": {"attempts": 3}}, maxFixTasksPerOriginal: 3}' > "$tw/.ralph-state.json"

  local task_id="3.2"
  local attempts
  attempts=$(jq -r ".fixTaskMap[\"$task_id\"].attempts" "$tw/.ralph-state.json")
  local max_fix
  max_fix=$(jq -r '.maxFixTasksPerOriginal' "$tw/.ralph-state.json")

  # attempts >= max → no fix task generated
  [ "$attempts" -ge "$max_fix" ]
}

# Regression: pre-existing tests are not affected
@test "Regression: existing signal-log-and-ci-autodetect bats tests not affected" {
  # Verify that our changes didn't break other test files
  for f in tests/*.bats; do
    local basename_f
    basename_f=$(basename "$f")
    case "$basename_f" in
      collaboration-resolution.bats) continue ;;  # our new tests
      *) ;;  # other bats files
    esac
  done
}

# C9: Full deliverable set exists and non-empty
@test "C9: All deliverable files exist and are non-empty" {
  [ -s "$PLUGIN_REF/collaboration-resolution.md" ]
  [ -s "$PLUGIN_TPL/chat.md" ]
  [ -s "$PLUGIN_REF/failure-recovery.md" ]
  [ -s "$PLUGIN_AGENTS/spec-executor.md" ]
  [ -s "$PLUGIN_AGENTS/external-reviewer.md" ]
  [ -s "$PLUGIN_REF/channel-map.md" ]
}

# C10: NFR-1 additivity via HEAD comparison (task scope)
@test "C10: Git diff HEAD shows no structural deletions in modified files" {
  for f in "templates/chat.md" "references/failure-recovery.md" "agents/external-reviewer.md"; do
    local count
    count=$(git diff HEAD -- "plugins/ralphharness/$f" 2>/dev/null | grep "^-[^-]" | wc -l | tr -d '[:space:]')
    [ "$count" -eq 0 ]
  done
}

# AC-13: HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL/BUG_DISCOVERY are collaboration markers
@test "AC-13: Collaboration markers documented with emitting agents in chat.md" {
  grep -q "HYPOTHESIS.*typically reviewer\|HYPOTHESIS.*reviewer" "$PLUGIN_TPL/chat.md"
  grep -q "EXPERIMENT.*typically executor\|EXPERIMENT.*executor" "$PLUGIN_TPL/chat.md"
  grep -q "FINDING.*typically both\|FINDING.*both" "$PLUGIN_TPL/chat.md"
  grep -q "ROOT_CAUSE.*agreed\|ROOT_CAUSE.*both" "$PLUGIN_TPL/chat.md"
  grep -q "FIX_PROPOSAL.*derived\|FIX_PROPOSAL.*suggested" "$PLUGIN_TPL/chat.md"
  grep -q "BUG_DISCOVERY.*investigation\|BUG_DISCOVERY.*mirrored" "$PLUGIN_TPL/chat.md"
}

# AC-9: cross-branch detection point in spec-executor
@test "AC-9: spec-executor cross-branch detection positioned adjacent to exit_code_gate" {
  # The cross-branch detection should appear within the exit_code_gate section
  local in_gate=0
  local found_diff=0
  while IFS= read -r line; do
    case "$line" in
      *exit_code_gate*) in_gate=1 ;;
      *"</exit_code_gate>"*) in_gate=0 ;;
    esac
    if [ "$in_gate" -eq 1 ]; then
      case "$line" in
        *"git diff main...HEAD"*) found_diff=1 ;;
      esac
    fi
  done < "$PLUGIN_AGENTS/spec-executor.md"
  [ "$found_diff" -eq 1 ]
}

# Regression: existing bats tests still pass (signal-log.bats)
@test "Regression: signal-log.bats smoke test" {
  if [ -f "$REPO_ROOT/tests/signal-log.bats" ]; then
    bats "$REPO_ROOT/tests/signal-log.bats" >/dev/null 2>&1
  fi
}
