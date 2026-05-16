#!/usr/bin/env bats
# pre-exec-check.bats — Tests for the pre-execution security critic script
# Maps to: design.md Test Coverage Table (Phase 3)

TEST_TMP=""
SCRIPT_PATH=""
FIXTURE_DIR=""

REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"

setup() {
    TEST_TMP=$(mktemp -d)
    FIXTURE_DIR="$REPO_ROOT/tests/fixtures/pre-exec"
    SCRIPT_PATH="$REPO_ROOT/hooks/scripts/pre-execution-check.sh"

    # Copy the signals.jsonl template into the workspace
    cp "$REPO_ROOT/templates/signals.jsonl" "$TEST_TMP/signals.jsonl"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: invoke pre-execution-check.sh and capture output/exit code
# Usage: run_check [--agent A] [--task T] [--paths P] [--command C] [--spec-path S]
# After call: CHECK_EXIT, CHECK_STDOUT, CHECK_STDERR are set
run_check() {
    local cmd="CLAUDE_PLUGIN_ROOT=$REPO_ROOT bash $SCRIPT_PATH"
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)    args+=("--agent" "$2");     shift 2 ;;
            --task)     args+=("--task" "$2");      shift 2 ;;
            --paths)    args+=("--paths" "$2");     shift 2 ;;
            --command)  args+=("--command" "$2");   shift 2 ;;
            --spec-path) args+=("--spec-path" "$2"); shift 2 ;;
        esac
    done
    local output
    output=$($cmd "${args[@]}" 2>&1) && CHECK_EXIT=0 || CHECK_EXIT=$?
    CHECK_STDOUT="$output"
}

# Helper: run check and capture stdout and stderr separately
# Usage: run_check_separate [--agent A] [--task T] [--paths P] [--command C] [--spec-path S]
# After call: SE_CHECK_EXIT, SE_CHECK_STDOUT, SE_CHECK_STDERR are set
run_check_separate() {
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)    args+=("--agent" "$2");     shift 2 ;;
            --task)     args+=("--task" "$2");      shift 2 ;;
            --paths)    args+=("--paths" "$2");     shift 2 ;;
            --command)  args+=("--command" "$2");   shift 2 ;;
            --spec-path) args+=("--spec-path" "$2"); shift 2 ;;
        esac
    done
    local _out_file _err_file
    _out_file=$(mktemp)
    _err_file=$(mktemp)
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" "${args[@]}" >"$_out_file" 2>"$_err_file" && SE_CHECK_EXIT=0 || SE_CHECK_EXIT=$?
    SE_CHECK_STDOUT=$(cat "$_out_file")
    SE_CHECK_STDERR=$(cat "$_err_file")
    rm -f "$_out_file" "$_err_file"
}

@test "bats harness is operational" {
    [ -f "$SCRIPT_PATH" ]
    [ -f "$TEST_TMP/signals.jsonl" ]
    [ -n "$TEST_TMP" ]
}

@test "in-bounds write exits 0 with allow event" {
    # Invoke with an in-bounds path (chat.md is in spec-executor Writes)
    run_check_separate --agent spec-executor --task 3.3 --paths chat.md --spec-path "$TEST_TMP"

    # 1. Assert exit code 0
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Extract the last line (the newly appended event) and verify it is valid JSON
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    # 3. Assert the event fields
    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "allow" ]
    [ "$risk" = "LOW" ]
    [ "$layer" = "none" ]
}

@test "Layer 1 Denylist write hard-blocks (exit 2)" {
    # .ralph-state.json is in spec-executor Denylist in the fixture
    run_check_separate --agent spec-executor --task 3.4 --paths '.ralph-state.json' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (hard-block)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=block layer=role-contract
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=block'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=role-contract'

    # 3. Assert stderr mentions Layer 1 / role-contract
    echo "$SE_CHECK_STDERR" | grep -qi 'layer[ -]*1\|role-contract\|denylist'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "block" ]
    [ "$layer" = "role-contract" ]
}

