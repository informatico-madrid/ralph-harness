#!/usr/bin/env bash
# discover-ci.sh — CI command discovery for Smart Ralph execution loop.
# Provides discover_ci_commands function that scans repo for CI commands.
# This is a standalone version to avoid sourcing the entire stop-watcher.sh.

# CI Command Discovery
discover_ci_commands() {
  local repo_root="$1"
  local tmpfile
  tmpfile=$(mktemp)

  # Scan .github/workflows/*.yml for "- run:" command lines
  if [ -d "$repo_root/.github/workflows" ]; then
    for wf in "$repo_root/.github/workflows"/*.yml; do
      [ -f "$wf" ] || continue
      # Extract content after "- run:" from each workflow file
      { grep -E '^[[:space:]]+-[[:space:]]+run:' "$wf" 2>/dev/null \
          | sed -E 's/^[[:space:]]*-[[:space:]]+run:[[:space:]]*//' \
          | while IFS= read -r line || [[ -n "$line" ]]; do
              [ -z "$line" ] && continue
              # Skip YAML block scalar indicators and comments
              case "$line" in
                \#*|"|"*) continue ;;
              esac
              line=$(printf '%s\n' "$line" | sed 's/[[:space:]]*$//')
              [ -z "$line" ] && continue
              echo "$line"
            done; } >> "$tmpfile"
    done
  fi

  # Scan tests/*.bats for test commands
  if [ -d "$repo_root/tests" ]; then
    for bats_file in "$repo_root/tests"/*.bats; do
      [ -f "$bats_file" ] || continue
      # Extract test runner invocations (e.g., "bats tests/", "test/unit.sh")
      grep -E '^[[:space:]]*(bats|test|./tests/)' "$bats_file" 2>/dev/null \
        | grep -v '^[[:space:]]*#' \
        | grep -v '^[[:space:]]*local ' \
        | head -5 \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]*$//' \
        | grep -v '^$' \
        >> "$tmpfile"
    done
  fi

  # Deduplicate, classify into categories, and return as JSON array
  if [ -s "$tmpfile" ]; then
    # Deduplicate input lines
    local deduped
    deduped=$(mktemp)
    sort -u "$tmpfile" > "$deduped"

    local json_entries="["
    local first=true
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      local category="test"
      case "$cmd" in
        *mocha*|*jest*|*vitest*|*pytest*|*bats*|*tape*|*nodeunit*|*tap*|*"npm test"*|*"npm run test"*|*"yarn test"*|*"pnpm test"*)
          category="test" ;;
        *eslint*|*prettier*|*stylelint*|*biome*|*flake8*|*pylint*|*shellcheck*|*black*|*checkstyle*|*"npm run lint"*|*"npm run format"*)
          category="lint" ;;
        *webpack*|*rollup*|*esbuild*|*vite*|*"npm run build"*|*gradle*|*mvn*|*make*|*cargo*|*"go build"*)
          category="build" ;;
        *--noEmit*|*mypy*|*pyright*|*"npx tsc"*)
          category="typecheck" ;;
        *tsc*)
          category="build" ;;
      esac
      if [ "$first" = true ]; then
        first=false
      else
        json_entries+=","
      fi
      json_entries+=$(jq -n --arg c "$cmd" --arg cat "$category" '{"command": $c, "category": $cat}')
    done < "$deduped"
    json_entries+="]"
    echo "$json_entries" | jq -S '.'
    rm -f "$deduped"
  else
    echo '[]'
  fi

  rm -f "$tmpfile"
}
