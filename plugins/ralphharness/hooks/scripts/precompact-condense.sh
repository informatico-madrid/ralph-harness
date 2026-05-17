#!/usr/bin/env bash
# precompact-condense.sh — Emergency condensation triggered by Claude Code PreCompact hook.
# Runs before auto-compaction (~95% of 200k token window) to prevent context overflow.
# Always exits 0 so it never blocks compaction.
#
# Usage: invoked automatically by PreCompact hook, no args needed.

set -euo pipefail

# Source path resolver
CLAUDE_PLUGIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/plugins/ralphharness"
source "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/path-resolver.sh"

# Resolve active spec
SPEC_PATH=""
SPEC_PATH="$(ralph_resolve_current 2>/dev/null || true)"

if [ -z "$SPEC_PATH" ]; then
  # No active spec — nothing to condense, exit silently
  exit 0
fi

# Normalize spec path to absolute
if [[ "$SPEC_PATH" == /* ]]; then
  : # already absolute
else
  SPEC_PATH="$(cd "$SPEC_PATH" 2>/dev/null && pwd 2>/dev/null || echo "$SPEC_PATH")"
fi

# Call condensation — always exit 0 even if it fails
"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/condense-context.sh" "$SPEC_PATH" --mode emergency 2>/dev/null || true

exit 0