@test "Layer 1 write outside the Writes set hard-blocks (exit 2)" {
    # docs/guide.md is NOT covered by any spec-executor Writes pattern
    # (Writes: .progress-task-*.md, chat.md, chat.executor.lastReadLine, src/*.ts)
    # and is NOT in the Denylist either — Writes miss = violation
    run_check_separate --agent spec-executor --task 3.6 --paths 'docs/guide.md' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (hard-block)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=block layer=role-contract
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=block'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=role-contract'

    # 3. Assert stderr mentions Layer 1 / role-contract / not in writes
    echo "$SE_CHECK_STDERR" | grep -qi 'layer[ -]*1\|role-contract\|not in writes'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "block" ]
    [ "$layer" = "role-contract" ]
}

@test "Layer 1 missing role-contracts.md → UNKNOWN/confirm" {
    # Use a temp empty dir where references/role-contracts.md does not exist.
    # This forces Layer 1 to return UNKNOWN via emit_unknown.
    local empty_dir
    empty_dir=$(mktemp -d)

    # Copy the signals.jsonl template into the workspace
    cp "$REPO_ROOT/templates/signals.jsonl" "$empty_dir/signals.jsonl"

    # Run the check with CLAUDE_PLUGIN_ROOT pointing to the empty dir
    local _out_file _err_file
    _out_file=$(mktemp)
    _err_file=$(mktemp)
    set +e
    CLAUDE_PLUGIN_ROOT="$empty_dir" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 9.9 --paths chat.md --spec-path "$empty_dir" \
        >"$_out_file" 2>"$_err_file"
    local exit_code=$?
    set -e
    local stdout stderr
    stdout=$(cat "$_out_file")
    stderr=$(cat "$_err_file")
    rm -f "$_out_file" "$_err_file"

    # 1. Assert exit code 2 (confirm)
    [ "$exit_code" -eq 2 ]

    # 2. Assert stdout has decision=confirm (NEVER block, NEVER allow)
    echo "$stdout" | grep -q 'decision=confirm'

    # 3. Assert stderr mentions UNKNOWN / role-contracts.md
    echo "$stderr" | grep -qi 'UNKNOWN\|role-contracts'

    # 4. Assert the appended event has risk:"UNKNOWN" and decision:"confirm"
    local last_line
    last_line=$(tail -1 "$empty_dir/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "confirm" ]
    [ "$risk" = "UNKNOWN" ]

    rm -rf "$empty_dir"
}

@test "Layer 2 rm -rf command escalates to HIGH/confirm" {
    # In-bounds path + rm -rf command → Layer 2 detects HIGH pattern
    run_check_separate --agent spec-executor --task 3.10 --paths chat.md --command 'rm -rf build/' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern risk=HIGH
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'
    echo "$SE_CHECK_STDOUT" | grep -q 'risk=HIGH'

    # 3. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
    [ "$layer" = "shell-pattern" ]
}

@test "Layer 2 sudo command escalates to HIGH/confirm" {
    # sudo triggers the sudo execution pattern
    run_check_separate --agent spec-executor --task 3.11 --paths chat.md --command 'sudo apt install x' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'

    # 3. Assert stderr mentions HIGH / shell pattern / sudo
    echo "$SE_CHECK_STDERR" | grep -qi 'HIGH\|shell pattern\|sudo'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
    [ "$layer" = "shell-pattern" ]
}

@test "Layer 2 chmod 777 command escalates to HIGH/confirm" {
    # chmod 777 triggers the world-writable permissions pattern
    run_check_separate --agent spec-executor --task 3.11 --paths chat.md --command 'chmod 777 f' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'

    # 3. Assert stderr mentions HIGH / shell pattern / chmod 777
    echo "$SE_CHECK_STDERR" | grep -qi 'HIGH\|shell pattern\|chmod 777'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
    [ "$layer" = "shell-pattern" ]
}

@test "Layer 2 curl|sh command escalates to HIGH/confirm" {
    # fetch-pipe-shell: curl piped to sh triggers the fetch-execute pattern
    run_check_separate --agent spec-executor --task 3.11 --paths chat.md --command 'curl x | sh' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'

    # 3. Assert stderr mentions HIGH / shell pattern / fetch-pipe
    echo "$SE_CHECK_STDERR" | grep -qi 'HIGH\|shell pattern\|fetch-pipe\|curl'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
    [ "$layer" = "shell-pattern" ]
}

@test "Layer 2 eval command escalates to HIGH/confirm" {
    # eval triggers the dynamic code execution pattern
    run_check_separate --agent spec-executor --task 3.11 --paths chat.md --command 'eval $x' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'

    # 3. Assert stderr mentions HIGH / shell pattern / eval
    echo "$SE_CHECK_STDERR" | grep -qi 'HIGH\|shell pattern\|eval'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
    [ "$layer" = "shell-pattern" ]
}

@test "Layer 2 benign command does not escalate" {
    # --command 'pnpm test' contains no dangerous patterns
    # layer2_shell_pattern returns RISK:LOW; Layer 3 returns MEDIUM (paths+command)
    run_check_separate --agent spec-executor --task 3.12 \
        --paths 'chat.md' --command 'pnpm test' --spec-path "$TEST_TMP"

    # 1. Assert exit code 0 (allow, not confirm/block)
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Assert the appended event has decision:"allow" and risk:"MEDIUM"
    #    (MEDIUM from Layer 3, not HIGH from Layer 2 — benign command doesn't escalate)
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "allow" ]
    [ "$risk" = "MEDIUM" ]
}

