#!/usr/bin/env bash
# replay-signals.sh — Deterministic replay of signals.jsonl at iteration N.
#
# Usage: replay-signals.sh <spec-path> [--at-iteration N]
#
# As the FIRST action, invokes migrate-state.sh to ensure legacy state is migrated.
#
# Algorithm: stateful fold over signals.jsonl line-by-line. For each (task, signal)
# pair, the latest event by (iteration, line-number) wins. Outputs only entries
# whose final status=="active" at iteration N. Tie-break by file order when
# iterations match.
#
# Maps to: design.md Implementation Step 13, FR-13, AC-4.3, NFR-4

set -euo pipefail

SPEC_PATH=""
AT_ITERATION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --at-iteration) AT_ITERATION="$2"; shift 2 ;;
    -*) echo "Usage: $0 <spec-path> [--at-iteration N]" >&2; exit 1 ;;
    *)  SPEC_PATH="$1"; shift ;;
  esac
done

if [[ -z "$SPEC_PATH" ]]; then
  echo "Usage: $0 <spec-path> [--at-iteration N]" >&2
  exit 1
fi

if [[ -z "$AT_ITERATION" ]]; then
  echo "Usage: $0 <spec-path> [--at-iteration N]" >&2
  exit 1
fi

# FIRST ACTION: migrate legacy state (per loader-site rule from 1.18a)
STATE_FILE="${SPEC_PATH}/.ralph-state.json"
if [[ -f "$STATE_FILE" ]]; then
  MIGRATE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migrate-state.sh"
  if [[ -f "$MIGRATE_SCRIPT" ]]; then
    bash "$MIGRATE_SCRIPT" "$STATE_FILE" 2>/dev/null || true
  fi
fi

SIGNALS_FILE="${SPEC_PATH}/signals.jsonl"
if [[ ! -f "$SIGNALS_FILE" ]]; then
  exit 0
fi

# Stateful fold: for each (task, signal) pair, track the latest entry.
# We use jq to process the JSONL and keep the latest entry per task+signal.
# Then filter to status=="active" at iteration <= AT_ITERATION.

# Parse the JSONL, skipping comment lines (starting with #),
# then apply the stateful fold to find active signals at AT_ITERATION.
grep -v '^#' "$SIGNALS_FILE" 2>/dev/null | grep -v '^$' | jq -s '
  # Filter to entries up to AT_ITERATION
  [ .[] | select(.iteration <= '"$AT_ITERATION"') |
    # Add line number for tie-breaking
    . + {line_num: (. as $e | range(0; input_line_number))}
  ] |
  # Group by task+signal
  group_by(.task + "|" + (.signal // "NONE")) |
  # For each group, pick the entry with the highest iteration (tie-break: highest line_num)
  map(
    sort_by(.iteration, .line_num) | last |
    select(.status == "active") |
    "\(.task)\t\(.signal)\t\(.status)"
  ) |
  join("\n")
' 2>/dev/null || true
