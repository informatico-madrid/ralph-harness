#!/usr/bin/env bats
# Bats suite for gate_verify_sequential(): preceding VERIFY block gate
#
# Tests: preceding [VERIFY] [ ] blocks, all [VERIFY] [x] passes,
# no [VERIFY] tasks pass, read-only signals.jsonl degrades gracefully.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

setup() {
    # Source lib-signals.sh for append_signal helper
    source "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
    mkdir -p "specs/fixture-multiphase"
    SPEC_PATH="specs/fixture-multiphase"
    TASKS_FILE="$SPEC_PATH/tasks.md"

    # Seed signals.jsonl with a template comment line
    echo '# signals.jsonl' > "$SPEC_PATH/signals.jsonl"

    # Inline gate_verify_sequential() — copied from stop-watcher.sh
    # (stop-watcher.sh reads stdin so we cannot source it directly)
    gate_verify_sequential() {
        local spec_path="$1"
        local tasks_file="$2"
        local task_index="$3"

        if [ ! -f "$tasks_file" ]; then
            return 0
        fi

        # Scan for unchecked [VERIFY] tasks below task_index.
        # Note: awk rules run sequentially on each line. We check for [VERIFY]
        # BEFORE incrementing idx, so the index is correct for the current line.
        local blocked
        blocked=$(awk -v target="$task_index" '
            /^- \[[ x]\]/ {
                if (/^- \[[ x\]].*\[VERIFY\]/ && /\[ \]/) {
                    print idx
                    exit 1
                }
                if (idx >= target) exit
                idx++
            }
        ' "$tasks_file")

        if [ -z "$blocked" ]; then
            return 0
        fi

        echo "BLOCKED: preceding VERIFY task ${blocked} unsatisfied" >&2

        # Emit DEADLOCK control signal to signals.jsonl (FR-2, AC-1.2, AC-1.7)
        if [ ! -f "$spec_path/signals.jsonl" ]; then
          cp "$REPO_ROOT/plugins/ralphharness/templates/signals.jsonl" "$spec_path/signals.jsonl" 2>/dev/null || true
        fi
        source "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh" 2>/dev/null || true

        local deadlock_payload
        deadlock_payload=$(jq -n \
          --arg source "gate_verify_sequential" \
          --arg reason "preceding VERIFY task ${blocked} unsatisfied" \
          --argjson taskIndex "$blocked" \
          --arg status "active" \
          --arg timestamp "$(date -u +%FT%TZ)" \
          '{type:"control",signal:"DEADLOCK",from:"gate_verify_sequential",to:"coordinator",taskIndex:$taskIndex,status:$status,timestamp:$timestamp,reason:$reason}')

        if ! append_signal "$spec_path" "$deadlock_payload"; then
          echo "[harness][gate] WARN: signals.jsonl write failed (read-only fs), skipping DEADLOCK" >> "$spec_path/.progress.md" 2>/dev/null
          return 0
        fi
        return 1
    }
}

teardown() {
    if [ -d "$FIXTURE_DIR" ]; then
        chmod -R u+w "$FIXTURE_DIR" 2>/dev/null || true
    fi
    rm -rf "$FIXTURE_DIR"
}

write_tasks() {
    printf '%s\n' "$1" > "$TASKS_FILE"
}

# ---- Case 1: preceding [VERIFY] [ ] → block (rc=1) ----
@test "preceding VERIFY unchecked blocks (rc=1)" {
    write_tasks '- [ ] 3.4 Preceding task
- [ ] 3.5 [VERIFY] Checkpoint A
- [ ] 3.6 Current task'

    local rc
    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2 >/dev/null 2>&1 || rc=1
    [ "${rc:-0}" -eq 1 ]
}

@test "preceding VERIFY unchecked emits DEADLOCK in signals.jsonl" {
    write_tasks '- [ ] 3.4 Preceding task
- [ ] 3.5 [VERIFY] Checkpoint A
- [ ] 3.6 Current task'

    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2 >/dev/null 2>&1 || true
    grep -q '"DEADLOCK"' "$SPEC_PATH/signals.jsonl"
}

# ---- Case 2: all preceding [VERIFY] [x] → pass (rc=0) ----
@test "all preceding VERIFY checked passes (rc=0)" {
    write_tasks '- [x] 3.4 Preceding task
- [x] 3.5 [VERIFY] Checkpoint A
- [ ] 3.6 Current task'

    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2
    local rc
    rc=$?
    [ "$rc" -eq 0 ]
}

@test "all preceding VERIFY checked does not emit DEADLOCK" {
    write_tasks '- [x] 3.4 Preceding task
- [x] 3.5 [VERIFY] Checkpoint A
- [ ] 3.6 Current task'

    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2 >/dev/null 2>&1 || true

    # Check no DEADLOCK was added (only the initial comment line)
    local dl_count
    dl_count=$(grep -c '"DEADLOCK"' "$SPEC_PATH/signals.jsonl" 2>/dev/null || echo "0")
    dl_count=${dl_count%%[^0-9]*}
    [ "$dl_count" -eq 0 ]
}

# ---- Case 3: no [VERIFY] tasks → pass (rc=0) ----
@test "no VERIFY tasks returns 0" {
    write_tasks '- [ ] 3.4 Normal task
- [ ] 3.5 Another task
- [ ] 3.6 Current task'

    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2
    local rc
    rc=$?
    [ "$rc" -eq 0 ]
}

# ---- Case 4: read-only signals.jsonl → WARN + rc=0 ----
@test "read-only signals.jsonl degrades gracefully (rc=0)" {
    write_tasks '- [ ] 3.4 Preceding task
- [ ] 3.5 [VERIFY] Checkpoint A
- [ ] 3.6 Current task'

    # Make signals.jsonl read-only so append_signal fails → graceful degradation
    chmod 444 "$SPEC_PATH/signals.jsonl"

    local rc
    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2 >/dev/null 2>&1 || rc=1
    [ "${rc:-0}" -eq 0 ]
    # Verify the WARN was logged to .progress.md
    grep -q 'WARN.*signals.jsonl write failed' "$SPEC_PATH/.progress.md"
}

# ---- Case 5: append-only discipline — assertion exists + git diff clean ----
@test "append-only assertion exists in stop-watcher.sh" {
    # The stop-watcher.sh must contain the append-only assertion block
    # (task 1.8: insertion at start of loop-control block)
    local sw_file="$REPO_ROOT/plugins/ralphharness/hooks/scripts/stop-watcher.sh"
    [ -f "$sw_file" ]

    # Verify the assertion logic is present: looks for deletion count in git diff
    grep -q 'deletion_count\|_deletion_count\|APPEND-ONLY' "$sw_file"
}

@test "git diff append-only discipline — zero content deletions" {
    # Assert that stop-watcher.sh changes from main are purely appended.
    # `^-` lines in a git diff that start with `-` followed by something
    # other than `-` represent content deletions (not the `--- a/b` headers).
    # Bats tests run in a temp directory so we must use absolute paths.
    local abs_path
    abs_path=$(cd "$REPO_ROOT" && pwd)

    local deletion_count
    deletion_count=$(git -C "$abs_path" diff main -- plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -c '^-[^-]' || true)
    deletion_count=${deletion_count%%[^0-9]*}
    [ "$deletion_count" -eq 0 ]
}
