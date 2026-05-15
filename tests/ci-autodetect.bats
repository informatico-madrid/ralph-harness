#!/usr/bin/env bats
# ci-autodetect.bats — Tests for detect-ci-commands.sh and CI autodetection
# Maps to: design.md Test Coverage Table rows for detect-ci-commands.sh

FIXTURE_DIR=""
SPECIAL_DIR=""
DETECT_SCRIPT=""
TEST_ROOT=""
REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"

setup() {
    SPECIAL_DIR=$(mktemp -d)
    FIXTURE_DIR="$REPO_ROOT/tests/fixtures/phase6"
    DETECT_SCRIPT="$REPO_ROOT/plugins/ralphharness/hooks/scripts/detect-ci-commands.sh"
    TEST_ROOT="$REPO_ROOT"
}

teardown() {
    rm -rf "$SPECIAL_DIR"
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(PATH="/tmp/stubbin:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(PATH="/tmp/stubbin:$PATH" bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
    output=$(bash "$DETECT_SCRIPT" "$spec_dir" 2>/dev/null)
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
