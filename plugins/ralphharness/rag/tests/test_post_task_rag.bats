#!/usr/bin/env bats
# bats tests for post-task-rag.sh integration.
# Phase 4 complete: file must exist; previous skip-on-missing behavior masked regressions.

setup() {
    post_task_file="$(dirname "$BATS_TEST_FILENAME")/../../hooks/scripts/post-task-rag.sh"
}

@test "post-task-rag.sh exists and is a regular file" {
    [ -f "$post_task_file" ]
}
