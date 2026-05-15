#!/usr/bin/env bash
# lib-signals.sh — Canonical signal-log helpers for Phase 6 (signal-log-and-ci-autodetect)
# All writers (coordinator, external-reviewer, spec-executor, human) source this file.
# fd 202 is reserved exclusively for signals.jsonl.lock.
#
# Usage:
#   source "$CLAUDE_PLUGIN_ROOT/hooks/scripts/lib-signals.sh"
#   append_signal "$SPEC_PATH" "$payload"
#   count=$(active_signal_count "$SPEC_PATH")

# BEGIN ATOMIC-APPEND
append_signal() {
  local spec_path="$1" payload="$2"
  # Validate JSON BEFORE acquiring the lock (no torn-write risk if invalid).
  echo "$payload" | jq -e . >/dev/null || { echo "[ralphharness] malformed signal payload, aborting" >&2; return 2; }
  (
    exec 202>"${spec_path}/signals.jsonl.lock"
    flock -x -w 5 202 || { echo "[ralphharness] flock timeout on signals.jsonl.lock" >&2; exit 75; }
    printf '%s\n' "$payload" >> "${spec_path}/signals.jsonl"
  ) 202>"${spec_path}/signals.jsonl.lock"
}
# END ATOMIC-APPEND

# BEGIN ACTIVE-SIGNAL-COUNT
active_signal_count() {
  local spec_path="$1"
  grep -v '^[[:space:]]*#' "${spec_path}/signals.jsonl" 2>/dev/null \
    | jq -c 'select(.status=="active") | select(.signal=="HOLD" or .signal=="PENDING" or .signal=="URGENT" or .signal=="DEADLOCK")' \
    | wc -l | tr -d ' '
}
# END ACTIVE-SIGNAL-COUNT

# BEGIN DEDUPE-CI-COMMANDS
# Deduplicates CI command arrays by (command, category) tuple.
# Reads concatenated JSON arrays from stdin, emits unique tuples.
# Per D4: dedupe by (command, category) to preserve semantic distinction.
dedupe_ci_commands() {
  jq -s 'add | unique_by([.command, .category])'
}
# END DEDUPE-CI-COMMANDS
