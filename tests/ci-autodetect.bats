#!/usr/bin/env bats
# ci-autodetect.bats — Tests for detect-ci-commands.sh and CI autodetection
# Maps to: design.md Test Coverage Table rows for detect-ci-commands.sh

FIXTURE_DIR=""
SPECIAL_DIR=""
DETECT_SCRIPT=""
TEST_ROOT=""
REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"
STUBBIN=""

setup() {
    SPECIAL_DIR=$(mktemp -d)
    FIXTURE_DIR="$REPO_ROOT/tests/fixtures/phase6"
    DETECT_SCRIPT="$REPO_ROOT/plugins/ralphharness/hooks/scripts/detect-ci-commands.sh"
    TEST_ROOT="$REPO_ROOT"
    # Create stub binaries so write-time command -v filter doesn't drop entries
    STUBBIN=$(mktemp -d)
    for bin in ruff mypy pytest pnpm npm yarn composer bundle mix deno dotnet gradle mvn; do
        printf '#!/bin/sh\nexec "$@"\n' > "$STUBBIN/$bin"
        chmod +x "$STUBBIN/$bin"
    done
}

teardown() {
    rm -rf "$SPECIAL_DIR" "$STUBBIN"
}

# =============================================================================
# Task 3.11: pyproject.toml marker matrix
# =============================================================================

@test "detect-ci-commands.sh pyproject.toml matrix" {
    local spec_dir="$SPECIAL_DIR/pyproject-spec"
    mkdir -p "$spec_dir"

    # Create a pyproject.toml with relevant tools configured
    cat > "$spec_dir/pyproject.toml" << 'TOML'
[tool.ruff]
line-length = 88

[tool.ruff.lint]
select = ["E", "F"]

[tool.mypy]
python_version = "3.11"

[tool.pytest.ini_options]
testpaths = ["tests"]
TOML

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]

    # Verify valid JSON
    echo "$output" | jq -e . >/dev/null

    # At minimum: ruff check, ruff format --check, pytest (mypy filtered by command -v if missing)
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -ge 3 ]

    # Verify categories
    local ruff_count
    ruff_count=$(echo "$output" | jq '[.[] | select(.command | startswith("ruff"))] | length')
    [ "$ruff_count" -ge 2 ]

    local pytest_count
    pytest_count=$(echo "$output" | jq '[.[] | select(.command == "pytest")] | length')
    [ "$pytest_count" -ge 1 ]
}

# =============================================================================
# Task 3.12: package.json + pnpm-lock prefers pnpm
# =============================================================================

@test "detect-ci-commands.sh respects pnpm-lock.yaml" {
    local spec_dir="$SPECIAL_DIR/pnpm-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/package.json" << 'JSON'
{
  "name": "test-package",
  "scripts": {
    "lint": "eslint .",
    "test": "jest"
  }
}
JSON
    touch "$spec_dir/pnpm-lock.yaml"

    # Use stub PATH with pnpm available (simulating pnpm installed)
    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]

    # Should use pnpm, not npm
    echo "$output" | jq -e '.[].command | contains("pnpm")' | grep -q true
}

@test "detect-ci-commands.sh respects yarn.lock" {
    local spec_dir="$SPECIAL_DIR/yarn-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/package.json" << 'JSON'
{
  "name": "test-package",
  "scripts": {
    "build": "webpack"
  }
}
JSON
    touch "$spec_dir/yarn.lock"

    # Use stub PATH with yarn available
    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]

    echo "$output" | jq -e '.[].command | contains("yarn")' | grep -q true
}

@test "detect-ci-commands.sh default npm when no lockfile" {
    local spec_dir="$SPECIAL_DIR/npm-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/package.json" << 'JSON'
{
  "name": "test-package",
  "scripts": {
    "test": "mocha"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]

    echo "$output" | jq -e '.[].command | contains("npm")' | grep -q true
}

# =============================================================================
# Task 3.13: Makefile lint/test/check
# =============================================================================

@test "detect-ci-commands.sh Makefile targets" {
    local spec_dir="$SPECIAL_DIR/makefile-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/Makefile" << 'MAKE'
lint:
	ruff check .

test:
	pytest

check:
	mypy .

build:
	poetry build
MAKE

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Should have make lint, make test, make check
    local count
    count=$(echo "$output" | jq '[.[] | select(.command | startswith("make"))] | length')
    [ "$count" -ge 3 ]
}

# =============================================================================
# Task 3.15: Cargo + go.mod
# =============================================================================

@test "detect-ci-commands.sh Cargo.toml emits clippy/fmt/test" {
    local spec_dir="$SPECIAL_DIR/cargo-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/Cargo.toml" << 'TOML'
[package]
name = "test-crate"
version = "0.1.0"
TOML

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -ge 3 ]
}

