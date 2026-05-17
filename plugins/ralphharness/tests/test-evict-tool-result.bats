#!/usr/bin/env bats
# test-evict-tool-result.bats — Integration tests for evict-tool-result.sh.

EVICTION_SCRIPT="${BATS_TEST_DIRNAME}/../hooks/scripts/evict-tool-result.sh"
LIB_SCRIPT="${BATS_TEST_DIRNAME}/../hooks/scripts/lib-context.sh"

setup() {
  TEST_TMP="$(mktemp -d)"
  SPEC_DIR="$TEST_TMP/spec"
  mkdir -p "$SPEC_DIR"
  # Seed with a state file so spec dir looks valid
  cat > "$SPEC_DIR/.ralph-state.json" << 'EOF'
{"phase":"execution","state":{"chat":{}}}
EOF
}

teardown() {
  chmod -R u+w "$TEST_TMP" 2>/dev/null || true
  rm -rf "$TEST_TMP"
}

run_eviction() {
  local input="$1" kind="$2"
  echo "$input" | bash "$EVICTION_SCRIPT" "$SPEC_DIR" "$kind" 2>/dev/null
}

run_eviction_pair() {
  local input="$1" kind="$2"
  echo "$input" | bash "$EVICTION_SCRIPT" "$SPEC_DIR" "$kind" --pair-debug 2>/dev/null
}

# ===== Eviction: above threshold =====

@test "evict-tool-result: grep above 100 lines is evicted" {
  local input
  input="$(seq 1 150 | sed 's/^/line /')"
  local output
  output="$(run_eviction "$input" grep)"
  # Should contain [evicted] marker
  echo "$output" | grep -q '\[evicted\]'
}

@test "evict-tool-result: gitdiff above 200 lines is evicted" {
  local input
  input="$(seq 1 250 | sed 's/^/diff /')"
  local output
  output="$(run_eviction "$input" gitdiff)"
  echo "$output" | grep -q '\[evicted\]'
}

@test "evict-tool-result: fileread above 500 lines is evicted" {
  local input
  input="$(seq 1 600 | sed 's/^/content /')"
  local output
  output="$(run_eviction "$input" fileread)"
  echo "$output" | grep -q '\[evicted\]'
}

@test "evict-tool-result: lsfind above 300 lines is evicted" {
  local input
  input="$(seq 1 350 | sed 's/^/found /')"
  local output
  output="$(run_eviction "$input" lsfind)"
  echo "$output" | grep -q '\[evicted\]'
}

# ===== Pass-through: below threshold =====

@test "evict-tool-result: grep below 100 lines passes through" {
  local input
  input="$(seq 1 50 | sed 's/^/line /')"
  local output
  output="$(run_eviction "$input" grep)"
  local line_count
  line_count="$(echo "$output" | wc -l)"
  [ "$line_count" -eq 50 ]
  ! echo "$output" | grep -q '\[evicted\]'
}

@test "evict-tool-result: gitdiff below 200 lines passes through" {
  local input
  input="$(seq 1 100 | sed 's/^/diff /')"
  local output
  output="$(run_eviction "$input" gitdiff)"
  local line_count
  line_count="$(echo "$output" | wc -l)"
  [ "$line_count" -eq 100 ]
  ! echo "$output" | grep -q '\[evicted\]'
}

# ===== Pair-debug pass-through =====

@test "evict-tool-result: pair-debug bypasses eviction" {
  local input
  input="$(seq 1 500 | sed 's/^/line /')"
  local output
  output="$(run_eviction_pair "$input" grep)"
  local line_count
  line_count="$(echo "$output" | wc -l)"
  [ "$line_count" -eq 500 ]
  ! echo "$output" | grep -q '\[evicted\]'
  [ ! -d "$SPEC_DIR/.tool-results" ]
}

# ===== Read-only degradation =====

@test "evict-tool-result: read-only spec degrades gracefully" {
  local ro_dir="$TEST_TMP/readonly"
  mkdir -p "$ro_dir"
  local input
  input="$(seq 1 150 | sed 's/^/line /')"
  chmod -R a-w "$ro_dir"
  local output
  output="$(echo "$input" | bash "$EVICTION_SCRIPT" "$ro_dir" grep 2>/dev/null)"
  # Should pass through all input (degradation)
  local line_count
  line_count="$(echo "$output" | wc -l)"
  [ "$line_count" -ge 150 ]
}
