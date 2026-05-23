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

detect_gemfile() {
  local base="$1"
  [[ -f "$base/Gemfile" ]] || return 0

  ENTRIES+=('{"command":"bundle exec rspec","category":"test"}')
  ENTRIES+=('{"command":"bundle exec rubocop","category":"lint"}')
}

detect_composer() {
  local base="$1"
  [[ -f "$base/composer.json" ]] || return 0

  # Parse scripts and categorize by name pattern
  if command -v jq >/dev/null 2>&1; then
    local scripts
    scripts=$(jq -r '.scripts // {} | keys[]' "$base/composer.json" 2>/dev/null || true)
    if [[ -n "$scripts" ]]; then
      while IFS= read -r script_name; do
        [[ -n "$script_name" ]] || continue
        local category="other"
        case "$script_name" in
          test*)             category="test" ;;
          lint*|cs*|fix*)    category="lint" ;;
          analyze*|analyse*|phpstan*|psalm*) category="typecheck" ;;
          build*)            category="build" ;;
        esac
        ENTRIES+=("{\"command\":\"composer run ${script_name}\",\"category\":\"${category}\"}")
      done <<< "$scripts"
      return 0
    fi
  fi

  # Fallback: no scripts key / no jq
  ENTRIES+=('{"command":"composer test","category":"test"}')
}

detect_gradle() {
  local base="$1"
  [[ -f "$base/build.gradle" || -f "$base/build.gradle.kts" ]] || return 0
  # Always emit ./gradlew so the filter can decide (executable check + WARN on stderr)
  if [[ -x "$base/gradlew" ]]; then
    ENTRIES+=('{"command":"./gradlew test","category":"test"}')
    ENTRIES+=('{"command":"./gradlew build","category":"build"}')
  else
    ENTRIES+=('{"command":"gradle test","category":"test"}')
    ENTRIES+=('{"command":"gradle build","category":"build"}')
  fi
}

detect_maven() {
  local base="$1"
  [[ -f "$base/pom.xml" ]] || return 0
  # Always emit ./mvnw so the filter can decide (executable check + WARN on stderr)
  if [[ -x "$base/mvnw" ]]; then
    ENTRIES+=('{"command":"./mvnw test","category":"test"}')
    ENTRIES+=('{"command":"./mvnw package","category":"build"}')
  else
    ENTRIES+=('{"command":"mvn test","category":"test"}')
    ENTRIES+=('{"command":"mvn package","category":"build"}')
  fi
}

detect_mix() {
  local base="$1"
  [[ -f "$base/mix.exs" ]] || return 0

  # Best-effort: grep known alias keys anywhere in mix.exs (atom-keyed: test:, "test:", "test.all:")
  local keys
  keys=$(grep -oE '(^|[^a-zA-Z0-9_])"?(test|lint|credo|dialyzer|format)[a-zA-Z0-9_.]*"?[[:space:]]*:' "$base/mix.exs" 2>/dev/null \
    | grep -oE '(test|lint|credo|dialyzer|format)[a-zA-Z0-9_.]*' || true)
  if [[ -n "$keys" ]]; then
    while IFS= read -r alias_name; do
      [[ -n "$alias_name" ]] || continue
      local category="other"
      case "$alias_name" in
        test*)    category="test" ;;
        lint*)    category="lint" ;;
        credo)    category="lint" ;;
        dialyz*)  category="typecheck" ;;
        format*)  category="lint" ;;
      esac
      ENTRIES+=("{\"command\":\"mix ${alias_name}\",\"category\":\"${category}\"}")
    done <<< "$keys"
    return 0
  fi

  # Canonical fallback
  ENTRIES+=('{"command":"mix test","category":"test"}')
  ENTRIES+=('{"command":"mix credo","category":"lint"}')
  ENTRIES+=('{"command":"mix dialyzer","category":"typecheck"}')
  ENTRIES+=('{"command":"mix format --check-formatted","category":"lint"}')
}

detect_deno() {
  local base="$1"
  [[ -f "$base/deno.json" || -f "$base/deno.jsonc" ]] || return 0

  # Best-effort: parse deno.json or deno.jsonc with jq, emit deno task <name> per key
  local cfg=""
  [[ -f "$base/deno.json" ]] && cfg="$base/deno.json"
  if [[ -z "$cfg" && -f "$base/deno.jsonc" ]]; then cfg="$base/deno.jsonc"; fi
  if [[ -n "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    local tasks
    tasks=$(jq -r '.tasks // {} | keys[]' "$cfg" 2>/dev/null || true)
    if [[ -n "$tasks" ]]; then
      while IFS= read -r task_name; do
        [[ -n "$task_name" ]] || continue
        local category="other"
        case "$task_name" in
          test*)              category="test" ;;
          lint*)              category="lint" ;;
          fmt*|format*)       category="lint" ;;
          check*|typecheck*)  category="typecheck" ;;
          build*|bundle*)     category="build" ;;
        esac
        ENTRIES+=("{\"command\":\"deno task ${task_name}\",\"category\":\"${category}\"}")
      done <<< "$tasks"
      return 0
    fi
  fi

  # Fallback: no tasks key / jq-fail / no tasks → canonical
  ENTRIES+=('{"command":"deno test","category":"test"}')
  ENTRIES+=('{"command":"deno lint","category":"lint"}')
  ENTRIES+=('{"command":"deno check","category":"typecheck"}')
  ENTRIES+=('{"command":"deno fmt --check","category":"lint"}')
}

detect_dotnet() {
  local base="$1"
  if compgen -G "$base/*.csproj" >/dev/null 2>&1 || compgen -G "$base/*.sln" >/dev/null 2>&1 || [[ -f "$base/global.json" ]]; then
    ENTRIES+=('{"command":"dotnet test","category":"test"}')
    ENTRIES+=('{"command":"dotnet build","category":"build"}')
    ENTRIES+=('{"command":"dotnet format --verify-no-changes","category":"lint"}')
  fi
  return 0
}

detect_ci_commands() {
  local SPEC_PATH="$1"
  local ENTRIES=()
  local FILTERED=()
  local cmd bin keep

  # --- Run all detect functions ---
  detect_pyproject "$SPEC_PATH"
  detect_package_json "$SPEC_PATH"
  detect_makefile "$SPEC_PATH"
  detect_cargo "$SPEC_PATH"
  detect_go_mod "$SPEC_PATH"
  detect_gemfile "$SPEC_PATH"
  detect_composer "$SPEC_PATH"
  detect_gradle "$SPEC_PATH"
  detect_maven "$SPEC_PATH"
  detect_mix "$SPEC_PATH"
  detect_deno "$SPEC_PATH"
  detect_dotnet "$SPEC_PATH"

  # --- Write-time command -v filter (AC-2.4, D5) ---
  for entry in "${ENTRIES[@]}"; do
    # Extract the binary name (first token of command string) using pure bash
    # entry: {"command":"ruff check .","category":"lint"}
    cmd="${entry#*\"command\":\"}"
    cmd="${cmd%%\",*}"
    bin="${cmd%% *}"
    keep=1
    if [[ "$bin" == ./* ]]; then
      [[ -x "$SPEC_PATH/$bin" ]] || keep=0
    else
      command -v "$bin" >/dev/null 2>&1 || keep=0
    fi
    if [[ "$keep" -eq 1 ]]; then
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
