#!/usr/bin/env bats

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$BATS_TEST_DIRNAME")"
@test "runtime-map-roo-code" {
    grep -q 'roo' "${REPO_ROOT}/plugins/ralphharness/references/pair-debug.md"
}

@test "runtime-map-qwen" {
    grep -q 'Qwen' "${REPO_ROOT}/plugins/ralphharness/references/pair-debug.md"
}

@test "runtime-map-cursor" {
    grep -q 'Cursor' "${REPO_ROOT}/plugins/ralphharness/references/pair-debug.md"
}

@test "runtime-unknown-fallback" {
    grep -qi 'manual' "${REPO_ROOT}/plugins/ralphharness/references/pair-debug.md"
}

@test "export-source-paths-absolute" {
    grep -q '<abs>' "${REPO_ROOT}/plugins/ralphharness/commands/implement.md"
}
