#!/usr/bin/env bats
# Bats suite for task-planner phase exit-gate emission rule.
#
# Asserts that a generated multi-phase tasks.md fixture has exactly one
# `[VERIFY] Phase X exit gate` as the last task of each phase block.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Build a 2-phase tasks.md fixture with proper phase exit gates.
build_good_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/tasks.md" << 'TASKEOF'
# Tasks: test-spec

## Phase 1: Make It Work

- [ ] 1.1 First task
  - **Do**:
    1. Do step 1
  - **Files**: file1.txt
  - **Done when**: Step complete
  - **Verify**: `echo PASS`
  - **Commit**: `feat: step 1`

- [ ] 1.2 Second task
  - **Do**: Do step 2
  - **Files**: file2.txt
  - **Done when**: Step complete
  - **Verify**: `echo PASS`
  - **Commit**: `feat: step 2`

- [ ] 1.G [VERIFY] Phase 1 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 1 are complete and green.
  - **Verify**: All Phase 1 `[VERIFY]` tasks above are `[x]`; `bash -n` passes on both scripts.
  - **Done when**: Phase 1 is fully satisfied; safe to advance to Phase 2.
  - **Commit**: `chore(harness): Phase 1 exit gate`

## Phase 2: Refactoring

- [ ] 2.1 Refactor task 1
  - **Do**: Do refactor step 1
  - **Files**: file3.txt
  - **Done when**: Refactored
  - **Verify**: `echo PASS`
  - **Commit**: `refactor: step 1`

- [ ] 2.2 Refactor task 2
  - **Do**: Do refactor step 2
  - **Files**: file4.txt
  - **Done when**: Refactored
  - **Verify**: `echo PASS`
  - **Commit**: `refactor: step 2`

- [ ] 2.G [VERIFY] Phase 2 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 2 are complete and green.
  - **Verify**: All Phase 2 `[VERIFY]` tasks above are `[x]`; both scripts pass `bash -n`.
  - **Done when**: Phase 2 is fully satisfied; safe to advance to Phase 3.
  - **Commit**: `chore(harness): Phase 2 exit gate`
TASKEOF
}

# Build a tasks.md fixture MISSING the Phase 2 exit gate.
build_missing_gate_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/tasks.md" << 'TASKEOF'
# Tasks: test-spec

## Phase 1: Make It Work

- [ ] 1.1 First task
  - **Do**: Do step 1
  - **Files**: file1.txt
  - **Done when**: Step complete
  - **Verify**: `echo PASS`
  - **Commit**: `feat: step 1`

- [ ] 1.G [VERIFY] Phase 1 exit gate
  - **Do**: Confirm all preceding tasks and checkpoints of Phase 1 are complete and green.
  - **Verify**: All Phase 1 `[VERIFY]` tasks above are `[x]`.
  - **Done when**: Phase 1 is fully satisfied.
  - **Commit**: `chore(harness): Phase 1 exit gate`

## Phase 2: Refactoring

- [ ] 2.1 Refactor task 1
  - **Do**: Do refactor step 1
  - **Files**: file2.txt
  - **Done when**: Refactored
  - **Verify**: `echo PASS`
  - **Commit**: `refactor: step 1`

- [ ] 2.2 Another refactor task
  - **Do**: Do refactor step 2
  - **Files**: file3.txt
  - **Done when**: Refactored
  - **Verify**: `echo PASS`
  - **Commit**: `refactor: step 2`
TASKEOF
}

setup() {
    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
}

teardown() {
    rm -rf "$FIXTURE_DIR"
}

# ---- Helper: assert phase exit-gate rule ----

# Checks that every ## Phase heading has exactly one [VERIFY] Phase N exit gate
# as the last task in that phase block (before the next ## heading or EOF).
verify_exit_gates() {
    local tasks_file="$1"
    local errors=0
    local current_phase=""
    local last_task_line=""
    local line_num=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # Detect new phase header
        if [[ "$line" =~ ^##\ Phase\ (.+) ]]; then
            # If we were in a phase, check the previous phase's last task
            if [ -n "$current_phase" ] && [ -n "$last_task_line" ]; then
                # Extract phase number from last task line
                local last_task_id
                last_task_id=$(echo "$last_task_line" | sed -n 's/^- \[[ x]\] \([0-9][0-9]*\.[0-9]*\).*/\1/p')
                # Check if it's a [VERIFY] Phase exit gate
                if ! echo "$last_task_line" | grep -q '\[VERIFY\]'; then
                    echo "FAIL: Phase '$current_phase' last task is not a [VERIFY] gate" >&2
                    errors=$((errors + 1))
                else
                    echo "OK: Phase '$current_phase' has [VERIFY] exit gate as last task" >&2
                fi
            fi
            current_phase="${BASH_REMATCH[1]}"
            last_task_line=""
            continue
        fi

        # Track the last task line (lines starting with "- [ ]" or "- [x]")
        local task_re='^- \[[ x]\]'
        if [[ "$line" =~ $task_re ]]; then
            last_task_line="$line"
        fi
    done < "$tasks_file"

    # Check the last phase (after EOF)
    if [ -n "$current_phase" ] && [ -n "$last_task_line" ]; then
        if ! echo "$last_task_line" | grep -q '\[VERIFY\]'; then
            echo "FAIL: Phase '$current_phase' last task is not a [VERIFY] gate" >&2
            errors=$((errors + 1))
        else
            echo "OK: Phase '$current_phase' has [VERIFY] exit gate as last task" >&2
        fi
    fi

    return $errors
}

# ---- Case 1: well-formed 2-phase fixture has exit gates ----
@test "well-formed 2-phase fixture has phase exit gates" {
    build_good_fixture "$FIXTURE_DIR"

    # Verify each phase has exactly one [VERIFY] Phase X exit gate as last task
    verify_exit_gates "$FIXTURE_DIR/tasks.md"
    local rc=$?
    [ "$rc" -eq 0 ]
}

# ---- Case 2: missing exit gate detected ----
@test "missing Phase exit gate is detected" {
    build_missing_gate_fixture "$FIXTURE_DIR"

    # Phase 2 is missing its exit gate — should return non-zero
    local stderr_output rc
    verify_exit_gates "$FIXTURE_DIR/tasks.md" 2>"$FIXTURE_DIR/gate_stderr" >/dev/null || rc=1
    stderr_output=$(cat "$FIXTURE_DIR/gate_stderr" 2>/dev/null || echo "")
    [ "${rc:-0}" -ne 0 ]
    [[ "$stderr_output" == *"FAIL"* ]]
}

# ---- Case 3: verify exit gate has correct naming pattern ----
@test "exit gate names match [VERIFY] Phase N pattern" {
    build_good_fixture "$FIXTURE_DIR"

    # Count all [VERIFY] exit gates and verify their naming
    local gate_count=0
    local task_file="$FIXTURE_DIR/tasks.md"
    local found_count=0

    while IFS= read -r line; do
        if echo "$line" | grep -q '\[VERIFY\] Phase [0-9]* exit gate'; then
            found_count=$((found_count + 1))
        fi
    done < "$task_file"

    [ "$found_count" -eq 2 ]
}
