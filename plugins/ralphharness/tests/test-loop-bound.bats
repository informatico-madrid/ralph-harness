#!/usr/bin/env bats
# bats test suite for >10 cycle bound verification
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"


@test "cycle-bound-10-in-pair-debug-md" {
    local pair_debug="${REPO_ROOT}/plugins/ralphharness/references/pair-debug.md"
    [ -f "$pair_debug" ]
    grep -q '10' "$pair_debug"
}

@test "cycle-bound-10-in-collaboration-resolution" {
    local collab="${REPO_ROOT}/plugins/ralphharness/references/collaboration-resolution.md"
    [ -f "$collab" ]
    grep -q 'more than 10 times' "$collab"
}

@test "cycle-bound-10-in-driver-role-file" {
    local driver="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-driver.md"
    [ -f "$driver" ]
    grep -q '10' "$driver"
}

@test "cycle-bound-10-in-navigator-role-file" {
    local navigator="${REPO_ROOT}/plugins/ralphharness/agents/pair-debug-navigator.md"
    [ -f "$navigator" ]
    grep -q '10' "$navigator"
}

@test "cycle-bound-not-3" {
    local collab="${REPO_ROOT}/plugins/ralphharness/references/collaboration-resolution.md"
    [ -f "$collab" ]
    ! grep -q 'more than 3 times' "$collab"
}
