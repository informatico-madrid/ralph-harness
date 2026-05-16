#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"
@test "driver-sections-complete" {
    local driver="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-driver.md"
    [ -f "$driver" ]
    local sections=$(grep -c '## Section' "$driver")
    [ "$sections" -ge 7 ]
}

@test "navigator-sections-complete" {
    local navigator="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-navigator.md"
    [ -f "$navigator" ]
    local sections=$(grep -c '## Section' "$navigator")
    [ "$sections" -ge 7 ]
}

@test "driver-pair-debug-marker-rule" {
    local driver="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-driver.md"
    grep -q 'PAIR-DEBUG:' "$driver"
}

@test "driver-grep-cleanup-step" {
    local driver="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-driver.md"
    grep -q 'grep.*PAIR-DEBUG' "$driver"
}

@test "navigator-never-edit-implementation" {
    local navigator="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-navigator.md"
    grep -q 'NEVER EDIT IMPLEMENTATION\|NEVER.*edit.*implementation' "$navigator"
}

@test "navigator-no-plugin-only-path" {
    local navigator="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-navigator.md"
    ! grep -q 'CLAUDE_PLUGIN_ROOT' "$navigator"
}
