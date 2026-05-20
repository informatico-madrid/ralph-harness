#!/usr/bin/env bats
# Bats suite for emit_task_metric(): advancement pass / iteration fail / count.
#
# Tests: taskIndex advancement → pass line for index-1 + state updated,
# taskIteration increase without index advancement → fail line for current index,
# multiple advancements → N metric lines, zero empty lines.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

setup() {
    # Source lib-signals.sh for append_signal helper (used by emitted DEADLOCK if needed)
    source "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
    mkdir -p "specs/fixture-multiphase"
    SPEC_PATH="specs/fixture-multiphase"
    STATE_FILE="$SPEC_PATH/.ralph-state.json"
    TASKS_FILE="$SPEC_PATH/tasks.md"
    METRICS_FILE="$SPEC_PATH/.metrics.jsonl"

    # Create a minimal state file
    jq -n '{
        spec: "fixture-multiphase",
        taskIndex: 0,
        taskIteration: 0,
        lastMetricTaskIndex: -1,
        lastMetricIteration: -1
    }' > "$STATE_FILE"

    # Create a tasks.md
    cat > "$TASKS_FILE" << 'TASKSEOF'
---
spec: fixture-multiphase
---

# Tasks: fixture

- [ ] 0.1 Initial task
- [ ] 1.1 Phase 2 task
- [ ] 2.1 Phase 3 task
TASKSEOF

    # Ensure a .metrics.jsonl exists (empty)
    : > "$METRICS_FILE"

    # Ensure git repo (commit_sha lookup in emit_task_metric)
    git init -q . 2>/dev/null || true
    git config user.email "test@test.com" 2>/dev/null || true
    git config user.name "Test" 2>/dev/null || true
    git add -A 2>/dev/null && git commit -q -m "initial" 2>/dev/null || true

    # Set CWD and CLAUDE_PLUGIN_ROOT for emit_task_metric
    export CWD="$FIXTURE_DIR"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

    # Inline emit_task_metric() — copied from stop-watcher.sh (same logic)
    emit_task_metric() {
        local spec_path="$1"
        local state_file="$2"

        if [ ! -f "$state_file" ]; then
            return 0
        fi

        local task_index task_iteration last_metric_task_index last_metric_iteration
        task_index=$(jq -r '.taskIndex // 0' "$state_file" 2>/dev/null || echo "0")
        task_iteration=$(jq -r '.taskIteration // 0' "$state_file" 2>/dev/null || echo "0")
        last_metric_task_index=$(jq -r '.lastMetricTaskIndex // -1' "$state_file" 2>/dev/null || echo "-1")
        last_metric_iteration=$(jq -r '.lastMetricIteration // -1' "$state_file" 2>/dev/null || echo "-1")

        local status="pass"
        if [ "$task_index" -gt "$last_metric_task_index" ] 2>/dev/null; then
            status="pass"
        elif [ "$task_index" -eq "$last_metric_task_index" ] && [ "$task_iteration" -gt "$last_metric_iteration" ] 2>/dev/null; then
            status="fail"
        else
            return 0
        fi

        local commit_sha
        commit_sha=$(git -C "$spec_path" log -1 --format=%H 2>/dev/null || echo "unknown")

        local task_name="unknown"
        local tasks_file="$CWD/$spec_path/tasks.md"
        if [ -f "$tasks_file" ]; then
            task_name=$(awk -v idx="$task_index" '
                /^- \[[ x]\]/ && c == idx {
                    sub(/^[- ]* \[[ x]\] /, "")
                    print
                    exit
                }
                /^- \[[ x]\]/ { c++ }
            ' "$tasks_file")
        fi

        source "$CLAUDE_PLUGIN_ROOT/plugins/ralphharness/hooks/scripts/write-metric.sh" 2>/dev/null || true

        local task_id="${task_index}.${task_iteration}"

        local write_exit=0
        write_metric "$spec_path" "$status" "$task_index" "$task_iteration" "0" "$task_name" "implementation" "$task_id" "$commit_sha" || write_exit=$?
        if [ "$write_exit" -ne 0 ]; then
            echo "[harness][metric] WARN: write_metric failed (exit $write_exit)" >> "$spec_path/.progress.md" 2>/dev/null
        fi

        local tmp="${state_file}.tmp"
        if jq --argjson ti "$task_index" --argjson ti2 "$task_iteration" \
            '.lastMetricTaskIndex = $ti | .lastMetricIteration = $ti2' \
            "$state_file" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$state_file"
        else
            rm -f "$tmp"
        fi

        return 0
    }
}

