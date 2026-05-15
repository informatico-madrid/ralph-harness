#!/usr/bin/env bash
# migrate-state.sh — One-shot migrator for legacy .ralph-state.json ciCommands shape.
#
# Contract: Every reader of .ralph-state.json that touches .ciCommands MUST call this
# migrator first. Legacy ciCommands were a string[]; the canonical shape is
# [{command, category}]. This script rewrites state once (idempotent) and logs a WARN.
#
# Loader sites (as of spec signal-log-and-ci-autodetect):
#   - implement.md Step 3 (lines ~179-180) — primary loader, invoked before orchestrator
#   - stop-watcher.sh — reads state via jq empty corruption check; does NOT read ciCommands
#     shape, so legacy ciCommands does not affect this reader (documented finding only)
#   - replay-signals.sh — future reader (Phase 3, task 3.21); must call migrate-state.sh
#     at script top
#
# Usage: bash plugins/ralphharness/hooks/scripts/migrate-state.sh <state-file>

set -euo pipefail

migrate_cicommands() {
  local state_file="$1"
  local spec_dir
  spec_dir="$(dirname "$state_file")"
  local progress_md="${spec_dir}/.progress.md"

  # Check if already migrated: ciCommands[0] should be an object
  local first_type
  first_type=$(jq -r '.ciCommands[0] | type // "null"' "$state_file" 2>/dev/null || echo "null")

  if [ "$first_type" = "string" ]; then
    # Legacy string[] detected — wrap each string into {command, category: "other"}
    local migrated
    migrated=$(jq '
      .ciCommands |= map(if type == "string" then {command: ., category: "other"} else . end)
    ' "$state_file")

    # Atomic write: tmp then mv
    echo "$migrated" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"

    # Log WARN to .progress.md
    echo "[ralphharness] WARN: migrated legacy ciCommands string[] to [{command,category}]" >> "$progress_md"
  fi
  # If first_type is "object" or "null", the state is already migrated — no-op.
}

# Main: expect one argument (state file path)
if [ $# -lt 1 ]; then
  echo "[ralphharness] migrate-state.sh: usage: migrate-state.sh <state-file>" >&2
  exit 1
fi

migrate_cicommands "$1"
