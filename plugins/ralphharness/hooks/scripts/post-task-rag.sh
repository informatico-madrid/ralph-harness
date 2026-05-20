#!/usr/bin/env bash
# post-task-rag.sh — Async RAG indexing for completed tasks.
#
# Called by stop-watcher.sh after each task advances.
# When RAG is disabled, returns immediately with zero overhead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib-rag for rag_index_task (provides async indexing with disown)
source "$SCRIPT_DIR/lib-rag.sh"

TASK_SPEC="${1:-}"
TASK_FILE="${2:-}"

if [ -z "$TASK_SPEC" ] || [ -z "$TASK_FILE" ]; then
    exit 0
fi

rag_index_task "$TASK_SPEC" "$TASK_FILE"
exit 0