@test "Layer 2 absent command does not escalate" {
    # No --command → layer2_shell_pattern returns RISK:LOW
    # With in-bounds paths, overall verdict should be allow (exit 0)
    run_check_separate --agent spec-executor --task 3.12 \
        --paths 'chat.md' --spec-path "$TEST_TMP"

    # 1. Assert exit code 0 (allow, not confirm/block)
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Assert the appended event has decision:"allow" and risk:"LOW"
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "allow" ]
    [ "$risk" = "LOW" ]
}

@test "Layer 3 task with no Files field routes to UNKNOWN/confirm" {
    # No --paths argument (simulates a task with no **Files:** field)
    # Both Layer 1 and Layer 3 detect missing paths → UNKNOWN
    local empty_dir
    empty_dir=$(mktemp -d)

    # Copy the signals.jsonl template into the workspace
    cp "$REPO_ROOT/templates/signals.jsonl" "$empty_dir/signals.jsonl"

    # Run the check with NO --paths argument
    local _out_file _err_file
    _out_file=$(mktemp)
    _err_file=$(mktemp)
    set +e
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.14 --spec-path "$empty_dir" \
        >"$_out_file" 2>"$_err_file"
    local exit_code=$?
    set -e
    local stdout stderr
    stdout=$(cat "$_out_file")
    stderr=$(cat "$_err_file")
    rm -f "$_out_file" "$_err_file"

    # 1. Assert exit code 2 (confirm)
    [ "$exit_code" -eq 2 ]

    # 2. Assert stdout has decision=confirm
    echo "$stdout" | grep -q 'decision=confirm'

    # 3. Assert stderr mentions UNKNOWN / no paths
    echo "$stderr" | grep -qi 'UNKNOWN\|no paths'

    # 4. Assert the appended event has risk:"UNKNOWN" and decision:"confirm"
    local last_line
    last_line=$(tail -1 "$empty_dir/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "confirm" ]
    [ "$risk" = "UNKNOWN" ]

    rm -rf "$empty_dir"
}

@test "combiner: Denylist + rm -rf together, Layer 1 wins" {
    # Both a Denylist path AND a dangerous command; Layer 1 hard-block must win
    run_check_separate --agent spec-executor --task 3.15 \
        --paths '.ralph-state.json' --command 'rm -rf x' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (block)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=block layer=role-contract
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=block'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=role-contract'

    # 3. Assert stderr mentions Layer 1 / role-contract
    echo "$SE_CHECK_STDERR" | grep -qi 'layer[ -]*1\|role-contract\|denylist'

    # 4. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk layer
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    layer=$(echo "$last_line" | jq -r '.layer')
    [ "$decision" = "block" ]
    [ "$layer" = "role-contract" ]
}

@test "ConfirmRisky LOW -> allow, exit 0" {
    # In-bounds path + no command -> Layer 1 clear(LOW) + Layer 2 LOW + Layer 3 LOW
    run_check_separate --agent spec-executor --task 3.16 \
        --paths 'chat.md' --spec-path "$TEST_TMP"

    # 1. Assert exit code 0 (allow)
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Assert the appended event has decision:"allow" and risk:"LOW"
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "allow" ]
    [ "$risk" = "LOW" ]
}

