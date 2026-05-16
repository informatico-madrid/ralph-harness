#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"
@test "grep-pair-debug-dirty" {
    local fixture="${REPO_ROOT}/plugins/ralphharness/tests/fixtures/with-pair-debug-logs.txt"
    mkdir -p "$(dirname "$fixture")"
    printf 'PAIR-DEBUG: suspect variable x=5\nPAIR-DEBUG: hypothesis under test: x causes failure\n' > "$fixture"
    local result=$(grep -c 'PAIR-DEBUG:' "$fixture")
    [ "$result" -gt 0 ]
}

@test "grep-pair-debug-clean" {
    local fixture="${REPO_ROOT}/plugins/ralphharness/tests/fixtures/cleaned.txt"
    mkdir -p "$(dirname "$fixture")"
    printf 'normal log line\nno special markers here\n' > "$fixture"
    local result
    result=$(grep -c 'PAIR-DEBUG:' "$fixture" 2>/dev/null) || true
    [ "${result:-0}" -eq 0 ]
}
