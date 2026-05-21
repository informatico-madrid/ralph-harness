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

@test "e2e: rag_retrieve runs Python pipeline when RAG_ENABLED=true" {
    if [ -z "${QDRANT_URL:-}" ]; then
        skip "QDRANT_URL not set"
    fi

    # Clean slate for this test
    local metrics_dir="${HOME:-/tmp}/.cache/smart-ralph/rag"
    mkdir -p "$metrics_dir" 2>/dev/null || true
    local metrics_log="$metrics_dir/retrieval-metrics.log"
    rm -f "$metrics_log" 2>/dev/null || true

    export RALPH_RAG_ENABLED=true
    export QDRANT_URL="${QDRANT_URL}"

    # Debug: show env
    echo "HOME=$HOME"
    echo "metrics_log=$metrics_log"
    echo "rag_enabled before: $(rag_enabled && echo YES || echo NO)"

    local result
    result=$(rag_retrieve "test query" "specs_tasks" 3)

    echo "result=[$result]"
    echo "metrics_file_exists=[$(test -f "$metrics_log" && echo YES || echo NO)]"
    if [ -f "$metrics_log" ]; then
        echo "metrics_content=$(cat "$metrics_log")"
    fi

    unset RALPH_RAG_ENABLED
    unset QDRANT_URL

    # The pipeline ran (exit 0). Result may be empty [] if no data in collection
    # or embedder unavailable, but the Python subprocess must have been invoked.
    # Verify: metrics log gets updated from the enabled path.
    [ -f "$metrics_log" ]
    # At least one entry with outcome should exist (ok or error)
    local outcome_match
    outcome_match=$(grep -cE '"outcome":\s*"(ok|error)"' "$metrics_log" 2>/dev/null || true)
    [ "$outcome_match" -gt 0 ]
}
