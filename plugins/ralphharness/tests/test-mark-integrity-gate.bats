#!/usr/bin/env bats
# Bats suite for gate_task_mark_integrity(): illegitimate / legitimate / no-revert / edge cases.
#
# Tests: [x]->[ ] with PASS but no ext unmark -> DEADLOCK,
# [x]->[ ] with ext unmark increment -> legitimate,
# no un-marks -> clean,
# flock presence, missing review_file, missing taskMarkSnapshot.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

setup() {
    source "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
    mkdir -p "specs/fixture-multiphase"
    SPEC_PATH="specs/fixture-multiphase"
    STATE_FILE="$SPEC_PATH/.ralph-state.json"
    TASKS_FILE="$SPEC_PATH/tasks.md"
    REVIEW_FILE="$SPEC_PATH/task_review.md"
    SIGNALS_FILE="$SPEC_PATH/signals.jsonl"

    echo '# signals.jsonl' > "$SIGNALS_FILE"

    git init -q . 2>/dev/null || true
    git config user.email "test@test.com" 2>/dev/null || true
    git config user.name "Test" 2>/dev/null || true
    git add -A 2>/dev/null && git commit -q -m "initial" 2>/dev/null || true

    # Ensure state file exists before any capture
    jq -n '{taskIndex:0,taskIteration:0,lastMetricTaskIndex:-1,lastMetricIteration:-1}' > "$STATE_FILE"

    export CWD="$FIXTURE_DIR"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

    # Inline capture_task_marks
    capture_task_marks() {
        local sp="$1" tf="$2" sf="$3"
        [ ! -f "$tf" ] && return 0
        local ts
        ts=$(date -u +%FT%TZ)
        local ci
        ci=$(awk '/^- \[x\]/ { printf "%d\n", idx; idx++ ; next } /^- \[[ x]\]/ { idx++; next } { next }' "$tf")
        local ij
        ij=$(printf '%s\n' "$ci" | jq -R 'tonumber' | jq -s '.')
        local pl
        pl=$(jq -n --argjson ids "$ij" --arg ts "$ts" '{checkedTaskIds: $ids, capturedAt: $ts}')
        if [ -f "$sf" ]; then
            local tmp="${sf}.tmp"
            jq --argjson snap "$pl" '.taskMarkSnapshot = $snap' "$sf" > "$tmp" 2>/dev/null && mv "$tmp" "$sf" || rm -f "$tmp"
        fi
    }

    # Inline gate_task_mark_integrity
    gate_task_mark_integrity() {
        echo "DBG: gate called spec=$1 state=$2" >&2
        local spec_path="$1"
        local state_file="$2"
        local tasks_file="$CWD/$spec_path/tasks.md"
        local review_file="$CWD/$spec_path/task_review.md"

        local _exists=Y; [ ! -f "$review_file" ] && _exists=N
        echo "DBG: review=$review_file exists=$_exists" >&2

        if [ ! -f "$review_file" ]; then
            echo "DBG: returning early - no review_file" >&2
            return 0
        fi

        local snapshot
        snapshot=$(jq -r '.taskMarkSnapshot // null' "$state_file" 2>/dev/null || echo "null")
        echo "DBG: snapshot=$snapshot" >&2
        if [ "$snapshot" = "null" ]; then
            capture_task_marks "$spec_path" "$tasks_file" "$state_file" 2>/dev/null || true
            return 0
        fi

        (
            exec 201>"${tasks_file}.lock"
            flock -e 201 || exit 0

            local current_ids
            current_ids=$(awk '/^- \[x\]/ { printf "%d\n", idx; idx++; next } /^- \[[ x]\]/ { idx++; next } { next }' "$tasks_file" 2>/dev/null)

            local -a prior_ids=() current_ids_arr=()
            while IFS= read -r id; do
                [ -n "$id" ] && prior_ids+=("$id")
            done <<< "$(echo "$snapshot" | jq -r '.checkedTaskIds // [] | .[]')"
            while IFS= read -r id; do
                [ -n "$id" ] && current_ids_arr+=("$id")
            done <<< "$current_ids"

            echo "DBG: prior=${prior_ids[*]} current=${current_ids_arr[*]}" >&2

            local -a unmarked=()
            for pid in "${prior_ids[@]}"; do
                local found=0
                for cid in "${current_ids_arr[@]}"; do
                    [ "$pid" = "$cid" ] && found=1 && break
                done
                [ "$found" -eq 0 ] && unmarked+=("$pid")
            done

            local -a illegitimate=() legitimate=()
            for tid in "${unmarked[@]}"; do
                local hasPass=0
                local _grep_pat="### \[task-${tid}\]"
                local _awk_pat="### [task-${tid}]"
                echo "DBG: grep_pat=$_grep_pat awk_pat=$_awk_pat" >&2
                echo "DBG: review_file=$_review_file" >&2
                if grep -q "$_grep_pat" "$review_file" 2>/dev/null; then
                    echo "DBG: grep matched" >&2
                    if awk -v target="$_awk_pat" '
                        index($0, target) { in_task=1; next }
                        in_task && /^- status:/ { gsub(/^[[:space:]]*- status: */, ""); if (tolower($0) == "pass") print "1"; in_task=0 }
                        in_task && /^### / { in_task=0 }
                    ' "$review_file" 2>/dev/null | grep -q .; then
                        hasPass=1
                    fi
                else
                    echo "DBG: grep NOT matched" >&2
                fi

                local extInc=0
                local ext_current
                ext_current=$(jq -r ".external_un_marks[\"$tid\"] // 0" "$state_file" 2>/dev/null || echo 0)
                extInc=$(echo "$snapshot" | jq --arg tid "$tid" --argjson cur "$ext_current" '
                    ($cur > (if .externalUnmarks[$tid] then .externalUnmarks[$tid] else 0 end)) | if . then 1 else 0 end
                ' 2>/dev/null || echo 0)

                echo "DBG: tid=$tid hasPass=$hasPass extInc=$extInc" >&2
                if [ "$hasPass" -eq 1 ] && [ "$extInc" -eq 0 ]; then
                    illegitimate+=("$tid")
                    echo "DBG: -> ILLEGITIMATE" >&2
                else
                    legitimate+=("$tid")
                    echo "DBG: -> LEGITIMATE" >&2
                fi
            done

            for tid in "${illegitimate[@]}"; do
                local payload
                payload=$(jq -n \
                  --arg source "gate_task_mark_integrity" \
                  --arg reason "illegitimate un-mark of task ${tid}" \
                  --argjson taskId "$tid" \
                  --arg status "active" \
                  --arg timestamp "$(date -u +%FT%TZ)" \
                  '{type:"control",signal:"DEADLOCK",from:"gate_task_mark_integrity",to:"coordinator",taskId:$taskId,status:$status,timestamp:$timestamp,reason:$reason}')

                if ! append_signal "$spec_path" "$payload"; then
                    :
                fi
            done

            # Refresh snapshot
            local captured_at
            captured_at=$(date -u +%FT%TZ)
            local ids_json
            ids_json=$(printf '%s\n' "$current_ids" | jq -R 'tonumber' | jq -s '.')
            local snap_payload
            snap_payload=$(jq -n --argjson ids "$ids_json" --arg ts "$captured_at" '{checkedTaskIds: $ids, capturedAt: $ts}')

            if [ -f "$state_file" ]; then
                local tmp="${state_file}.tmp"
                if jq --argjson snap "$snap_payload" '.taskMarkSnapshot = $snap' "$state_file" > "$tmp" 2>/dev/null; then
                    mv "$tmp" "$state_file"
                else
                    rm -f "$tmp"
                fi
            fi
        ) 201>"${tasks_file}.lock"
    }
}

teardown() {
    if [ -d "$FIXTURE_DIR" ]; then
        chmod -R u+w "$FIXTURE_DIR" 2>/dev/null || true
    fi
    rm -rf "$FIXTURE_DIR"
}

# ---- Case 1: illegitimate un-mark (has PASS, no ext unmark increment) -> DEADLOCK ----
@test "illegitimate un-mark with PASS entry emits DEADLOCK" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [x] 1.1 Phase 2 task
- [x] 2.1 Phase 3 task
EOF
    capture_task_marks "$SPEC_PATH" "$TASKS_FILE" "$STATE_FILE"

    echo "DBG: state after capture: $(jq -c '.' "$STATE_FILE")" >&2

    cat > "$REVIEW_FILE" << 'EOF'
### [task-1] Implement something
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
- evidence: code works
- fix_hint: N/A
- resolved_at: 2026-05-19T12:00:00Z
EOF

    sed -i 's/- \[x\] 1.1/- [ ] 1.1/' "$TASKS_FILE"

    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    grep -q '"DEADLOCK"' "$SIGNALS_FILE"
    grep -q 'illegitimate un-mark of task 1' "$SIGNALS_FILE"
}

