#!/usr/bin/env bats
# test-lib-context.bats — Unit tests for lib-context.sh helper functions.
# Tests all 5 functions: combined_line_count, transcript_usage_pct,
# spec_dir_writable, context_window_size, write_condensation_metric.

LIB_SCRIPT="${BATS_TEST_DIRNAME}/../hooks/scripts/lib-context.sh"

setup() {
  source "$LIB_SCRIPT"
  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ===== combined_line_count =====

@test "combined_line_count: correct sum of chat.md + .progress.md" {
  mkdir -p "$TEST_TMP/spec"
  printf '%s\n' $(seq 1 100) > "$TEST_TMP/spec/chat.md"
  printf '%s\n' $(seq 1 50) > "$TEST_TMP/spec/.progress.md"
  
  result="$(combined_line_count "$TEST_TMP/spec")"
  [ "$result" -eq 150 ]
}

@test "combined_line_count: missing .progress.md counts as 0" {
  mkdir -p "$TEST_TMP/spec"
  printf '%s\n' $(seq 1 200) > "$TEST_TMP/spec/chat.md"
  # No .progress.md
  
  result="$(combined_line_count "$TEST_TMP/spec")"
  [ "$result" -eq 200 ]
}

@test "combined_line_count: both files missing returns 0" {
  mkdir -p "$TEST_TMP/spec"
  # No files at all
  
  result="$(combined_line_count "$TEST_TMP/spec")"
  [ "$result" -eq 0 ]
}

# ===== transcript_usage_pct =====

@test "transcript_usage_pct: empty file returns 0" {
  touch "$TEST_TMP/empty.jsonl"
  result="$(transcript_usage_pct "$TEST_TMP/empty.jsonl")"
  [ "$result" -eq 0 ]
}

@test "transcript_usage_pct: missing file returns 0" {
  result="$(transcript_usage_pct "$TEST_TMP/nonexistent.jsonl")"
  [ "$result" -eq 0 ]
}

@test "transcript_usage_pct: malformed JSONL returns 0" {
  printf 'not json\nalso not json\n{bad json' > "$TEST_TMP/malformed.jsonl"
  result="$(transcript_usage_pct "$TEST_TMP/malformed.jsonl")"
  [ "$result" -eq 0 ]
}

@test "transcript_usage_pct: normal usage below 85% returns correct pct" {
  # 200k window, 150k tokens → 75%
  printf '{"message":{"role":"assistant","usage":{"input_tokens":150000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$TEST_TMP/normal.jsonl"
  result="$(transcript_usage_pct "$TEST_TMP/normal.jsonl")"
  [ "$result" -eq 75 ]
}

@test "transcript_usage_pct: usage above 85% returns correct pct" {
  # 200k window, 175k tokens → 87%
  printf '{"message":{"role":"assistant","usage":{"input_tokens":175000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$TEST_TMP/high.jsonl"
  result="$(transcript_usage_pct "$TEST_TMP/high.jsonl")"
  [ "$result" -eq 87 ]
}

# ===== spec_dir_writable =====

@test "spec_dir_writable: writable directory returns 0" {
  spec_dir="$TEST_TMP/writable"
  mkdir -p "$spec_dir"
  
  spec_dir_writable "$spec_dir"
  [ $? -eq 0 ]
}

@test "spec_dir_writable: non-existent directory returns 1" {
  spec_dir="$TEST_TMP/nonexistent"

  ! spec_dir_writable "$spec_dir"
}

# ===== context_window_size =====

@test "context_window_size: returns 200000" {
  result="$(context_window_size)"
  [ "$result" -eq 200000 ]
}

# ===== write_condensation_metric =====

@test "write_condensation_metric: appends valid JSONL with correct fields" {
  spec_dir="$TEST_TMP/metrics"
  mkdir -p "$spec_dir"
  
  write_condensation_metric "$spec_dir" "proactive" 2270 305 87 ".archive.20260517T120000Z.md"
  
  # Check .metrics.jsonl exists
  [ -f "$spec_dir/.metrics.jsonl" ]
  
  # Check last line is valid JSON
  last_line="$(tail -1 "$spec_dir/.metrics.jsonl")"
  echo "$last_line" | jq -e '.schemaVersion == 1' > /dev/null
  echo "$last_line" | jq -e '.event == "condensation"' > /dev/null
  echo "$last_line" | jq -e '.mode == "proactive"' > /dev/null
  echo "$last_line" | jq -e '.linesBefore == 2270' > /dev/null
  echo "$last_line" | jq -e '.linesAfter == 305' > /dev/null
  echo "$last_line" | jq -e '.tokensBeforePct == 87' > /dev/null
  echo "$last_line" | jq -e '.archivePath == ".archive.20260517T120000Z.md"' > /dev/null
}
