#!/usr/bin/env bash
# post-task-rag.sh — Async RAG indexing for completed tasks.
#
# Called by stop-watcher.sh after each task advances.
# When RAG is disabled, returns immediately with zero overhead.
#
# Usage: post-task-rag.sh "$SPEC_PATH" "$COMPLETED_TASK_BLOCK"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib-rag.sh"

TASK_SPEC_PATH="${1:-}"
TASK_BLOCK="${2:-}"

if [ -z "$TASK_SPEC_PATH" ] || [ -z "$TASK_BLOCK" ]; then
    exit 0
fi

# Extract spec name from path (e.g., "specs/foo" → "foo")
SPEC_NAME=$(basename "$TASK_SPEC_PATH")

# Write task block to temp file for Python to read
TASK_TMP=$(mktemp)
printf '%s' "$TASK_BLOCK" > "$TASK_TMP"

# Call rag_index_task with temp file and spec path
rag_index_task "$SPEC_NAME" "$TASK_TMP"

# Cleanup
rm -f "$TASK_TMP"

exit 0