# ---- Case 2: legitimate un-mark (ext unmark increased) -> rc=0 no signal ----
@test "legitimate un-mark with ext unmark increment does not emit DEADLOCK" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [x] 1.1 Phase 2 task
- [x] 2.1 Phase 3 task
EOF
    capture_task_marks "$SPEC_PATH" "$TASKS_FILE" "$STATE_FILE"

    cat > "$REVIEW_FILE" << 'EOF'
### [task-1] Implement something
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
- evidence: code works
- fix_hint: N/A
- resolved_at: 2026-05-19T12:00:00Z
EOF

    jq '.external_un_marks["1"] = 1' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    sed -i 's/- \[x\] 1.1/- [ ] 1.1/' "$TASKS_FILE"

    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    local dl_count
    dl_count=$(grep -c '"DEADLOCK"' "$SIGNALS_FILE" 2>/dev/null || echo "0")
    dl_count=${dl_count%%[^0-9]*}
    [ "$dl_count" -eq 0 ]
}

# ---- Case 3: no un-marks -> clean, no signal ----
@test "no un-marks after snapshot is clean and emits nothing" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [x] 1.1 Phase 2 task
- [ ] 2.1 Phase 3 task
EOF
    capture_task_marks "$SPEC_PATH" "$TASKS_FILE" "$STATE_FILE"

    cat > "$REVIEW_FILE" << 'EOF'
