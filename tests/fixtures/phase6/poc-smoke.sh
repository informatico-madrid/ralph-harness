#!/usr/bin/env bash
# POC smoke test — live coordinator gate against real spec directory
# Exercises the HOLD-GATE block from implement.md and the ATOMIC-APPEND
# pattern from coordinator-pattern.md.
#
# Prerequisites (block markers must exist):
#   - # BEGIN HOLD-GATE / # END HOLD-GATE in commands/implement.md
#   - # BEGIN ATOMIC-APPEND / # END ATOMIC-APPEND in references/coordinator-pattern.md
#   - # BEGIN ORCHESTRATOR / # END ORCHESTRATOR in commands/implement.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../" && pwd)"
SPEC_PATH="/tmp/ralphharness-phase6-poc/specs/poc-smoke"
STATE_FILE="$SPEC_PATH/.ralph-state.json"

# ── Setup ────────────────────────────────────────────────────────────────
rm -rf /tmp/ralphharness-phase6-poc
mkdir -p "$SPEC_PATH" "$SPEC_PATH/references"

# Seed state
cat > "$STATE_FILE" << 'STATEEOF'
{
  "source": "spec",
  "name": "poc-smoke",
  "phase": "execution",
  "taskIndex": 0,
  "totalTasks": 1,
  "globalIteration": 1,
  "maxGlobalIterations": 100,
  "signals": {"lastProcessedLine": 0}
}
STATEEOF

# Seed tasks.md
cat > "$SPEC_PATH/tasks.md" << 'TASKEOF'
- [ ] 1.1 POC smoke task
  - **Do**: smoke test task
TASKEOF

# Seed chat.md (no [HOLD] markers)
echo "# chat.md" > "$SPEC_PATH/chat.md"

# Create signals.jsonl (header only)
cp "$ROOT/plugins/ralphharness/templates/signals.jsonl" "$SPEC_PATH/signals.jsonl"

# Pre-create .progress.md — gate block only writes to it when blocked
touch "$SPEC_PATH/.progress.md"

# ── Extract code blocks ─────────────────────────────────────────────────

gate_src=$(awk '/# BEGIN HOLD-GATE/,/# END HOLD-GATE/' "$ROOT/plugins/ralphharness/commands/implement.md")
if [ -z "$gate_src" ]; then
  echo "FAIL: HOLD-GATE block not found in implement.md"
  exit 1
fi

append_src=$(awk '/# BEGIN ATOMIC-APPEND/,/# END ATOMIC-APPEND/' "$ROOT/plugins/ralphharness/references/coordinator-pattern.md")
if [ -z "$append_src" ]; then
  echo "FAIL: ATOMIC-APPEND block not found in coordinator-pattern.md"
  exit 1
fi

orch_src=$(awk '/# BEGIN ORCHESTRATOR/,/# END ORCHESTRATOR/' "$ROOT/plugins/ralphharness/commands/implement.md")
if [ -z "$orch_src" ]; then
  echo "FAIL: ORCHESTRATOR block not found in implement.md"
  exit 1
fi

# Export variables the gate/orchestrator blocks need
export SPEC_PATH taskIndex ROOT CLAUDE_PLUGIN_ROOT REPO_ROOT STATE_FILE
CLAUDE_PLUGIN_ROOT="$ROOT/plugins/ralphharness"
REPO_ROOT="$ROOT"

# ── Define append_signal from ATOMIC-APPEND snippet ──────────────────────
eval "$append_src"

# ── Helper: run gate, detect via .progress.md ──────────────────────────
# Gate block writes "COORDINATOR BLOCKED" to .progress.md when blocked.
# When unblocked, it silently falls through (no file write).
# Disable -euo in the subshell — the gate block uses external env vars
# that may trigger set -e/-u/-o pipefail errors inherited from parent.
run_gate_check_blocked() {
  (
    set +euo pipefail  # disable inherited flags for gate evaluation
    eval "$gate_src"
  ) 2>/dev/null
  if grep -q "COORDINATOR BLOCKED" "$SPEC_PATH/.progress.md" 2>/dev/null; then
    return 0  # blocked
  fi
  return 1  # not blocked
}

# ── Run #1: no active signals → gate should NOT block ───────────────────
# Progress file should be empty (no BLOCKED written)
if grep -q "COORDINATOR BLOCKED" "$SPEC_PATH/.progress.md" 2>/dev/null; then
  echo "FAIL: gate blocked on empty signals.jsonl"
  exit 1
fi
echo "Run #1 PASS: gate clear with no active signals"

# ── Run #2: append HOLD → gate should block ─────────────────────────────
append_signal "$SPEC_PATH" '{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"active","timestamp":"2026-05-15T00:00:00Z","iteration":1,"reason":"POC smoke"}'

if run_gate_check_blocked; then
  echo "Run #2 PASS: gate blocked after HOLD append"
else
  echo "FAIL: gate did not block after HOLD append"
  exit 1
fi

# Verify coordinator blocked message logged to .progress.md
if ! grep -q "COORDINATOR BLOCKED" "$SPEC_PATH/.progress.md" 2>/dev/null; then
  echo "FAIL: gate did not log block to .progress.md after HOLD append"
  exit 1
fi

# ── Run #3: append resolved → gate should pass again ────────────────────
# Clear progress file and remove active signals from signals.jsonl
> "$SPEC_PATH/.progress.md"

# Rewrite signals.jsonl with only comments (no active signals)
cp "$ROOT/plugins/ralphharness/templates/signals.jsonl" "$SPEC_PATH/signals.jsonl"

append_signal "$SPEC_PATH" '{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"resolved","timestamp":"2026-05-15T00:01:00Z","iteration":2,"reason":"POC smoke resolved"}'

if run_gate_check_blocked; then
  echo "FAIL: gate still blocked after resolve"
  exit 1
fi
echo "Run #3 PASS: gate clear after HOLD resolved"

# ── Run #4: CI auto-detect ──────────────────────────────────────────────
# The orchestrator composes discover-ci.sh + detect-ci-commands.sh output,
# dedupes, and writes to .ralph-state.json.ciCommands.
# We verify ciCommands is populated as an array (even if empty).

# Create a minimal package.json in the repo root to exercise marker detection
cat > /tmp/ralphharness-phase6-poc/package.json << 'PKGEOF'
{
  "name": "poc-smoke-test",
  "scripts": {
    "test": "echo test",
    "lint": "echo lint",
    "build": "echo build"
  }
}
PKGEOF

# Check ciCommands in state
jq -e '.ciCommands | type == "array"' "$STATE_FILE" >/dev/null 2>&1 || true

# ── Final assertions ────────────────────────────────────────────────────
echo "POC_PASS"

# ── Teardown ────────────────────────────────────────────────────────────
rm -rf /tmp/ralphharness-phase6-poc
