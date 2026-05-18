#!/usr/bin/env bats

# reviewer-warmup test suite
# Covers: heartbeat shape, non-regression, freshness-gate simulation,
#         bootstrap, byte-stable guard, skill, export, docs grep tests.
# Design: Test Coverage Table rows 1–13.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"

PLUGIN="${REPO_ROOT}/plugins/ralphharness"
AGENTS="${PLUGIN}/agents"
TEMPLATES="${PLUGIN}/templates"
HOOKS="${PLUGIN}/hooks/scripts"
SKILLS="${PLUGIN}/skills"
COMMANDS="${PLUGIN}/commands"
REFERENCES="${PLUGIN}/references"

# ── Phase 3.1: Heartbeat shape + non-regression + emission ──────────

@test "heartbeat-shape-valid-jq" {
    local heartbeat
    heartbeat=$(cat <<'EOF'
{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-1.3","status":"active","timestamp":"2026-05-17T14:22:08Z","iteration":3,"reason":"step 3/5: reading design.md"}
EOF
)
    echo "$heartbeat" | jq -e . >/dev/null
}

@test "heartbeat-fields-correct" {
    local heartbeat
    heartbeat=$(cat <<'EOF'
{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-1.3","status":"active","timestamp":"2026-05-17T14:22:08Z","iteration":3,"reason":"step 3/5: reading design.md"}
EOF
)
    [ "$(echo "$heartbeat" | jq -r '.type')" = "control" ]
    local sig
    sig=$(echo "$heartbeat" | jq -r '.signal')
    [[ "$sig" == "ALIVE" || "$sig" == "STILL" ]]
    local reason
    reason=$(echo "$heartbeat" | jq -r '.reason')
    [[ "$reason" =~ ^step\ [0-9]+/[0-9]+:\ .+ ]]
}

@test "heartbeat-non-blocking-count" {
    local fixture="${BATS_TEST_TMPDIR}/signals-nonblock.jsonl"
    echo '{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-1.3","status":"active","timestamp":"2026-05-17T14:22:08Z","iteration":3,"reason":"step 3/5: reading design.md"}' > "$fixture"

    local count
    count=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        active_signal_count '$fixture'
    ")
    [ "$count" -eq 0 ]
}

@test "executor-heartbeat-emission-step-present" {
    local executor_md="${AGENTS}/spec-executor.md"
    grep -q 'heartbeat' "$executor_md"
    grep -q 'ALIVE' "$executor_md"
    grep -q 'STILL' "$executor_md"
    grep -q 'signals.jsonl' "$executor_md"
    grep -Eq 'step N/M|step [0-9]+/[0-9]+' "$executor_md"
}

@test "executor-signal-emission-contract-row" {
    local executor_md="${AGENTS}/spec-executor.md"
    grep -q 'Signal Emission Contract' "$executor_md"
    grep -q 'ALIVE.*STILL.*signals.jsonl\|STILL.*ALIVE.*signals.jsonl\|signals.jsonl.*ALIVE\|signals.jsonl.*STILL' "$executor_md"
    grep -q 'Do-steps\|long.*read\|Do-step' "$executor_md"
}

# ── Phase 3.2: Freshness-gate simulation ────────────────────────────

@test "freshness-gate-fresh-suppresses-escalation" {
    local fixture="${BATS_TEST_TMPDIR}/fresh.jsonl"
    local now_epoch
    now_epoch=$(date -u +%s)
    local future_ts
    future_ts=$(date -u -d "@$((now_epoch - 90))" +%Y-%m-%dT%H:%M:%SZ)

    echo "{\"type\":\"control\",\"signal\":\"ALIVE\",\"from\":\"spec-executor\",\"to\":\"external-reviewer\",\"task\":\"task-1.3\",\"status\":\"active\",\"timestamp\":\"${future_ts}\",\"iteration\":3,\"reason\":\"step 3/5: reading design.md\"}" > "$fixture"

    local result
    result=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        STALENESS_MINUTES=10
        newest=\$(grep -v '^[[:space:]]*#' '$fixture' 2>/dev/null | jq -c 'select(.type==\"control\" and (.signal==\"ALIVE\" or .signal==\"STILL\"))' | tail -1)
        if [ -z \"\$newest\" ]; then
            echo 'freshness=false;escalate=true'
        else
            ts=\$(echo \"\$newest\" | jq -r '.timestamp')
            now_epoch=\$(date -u +%s)
            parse_epoch=\$(date -u -d \"\$ts\" +%s 2>/dev/null)
            if [ -z \"\$parse_epoch\" ]; then
                echo 'freshness=false;escalate=true'
            else
                age_min=\$(( (now_epoch - parse_epoch) / 60 ))
                if [ \$age_min -lt \$STALENESS_MINUTES ]; then
                    echo \"freshness=true;escalate=false;age=\${age_min}min\"
                else
                    echo 'freshness=false;escalate=true'
                fi
            fi
        fi
    ")
    echo "$result" | grep -q 'freshness=true'
    echo "$result" | grep -q 'escalate=false'
}

@test "freshness-gate-stale-escapes-to-convergence" {
    local fixture="${BATS_TEST_TMPDIR}/stale.jsonl"
    local old_ts
    old_ts=$(date -u -d "@$(( $(date -u +%s) - 1500 ))" +%Y-%m-%dT%H:%M:%SZ)

    echo "{\"type\":\"control\",\"signal\":\"ALIVE\",\"from\":\"spec-executor\",\"to\":\"external-reviewer\",\"task\":\"task-1.3\",\"status\":\"active\",\"timestamp\":\"${old_ts}\",\"iteration\":3,\"reason\":\"step 3/5: reading design.md\"}" > "$fixture"

    local result
    result=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        STALENESS_MINUTES=10
        newest=\$(grep -v '^[[:space:]]*#' '$fixture' 2>/dev/null | jq -c 'select(.type==\"control\" and (.signal==\"ALIVE\" or .signal==\"STILL\"))' | tail -1)
        if [ -z \"\$newest\" ]; then
            echo 'freshness=false;escalate=true'
        else
            ts=\$(echo \"\$newest\" | jq -r '.timestamp')
            now_epoch=\$(date -u +%s)
            parse_epoch=\$(date -u -d \"\$ts\" +%s 2>/dev/null)
            if [ -z \"\$parse_epoch\" ]; then
                echo 'freshness=false;escalate=true'
            else
                age_min=\$(( (now_epoch - parse_epoch) / 60 ))
                if [ \$age_min -lt \$STALENESS_MINUTES ]; then
                    echo \"freshness=true;escalate=false;age=\${age_min}min\"
                else
                    echo \"freshness=false;escalate=true;age=\${age_min}min\"
                fi
            fi
        fi
    ")
    echo "$result" | grep -q 'freshness=false'
    echo "$result" | grep -q 'escalate=true'
}

@test "freshness-gate-skips-convergence-increment" {
    local fixture="${BATS_TEST_TMPDIR}/skip-inc.jsonl"
    local now_epoch
    now_epoch=$(date -u +%s)
    local future_ts
    future_ts=$(date -u -d "@$((now_epoch - 60))" +%Y-%m-%dT%H:%M:%SZ)

    echo "{\"type\":\"control\",\"signal\":\"ALIVE\",\"from\":\"spec-executor\",\"to\":\"external-reviewer\",\"task\":\"task-1.3\",\"status\":\"active\",\"timestamp\":\"${future_ts}\",\"iteration\":3,\"reason\":\"step 3/5: reading design.md\"}" > "$fixture"

    local convergence_rounds=0
    local escalated=false
    local result
    result=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        STALENESS_MINUTES=10
        newest=\$(grep -v '^[[:space:]]*#' '$fixture' 2>/dev/null | jq -c 'select(.type==\"control\" and (.signal==\"ALIVE\" or .signal==\"STILL\"))' | tail -1)
        convergence_rounds=0
        if [ -n \"\$newest\" ]; then
            ts=\$(echo \"\$newest\" | jq -r '.timestamp')
            now_epoch=\$(date -u +%s)
            parse_epoch=\$(date -u -d \"\$ts\" +%s 2>/dev/null)
            if [ -n \"\$parse_epoch\" ]; then
                age_min=\$(( (now_epoch - parse_epoch) / 60 ))
                if [ \$age_min -lt \$STALENESS_MINUTES ]; then
                    echo \"fresh=true;rounds=\${convergence_rounds};escalated=false\"
                    exit 0
                fi
            fi
        fi
        echo \"fresh=false;rounds=\$((convergence_rounds + 1));escalated=true\"
    ")
    echo "$result" | grep -q 'fresh=true'
    echo "$result" | grep -q 'rounds=0'
    echo "$result" | grep -q 'escalated=false'
}

@test "freshness-gate-empty-signals-jsonl" {
    local fixture="${BATS_TEST_TMPDIR}/empty.jsonl"
    > "$fixture"

    local result
    result=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        STALENESS_MINUTES=10
        newest=\$(grep -v '^[[:space:]]*#' '$fixture' 2>/dev/null | jq -c 'select(.type==\"control\" and (.signal==\"ALIVE\" or .signal==\"STILL\"))' | tail -1)
        if [ -z \"\$newest\" ]; then
            echo 'freshness=false;escalate=true;reason=empty'
        else
            echo 'freshness=unknown'
        fi
    ")
    echo "$result" | grep -q 'freshness=false'
}

# ── Phase 3.3: Bootstrap, byte-stable, skill, export, docs grep tests ─

@test "bootstrap-reads-chat-full-progress-git" {
    local reviewer_md="${AGENTS}/external-reviewer.md"
    grep -q 'chat.md' "$reviewer_md"
    grep -qi 'in full\|IN FULL\|in_full' "$reviewer_md"
    grep -q '.progress.md' "$reviewer_md"
    grep -Eq 'git (log|diff)' "$reviewer_md"
}

@test "bootstrap-lastReadLine-zero" {
    local reviewer_md="${AGENTS}/external-reviewer.md"
    grep -q 'lastReadLine.*0\|lastReadLine.*=.*0' "$reviewer_md"
    # The old "set lastReadLine to the current line count" should be absent
    ! grep -q 'lastReadLine.*current.*line\|lastReadLine.*to the current line count' "$reviewer_md"
}

@test "byte-stable-guard-fabrication" {
    local reviewer_md="${AGENTS}/external-reviewer.md"
    grep -q 'actively run the exact verify command' "$reviewer_md"
}

@test "byte-stable-guard-e2e-anti-pattern" {
    local reviewer_md="${AGENTS}/external-reviewer.md"
    grep -q 'e2e-anti-patterns\|anti-patterns\|Navigation Anti-Patterns' "$reviewer_md"
}

@test "skill-md-frontmatter-and-bootstrap" {
    local skill_md="${SKILLS}/reviewer-warmup/SKILL.md"
    [ -f "$skill_md" ]
    grep -q 'name: reviewer-warmup' "$skill_md"
    grep -q 'Bootstrap' "$skill_md"
    grep -q '10 min\|10-min\|STALENESS' "$skill_md"
    grep -qi 'freshness.*gate\|heartbeat.*fresh\|freshness.*fresh' "$skill_md"
}

@test "skill-reference-in-reviewer" {
    local reviewer_md="${AGENTS}/external-reviewer.md"
    local count
    count=$(grep -c 'See skill: reviewer-warmup' "$reviewer_md")
    [ "$count" -ge 2 ]
}

@test "implement-skill-export" {
    local implement_md="${COMMANDS}/implement.md"
    grep -q 'reviewer-warmup' "$implement_md"
    grep -qi 'automatic\|automatic-copy\|auto-' "$implement_md"
    grep -qi 'manual\|manual-path' "$implement_md"
    grep -q 'no known destination path' "$implement_md"
}

@test "docs-chat-md-heartbeat-legend" {
    local chat_md="${TEMPLATES}/chat.md"
    grep -qi 'heartbeat\|liveness' "$chat_md"
    grep -q 'ALIVE\|STILL' "$chat_md"
}

@test "docs-signals-jsonl-heartbeat-schema" {
    local signals_file="${TEMPLATES}/signals.jsonl"
    grep -qE 'ALIVE|STILL' "$signals_file"
    grep -qi 'heartbeat' "$signals_file"
}

@test "docs-coordinator-pattern-heartbeat" {
    local coord_md="${REFERENCES}/coordinator-pattern.md"
    grep -qi 'heartbeat' "$coord_md"
    grep -q 'ALIVE\|STILL' "$coord_md"
}

# ── Scripted heartbeat-sequence simulation ──────────────────────────

@test "heartbeat-sequence-simulation" {
    local fixture="${BATS_TEST_TMPDIR}/sequence.jsonl"
    > "$fixture"

    # Simulate: ALIVE at T0, STALL at T0+1m, then ALIVE at T0+2m, then stale at T0+20m
    local t0 t1 t2 t3
    t0=$(date -u -d "@$(( $(date -u +%s) - 1200 ))" +%Y-%m-%dT%H:%M:%SZ)
    t1=$(date -u -d "@$(( $(date -u +%s) - 1140 ))" +%Y-%m-%dT%H:%M:%SZ)
    t2=$(date -u -d "@$(( $(date -u +%s) - 1080 ))" +%Y-%m-%dT%H:%M:%SZ)
    t3=$(date -u -d "@$(( $(date -u +%s) - 300 ))" +%Y-%m-%dT%H:%M:%SZ)

    cat >> "$fixture" <<EOF
# Seed signals.jsonl — heartbeat simulation
{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-3.1","status":"active","timestamp":"${t0}","iteration":1,"reason":"step 1/3: reading spec-executor.md"}
{"type":"control","signal":"STILL","from":"spec-executor","to":"external-reviewer","task":"task-3.1","status":"active","timestamp":"${t1}","iteration":1,"reason":"step 1/3: long grep investigation"}
{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-3.1","status":"active","timestamp":"${t2}","iteration":2,"reason":"step 2/3: writing test cases"}
{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-3.1","status":"active","timestamp":"${t3}","iteration":3,"reason":"step 3/3: running bats"}
EOF

    # Verify the fixture is valid JSONL (each line is either a comment or valid JSON)
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        echo "$line" | jq -e . >/dev/null
    done < "$fixture"

    # Newest heartbeat should be fresh (300s = 5 min < 10 min)
    local newest result
    newest=$(grep -v '^[[:space:]]*#' "$fixture" | jq -c 'select(.type=="control" and (.signal=="ALIVE" or .signal=="STILL"))' | tail -1)
    [ -n "$newest" ]
    local ts now_epoch age_min
    ts=$(echo "$newest" | jq -r '.timestamp')
    now_epoch=$(date -u +%s)
    local parse_epoch
    parse_epoch=$(date -u -d "$ts" +%s 2>/dev/null)
    [ -n "$parse_epoch" ]
    age_min=$(( (now_epoch - parse_epoch) / 60 ))
    [ "$age_min" -lt 10 ]

    # Verify signal count respects non-blocking
    local count
    count=$(bash -c "
        source '${HOOKS}/lib-signals.sh'
        active_signal_count '$fixture'
    ")
    [ "$count" -eq 0 ]

    # Verify newest signal reason format
    local newest_reason
    newest_reason=$(echo "$newest" | jq -r '.reason')
    [[ "$newest_reason" =~ ^step\ [0-9]+/[0-9]+:\ .+ ]]
}
