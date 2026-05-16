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
# Usage: run_check [--agent A] [--task T] [--paths P] [--command C]
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

@test "bats harness is operational" {
    [ -f "$SCRIPT_PATH" ]
    [ -f "$TEST_TMP/signals.jsonl" ]
    [ -n "$TEST_TMP" ]
}
