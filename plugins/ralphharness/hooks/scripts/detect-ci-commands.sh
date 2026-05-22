#!/usr/bin/env bash

# detect-ci-commands.sh — Scan project markers and emit per-category CI commands.
# Usage: detect-ci-commands.sh <spec-path> [--force]
# Output: JSON array [{command, category}, ...]

# --- Marker detection functions ---

detect_pyproject() {
  local base="$1"
  [[ -f "$base/pyproject.toml" ]] || return 0

  ENTRIES+=('{"command":"ruff check .","category":"lint"}')
  ENTRIES+=('{"command":"ruff format --check .","category":"lint"}')
  ENTRIES+=('{"command":"mypy .","category":"typecheck"}')
  ENTRIES+=('{"command":"pytest","category":"test"}')
}

detect_package_json() {
  local base="$1"
  [[ -f "$base/package.json" ]] || return 0

  # Detect lockfile to choose package manager
  local pkgmgr="npm"
  if [[ -f "$base/pnpm-lock.yaml" ]]; then
    pkgmgr="pnpm"
  elif [[ -f "$base/yarn.lock" ]]; then
    pkgmgr="yarn"
  fi

  # Parse scripts and categorize by name pattern
  if command -v jq >/dev/null 2>&1; then
    local scripts
    scripts=$(jq -r '.scripts // {} | keys[]' "$base/package.json" 2>/dev/null || true)
    while IFS= read -r script_name; do
      [[ -n "$script_name" ]] || continue
      local category="other"
      case "$script_name" in
        lint*)         category="lint" ;;
        typecheck*|type-*|check-types*|tsc*) category="typecheck" ;;
        test*|spec*)   category="test" ;;
        build*|bundle*|pack*)  category="build" ;;
      esac
      ENTRIES+=("{\"command\":\"${pkgmgr} run ${script_name}\",\"category\":\"${category}\"}")
    done <<< "$scripts"
  fi
}

detect_makefile() {
  local base="$1"
  local mf=""
  for candidate in "$base/Makefile" "$base/makefile"; do
    if [[ -f "$candidate" ]]; then
      mf="$candidate"
      break
    fi
  done
  [[ -n "$mf" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    local category="other"
    case "$target" in
      lint)          category="lint" ;;
      test)          category="test" ;;
      check)         category="typecheck" ;;
      build|bundle)  category="build" ;;
      lint-*)        category="lint" ;;
      test-*)        category="test" ;;
    esac
    ENTRIES+=("{\"command\":\"make ${target}\",\"category\":\"${category}\"}")
  done < <(grep -E '^[a-zA-Z_-]+:' "$mf" 2>/dev/null | sed 's/:.*//' | grep -E '^(lint|test|check|build|lint-|test-)' || true)
}

detect_cargo() {
  local base="$1"
  [[ -f "$base/Cargo.toml" ]] || return 0

  ENTRIES+=('{"command":"cargo clippy","category":"lint"}')
  ENTRIES+=('{"command":"cargo fmt --check","category":"lint"}')
  ENTRIES+=('{"command":"cargo test","category":"test"}')
}

detect_go_mod() {
  local base="$1"
  [[ -f "$base/go.mod" ]] || return 0

  ENTRIES+=('{"command":"go vet ./...","category":"lint"}')
  ENTRIES+=('{"command":"go test ./...","category":"test"}')
}

detect_ci_commands() {
  local SPEC_PATH="$1"
  local ENTRIES=()
  local FILTERED=()

  # --- Run all detect functions ---
  detect_pyproject "$SPEC_PATH"
  detect_package_json "$SPEC_PATH"
  detect_makefile "$SPEC_PATH"
  detect_cargo "$SPEC_PATH"
  detect_go_mod "$SPEC_PATH"

  # --- Write-time command -v filter (AC-2.4, D5) ---
  for entry in "${ENTRIES[@]}"; do
    # Extract the binary name (first token of command string) using pure bash
    # entry: {"command":"ruff check .","category":"lint"}
    local cmd="${entry#*\"command\":\"}"
    cmd="${cmd%%\",*}"
    local bin="${cmd%% *}"
    if command -v "$bin" >/dev/null 2>&1; then
      FILTERED+=("$entry")
    else
      echo "[detect-ci-commands] WARN: skipping $cmd binary $bin not on PATH" >&2
    fi
  done

  # --- Output ---
  if [[ ${#FILTERED[@]} -eq 0 ]]; then
    echo "[]"
  else
    ENTRIES=("${FILTERED[@]}")
    local last_idx=$(( ${#ENTRIES[@]} - 1 ))
    echo "["
    local i
    for i in "${!ENTRIES[@]}"; do
      if [[ $i -eq $last_idx ]]; then
        echo "  ${ENTRIES[$i]}"
      else
        echo "  ${ENTRIES[$i]},"
      fi
    done
    echo "]"
  fi
  return 0
}

# CLI body: only runs when executed directly (not sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  FORCE=0
  SPEC_PATH=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE=1; shift ;;
      -*)      echo "Usage: $0 <spec-path> [--force]" >&2; exit 1 ;;
      *)       SPEC_PATH="$1"; shift ;;
    esac
  done

  if [[ -z "$SPEC_PATH" ]]; then
    echo "Usage: $0 <spec-path> [--force]" >&2
    exit 1
  fi

  if [[ ! -d "$SPEC_PATH" ]]; then
    echo "Error: spec path '$SPEC_PATH' does not exist" >&2
    exit 1
  fi

  detect_ci_commands "$SPEC_PATH"
fi