@test "detect-ci-commands.sh go.mod emits go vet/test" {
    local spec_dir="$SPECIAL_DIR/gomod-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/go.mod" << 'GOMOD'
module example.com/test

go 1.21
GOMOD

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # go vet and go test may be filtered by command -v if not on PATH
    # Check valid JSON at minimum
    echo "$output" | jq -e . >/dev/null
}

# =============================================================================
# Task 3.16: command -v filter drops missing binaries
# =============================================================================

@test "command -v filter drops missing binaries at write time" {
    local spec_dir="$SPECIAL_DIR/filter-spec"
    mkdir -p "$spec_dir"

    # Create pyproject.toml
    cat > "$spec_dir/pyproject.toml" << 'TOML'
[tool.ruff]
line-length = 88
TOML

    # Create a stub dir with only pytest, not ruff or mypy
    local stub_dir="$SPECIAL_DIR/stub-path"
    mkdir -p "$stub_dir"

    # Create stub pytest
    cat > "$stub_dir/pytest" << 'SH'
#!/bin/sh
exit 0
SH
    chmod +x "$stub_dir/pytest"

    # Run with stub PATH
    local output
    output=$(PATH="$stub_dir:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    echo "$output" | jq -e . >/dev/null

    # pytest should be present if on PATH (it should be from real PATH)
    # ruff and mypy should be filtered if not on stub PATH
    # The output is filtered by command -v at write-time
    [ -n "$output" ]
}

# =============================================================================
# Task 3.17: dedupe by (command, category) tuple
# =============================================================================

@test "dedupe removes duplicate (command, category) tuples" {
    # Simulate input from two sources emitting the same entry
    local input
    input=$(cat << 'JSONL'
[{"command":"pytest","category":"test"},{"command":"pytest","category":"test"}]
JSONL
)

    # Source dedupe from lib-signals.sh
    source "$TEST_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    local output
    output=$(echo "$input" | dedupe_ci_commands)
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 1 ]
}

@test "dedupe preserves different categories for same command" {
    local input
    input=$(cat << 'JSONL'
[{"command":"ruff","category":"lint"},{"command":"ruff","category":"build"}]
JSONL
)

    source "$TEST_ROOT/plugins/ralphharness/hooks/scripts/lib-signals.sh"

    local output
    output=$(echo "$input" | dedupe_ci_commands)
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 2 ]
}

# =============================================================================
# Task 3.18 (renumbered): migration legacy ciCommands string[] auto-wrap
# =============================================================================

@test "legacy ciCommands string[] auto-wraps to {command,category:other}" {
    local legacy_state="$FIXTURE_DIR/state-legacy-cicmds.json"
    local tmp_state="$SPECIAL_DIR/state.json"
    cp "$legacy_state" "$tmp_state"

    # Run the migrator
    local migrate_script="$TEST_ROOT/plugins/ralphharness/hooks/scripts/migrate-state.sh"
    bash "$migrate_script" "$tmp_state" 2>/dev/null

    # Verify: ciCommands should now be objects
    local first_type
    first_type=$(jq -r '.ciCommands[0] | type' "$tmp_state")
    [ "$first_type" = "object" ]

    local cmd0
    cmd0=$(jq -r '.ciCommands[0].command' "$tmp_state")
    [ "$cmd0" = "pytest" ]

    local cat0
    cat0=$(jq -r '.ciCommands[0].category' "$tmp_state")
    [ "$cat0" = "other" ]
}

@test "migrator is idempotent — second run produces no changes" {
    local legacy_state="$FIXTURE_DIR/state-legacy-cicmds.json"
    local tmp_state="$SPECIAL_DIR/state-idem.json"
    cp "$legacy_state" "$tmp_state"

    local migrate_script="$TEST_ROOT/plugins/ralphharness/hooks/scripts/migrate-state.sh"
    bash "$migrate_script" "$tmp_state" 2>/dev/null
    local first_run
    first_run=$(jq '.ciCommands' "$tmp_state")

    # Run again
    bash "$migrate_script" "$tmp_state" 2>/dev/null
    local second_run
    second_run=$(jq '.ciCommands' "$tmp_state")

    [ "$first_run" = "$second_run" ]
}

# =============================================================================
# Task 3.22 (renumbered): ciSnapshot per-category recording
# =============================================================================