@test "ConfirmRisky MEDIUM -> allow, exit 0" {
    # In-bounds path + benign command -> Layer 1 clear(LOW) + Layer 2 LOW + Layer 3 MEDIUM
    run_check_separate --agent spec-executor --task 3.16 \
        --paths 'chat.md' --command 'pnpm test' --spec-path "$TEST_TMP"

    # 1. Assert exit code 0 (allow)
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Assert the appended event has decision:"allow" and risk:"MEDIUM"
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "allow" ]
    [ "$risk" = "MEDIUM" ]
}

@test "ConfirmRisky HIGH -> confirm, exit 2" {
    # In-bounds path + rm -rf -> Layer 1 clear + Layer 2 HIGH + Layer 3 MEDIUM
    run_check_separate --agent spec-executor --task 3.16 \
        --paths 'chat.md' --command 'rm -rf x' --spec-path "$TEST_TMP"

    # 1. Assert exit code 2 (confirm)
    [ "$SE_CHECK_EXIT" -eq 2 ]

    # 2. Assert stdout has decision=confirm layer=shell-pattern risk=HIGH
    echo "$SE_CHECK_STDOUT" | grep -q 'decision=confirm'
    echo "$SE_CHECK_STDOUT" | grep -q 'layer=shell-pattern'
    echo "$SE_CHECK_STDOUT" | grep -q 'risk=HIGH'

    # 3. Assert the appended event has correct fields
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "confirm" ]
    [ "$risk" = "HIGH" ]
}

