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

# --- Base-ref resolution (task 1.2) ---
base=""
if git merge-base HEAD origin/main >/dev/null 2>&1; then
  base=$(git merge-base HEAD origin/main)
else
  # Fallback: resolve current spec via .current-spec + read checkpoint SHA
  _spec_path=""
  _current_spec_file=""
  if [[ -n "${RALPH_CWD:-}" ]] && [[ -d "${RALPH_CWD}" ]]; then
    _spec_dir="${RALPH_CWD}"
  else
    _spec_dir="$(pwd)"
  fi
  # Search common spec directories for .current-spec
  for _candidate_dir in specs _specs; do
    if [[ -f "$_spec_dir/$_candidate_dir/.current-spec" ]]; then
      _spec_dir="$_spec_dir/$_candidate_dir"
      _current_spec_file="$_spec_dir/.current-spec"
      break
    fi
  done
  if [[ -n "${_current_spec_file:-}" ]] && [[ -f "$_current_spec_file" ]]; then
    _spec_name="$(cat "$_current_spec_file" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -n "$_spec_name" ]] && [[ -d "$_spec_dir/$_spec_name" ]]; then
      _spec_path="$_spec_dir/$_spec_name"
    fi
  fi
  if [[ -n "${_spec_path:-}" ]] && [[ -f "$_spec_path/.ralph-state.json" ]]; then
    _ckpt_sha="$(jq -r '.checkpoint.sha // empty' "$_spec_path/.ralph-state.json" 2>/dev/null || true)"
    if [[ -n "$_ckpt_sha" ]] && [[ "$_ckpt_sha" != "null" ]]; then
      base="$_ckpt_sha"
      echo "WARN: origin/main unreachable, base=$_ckpt_sha" >&2
    fi
  fi
  if [[ -z "$base" ]]; then
    echo "ERROR: cannot resolve base ref" >&2
    exit 3
  fi
fi

# TODO (task 1.3): three-state diff (committed $base→HEAD, staged, working-tree)
#   + optional pattern check.

exit 0
