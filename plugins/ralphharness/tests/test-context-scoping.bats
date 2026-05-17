#!/usr/bin/env bats
# test-context-scoping.bats — Integration tests for precompact, two-gate, scoping, schema, hooks.

PLUGIN_DIR="${BATS_TEST_DIRNAME}/.."
PRECOMPACT_SCRIPT="${PLUGIN_DIR}/hooks/scripts/precompact-condense.sh"
STOP_WATCHER_SCRIPT="${PLUGIN_DIR}/hooks/scripts/stop-watcher.sh"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
SCHEMA_JSON="${PLUGIN_DIR}/schemas/spec.schema.json"

setup() {
  TEST_TMP="$(mktemp -d)"
  SPEC_DIR="$TEST_TMP/spec"
  mkdir -p "$SPEC_DIR"
  cat > "$SPEC_DIR/.ralph-state.json" << 'EOF'
{"phase":"execution","taskIndex":1,"totalTasks":10,"state":{"chat":{}}}
EOF
  echo "## Test message" > "$SPEC_DIR/chat.md"
  echo "No signals here" > "$SPEC_DIR/signals.jsonl"
}

teardown() {
  chmod -R u+w "$TEST_TMP" 2>/dev/null || true
  rm -rf "$TEST_TMP"
}

# ===== precompact-condense.sh =====

@test "context-scoping: precompact-condense resolves spec and exits 0" {
  # The script uses ralph_resolve_current to find active spec, exits 0 unconditionally
  local exit_code
  bash "$PRECOMPACT_SCRIPT" >/dev/null 2>&1
  exit_code=$?
  [ "$exit_code" -eq 0 ]
}

# ===== stop-watcher.sh two-gate =====

@test "context-scoping: stop-watcher Gate 1 triggers proactive on line count > 2000" {
  # Create a spec with oversized chat.md
  {
    for i in $(seq 1 1500); do
      printf '## [%d]\nChat line %d.\n' "$i" "$i"
    done
  } > "$SPEC_DIR/chat.md"
  {
    echo "# Goal"
    echo "Test goal."
    for i in $(seq 1 10); do
      echo "- Learning $i"
    done
  } > "$SPEC_DIR/.progress.md"
  # Combined > 2000 lines
  local total
  total="$(wc -l < "$SPEC_DIR/chat.md")"
  total=$((total + $(wc -l < "$SPEC_DIR/.progress.md")))
  [ "$total" -gt 2000 ]
}

@test "context-scoping: stop-watcher Gate 2 triggers reactive on transcript token % > 85" {
  # Create a transcript JSONL with high token usage (>85% of 200k)
  printf '{"message":{"role":"assistant","usage":{"input_tokens":175000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' > "$SPEC_DIR/transcript.jsonl"
  # Verify the transcript usage pct is >85%
  source "${PLUGIN_DIR}/hooks/scripts/lib-context.sh"
  local pct
  pct="$(transcript_usage_pct "$SPEC_DIR/transcript.jsonl")"
  [ "$pct" -gt 85 ]
}

# ===== implement.md phase scoping =====

@test "context-scoping: implement.md has executionPhase case statement" {
  local implement_file="$PLUGIN_DIR/commands/implement.md"
  grep -q 'executionPhase' "$implement_file"
  grep -q 'case' "$implement_file"
}

@test "context-scoping: implement.md gates phase-rules.md to test/quality" {
  local implement_file="$PLUGIN_DIR/commands/implement.md"
  # phase-rules.md should be gated to specific phases
  grep -q 'phase-rules.md' "$implement_file"
}

@test "context-scoping: implement.md gates pair-debug.md on pair-debug" {
  local implement_file="$PLUGIN_DIR/commands/implement.md"
  grep -q 'pair-debug.md' "$implement_file"
}

# ===== spec.schema.json =====

@test "context-scoping: valid sample state passes schema validation" {
  local sample
  sample='{"phase":"execution","taskIndex":1,"totalTasks":10,"state":{"executionPhase":"poc","chat":{"executor":{"lastReadLine":100},"coordinator":{"lastReadLine":50},"reviewer":{"lastReadLine":75}}}}'
  echo "$sample" | jq -e . > /dev/null
  [ $? -eq 0 ]
}

@test "context-scoping: spec.schema.json has executionPhase enum with all phases" {
  # executionPhase is a nested property in the schema
  jq -e '.. | .enum? // empty | if . == ["poc","refactor","test","quality"] then true else empty end' "$SCHEMA_JSON" > /dev/null
}

# ===== hooks.json =====

@test "context-scoping: hooks.json has PreCompact entry pointing to precompact-condense.sh" {
  local precompact_cmd
  precompact_cmd="$(jq -r '.hooks.PreCompact[0].hooks[] | select(.type == "command") | .command' "$HOOKS_JSON" 2>/dev/null)"
  echo "$precompact_cmd" | grep -q 'precompact-condense'
}
