#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"
@test "branch-a-same-instance" {
    grep -q 'This same instance' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}

@test "branch-b-second-instance" {
    grep -q 'A second Claude Code instance' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}

@test "branch-c-foreign-runtime" {
    grep -q 'Roo Code.*Qwen.*Cursor' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}

@test "branch-c-unknown-fallback" {
    grep -q 'no known destination path' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}

@test "export-report-has-paths" {
    grep -q 'source:' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
    grep -q 'destination:' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}

@test "no-name-only-instruction" {
    ! grep -q '^\s*@external-reviewer\b' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}
