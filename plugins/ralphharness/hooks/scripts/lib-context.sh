#!/usr/bin/env bash
# lib-context.sh — Shared context helpers for Smart Ralph context middleware.
# Sourced by stop-watcher.sh, condense-context.sh, and the PreCompact hook.
# Parallel to lib-signals.sh — keeps context concerns separate from signal concerns.
#
# Usage:
#   source "$CLAUDE_PLUGIN_ROOT/hooks/scripts/lib-context.sh"
#   lines=$(combined_line_count "$SPEC_PATH")
#   pct=$(transcript_usage_pct "$TRANSCRIPT_PATH")
#   write_condensation_metric "$SPEC_PATH" "proactive" 2270 305 87 ".archive.20260517T120000Z.md"

# BEGIN COMBINED-LINE-COUNT
# Returns combined line count of chat.md + .progress.md in the spec directory.
# Missing files count as 0 lines.
# Usage: combined_line_count <spec_path>
# Echoes: integer total line count
combined_line_count() {
  local spec_path="$1"
  local count=0
  local file

  for file in chat.md .progress.md; do
    if [ -f "${spec_path}/${file}" ]; then
      local lines
      lines="$(wc -l < "${spec_path}/${file}" 2>/dev/null || echo 0)"
      if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
        echo "[ralphharness] WARN: wc returned non-numeric for ${file} in ${spec_path}, treating as 0" >&2
        lines=0
      fi
      count=$(( count + lines ))
    fi
  done

  echo "$count"
}
# END COMBINED-LINE-COUNT

# BEGIN TRANSCRIPT-USAGE-PCT
# Computes token usage percentage from the transcript JSONL.
# Reads the LAST assistant message with .message.usage from the tail.
# Returns integer 0-100.
# Usage: transcript_usage_pct <transcript_path>
# Echoes: integer percentage (0-100)
transcript_usage_pct() {
  local transcript_path="${1:-}"

  # Empty path, missing file, or empty file → 0%
  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ] || [ ! -s "$transcript_path" ]; then
    echo 0
    return 0
  fi

  local usage_tokens=0
  local line

  # Tail the JSONL and find the LAST assistant message with .message.usage.
  # First match wins when iterating from tail.
  local line_count=0
  local malformed_count=0
  while IFS= read -r line; do
    line_count=$((line_count + 1))
    # Tolerate up to 10 malformed lines (e.g. compact markers, non-JSON lines)
    local usage
    usage="$(echo "$line" | jq -r 'select(.message.role=="assistant") | .message.usage // empty' 2>/dev/null)"
    if [ -n "$usage" ] && [ "$usage" != "null" ]; then
      usage_tokens="$(echo "$usage" | jq -r '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null || echo 0)"
      if [[ "$usage_tokens" =~ ^[0-9]+$ ]]; then
        break
      fi
    fi
  done < <(tac "$transcript_path" 2>/dev/null)

  local pct=0
  if [ "$usage_tokens" -gt 0 ] 2>/dev/null; then
    local window
    window="$(context_window_size)"
    if [ "$window" -gt 0 ] 2>/dev/null; then
      pct=$(( usage_tokens * 100 / window ))
    fi
  fi

  echo "$pct"
}
# END TRANSCRIPT-USAGE-PCT

# BEGIN SPEC-DIR-WRITABLE
# Returns 0 if the spec directory is writable, 1 if not.
# Usage: spec_dir_writable <spec_path>
spec_dir_writable() {
  local spec_path="$1"
  if [ -d "$spec_path" ] && [ -w "$spec_path" ]; then
    return 0
  else
    return 1
  fi
}
# END SPEC-DIR-WRITABLE

# BEGIN CONTEXT-WINDOW-SIZE
# Returns the context window size constant.
# Default: 200000 (Opus/Sonnet/Haiku 200k window).
# Edit this function to change for non-Opus models.
# Usage: context_window_size
# Echoes: integer window size
context_window_size() {
  echo 200000
}
# END CONTEXT-WINDOW-SIZE

# BEGIN WRITE-CONDENSATION-METRIC
# Appends a condensation event to .metrics.jsonl with flock concurrency protection.
# Uses fd 201 for .metrics.lock (distinct from fd 200 chat-lock and fd 202 signals-lock).
# Must be called AFTER the fd-200 chat-lock subshell in condense-context.sh has closed.
#
# Usage: write_condensation_metric <spec_path> <mode> <linesBefore> <linesAfter> <tokensPct> <archivePath>
#   mode: proactive | reactive | emergency
#   linesBefore: combined line count before condensation
#   linesAfter: combined line count after condensation
#   tokensPct: transcript usage % (0 for proactive line-count triggers)
#   archivePath: relative path to the archive file (e.g. ".archive.20260517T120000Z.md")
write_condensation_metric() {
  local spec_path="$1"
  local mode="$2"
  local lines_before="$3"
  local lines_after="$4"
  local tokens_pct="$5"
  local archive_path="$6"

  local lock_file="${spec_path}/.metrics.lock"
  local metrics_file="${spec_path}/.metrics.jsonl"

  # Generate event ID and timestamp
  local event_id
  if event_id="$(date +%s%N 2>/dev/null)" && [[ "$event_id" =~ ^[0-9]+$ ]]; then
    : # Linux: nanosecond epoch
  else
    event_id="$(date +%s 2>/dev/null || echo 0)000000000"
  fi

  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"

  # Acquire exclusive lock on fd 201 for .metrics.lock
  (
    flock -x 201 || {
      echo "[ralphharness] ERROR: failed to acquire lock for ${metrics_file}" >&2
      exit 1
    }

    # Append condensation event via jq -n --arg (injection-safe)
    if ! jq -c -n \
      --arg schemaVersion "1" \
      --arg eventId "$event_id" \
      --arg timestamp "$timestamp" \
      --arg spec "$spec_path" \
      --arg event "condensation" \
      --arg mode "$mode" \
      --argjson linesBefore "$lines_before" \
      --argjson linesAfter "$lines_after" \
      --argjson tokensBeforePct "$tokens_pct" \
      --arg archivePath "$archive_path" \
      '{
        schemaVersion: ($schemaVersion | tonumber),
        eventId: $eventId,
        timestamp: $timestamp,
        spec: $spec,
        event: $event,
        mode: $mode,
        linesBefore: $linesBefore,
        linesAfter: $linesAfter,
        tokensBeforePct: $tokensBeforePct,
        archivePath: $archivePath
      }' >> "$metrics_file" 2>/dev/null; then
      echo "[ralphharness] ERROR: jq failed writing condensation metric to ${metrics_file}" >&2
      exit 1
    fi

  ) 201>"$lock_file"
}
# END WRITE-CONDENSATION-METRIC
