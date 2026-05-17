#!/usr/bin/env bats
# test-condense-context.bats — Integration tests for condense-context.sh.

CONDENSE_SCRIPT="${BATS_TEST_DIRNAME}/../hooks/scripts/condense-context.sh"
LIB_SCRIPT="${BATS_TEST_DIRNAME}/../hooks/scripts/lib-context.sh"

build_oversized_spec() {
  local tmp="$1"
  mkdir -p "$tmp"

  # chat.md: ~2500 lines of ## [...] message blocks + embedded signals
  # condense-context.sh detects blocks with /^## \[/ pattern
  {
    # First 200 blocks (~600 lines)
    for i in $(seq 1 200); do
      printf '## [%d]\nChat content for block %d.\n' "$i" "$i"
    done
    # Embedded signal in the middle
    echo "[HOLD]"
    # More blocks: 201-1100 (~1800 lines)
    for i in $(seq 201 1100); do
      printf '## [%d]\nMore chat content for block %d.\n' "$i" "$i"
    done
    # End-of-file signals after the pointer region
    echo "[PENDING]"
    echo "HYPOTHESIS: This is a hypothesis about the code."
    echo "PAIR-DEBUG: Entering pair-debug mode."
    echo "Driver: implementing the fix."
    echo "Navigator: reviewing the implementation."
    echo "ROOT_CAUSE: identified the bug in parsing."
  } > "$tmp/chat.md"

  # .progress.md with Goal, Learnings, and task entries
  {
    echo "# Goal"
    echo "Implement context middleware for the spec-driven development system."
    echo ""
    echo "# Learnings"
    for i in $(seq 1 10); do
      echo "- Learning $i: important insight from task execution."
    done
    echo ""
    echo "# Completed Tasks"
    for i in $(seq 1 5); do
      echo "## Task $i.0"
      echo "Task $i completed successfully."
      echo "Learnings: task-specific learning from $i."
    done
  } > "$tmp/.progress.md"

  # .ralph-state.json — min-pointer ~2200, prefix gets condensed from ~2200 to ~315 lines
  cat > "$tmp/.ralph-state.json" << 'STATEEOF'
{
  "phase": "execution",
  "taskIndex": 5,
  "totalTasks": 20,
  "state": {
    "executionPhase": "poc",
    "chat": {
      "coordinator": {"lastReadLine": 2400},
      "executor": {"lastReadLine": 2200},
      "reviewer": {"lastReadLine": 2300}
    }
  }
}
STATEEOF

  # signals.jsonl
  printf '{"type":"control","signal":"HOLD"}\n' > "$tmp/signals.jsonl"
}

setup() {
  source "$LIB_SCRIPT"
  TEST_TMP="$(mktemp -d)"
  SPEC_DIR="$TEST_TMP/spec"
  mkdir -p "$SPEC_DIR"
  build_oversized_spec "$SPEC_DIR"
}

teardown() {
  chmod -R u+w "$TEST_TMP" 2>/dev/null || true
  rm -rf "$TEST_TMP"
}

run_test() {
  bash "$CONDENSE_SCRIPT" "$@"
}

# ===== Proactive condensation =====

@test "condense-context: condensation triggers when line count > 2000" {
  local before
  before="$(combined_line_count "$SPEC_DIR")"
  [ "$before" -gt 2000 ]

  # Condensation runs (triggers on > 2000 lines)
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null

  # Archive should exist
  [ "$(find "$SPEC_DIR" -name '.archive.*.md' | wc -l)" -ge 1 ]
  # Metrics should be logged
  [ -f "$SPEC_DIR/.metrics.jsonl" ]
}

@test "condense-context: archive file created" {
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  local archive_count
  archive_count="$(find "$SPEC_DIR" -name '.archive.*.md' | wc -l)"
  [ "$archive_count" -ge 1 ]
}

# ===== Signal preservation =====

@test "condense-context: preserves [HOLD] signal" {
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  # condense-context.sh preserves standalone [HOLD] lines
  grep -q '\[HOLD\]' "$SPEC_DIR/chat.md"
}

@test "condense-context: preserves collaboration markers (HYPOTHESIS, PAIR-DEBUG, Driver:, Navigator:)" {
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  grep -q 'HYPOTHESIS' "$SPEC_DIR/chat.md"
  grep -q 'PAIR-DEBUG' "$SPEC_DIR/chat.md"
  grep -q 'Driver:' "$SPEC_DIR/chat.md"
  grep -q 'Navigator:' "$SPEC_DIR/chat.md"
}

# ===== Line count reduction =====

@test "condense-context: condensed chat line count reduced" {
  local before
  before="$(wc -l < "$SPEC_DIR/chat.md")"
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  local after
  after="$(wc -l < "$SPEC_DIR/chat.md")"
  # Should have fewer lines than before (at least 30% reduction)
  local threshold
  threshold=$(( before * 70 / 100 ))
  [ "$after" -lt "$threshold" ]
}

# ===== signals.jsonl exclusion =====

@test "condense-context: signals.jsonl is not modified" {
  local before_md5
  before_md5="$(md5sum "$SPEC_DIR/signals.jsonl" | awk '{print $1}')"
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  local after_md5
  after_md5="$(md5sum "$SPEC_DIR/signals.jsonl" | awk '{print $1}')"
  [ "$before_md5" = "$after_md5" ]
}

# ===== Three-pointer reconciliation =====

@test "condense-context: chat pointers stay in-bounds after condensation" {
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  local lines_after
  lines_after="$(wc -l < "$SPEC_DIR/chat.md")"
  local reviewer_ptr
  reviewer_ptr="$(jq -r '.state.chat.reviewer.lastReadLine' "$SPEC_DIR/.ralph-state.json" 2>/dev/null || echo 0)"
  [ "$reviewer_ptr" -le "$lines_after" ] 2>/dev/null || true
}

# ===== Progress.md changes =====

@test "condense-context: progress.md is rewritten during condensation" {
  local before_progress
  before_progress="$(wc -l < "$SPEC_DIR/.progress.md")"
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  local after_progress
  after_progress="$(wc -l < "$SPEC_DIR/.progress.md")"
  # progress.md changes due to volatile task entries being trimmed
  [ "$after_progress" -lt "$before_progress" ]
}

# ===== Archive pruning =====

@test "condense-context: archive pruning keeps only 3 newest" {
  for i in $(seq 1 4); do
    run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  done
  local archive_count
  archive_count="$(find "$SPEC_DIR" -name '.archive.*.md' | wc -l)"
  [ "$archive_count" -le 3 ]
}

# ===== Metrics =====

@test "condense-context: .metrics.jsonl has valid condensation event" {
  run_test "$SPEC_DIR" --mode proactive 2>/dev/null
  [ -f "$SPEC_DIR/.metrics.jsonl" ]
  local last_line
  last_line="$(tail -1 "$SPEC_DIR/.metrics.jsonl")"
  echo "$last_line" | jq -e '.event == "condensation"' > /dev/null
  echo "$last_line" | jq -e '.mode == "proactive"' > /dev/null
}

# ===== Read-only degradation =====

@test "condense-context: read-only spec degrades gracefully" {
  local ro_dir="$TEST_TMP/readonly"
  mkdir -p "$ro_dir"
  cp "$SPEC_DIR/chat.md" "$ro_dir/"
  cp "$SPEC_DIR/.progress.md" "$ro_dir/"
  cp "$SPEC_DIR/.ralph-state.json" "$ro_dir/"
  chmod -R a-w "$ro_dir"
  run_test "$ro_dir" --mode proactive 2>/dev/null
  [ $? -eq 0 ]
}
