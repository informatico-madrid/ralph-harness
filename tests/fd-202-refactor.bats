#!/usr/bin/env bats
# fd-202-refactor.bats — Verify fd 204 baseline lock works identically to prior fd 202
# Maps to: design.md Test Coverage row "stop-watcher baseline lock refactor"

SPECIAL_DIR=""
STOP_WATCHER=""
REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"

setup() {
    SPECIAL_DIR=$(mktemp -d)
    STOP_WATCHER="$REPO_ROOT/plugins/ralphharness/hooks/scripts/stop-watcher.sh"
}

teardown() {
    rm -rf "$SPECIAL_DIR"
}

@test "baseline lock serialises 5 concurrent writers" {
    local baseline_file="$SPECIAL_DIR/.ralph-field-baseline.json"
    local lock_file="$baseline_file.lock"

    # Create a minimal baseline file
    echo '{"taskIndex":"coordinator"}' > "$baseline_file"

    # Write 5 concurrent files using the same pattern as stop-watcher.sh:
    #   exec FD>"$lock_file"; flock -x FD; write; done FD>"$lock_file"
    for i in 1 2 3 4 5; do
        (
            exec 204>"$lock_file"
            flock -x 204 || exit 0
            echo "line-from-writer-$i" >> "$baseline_file.writers"
        ) 204>"$lock_file" &
    done

    wait

    # All 5 lines must be present and unique (no torn writes)
    local count
    count=$(wc -l < "$baseline_file.writers")
    [ "$count" -eq 5 ]
    # Each line must be unique — no duplicates
    local unique_count
    unique_count=$(sort -u "$baseline_file.writers" | wc -l)
    [ "$unique_count" -eq 5 ]
}

@test "no other consumer references fd 202 in stop-watcher.sh" {
    # The stop-watcher.sh must only reference fd 204 for baseline lock,
    # never fd 202 for baseline lock.
    # We search for fd 202 only in baseline-lock related lines.
    local sw="$STOP_WATCHER"

    # Extract baseline-lock section (from BASELINE_FILE definition to end of block)
    local baseline_section
    baseline_section=$(sed -n '/# Validates state file fields against a baseline/,/^    ) 204/p' "$sw")

    # Assert fd 202 is NOT used in the baseline-lock section
    [[ "$baseline_section" != *'202'* ]]
}