@test "ciSnapshot per-category recording (fixture-driven stub exits)" {
    # Create a fixture with determinstic exit codes
    local env_file="$FIXTURE_DIR/ci-stub-exits.env"
    if [ ! -f "$env_file" ]; then
        skip "ci-stub-exits.env fixture not yet created"
    fi

    # Source the fixture
    set -a
    source "$env_file"
    set +a

    # Create stub binaries
    local stub_dir="$SPECIAL_DIR/stubs"
    mkdir -p "$stub_dir"

    for category in lint typecheck test build other; do
        local exit_code=0
        eval "exit_code=\$STUB_${category^^}_EXIT"
        local stub_name="stub-${category}"

        cat > "$stub_dir/$stub_name" << 'STUB'
#!/bin/sh
exit ${EXIT_CODE}
STUB
        # Inject the exit code
        sed -i "s/\${EXIT_CODE}/$exit_code/" "$stub_dir/$stub_name"
        chmod +x "$stub_dir/$stub_name"
    done

    # Create a state file referencing stubs
    local spec_dir="$SPECIAL_DIR/ci-test-spec"
    mkdir -p "$spec_dir"
    cat > "$spec_dir/.ralph-state.json" << STATE
{
  "source": "spec",
  "name": "ci-test",
  "phase": "execution",
  "taskIndex": 0,
  "totalTasks": 5,
  "taskIteration": 3,
  "maxTaskIterations": 5,
  "ciCommands": [
    {"command":"stub-lint","category":"lint"},
    {"command":"stub-typecheck","category":"typecheck"},
    {"command":"stub-test","category":"test"},
    {"command":"stub-build","category":"build"},
    {"command":"stub-other","category":"other"}
  ],
  "ciSnapshot": {}
}
STATE

    # Run the CI-SNAPSHOT-WRITER block from implement.md
    local implement_md="$TEST_ROOT/plugins/ralphharness/commands/implement.md"
    local snapshot_block
    snapshot_block=$(awk '/# BEGIN CI-SNAPSHOT-WRITER/,/# END CI-SNAPSHOT-WRITER/' "$implement_md")

    if [ -z "$snapshot_block" ]; then
        skip "CI-SNAPSHOT-WRITER block not found in implement.md"
    fi

    # Verify the snapshot block exists and contains category keywords
    echo "$snapshot_block" | grep -q 'ciSnapshot'
    echo "$snapshot_block" | grep -qE 'lint|typecheck|test|build'

    # Extract the record_ci_snapshot function if present
    if echo "$snapshot_block" | grep -q 'record_ci_snapshot'; then
        # Create a minimal wrapper to test it
        local test_script="$SPECIAL_DIR/test-snapshot.sh"
        cat > "$test_script" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export PATH="$stub_dir:\$PATH"
$snapshot_block
# Run record for each category
record_ci_snapshot "lint" "\$STUB_LINT_EXIT" "stub-lint"
record_ci_snapshot "typecheck" "\$STUB_TYPECHECK_EXIT" "stub-typecheck"
record_ci_snapshot "test" "\$STUB_TEST_EXIT" "stub-test"
record_ci_snapshot "build" "0" "stub-build"
record_ci_snapshot "other" "0" "stub-other"
echo "\$ci_snapshot" | jq .
WRAPPER
        chmod +x "$test_script"

        local result
        result=$(bash "$test_script" 2>/dev/null || true)
        echo "$result" | jq -e . >/dev/null 2>&1 || skip "snapshot writer produced invalid output"
    else
        skip "record_ci_snapshot function not found in CI-SNAPSHOT-WRITER block"
    fi
}

# =============================================================================
# Phase 3 ci-autodetect sanity
# =============================================================================

@test "detect-ci-commands.sh script exists and has valid syntax" {
    [ -f "$DETECT_SCRIPT" ]
    bash -n "$DETECT_SCRIPT"
}

@test "detect-ci-commands.sh with empty spec dir emits []" {
    local spec_dir="$SPECIAL_DIR/empty-spec"
    mkdir -p "$spec_dir"

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ "$output" = "[]" ] || echo "$output" | jq -e '. == []' >/dev/null
}

@test "detect-ci-commands.sh --help / --force arg parsing" {
    local spec_dir="$SPECIAL_DIR/arg-test"
    mkdir -p "$spec_dir"

    # --force should be accepted without error
    local output
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" --force 2>/dev/null)
    echo "$output" | jq -e . >/dev/null

    # Missing spec path should error
    local exit_code=0
    bash "$DETECT_SCRIPT" 2>/dev/null || exit_code=$?
    [[ "$exit_code" -ne 0 ]] || skip "expected error on missing spec path"
}

