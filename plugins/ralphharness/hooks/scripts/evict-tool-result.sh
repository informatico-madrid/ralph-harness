#!/usr/bin/env bash
# evict-tool-result.sh — Agent-invoked tool-result eviction helper for Smart Ralph.
# Routes oversized tool output to disk; emits a preview for chat.
# NOT interception — invoked by the agent per a prompt-rule.
#
# Usage:
#   echo "<tool output>" | evict-tool-result.sh <spec_path> <tool_kind> [--pair-debug]
#   tool_kind in: grep | gitdiff | fileread | lsfind
#   stdout: first 50 lines + summary if evicted, or input unchanged if below threshold
#   Exit 0: always (degradation never blocks)

set -euo pipefail

# --- Arg Parsing ---
SPEC_PATH=""
TOOL_KIND=""
PAIR_DEBUG=0

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pair-debug)
      PAIR_DEBUG=1
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# First non-flag arg is spec_path, second is tool_kind
SPEC_PATH="${ARGS[0]:-}"
TOOL_KIND="${ARGS[1]:-}"

if [ -z "$SPEC_PATH" ] || [ -z "$TOOL_KIND" ]; then
  echo "[ralphharness] ERROR: usage: evict-tool-result.sh <spec_path> <tool_kind> [--pair-debug]" >&2
  cat  # pass through stdin if args missing
  exit 0
fi

# Validate tool_kind
case "$TOOL_KIND" in
  grep|gitdiff|fileread|lsfind) ;;
  *)
    echo "[ralphharness] WARN: unknown tool_kind '$TOOL_KIND', passing through" >&2
    cat
    exit 0
    ;;
esac

# --- Read stdin ---
INPUT="$(cat)"
INPUT_LINES="$(echo "$INPUT" | wc -l)"

# --- Pair-debug: always pass through ---
if [ "$PAIR_DEBUG" -eq 1 ]; then
  echo "$INPUT"
  exit 0
fi

# --- Per-kind thresholds ---
declare -A THRESHOLDS
THRESHOLDS[grep]=100
THRESHOLDS[gitdiff]=200
THRESHOLDS[fileread]=500
THRESHOLDS[lsfind]=300

THRESHOLD="${THRESHOLDS[$TOOL_KIND]:-300}"

# --- Pass-through if below threshold ---
if [ "$INPUT_LINES" -le "$THRESHOLD" ]; then
  echo "$INPUT"
  exit 0
fi

# --- Spec dir writable check ---
if [ -d "$SPEC_PATH" ] && [ -w "$SPEC_PATH" ]; then
  EVICTED=1
else
  echo "$INPUT"
  echo "[evicted] degraded: spec dir not writable" >&2
  exit 0
fi

# --- Evict to disk ---
TOOL_RESULTS_DIR="${SPEC_PATH}/.tool-results"
mkdir -p "$TOOL_RESULTS_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVICT_FILE="${TOOL_RESULTS_DIR}/${TOOL_KIND}-${TIMESTAMP}.txt"

# Write full content to disk
printf '%s\n' "$INPUT" > "$EVICT_FILE"

# Emit first 50 lines as preview
echo "$INPUT" | head -n 50
echo ""
echo "[evicted] ${INPUT_LINES} lines total, full output: .tool-results/${TOOL_KIND}-${TIMESTAMP}.txt"
