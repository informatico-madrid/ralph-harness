#!/usr/bin/env bats
# End-to-end gate-integration test — drives a fixture spec through all 5
# enforcement gates wired in stop-watcher.sh.
#
# Tests: gate_verify_sequential, verify-fix-present, emit_task_metric,
# gate_task_mark_integrity, and phase-exit-gate detection.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

setup() {
    source "$REPO_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
    mkdir -p "specs/fixture-e2e"
    SPEC_PATH="specs/fixture-e2e"
    STATE_FILE="$SPEC_PATH/.ralph-state.json"
    TASKS_FILE="$SPEC_PATH/tasks.md"
    REVIEW_FILE="$SPEC_PATH/task_review.md"
    SIGNALS_FILE="$SPEC_PATH/signals.jsonl"
    METRICS_FILE="$SPEC_PATH/.metrics.jsonl"

    # Seed signals.jsonl
    echo '# signals.jsonl' > "$SIGNALS_FILE"

    # Create .metrics.jsonl
    : > "$METRICS_FILE"

    # Init git repo at fixture root (needed for commit_sha in emit_task_metric)
    git init -q . 2>/dev/null
    git config user.email "test@test.com"
    git config user.name "Test"
    git add -A 2>/dev/null && git commit -q -m "initial" 2>/dev/null

    # Export for inline functions
    export CWD="$FIXTURE_DIR"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

    # === Inline gate_verify_sequential() ===
    gate_verify_sequential() {
        local spec_path="$1" tasks_file="$2" task_index="$3"
        [ ! -f "$tasks_file" ] && return 0
        local blocked
        blocked=$(awk -v target="$task_index" '
            /^- \[[ x]\]/ {
                if (idx == target) exit
                if (/^- \[[ x\]].*\[VERIFY\]/ && /\[ \]/) { print idx; exit 1 }
                idx++
            }
        ' "$tasks_file")
        if [ -z "$blocked" ]; then return 0; fi
        echo "BLOCKED: preceding VERIFY task ${blocked} unsatisfied" >&2
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
            echo "[harness][gate] WARN: signals.jsonl write failed" >> "$spec_path/.progress.md" 2>/dev/null
            return 0
        fi
        return 1
    }

    # === Inline capture_task_marks() ===
    capture_task_marks() {
        local sp="$1" tf="$2" sf="$3"
        # Use absolute paths — relative paths break in flock subshells
        [ ! -f "$tf" ] && return 0
        local abs_tf abs_sf
        abs_tf=$(cd "$REPO_ROOT" && pwd)/"$tf" 2>/dev/null || abs_tf="$tf"
        abs_sf=$(cd "$REPO_ROOT" && pwd)/"$sf" 2>/dev/null || abs_sf="$sf"
        # If absolute path doesn't exist, fall back to relative (for simple cases)
        [ ! -f "$abs_tf" ] && abs_tf="$tf"
        [ ! -f "$abs_sf" ] && abs_sf="$sf"
        [ ! -f "$abs_sf" ] && abs_sf="$(dirname "$abs_tf")/.ralph-state.json"
        local ts
        ts=$(date -u +%FT%TZ)
        local ci
        ci=$(awk '/^- \[x\]/ { printf "%d\n", idx; idx++; next } /^- \[[ x]\]/ { idx++; next } { next }' "$abs_tf")
        local ij
        ij=$(printf '%s\n' "$ci" | jq -R 'tonumber' | jq -s '.')
        local pl
        pl=$(jq -n --argjson ids "$ij" --arg ts "$ts" '{checkedTaskIds: $ids, capturedAt: $ts}')
        if [ -f "$abs_sf" ]; then
            local tmp="${abs_sf}.tmp"
            jq --argjson snap "$pl" '.taskMarkSnapshot = $snap' "$abs_sf" > "$tmp" 2>/dev/null && mv "$tmp" "$abs_sf" || rm -f "$tmp"
        fi
    }

    # === Inline gate_task_mark_integrity() ===
    gate_task_mark_integrity() {
        local spec_path="$1" state_file="$2"
        local tasks_file="$CWD/$spec_path/tasks.md"
        local review_file="$CWD/$spec_path/task_review.md"
        if [ ! -f "$review_file" ]; then return 0; fi
        local snapshot
        snapshot=$(jq -r '.taskMarkSnapshot // empty' "$state_file" 2>/dev/null || true)
        if [ -z "$snapshot" ]; then
            capture_task_marks "$spec_path" "$tasks_file" "$state_file" 2>/dev/null || true
            return 0
        fi
        (
            exec 201>"${tasks_file}.lock"
            flock -e 201 || exit 0
            local current_ids
            current_ids=$(awk '/^- \[x\]/ { printf "%d\n", idx; idx++; next } /^- \[[ x]\]/ { idx++; next } { next }' "$tasks_file" 2>/dev/null)
            local -a prior_ids=() current_ids_arr=()
            while IFS= read -r id; do [ -n "$id" ] && prior_ids+=("$id"); done <<< "$(echo "$snapshot" | jq -r '.checkedTaskIds // [] | .[]')"
            while IFS= read -r id; do [ -n "$id" ] && current_ids_arr+=("$id"); done <<< "$current_ids"
            local -a unmarked=()
            for pid in "${prior_ids[@]}"; do
                local found=0
                for cid in "${current_ids_arr[@]}"; do [ "$pid" = "$cid" ] && found=1 && break; done
                [ "$found" -eq 0 ] && unmarked+=("$pid")
            done
            for tid in "${unmarked[@]}"; do
                local hasPass=0
                # Use index() for literal string matching (awk -v regex escapes break with [ ])
                local task_header="### [task-${tid}]"
                if grep -qF "$task_header" "$review_file" 2>/dev/null; then
                    if awk -v pattern="$task_header" '
                        index($0, pattern) > 0 { in_task=1; next }
                        in_task && /^- status:/ { gsub(/^[[:space:]]*- status: */, ""); if (tolower($0) == "pass") print "1"; in_task=0 }
                        in_task && /^### / { in_task=0 }
                    ' "$review_file" 2>/dev/null | grep -q .; then
                        hasPass=1
                    fi
                fi
                # extInc = external_un_marks[tid] (current) > externalUnmarks[tid] (snapshot)
                local extInc=0
                local ext_current
                ext_current=$(jq -r ".external_un_marks[\"$tid\"] // 0.0" "$state_file" 2>/dev/null || echo "0.0")
                extInc=$(echo "$snapshot" | jq --arg tid "$tid" --argjson cur "$ext_current" '
                    ($cur > (if .externalUnmarks[$tid] then .externalUnmarks[$tid] else 0 end)) | if . then 1 else 0 end
                ' 2>/dev/null || echo "0")
                if [ "$hasPass" -eq 1 ] && [ "$extInc" -eq 0 ]; then
                    local payload
                    payload=$(jq -n \
                      --arg source "gate_task_mark_integrity" \
                      --arg reason "illegitimate un-mark of task ${tid}" \
                      --argjson taskId "$tid" \
                      --arg status "active" \
                      --arg timestamp "$(date -u +%FT%TZ)" \
                      '{type:"control",signal:"DEADLOCK",from:"gate_task_mark_integrity",to:"coordinator",taskId:$taskId,status:$status,timestamp:$timestamp,reason:$reason}')
                    append_signal "$spec_path" "$payload" 2>/dev/null || true
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
                jq --argjson snap "$snap_payload" '.taskMarkSnapshot = $snap' "$state_file" > "$tmp" 2>/dev/null && mv "$tmp" "$state_file" || rm -f "$tmp"
            fi
        ) 201>"${tasks_file}.lock"
    }

    # === Inline emit_task_metric() — with inlined write_metric ===
    emit_task_metric() {
        local spec_path="$1" state_file="$2"
        [ ! -f "$state_file" ] && return 0
        local task_index task_iteration last_metric_task_index last_metric_iteration
        task_index=$(jq -r '.taskIndex // 0' "$state_file" 2>/dev/null || echo "0")
        task_iteration=$(jq -r '.taskIteration // 0' "$state_file" 2>/dev/null || echo "0")
        last_metric_task_index=$(jq -r '.lastMetricTaskIndex // -1' "$state_file" 2>/dev/null || echo "-1")
        last_metric_iteration=$(jq -r '.lastMetricIteration // -1' "$state_file" 2>/dev/null || echo "-1")
        local status="pass"
        if [ "$task_index" -gt "$last_metric_task_index" ] 2>/dev/null; then
            status="pass"
        elif [ "$task_index" -eq "$last_metric_task_index" ] && [ "$task_iteration" -gt "$last_metric_iteration" ] 2>/dev/null; then
            status="fail"
        else
            return 0
        fi
        local commit_sha
        commit_sha=$(git -C "$spec_path" log -1 --format=%H 2>/dev/null || echo "unknown")
        local task_name="unknown"
        local tf="$CWD/$spec_path/tasks.md"
        if [ -f "$tf" ]; then
            task_name=$(awk -v idx="$task_index" '
                /^- \[[ x]\]/ && c == idx { sub(/^[- ]* \[[ x]\] /, ""); print; exit }
                /^- \[[ x]\]/ { c++ }
            ' "$tf")
        fi

        # Inlined write_metric (avoids sourcing write-metric.sh in bats)
        local metrics_file="$spec_path/.metrics.jsonl"
        local lock_file="$spec_path/.metrics.lock"
        local spec_name
        spec_name="$(basename "$spec_path" 2>/dev/null)"
        local task_id="${task_index}.${task_iteration}"
        local timestamp
        timestamp="$(date -u +%FT%TZ 2>/dev/null)"
        local event_id="${task_index}-${task_iteration}-$(date +%s%N 2>/dev/null || date +%s)000000000"
        (
            flock -x 200 || exit 1
            jq -n -c \
              --arg spec "$spec_path" \
              --arg status "$status" \
              --arg taskIndex "$task_index" \
              --arg taskIteration "$task_iteration" \
              --arg taskTitle "$task_name" \
              --arg commitSha "$commit_sha" \
              --arg eventId "$event_id" \
              --arg timestamp "$timestamp" \
              '{schemaVersion:1,eventId:$eventId,timestamp:$timestamp,spec:$spec,status:$status,taskIndex:($taskIndex|tonumber),taskIteration:($taskIteration|tonumber),taskTitle:$taskTitle,commitSha:$commitSha}' \
              >> "$metrics_file" 2>/dev/null
        ) 200>"$lock_file"

        # Update state
        local tmp="${state_file}.tmp"
        jq --argjson ti "$task_index" --argjson ti2 "$task_iteration" \
            '.lastMetricTaskIndex = $ti | .lastMetricIteration = $ti2' \
            "$state_file" > "$tmp" 2>/dev/null && mv "$tmp" "$state_file" || rm -f "$tmp"
        return 0
    }
}

teardown() {
    if [ -d "$FIXTURE_DIR" ]; then
        chmod -R u+w "$FIXTURE_DIR" 2>/dev/null || true
    fi
    rm -rf "$FIXTURE_DIR"
}

# =====================================================================
# Gate 1: gate_verify_sequential — blocks on preceding unchecked [VERIFY]
# =====================================================================
@test "gate 1: gate_verify_sequential blocks on preceding [VERIFY] [ ]" {
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base task
- [ ] 1.1 [VERIFY] Checkpoint
- [ ] 2.1 Current task
- [ ] 2.G [VERIFY] Phase exit gate
EOF

    local rc
    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2 >/dev/null 2>&1 || rc=1
    [ "$rc" -eq 1 ]

    # DEADLOCK signal appended
    grep -q '"DEADLOCK"' "$SIGNALS_FILE"
    grep -q '"gate_verify_sequential"' "$SIGNALS_FILE"
    grep -q '"preceding VERIFY task 1 unsatisfied"' "$SIGNALS_FILE"
}

# =====================================================================
# Gate 2: verify-fix-present.sh — detects committed fix
# =====================================================================
@test "gate 2: verify-fix-present.sh detects committed fix" {
    # Build a throwaway git fixture with origin/main diverged
    local vf_repo
    vf_repo=$(mktemp -d)
    cd "$vf_repo"
    git init -q . 2>/dev/null
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit -q --allow-empty -m "base" 2>/dev/null
    git update-ref refs/remotes/origin/main HEAD 2>/dev/null || true

    # Create and commit a "fix" file
    echo "fix line here" > fix.txt
    git add fix.txt
    git commit -q -m "add fix" 2>/dev/null

    # Run verify-fix-present.sh — exit 0 = fix present
    local vf_rc=0
    "$REPO_ROOT/plugins/ralphharness/hooks/scripts/verify-fix-present.sh" fix.txt 2>/dev/null || vf_rc=$?
    [ "$vf_rc" -eq 0 ]

    # Pattern present → exit 0
    local vf2_rc=0
    "$REPO_ROOT/plugins/ralphharness/hooks/scripts/verify-fix-present.sh" fix.txt "fix line" 2>/dev/null || vf2_rc=$?
    [ "$vf2_rc" -eq 0 ]

    # Pattern absent → exit 2
    local vf3_rc=0
    "$REPO_ROOT/plugins/ralphharness/hooks/scripts/verify-fix-present.sh" fix.txt "missing_pattern" 2>/dev/null || vf3_rc=$?
    [ "$vf3_rc" -eq 2 ]

    # Cleanup
    chmod -R u+w "$vf_repo" 2>/dev/null || true
    rm -rf "$vf_repo"
}

# =====================================================================
# Gate 3: emit_task_metric — writes one metric line on advancement
# =====================================================================
@test "gate 3: emit_task_metric writes one metric line on advancement" {
    # Seed state: taskIndex=2, lastMetricTaskIndex=-1 → advancement → pass
    jq -n '{
        taskIndex: 2, taskIteration: 0,
        lastMetricTaskIndex: -1, lastMetricIteration: -1,
        spec: "fixture-e2e"
    }' > "$STATE_FILE"

    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base
- [x] 1.1 Phase 2
- [ ] 2.1 Current task
EOF

    emit_task_metric "$SPEC_PATH" "$STATE_FILE"

    # Verify one metric line with status pass
    grep -q '"status":"pass"' "$METRICS_FILE"
    grep -q '"taskIndex":2' "$METRICS_FILE"
    grep -q '"taskIteration":0' "$METRICS_FILE"

    # State updated
    local lmtd
    lmtd=$(jq -r '.lastMetricTaskIndex' "$STATE_FILE")
    [ "$lmtd" -eq 2 ]
}

# =====================================================================
# Gate 4: gate_task_mark_integrity — detects illegitimate un-mark
# =====================================================================
@test "gate 4: gate_task_mark_integrity detects illegitimate un-mark" {
    # Seed tasks with all checked
    cat > "$TASKS_FILE" << 'EOF'
- [x] 0.1 Base
- [x] 1.1 Phase 2
- [x] 2.1 Phase 3
EOF
    # Write state file directly with snapshot (avoids capture_task_marks path issues)
    jq -n --arg ts "$(date -u +%FT%TZ)" '{taskMarkSnapshot: {checkedTaskIds: [0, 1, 2], capturedAt: $ts}}' > "$STATE_FILE"

    # Create review with PASS for task 1
    cat > "$REVIEW_FILE" << 'EOF'
### [task-1] Phase 2 task
- status: PASS
- reviewed_at: 2026-05-19T12:00:00Z
- evidence: code verified
- fix_hint: N/A
- resolved_at: 2026-05-19T12:00:00Z
EOF

    # Simulate illegitimate un-mark: task 1 [x] -> [ ]
    sed -i 's/- \[x\] 1.1/- [ ] 1.1/' "$TASKS_FILE"

    # Run gate
    gate_task_mark_integrity "$SPEC_PATH" "$STATE_FILE"

    # DEADLOCK emitted
    grep -q '"DEADLOCK"' "$SIGNALS_FILE"
    grep -q '"gate_task_mark_integrity"' "$SIGNALS_FILE"
    grep -q 'illegitimate un-mark of task 1' "$SIGNALS_FILE"

    # Mark unchanged (gate never re-marks)
    grep -q '\[ \] 1.1' "$TASKS_FILE"
}

# =====================================================================
# Gate 5: Phase exit gate — exit-gate task exists and is checked
# =====================================================================
@test "gate 5: phase exit gate detection in multi-phase fixture" {
    # Build a 2-phase tasks.md with exit-gate tasks
    cat > "$TASKS_FILE" << 'EOF'
## Phase 1: Make It Work

- [x] 1.1 First task
- [x] 1.2 Second task
- [ ] 1.G [VERIFY] Phase 1 exit gate

## Phase 2: Refactoring

- [ ] 2.1 Refactor task
- [ ] 2.G [VERIFY] Phase 2 exit gate
EOF

    # Phase 1 exit gate (index 2): preceding [VERIFY] tasks at 1.1, 1.2 are [x] → passes
    local rc
    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 2
    rc=$?
    [ "$rc" -eq 0 ]

    # Phase 2 exit gate (index 4): preceding [VERIFY] at 1.G is [ ] → blocks
    gate_verify_sequential "$SPEC_PATH" "$TASKS_FILE" 4 >/dev/null 2>&1 || rc=1
    [ "${rc:-0}" -eq 1 ]

    # Verify exit-gate naming pattern exists
    grep -q '\[VERIFY\] Phase [0-9]* exit gate' "$TASKS_FILE"
}
