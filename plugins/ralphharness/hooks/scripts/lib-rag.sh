#!/usr/bin/env bash
# lib-rag.sh — Bash hooks for the RAG integration module.
#
# Provides rag_enabled, rag_retrieve, and rag_index_task functions
# that wrap the Python rag module. When RAG is disabled, all functions
# return immediately with zero overhead (zero subprocess calls).
#
# Usage: source lib-rag.sh
#   rag_enabled                    # Returns 0 if RAG enabled, 1 otherwise
#   rag_retrieve "$query" "$col" "$top_k"  # Retrieves chunks, prints TSV to stdout
#   rag_index_task "$spec" "$task_path"  # Indexes a completed task (async)

# Prevent double sourcing
if [ -n "${_RAG_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_RAG_LOADED=1

# ── rag_enabled ──────────────────────────────────────────────────────────
# Returns 0 if RAG is enabled in config, 1 otherwise.
# When disabled, no subprocess is spawned.

rag_enabled() {
    # Fast path: check RAG_ENABLED env var (bypasses file I/O)
    if [ -n "$RAG_ENABLED" ]; then
        case "$RAG_ENABLED" in
            true|yes|1) return 0 ;;
            *) return 1 ;;
        esac
    fi

    # Check if Python module is available
    if ! command -v python >/dev/null 2>&1; then
        return 1
    fi

    # Quick check: does the Python module exist?
    if ! PYTHONPATH=. python -c "import plugins.ralphharness.rag.config" 2>/dev/null; then
        return 1
    fi

    # Check if RAG is enabled
    local enabled
    enabled=$(PYTHONPATH=. python -c "from plugins.ralphharness.rag.config import RAGConfig; print(RAGConfig.load().enabled)" 2>/dev/null) || true

    case "$enabled" in
        True|true) return 0 ;;
        *) return 1 ;;
    esac
}

# ── rag_retrieve ─────────────────────────────────────────────────────────
# Retrieve relevant chunks for a query.
#
# Usage: rag_retrieve "$query" "$collection" "$top_k"
#
# Output: TSV lines path\tscore\tcontent\n (empty on disabled/error)
# Exit code: 0 always (never blocks the loop)

rag_retrieve() {
    local query="${1:-}"
    local collection="${2:-}"
    local top_k="${3:-3}"

    # Disabled path: emit disabled metric and return
    if ! rag_enabled; then
        _rag_emit_disabled_metric "$query" "$collection" "$top_k"
        return 0
    fi

    # Enabled path: call Python module with timeout
    local result
    result=$(timeout 2s PYTHONPATH=. python -m plugins.ralphharness.rag retrieve \
        --query "$query" \
        --collection "$collection" \
        --top-k "$top_k" 2>/dev/null) || result=""

    # Parse JSON envelope into TSV if we got results
    if [ -n "$result" ] && [ "$result" != "[]" ]; then
        printf '%s' "$result" | jq -r '.results[] | "\(.source_path)\t\(.score)\t\(.content)"' 2>/dev/null || true
    fi

    return 0
}

# ── rag_index_task ───────────────────────────────────────────────────────
# Index a completed task (called post-task-complete).
# Asynchronous: spawns Python in background so it never blocks the loop.
#
# Usage: rag_index_task "$spec_name" "$task_file"
#
# Exit code: 0 always

rag_index_task() {
    local spec_name="${1:-}"
    local task_file="${2:-}"

    # Disabled path: return immediately
    if ! rag_enabled; then
        return 0
    fi

    # Async indexing: never block the loop
    PYTHONPATH=. python -m plugins.ralphharness.rag index \
        --source "$task_file" \
        --collection "specs_tasks" \
        --spec-name "$spec_name" \
        >/dev/null 2>&1 &
    # Disown so it doesn't become a zombie when the shell exits
    disown 2>/dev/null || true

    return 0
}

# ── rag_health_check ─────────────────────────────────────────────────────
# Quick health check called on session start.
# Returns 0 if provider is reachable, 1 otherwise.
#
# Usage: rag_health_check

rag_health_check() {
    if ! rag_enabled; then
        return 1
    fi

    PYTHONPATH=. python -m plugins.ralphharness.rag doctor >/dev/null 2>&1
    return $?
}

# ── Internal helpers ─────────────────────────────────────────────────────

_rag_emit_disabled_metric() {
    local query="${1:-}"
    local collection="${2:-}"
    local top_k="${3:-3}"
    local spec_name="${SPEC_NAME:-unknown}"

    # Compute SHA-256 of query (never store raw query)
    local query_hash
    query_hash=$(printf '%s' "$query" | sha256sum | cut -d' ' -f1)
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Write to metrics log
    local metrics_dir
    metrics_dir="${XDG_CACHE_HOME:-$HOME/.cache}/smart-ralph/rag"
    mkdir -p "$metrics_dir" 2>/dev/null || true

    local metrics_log="$metrics_dir/retrieval-metrics.log"
    printf '{"ts":"%s","op":"retrieve","spec":"%s","query_sha256":"%s","collection":"%s","top_k":%d,"provider_used":"none","embedder_used":"none","latency_ms":0,"result_count":0,"outcome":"disabled"}\n' \
        "$ts" "$spec_name" "$query_hash" "$collection" "$top_k" \
        >> "$metrics_log" 2>/dev/null || true
}
