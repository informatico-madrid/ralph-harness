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
    set +e
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT_PATH" "${args[@]}" >"$_out_file" 2>"$_err_file"
    SE_CHECK_EXIT=$?
    set -e
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
