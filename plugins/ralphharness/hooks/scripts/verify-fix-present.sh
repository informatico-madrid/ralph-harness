#!/usr/bin/env bash
set -euo pipefail

# verify-fix-present.sh — deterministic fix-presence gate
#
# Exit-code contract:
#   0  — fix present (file changed and pattern matches, if supplied)
#   1  — file unchanged since base in all 3 states (committed, staged, working-tree)
#   2  — pattern absent in committed version of the file
#   3  — base ref unresolvable (merge-base + checkpoint fallback exhausted)
#
# Usage: verify-fix-present.sh <file> [pattern]
#
# Components: 2 (three-state diff)
# Requirements: FR-5, AC-2.1

file="${1:-}"
pattern="${2:-}"

if [[ -z "$file" ]]; then
  echo "Usage: verify-fix-present.sh <file> [pattern]" >&2
  echo "  file  — path to file to check (relative to repo root)" >&2
  echo "  pattern — optional literal string to confirm present in committed file" >&2
  exit 2
fi

# TODO (task 1.2): compute base ref (git merge-base HEAD origin/main,
#   fallback to checkpoint SHA, exit 3 on failure).
#
# TODO (task 1.3): three-state diff (committed $base→HEAD, staged, working-tree)
#   + optional pattern check.

exit 0