@test "ConfirmRisky UNKNOWN -> confirm, exit 2" {
    # Empty dir -> no role-contracts.md -> Layer 1 UNKNOWN dominates
    local empty_dir
    empty_dir=$(mktemp -d)

    cp "$REPO_ROOT/templates/signals.jsonl" "$empty_dir/signals.jsonl"

    local _out_file _err_file
    _out_file=$(mktemp)
    _err_file=$(mktemp)
    set +e
    CLAUDE_PLUGIN_ROOT="$empty_dir" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.16 --paths 'chat.md' \
        --spec-path "$empty_dir" \
        >"$_out_file" 2>"$_err_file"
    local exit_code=$?
    set -e
    local stdout stderr
    stdout=$(cat "$_out_file")
    stderr=$(cat "$_err_file")
    rm -f "$_out_file" "$_err_file"

    # 1. Assert exit code 2 (confirm)
    [ "$exit_code" -eq 2 ]

    # 2. Assert stdout has decision=confirm
    echo "$stdout" | grep -q 'decision=confirm'

    # 3. Assert stderr mentions UNKNOWN / role-contracts
    echo "$stderr" | grep -qi 'UNKNOWN\|role-contracts'

    # 4. Assert the appended event has risk:"UNKNOWN" and decision:"confirm"
    local last_line
    last_line=$(tail -1 "$empty_dir/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    local decision risk
    decision=$(echo "$last_line" | jq -r '.decision')
    risk=$(echo "$last_line" | jq -r '.risk')
    [ "$decision" = "confirm" ]
    [ "$risk" = "UNKNOWN" ]

    rm -rf "$empty_dir"
}

@test "determinism — identical inputs produce identical decision output" {
    # Run the script twice with the same arguments; assert matching exit code
    # and matching stdout.  The appended event payload must also be identical
    # apart from the `timestamp` field.
    local run1_dir run2_dir
    run1_dir=$(mktemp -d)
    run2_dir=$(mktemp -d)

    cp "$REPO_ROOT/templates/signals.jsonl" "$run1_dir/signals.jsonl"
    cp "$REPO_ROOT/templates/signals.jsonl" "$run2_dir/signals.jsonl"

    local _o1 _e1 _o2 _e2
    _o1=$(mktemp); _e1=$(mktemp)
    _o2=$(mktemp); _e2=$(mktemp)

    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.20 \
        --paths 'chat.md' --command 'pnpm test' \
        --spec-path "$run1_dir" >"$_o1" 2>"$_e1" && RC1=0 || RC1=$?
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.20 \
        --paths 'chat.md' --command 'pnpm test' \
        --spec-path "$run2_dir" >"$_o2" 2>"$_e2" && RC2=0 || RC2=$?

    # 1. Exit codes must match
    [ "$RC1" -eq "$RC2" ]

    # 2. stdout must match (decision line is deterministic)
    [ "$(cat "$_o1")" = "$(cat "$_o2")" ]

    # 3. Event payloads must match modulo timestamp
    local e1 e2
    e1=$(tail -1 "$run1_dir/signals.jsonl")
    e2=$(tail -1 "$run2_dir/signals.jsonl")

    # Remove the timestamp field for comparison
    local e1_no_ts e2_no_ts
    e1_no_ts=$(echo "$e1" | jq 'del(.timestamp)')
    e2_no_ts=$(echo "$e2" | jq 'del(.timestamp)')
    [ "$e1_no_ts" = "$e2_no_ts" ]

    rm -f "$_o1" "$_e1" "$_o2" "$_e2"
    rm -rf "$run1_dir" "$run2_dir"
}

@test "speed — single invocation completes in < 100 ms" {
    local sp_dir
    sp_dir=$(mktemp -d)
    cp "$REPO_ROOT/templates/signals.jsonl" "$sp_dir/signals.jsonl"

    local _o _e
    _o=$(mktemp); _e=$(mktemp)

    local t_start_ns t_end_ns elapsed_ms
    t_start_ns=$(date +%s%N)
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.20.speed \
        --paths 'chat.md' --command 'pnpm test' \
        --spec-path "$sp_dir" >"$_o" 2>"$_e" && _rc=0 || _rc=$?
    t_end_ns=$(date +%s%N)

    # Convert nanoseconds to milliseconds
    elapsed_ms=$(( (t_end_ns - t_start_ns) / 1000000 ))

    # Assert < 100 ms (NFR-2)
    [ "$elapsed_ms" -lt 100 ]

    rm -f "$_o" "$_e"
    rm -rf "$sp_dir"
}

@test "audit append: one valid line, schema-conformant, immutable" {
    # Seed signals.jsonl with one prior event line (a control event).
    # Store its canonical SHA so we can verify byte-identity after script invocation.
    local prior_line='{"signal":"PENDING","status":"active","timestamp":"2026-05-16T10:00:00Z"}'
    printf '%s\n' "$prior_line" > "$TEST_TMP/signals.jsonl"
    local prior_sha
    prior_sha=$(printf '%s\n' "$prior_line" | jq -c .)

    # Line count before invocation
    local lines_before
    lines_before=$(wc -l < "$TEST_TMP/signals.jsonl")

    # Invoke with an in-bounds path
    run_check_separate --agent spec-executor --task 3.18 --paths chat.md --spec-path "$TEST_TMP"

    # 1. Assert the script exits 0 (allow)
    [ "$SE_CHECK_EXIT" -eq 0 ]

    # 2. Assert exactly one new line was appended
    local lines_after
    lines_after=$(wc -l < "$TEST_TMP/signals.jsonl")
    [ "$lines_after" -eq $(( lines_before + 1 )) ]

    # 3. Assert the new (last) line is valid JSON
    local last_line
    last_line=$(tail -1 "$TEST_TMP/signals.jsonl")
    [ "$(echo "$last_line" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]

    # 4. Assert the new line matches the securityDecisionEvent schema:
    #    required fields: type, decision, layer, risk, agent, task, reason, timestamp, iteration
    local schema_check
    schema_check=$(echo "$last_line" | jq -e '
        .type        == "security-decision" and
        (.decision  == "allow" or .decision == "block" or .decision == "confirm") and
        (.layer     == "role-contract" or .layer == "shell-pattern" or .layer == "risk" or .layer == "none") and
        (.risk      == "LOW" or .risk == "MEDIUM" or .risk == "HIGH" or .risk == "UNKNOWN") and
        (.agent     | type) == "string" and
        (.task      | type) == "string" and
        (.reason    | type) == "string" and
        (.timestamp | type) == "string" and
        (.iteration | type) == "number" and
        (.iteration >= 1) and
        ((.path  | type) == "string" or (.path  == null)) and
        ((.command | type) == "string" or (.command == null))
    ' 2>/dev/null)
    [ "$schema_check" = "true" ]

    # 5. Assert the pre-existing line is byte-identical (immutability)
    local first_line_after
    first_line_after=$(head -1 "$TEST_TMP/signals.jsonl")
    first_line_after=$(echo "$first_line_after" | jq -c .)
    [ "$first_line_after" = "$prior_sha" ]
}

@test "replay-signals.sh over security-decision events" {
    # Build a temp log mixing control and security-decision events.
    # Run pre-execution-check.sh to generate a security-decision event.
    # Run replay-signals.sh and assert it completes without error
    # and the security decision is visible in output.

    local _dir="$TEST_TMP/replay"
    mkdir -p "$_dir"

    # Copy the signals.jsonl template into the workspace
    cp "$REPO_ROOT/templates/signals.jsonl" "$_dir/signals.jsonl"

    # Add a control event at iteration 1 so replay has something to surface
    printf '{"type":"control","signal":"ACK","from":"coordinator","to":"external-reviewer","task":"3.19","status":"active","timestamp":"2026-05-16T00:00:00Z","iteration":1,"reason":"test ack"}\n' >> "$_dir/signals.jsonl"

    # Add a standalone security-decision event at iteration 1
    local sec_event
    sec_event=$(jq -c -n '{
      type:"security-decision",
      decision:"allow",
      layer:"none",
      risk:"LOW",
      agent:"spec-executor",
      task:"3.19",
      path:"chat.md",
      command:null,
      reason:"automated security decision",
      timestamp:"2026-05-16T00:00:01Z",
      iteration:1
    }')
    echo "$sec_event" >> "$_dir/signals.jsonl"

    # Write iteration = 2 into .ralph-state.json so the replay picks up iteration 1 events
    jq -n '{globalIteration: 2}' > "$_dir/.ralph-state.json"

    # Run the pre-execution check to generate an additional security-decision event
    local _out _err
    _out=$(mktemp); _err=$(mktemp)
    set +e
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" \
        --agent spec-executor --task 3.19 --paths 'chat.md' \
        --spec-path "$_dir" >"$_out" 2>"$_err"
    local check_exit=$?
    set -e
    local check_stdout
    check_stdout=$(cat "$_out")
    rm -f "$_out" "$_err"

    # 1. pre-execution-check.sh should succeed (allow in-bounds chat.md write)
    [ "$check_exit" -eq 0 ]

    # 2. Verify a security-decision event was appended to signals.jsonl
    local appended
    appended=$(tail -1 "$_dir/signals.jsonl")
    [ "$(echo "$appended" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)" = "ok" ]
    local app_type
    app_type=$(echo "$appended" | jq -r '.type')
    [ "$app_type" = "security-decision" ]

    # 3. Run replay-signals.sh and assert it completes without error
    local RS_SCRIPT="$REPO_ROOT/hooks/scripts/replay-signals.sh"
    [ -f "$RS_SCRIPT" ]
    local replay_out
    replay_out=$(bash "$RS_SCRIPT" "$_dir" --at-iteration 2)
    local replay_exit=$?
    [ "$replay_exit" -eq 0 ]

    # 4. Assert the replayed output contains evidence of the security-decision event
    #    (task ID, agent name, decision type, or "security-decision")
    echo "$replay_out" | grep -q "3.19"

    rm -rf "$_dir"
}