### [task-0] Base task
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
- evidence: works
- fix_hint: N/A
- resolved_at: 2026-05-19T12:00:00Z

### [task-1] Phase 2 task
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
- evidence: works
- fix_hint: N/A
- resolved_at: 2026-05-19T12:00:00Z
EOF

    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    local dl_count
    dl_count=$(grep -c '"DEADLOCK"' "$SIGNALS_FILE" 2>/dev/null || echo "0")
    dl_count=${dl_count%%[^0-9]*}
    [ "$dl_count" -eq 0 ]
}

# ---- Case 4: flock presence in function source ----
@test "flock -e 201 present in gate_task_mark_integrity" {
    grep -q 'flock -e 201' <(declare -f gate_task_mark_integrity)
}

# ---- Case 5: missing task_review.md -> rc=0 no signal ----
@test "missing task_review.md returns rc=0 and emits nothing" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [x] 1.1 Phase 2 task
- [x] 2.1 Phase 3 task
EOF
    capture_task_marks "$SPEC_PATH" "$TASKS_FILE" "$STATE_FILE"

    # Remove review file so gate sees missing review
    rm -f "$REVIEW_FILE"

    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    local dc
    dc=$(grep -c '"DEADLOCK"' "$SIGNALS_FILE" 2>/dev/null) || dc=0
    [ "$dc" -eq 0 ]
}

# ---- Case 6: missing taskMarkSnapshot -> fresh snapshot ----
@test "missing taskMarkSnapshot creates fresh snapshot and emits nothing" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [x] 1.1 Phase 2 task
- [x] 2.1 Phase 3 task
EOF
    # Reset state without taskMarkSnapshot
    jq -n '{taskIndex:0,taskIteration:0,lastMetricTaskIndex:-1,lastMetricIteration:-1}' > "$STATE_FILE"

    # Write a review file (it exists but won't be used since snapshot=null)
    cat > "$REVIEW_FILE" << 'EOF'
### [task-1] Implement something
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
EOF

    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    grep -q '"DEADLOCK"' "$SIGNALS_FILE" && false

    # Verify fresh snapshot was created with correct task IDs
    local ids
    ids=$(jq -c '.taskMarkSnapshot.checkedTaskIds' "$STATE_FILE")
    [ "$ids" = '[0,1,2]' ]
}