teardown() {
    if [ -d "$FIXTURE_DIR" ]; then
        chmod -R u+w "$FIXTURE_DIR" 2>/dev/null || true
    fi
    rm -rf "$FIXTURE_DIR"
}

# ---- Case 1: taskIndex advanced → pass line for index-1 + state updated ----
@test "taskIndex advancement emits pass metric and updates lastMetricTaskIndex" {
    # Start at taskIndex=0, lastMetricTaskIndex=-1 → advancement → pass for index 0
    local rc
    emit_task_metric "$SPEC_PATH" "$STATE_FILE"
    rc=$?
    [ "$rc" -eq 0 ]

    # Verify .metrics.jsonl has one line with status pass and taskIndex 0
    grep -q '"status":"pass"' "$METRICS_FILE"
    grep -q '"taskIndex":0' "$METRICS_FILE"

    # Verify lastMetricTaskIndex updated in state
    local lmtd
    lmtd=$(jq -r '.lastMetricTaskIndex' "$STATE_FILE")
    [ "$lmtd" -eq 0 ]

    local lmdi
    lmdi=$(jq -r '.lastMetricIteration' "$STATE_FILE")
    [ "$lmdi" -eq 0 ]
}

# ---- Case 2: taskIteration up no advance → fail line for current index ----
@test "taskIteration increase without index advancement emits fail metric" {
    # Advance to taskIndex=2 first
    jq '.taskIndex = 2 | .taskIteration = 0 | .lastMetricTaskIndex = 2 | .lastMetricIteration = 0' \
        "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    # Now increase iteration only → fail for current index
    jq '.taskIteration = 1' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    local rc
    emit_task_metric "$SPEC_PATH" "$STATE_FILE"
    rc=$?
    [ "$rc" -eq 0 ]

    # Verify .metrics.jsonl has one line with status fail and taskIndex 2
    grep -q '"status":"fail"' "$METRICS_FILE"
    grep -q '"taskIndex":2' "$METRICS_FILE"

    # lastMetricIteration should be updated to 1
    local lmdi
    lmdi=$(jq -r '.lastMetricIteration' "$STATE_FILE")
    [ "$lmdi" -eq 1 ]
}

# ---- Case 3: N advancements → N metric lines, zero empty lines ----
@test "multiple task advancements produce one line per advancement" {
    # Reset state and reset metrics file
    : > "$METRICS_FILE"
    jq '{taskIndex:0, taskIteration:0, lastMetricTaskIndex:-1, lastMetricIteration:-1}' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    # Cycle 1: taskIndex=0, lastMetricTaskIndex=-1 → advancement → pass for index 0
    emit_task_metric "$SPEC_PATH" "$STATE_FILE"

    # Cycle 2: set taskIndex=1, lastMetricTaskIndex=0 → advancement → pass for index 1
    jq '.taskIndex = 1 | .lastMetricTaskIndex = 0' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    emit_task_metric "$SPEC_PATH" "$STATE_FILE"

    # Cycle 3: set taskIndex=2, lastMetricTaskIndex=1 → advancement → pass for index 2
    jq '.taskIndex = 2 | .lastMetricTaskIndex = 1' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    emit_task_metric "$SPEC_PATH" "$STATE_FILE"

    # Count non-empty lines in .metrics.jsonl
    local line_count
    line_count=$(grep -c . "$METRICS_FILE")
    [ "$line_count" -eq 3 ]

    # Verify zero empty lines (use grep | wc pattern to handle grep exit code)
    local empty_count
    empty_count=$(grep -c '^$' "$METRICS_FILE" 2>/dev/null || true)
    empty_count=${empty_count:-0}
    empty_count=$(echo "$empty_count" | tr -d '[:space:]')
    [ "$empty_count" -eq 0 ]

    # Verify all three statuses are pass
    local pass_count
    pass_count=$(grep -c '"status":"pass"' "$METRICS_FILE")
    [ "$pass_count" -eq 3 ]

    # Verify indices 0, 1, 2 each appear exactly once
    local idx0
    idx0=$(grep -c '"taskIndex":0' "$METRICS_FILE")
    [ "$idx0" -eq 1 ]
    local idx1
    idx1=$(grep -c '"taskIndex":1' "$METRICS_FILE")
    [ "$idx1" -eq 1 ]
    local idx2
    idx2=$(grep -c '"taskIndex":2' "$METRICS_FILE")
    [ "$idx2" -eq 1 ]
}