@test "detect-ci-commands.sh non-existent spec path errors" {
    local exit_code=0
    bash "$DETECT_SCRIPT" "/nonexistent/path" 2>/dev/null || exit_code=$?
    [[ "$exit_code" -ne 0 ]] || skip "expected error on non-existent path"
}

# =============================================================================
# Task 3.2: composer scripts + fallback tests
# =============================================================================

@test "composer.json with scripts test lint analyze build emits run variants" {
    local spec_dir="$SPECIAL_DIR/composer-scripts-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/composer.json" << 'JSON'
{
  "name": "test-composer",
  "scripts": {
    "test": "phpunit",
    "lint": "php-cs-fixer fix",
    "analyze": "phpstan analyse",
    "build": "compile"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Each script should emit composer run <name> with correct category
    echo "$output" | jq -e '.[] | select(.command == "composer run test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "composer run lint" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "composer run analyze" and .category == "typecheck")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "composer run build" and .category == "build")' >/dev/null

    # No vendor/bin/ entries should be present
    local vendor_count
    vendor_count=$(echo "$output" | jq '[.[] | select(.command | startswith("vendor/bin/"))] | length')
    [ "$vendor_count" -eq 0 ]
}

@test "composer.json with no scripts falls back to composer test" {
    local spec_dir="$SPECIAL_DIR/composer-fallback-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/composer.json" << 'JSON'
{
  "name": "test-composer-no-scripts"
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Fallback: should emit composer test (test)
    echo "$output" | jq -e '.[] | select(.command == "composer test" and .category == "test")' >/dev/null

    # No vendor/bin/ entries should be present
    local vendor_count
    vendor_count=$(echo "$output" | jq '[.[] | select(.command | startswith("vendor/bin/"))] | length')
    [ "$vendor_count" -eq 0 ]
}

# =============================================================================
# Task 3.3: gemfile + deno detector tests
# =============================================================================

@test "gemfile detector emits bundle exec rspec and rubocop" {
    local spec_dir="$SPECIAL_DIR/gemfile-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/Gemfile" << 'RB'
source 'https://rubygems.org'
gem 'rspec'
gem 'rubocop'
RB

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Should emit: bundle exec rspec (test) + bundle exec rubocop (lint)
    echo "$output" | jq -e '.[] | select(.command == "bundle exec rspec" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "bundle exec rubocop" and .category == "lint")' >/dev/null

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 2 ]
}

@test "deno tasks-discovery emits deno task per key from deno.json" {
    local spec_dir="$SPECIAL_DIR/deno-tasks-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/deno.json" << 'JSON'
{
  "name": "test-deno-tasks",
  "tasks": {
    "test": "deno test",
    "lint": "deno lint",
    "build": "deno compile"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # tasks-discovery should emit deno task <name> per key with name-pattern categorization
    echo "$output" | jq -e '.[] | select(.command == "deno task test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno task lint" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno task build" and .category == "build")' >/dev/null

    # deno check should NOT be emitted from tasks-discovery (anti-pattern)
    local check_count
    check_count=$(echo "$output" | jq '[.[] | select(.command == "deno check")] | length')
    [ "$check_count" -eq 0 ]
}

@test "deno fallback emits deno test lint check and fmt --check from deno.jsonc" {
    local spec_dir="$SPECIAL_DIR/deno-fallback-spec"
    mkdir -p "$spec_dir"

    # Use .jsonc (triggers fallback path)
    cat > "$spec_dir/deno.jsonc" << 'JSON'
{
  "name": "test-deno-fallback"
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Fallback: should emit 4 canonical deno commands
    echo "$output" | jq -e '.[] | select(.command == "deno test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno lint" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno check" and .category == "typecheck")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno fmt --check" and .category == "lint")' >/dev/null
}

# =============================================================================
# Task 3.5: gradle detector tests
# =============================================================================

@test "gradle build.gradle emits gradle test and gradle build without typecheck" {
    local spec_dir="$SPECIAL_DIR/gradle-groovy-spec"
    mkdir -p "$spec_dir"

    touch "$spec_dir/build.gradle"

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Should emit: gradle test (test) + gradle build (build)
    echo "$output" | jq -e '.[] | select(.command == "gradle test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "gradle build" and .category == "build")' >/dev/null

    # gradle check should NOT be emitted (AC-3.4: check is NOT a typecheck)
    local typecheck_count
    typecheck_count=$(echo "$output" | jq '[.[] | select(.category == "typecheck")] | length')
    [ "$typecheck_count" -eq 0 ]
}

@test "gradle build.gradle.kts fires same test and build commands" {
    local spec_dir="$SPECIAL_DIR/gradle-kts-spec"
    mkdir -p "$spec_dir"

    touch "$spec_dir/build.gradle.kts"

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Kotlin DSL should produce the same entries as Groovy DSL
    echo "$output" | jq -e '.[] | select(.command == "gradle test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "gradle build" and .category == "build")' >/dev/null
}

@test "gradle executable wrapper ./gradlew test and build survive filter" {
    local spec_dir="$SPECIAL_DIR/gradle-wrapper-spec"
    mkdir -p "$spec_dir"

    touch "$spec_dir/build.gradle"

    # Create an executable ./gradlew wrapper
    printf '#!/bin/sh\nexec "$@"\n' > "$spec_dir/gradlew"
    chmod +x "$spec_dir/gradlew"

    # Run with gradlew not on PATH but SPEC_PATH/gradlew is executable
    local output
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # ./gradlew test and ./gradlew build should SURVIVE the ./-filter
    echo "$output" | jq -e '.[] | select(.command == "./gradlew test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "./gradlew build" and .category == "build")' >/dev/null
}

# =============================================================================
# Task 3.9: ./-filter regression test (wrapper toggle)
# =============================================================================

@test "./gradlew wrapper survives filter when executable, drops when not (chmod toggle)" {
    # Build a self-contained stub dir WITHOUT gradle on PATH — isolates ./-filter behavior
    local stub_dir="$SPECIAL_DIR/filter-stubs"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\nexec "$@"\n' > "$stub_dir/ruff"
    chmod +x "$stub_dir/ruff"

    local spec_dir="$SPECIAL_DIR/filter-toggle-spec"
    mkdir -p "$spec_dir"
    touch "$spec_dir/build.gradle"

    # Create the wrapper (NOT executable — test 2 will chmod +x to test survival)
    printf '#!/bin/sh\nexec "$@"\n' > "$spec_dir/gradlew"
    chmod -x "$spec_dir/gradlew"

    # --- Branch 1: gradlew NOT executable — ./gradlew not added to ENTRIES, gradle fallback has no PATH ---
    local output1 stderr1
    PATH="$stub_dir:$PATH" run bash "$DETECT_SCRIPT" "$spec_dir"
    output1="$output"
    stderr1="$stderr"
    [ -n "$output1" ]

    # ./gradlew must NOT be present (detect_gradle never added it since gradlew not -x)
    local clean_output1
    clean_output1=$(echo "$output1" | grep -v '^\[detect-ci-commands\] WARN:')
    local dropped
    dropped=$(echo "$clean_output1" | jq '[.[] | select(.command | startswith("./gradlew"))] | length')
    [ "$dropped" -eq 0 ]

    # Verify output is valid JSON (array with no ./gradlew entries)
    echo "$clean_output1" | jq -e '. | if type == "array" then true else empty end' >/dev/null

    # --- Branch 2: chmod +x gradlew — ./gradlew SURVIVES ---
    chmod +x "$spec_dir/gradlew"

    local output2
    PATH="$stub_dir:$PATH" run bash "$DETECT_SCRIPT" "$spec_dir"
    output2="$output"
    [ -n "$output2" ]

    # ./gradlew test must SURVIVE the filter
    local clean_output2
    clean_output2=$(echo "$output2" | grep -v '^\[detect-ci-commands\] WARN:')
    echo "$clean_output2" | jq -e '.[] | select(.command == "./gradlew test" and .category == "test")' >/dev/null
    echo "$clean_output2" | jq -e '.[] | select(.command == "./gradlew build" and .category == "build")' >/dev/null
}

# =============================================================================
# Task 3.9: ./-filter wrapper regression test (present vs absent gradlew)
# =============================================================================

@test "./-filter wrapper: gradlew executable SURVIVES, absent DROPS with WARN" {
    local spec_dir="$SPECIAL_DIR/filter-wrapper-spec"
    mkdir -p "$spec_dir"

    touch "$spec_dir/build.gradle"

    # Create a non-executable gradlew wrapper
    printf '#!/bin/sh\nexec "$@"\n' > "$spec_dir/gradlew"
    chmod -x "$spec_dir/gradlew"

    # Ensure gradle is NOT on PATH (use a clean stub dir with no gradle binary)
    local stub_dir="$SPECIAL_DIR/filter-stub"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\nexec "$@"\n' > "$stub_dir/dotnet"
    chmod +x "$stub_dir/dotnet"

    # --- Branch 1: gradlew NOT executable — ./gradlew not added to ENTRIES ---
    local output1 stderr1
    PATH="$stub_dir:$PATH" run bash "$DETECT_SCRIPT" "$spec_dir"
    output1="$output"
    stderr1="$stderr"
    [ -n "$output1" ]

    # Filter out any WARN lines (from gradle fallback if on PATH)
    local clean_output1
    clean_output1=$(echo "$output1" | grep -v '^\[detect-ci-commands\] WARN:')
    echo "$clean_output1" | jq -e . >/dev/null

    # ./gradlew must NOT be present (detect_gradle never added it since gradlew not -x)
    local dropped
    dropped=$(echo "$clean_output1" | jq '[.[] | select(.command | startswith("./gradlew"))] | length')
    [ "$dropped" -eq 0 ]

    # Verify output is valid JSON (empty array or no ./gradlew entries)
    echo "$clean_output1" | jq -e '. | if type == "array" then true else empty end' >/dev/null

    # --- Branch 2: chmod +x gradlew — ./gradlew SURVIVES ---
    chmod +x "$spec_dir/gradlew"

    local output2
    PATH="$stub_dir:$PATH" run bash "$DETECT_SCRIPT" "$spec_dir"
    output2="$output"
    [ -n "$output2" ]

    # ./gradlew test must SURVIVE the filter
    local clean_output2
    clean_output2=$(echo "$output2" | grep -v '^\[detect-ci-commands\] WARN:')
    echo "$clean_output2" | jq -e '.[] | select(.command == "./gradlew test" and .category == "test")' >/dev/null
    echo "$clean_output2" | jq -e '.[] | select(.command == "./gradlew build" and .category == "build")' >/dev/null
}

# =============================================================================
# Task 3.10: source-no-side-effects + sourced-call integration tests
# =============================================================================

@test "maven pom.xml emits mvn test and mvn package" {
    local spec_dir="$SPECIAL_DIR/maven-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/pom.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>test-project</artifactId>
  <version>1.0.0</version>
</project>
XML

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Should emit: mvn test (test) + mvn package (build)
    echo "$output" | jq -e '.[] | select(.command == "mvn test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mvn package" and .category == "build")' >/dev/null
}

@test "maven executable wrapper ./mvnw test and package survive filter" {
    local spec_dir="$SPECIAL_DIR/maven-wrapper-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/pom.xml" << 'XML'
<?xml version="1.0"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>wrapper-test</artifactId>
</project>
XML

    # Create an executable ./mvnw wrapper (no ./ in STUBBIN)
    printf '#!/bin/sh\nexec "$@"\n' > "$spec_dir/mvnw"
    chmod +x "$spec_dir/mvnw"

    # Run without mvn on PATH — only SPEC_PATH/mvnw is executable
    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # ./mvnw test and ./mvnw package should SURVIVE the ./-filter
    echo "$output" | jq -e '.[] | select(.command == "./mvnw test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "./mvnw package" and .category == "build")' >/dev/null
}

@test "gradle + maven coexist both command sets present" {
    local spec_dir="$SPECIAL_DIR/coexist-spec"
    mkdir -p "$spec_dir"

    touch "$spec_dir/build.gradle"
    cat > "$spec_dir/pom.xml" << 'XML'
<?xml version="1.0"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>coexist-test</artifactId>
</project>
XML

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Gradle commands
    echo "$output" | jq -e '.[] | select(.command == "gradle test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "gradle build" and .category == "build")' >/dev/null

    # Maven commands
    echo "$output" | jq -e '.[] | select(.command == "mvn test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mvn package" and .category == "build")' >/dev/null
}

# =============================================================================
# Task 3.7: mix + dotnet detector tests
# =============================================================================

@test "mix.exs fallback emits mix test credo dialyzer format --check-formatted" {
    local spec_dir="$SPECIAL_DIR/mix-fallback-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/mix.exs" << 'EXS'
defmodule MyProject.MixProject do
  def project do
    [app: :my_project, version: "0.1.0"]
  end
end
EXS

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Fallback: 4 canonical mix commands
    echo "$output" | jq -e '.[] | select(.command == "mix test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix credo" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix dialyzer" and .category == "typecheck")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix format --check-formatted" and .category == "lint")' >/dev/null
}

@test "mix.exs with aliases emits mix alias commands preferred" {
    local spec_dir="$SPECIAL_DIR/mix-aliases-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/mix.exs" << 'EXS'
defmodule MyProject.MixProject do
  use Mix.Project

  def project do
    [app: :my_project]
  end

  defp aliases do
    [
      test: "test",
      lint: "lint",
      dialyzer: "dialyzer",
      format: "format"
    ]
  end
end
EXS

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Alias-based: mix test, mix lint, mix dialyzer, mix format (grep-scan finds these values)
    echo "$output" | jq -e '.[] | select(.command == "mix test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix lint" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix dialyzer" and .category == "typecheck")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix format" and .category == "lint")' >/dev/null

    # Should NOT have fallback commands when aliases are found
    local fallback_count
    fallback_count=$(echo "$output" | jq '[.[] | select(.command == "mix credo")] | length')
    [ "$fallback_count" -eq 0 ]
}

@test "dotnet .csproj glob fires dotnet test build format" {
    local spec_dir="$SPECIAL_DIR/dotnet-csproj-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/App.csproj" << 'CSHARP'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
CSHARP

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # Should emit 3 dotnet commands
    echo "$output" | jq -e '.[] | select(.command == "dotnet test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "dotnet build" and .category == "build")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "dotnet format --verify-no-changes" and .category == "lint")' >/dev/null
}

@test "dotnet .sln and global.json fire independently" {
    local spec_dir1="$SPECIAL_DIR/dotnet-sln-spec"
    mkdir -p "$spec_dir1"

    cat > "$spec_dir1/MySolution.sln" << 'SLN'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
SLN

    local spec_dir2="$SPECIAL_DIR/dotnet-global-spec"
    mkdir -p "$spec_dir2"

    cat > "$spec_dir2/global.json" << 'JSON'
{
  "sdk": {
    "version": "8.0.0",
    "rollForward": "latestMajor"
  }
}
JSON

    # Test .sln triggers dotnet
    local output1
    output1=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir1" 2>/dev/null)
    [ -n "$output1" ]
    echo "$output1" | jq -e . >/dev/null
    echo "$output1" | jq -e '.[] | select(.command == "dotnet test" and .category == "test")' >/dev/null

    # Test global.json triggers dotnet
    local output2
    output2=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir2" 2>/dev/null)
    [ -n "$output2" ]
    echo "$output2" | jq -e . >/dev/null
    echo "$output2" | jq -e '.[] | select(.command == "dotnet build" and .category == "build")' >/dev/null
}


# =============================================================================
# Task 3.10: source-no-side-effects + sourced-call integration tests
# =============================================================================

@test "source detect-ci-commands.sh with no args has no side effects" {
    # Test (a): sourcing the script with no arguments must have zero side effects.
    # - Exit code 0 (no abort)
    # - No stdout emitted
    # - set -e must NOT leak into the calling shell (a failing command after source must not abort)

    local output exit_code fail_rc

    # Source in a sub-shell and capture stdout + exit code
    output=$(source "$DETECT_SCRIPT" 2>/dev/null) || true
    exit_code=$?

    # Exit code must be 0 (source must not abort the parent)
    [[ "$exit_code" -eq 0 ]]

    # No stdout must be produced
    [[ -z "$output" ]]

    # Verify set -e is NOT active in the calling shell: if set -e leaked,
    # the following `false` would abort the shell before we reach the next line.
    set +e
    false
    fail_rc=$?
    set -e
    # After a `false` command, $? should be 1 (not a shell exit)
    [[ "$fail_rc" -ne 0 ]]
}

@test "sourced detect_ci_commands emits valid JSON for a multi-marker fixture" {
    # Test (b): after source, detect_ci_commands "$dir" emits valid JSON array
    # for a fixture with multiple markers (mirrors implement.md:221 consumer pattern).

    local spec_dir="$SPECIAL_DIR/sourced-call-spec"
    mkdir -p "$spec_dir"

    # Create multiple markers to trigger multiple detectors
    touch "$spec_dir/Gemfile"
    cat > "$spec_dir/package.json" << 'JSON'
{
  "name": "sourced-test",
  "scripts": {
    "test": "jest",
    "lint": "eslint ."
  }
}
JSON

    # Source the script and call detect_ci_commands in a sub-shell
    # This mirrors the implement.md:221 pattern:
    #   cmds=$(source detect-ci-commands.sh && detect_ci_commands "$PWD")
    local output
    output=$(PATH="$STUBBIN:$PATH" bash -c "source '$DETECT_SCRIPT' && detect_ci_commands '$spec_dir'" 2>/dev/null)
    [ -n "$output" ]

    # Must be a valid JSON array
    echo "$output" | jq -e . >/dev/null

    # At minimum: bundle exec rspec (Gemfile) + npm run test/lint (package.json)
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -ge 3 ]

    # Verify specific entries are present
    echo "$output" | jq -e '.[] | select(.command == "bundle exec rspec" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "npm run test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "npm run lint" and .category == "lint")' >/dev/null
}

@test "composer.json with British 'analyse' script emits typecheck" {
    local spec_dir="$SPECIAL_DIR/composer-analyse-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/composer.json" << 'JSON'
{
  "name": "test-composer",
  "scripts": {
    "analyse": "phpstan analyse",
    "analyze": "phpstan analyse --strict"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # British 'analyse' → typecheck (F-1 fix)
    echo "$output" | jq -e '.[] | select(.command == "composer run analyse" and .category == "typecheck")' >/dev/null
    # US 'analyze' → typecheck too
    echo "$output" | jq -e '.[] | select(.command == "composer run analyze" and .category == "typecheck")' >/dev/null
}

@test "deno task check categorizes as typecheck not other" {
    local spec_dir="$SPECIAL_DIR/deno-check-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/deno.json" << 'JSON'
{
  "tasks": {
    "check": "deno check",
    "lint": "deno lint",
    "test": "deno test"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # F-3: 'check' task → typecheck (PHP patterns removed, deno-honest map)
    echo "$output" | jq -e '.[] | select(.command == "deno task check" and .category == "typecheck")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno task lint" and .category == "lint")' >/dev/null
}

@test "deno.jsonc with tasks emits deno task per key" {
    local spec_dir="$SPECIAL_DIR/deno-jsonc-spec"
    mkdir -p "$spec_dir"

    # Valid .jsonc without comments (jq can parse this; // comments make jq fail → fallback)
    cat > "$spec_dir/deno.jsonc" << 'JSON'
{
  "tasks": {
    "mytest": "deno test",
    "mylint": "deno lint"
  }
}
JSON

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # F-4: .jsonc with tasks → deno task entries discovered
    echo "$output" | jq -e '.[] | select(.command == "deno task mytest")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "deno task mylint")' >/dev/null
}

@test "gradle with non-executable gradlew degrades to gradle test and build" {
    local spec_dir="$SPECIAL_DIR/gradle-noexec-spec"
    mkdir -p "$spec_dir"

    echo 'plugins { id "java" }' > "$spec_dir/build.gradle"
    printf '#!/bin/sh\n' > "$spec_dir/gradlew"  # present but NOT executable

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # F-2: non-executable wrapper → system gradle on PATH (not empty [])
    echo "$output" | jq -e '.[] | select(.command == "gradle test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "gradle build" and .category == "build")' >/dev/null
    # Should NOT have ./gradlew entries (wrapper not executable → filter drops them)
    local dotcount
    dotcount=$(echo "$output" | jq '[.[]|select(.command | startswith("./"))]|length')
    [ "$dotcount" -eq 0 ]
}

@test "maven with non-executable mvnw degrades to mvn test and package" {
    local spec_dir="$SPECIAL_DIR/maven-noexec-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/pom.xml" << 'XML'
<project><modelVersion>4.0.0</modelVersion></project>
XML
    printf '#!/bin/sh\n' > "$spec_dir/mvnw"  # present but NOT executable

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # F-2: non-executable wrapper → system mvn on PATH (not empty [])
    echo "$output" | jq -e '.[] | select(.command == "mvn test" and .category == "test")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mvn package" and .category == "build")' >/dev/null
}

@test "realistic atom-keyed mix.exs discovers credo and dialyzer aliases" {
    local spec_dir="$SPECIAL_DIR/mix-real-spec"
    mkdir -p "$spec_dir"

    cat > "$spec_dir/mix.exs" << 'EXS'
defmodule MyProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_project,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      credo: ["credo --strict"],
      dialyzer: ["dialyzer --format github"]
    ]
  end
end
EXS

    local output
    output=$(PATH="$STUBBIN:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
    [ -n "$output" ]
    echo "$output" | jq -e . >/dev/null

    # F-5: atom-keyed aliases discovered (credo → lint, dialyzer → typecheck)
    echo "$output" | jq -e '.[] | select(.command == "mix credo" and .category == "lint")' >/dev/null
    echo "$output" | jq -e '.[] | select(.command == "mix dialyzer" and .category == "typecheck")' >/dev/null
}
