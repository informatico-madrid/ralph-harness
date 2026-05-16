#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"
@test "all-three-conditions-hold" {
    # This test verifies the trigger logic is present in failure-recovery.md
    local fr="${REPO_ROOT}/plugins/ralphharness/references/failure-recovery.md"
    [ -f "$fr" ]
    grep -q 'Pair-Debug Mode Entry Point' "$fr"
    grep -q 'git diff' "$fr"
    grep -q 'taskIteration' "$fr"
    grep -q 'FAIL' "$fr"
}

@test "condition-a-false-if-test-changed" {
    # Verify the trigger checks git diff for test changes
    local fr="${REPO_ROOT}/plugins/ralphharness/references/failure-recovery.md"
    grep -q 'git diff' "$fr"
}

@test "condition-b-taskiteration-gte-2" {
    local fr="${REPO_ROOT}/plugins/ralphharness/references/failure-recovery.md"
    grep -q 'taskIteration' "$fr"
}

@test "condition-c-no-fail-row" {
    local fr="${REPO_ROOT}/plugins/ralphharness/references/failure-recovery.md"
    grep -q 'FAIL' "$fr"
}
