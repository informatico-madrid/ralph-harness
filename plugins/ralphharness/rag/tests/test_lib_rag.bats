#!/usr/bin/env bats
# bats tests for lib-rag.sh

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../../hooks/scripts/lib-rag.sh"
}

@test "rag_enabled returns 1 (failure) when disabled" {
    run rag_enabled
    [ "$status" -ne 0 ]
}

@test "rag_retrieve returns empty when disabled" {
    run rag_retrieve "test query" "test_collection" 3
    [ -z "$output" ]
}

@test "rag_index_task returns 0 when disabled" {
    run rag_index_task "test-spec" "/dev/null"
    [ "$status" -eq 0 ]
}

@test "rag_health_check returns 1 (failure) when disabled" {
    run rag_health_check
    [ "$status" -ne 0 ]
}

@test "disabled path writes metrics" {
    local metrics_dir="${HOME:-/tmp}/.cache/smart-ralph/rag"
    mkdir -p "$metrics_dir" 2>/dev/null || true
    local metrics_log="$metrics_dir/retrieval-metrics.log"
    rm -f "$metrics_log" 2>/dev/null || true

    run rag_retrieve "query" "col" 3

    [ -f "$metrics_log" ]
}
