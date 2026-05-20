#!/usr/bin/env bats
# Bats suite for verify-fix-present.sh: committed/staged/working-tree diffs

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FIXER_SCRIPT="$REPO_ROOT/plugins/ralphharness/hooks/scripts/verify-fix-present.sh"

setup() {
    FIXTURE_DIR=$(mktemp -d)
    cd "$FIXTURE_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    # Create a base commit
    git commit -q --allow-empty -m "base"
    # Create a fake origin/main pointing to base
    git branch origin/main
}

teardown() {
    rm -rf "$FIXTURE_DIR"
}

@test "fix committed returns 0" {
    echo "new content" > "target.txt"
    git add target.txt
    git commit -q -m "add target"
    run "$FIXER_SCRIPT" "target.txt"
    [ "$status" -eq 0 ]
}

@test "fix staged not committed returns 0" {
    echo "staged content" > "staged.txt"
    git add staged.txt
    run "$FIXER_SCRIPT" "staged.txt"
    [ "$status" -eq 0 ]
}

@test "fix unstaged returns 0" {
    # File must be tracked for git diff --quiet to detect working-tree changes
    echo "base" > "unstaged.txt"
    git add unstaged.txt
    git commit -q -m "track unstaged"
    echo "modified" > "unstaged.txt"
    run "$FIXER_SCRIPT" "unstaged.txt"
    [ "$status" -eq 0 ]
}

@test "file unchanged returns 1 with FIX ABSENT" {
    # No changes to any state — all three diffs empty
    # Use a file that doesn't exist to ensure all checks show no diff
    run "$FIXER_SCRIPT" "nonexistent.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FIX ABSENT"* ]]
}

@test "pattern present returns 0" {
    echo "fix: add critical safety check" > "safety.txt"
    git add safety.txt
    git commit -q -m "add safety"
    run "$FIXER_SCRIPT" "safety.txt" "critical safety check"
    [ "$status" -eq 0 ]
}

@test "pattern absent returns 2" {
    echo "feature code" > "feature.txt"
    git add feature.txt
    git commit -q -m "add feature"
    run "$FIXER_SCRIPT" "feature.txt" "safety check"
    [ "$status" -eq 2 ]
    [[ "$output" == *"PATTERN ABSENT"* ]]
}

@test "checkpoint fallback returns 0 with WARN" {
    # Save the empty base commit SHA (before any fix)
    BASE_SHA=$(git rev-parse HEAD)
    # Remove origin/main so merge-base fails
    git branch -D origin/main
    # Create a change on HEAD (the fix)
    echo "checkpointed fix" > "checkpoint.txt"
    git add checkpoint.txt
    git commit -q -m "checkpointed fix"
    # Set checkpoint SHA to base (before fix), so diff HEAD vs base shows change
    mkdir -p specs/test-spec
    echo "test-spec" > specs/.current-spec
    jq -n --arg sha "$BASE_SHA" '{"checkpoint":{"sha":$sha}}' > specs/test-spec/.ralph-state.json
    # Set RALPH_CWD to fixture root so script finds specs/ directory
    RALPH_CWD="$FIXTURE_DIR" run "$FIXER_SCRIPT" "checkpoint.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[harness][verify-fix] WARN"* ]]
}

@test "no SHA fallback returns 3" {
    # Remove origin/main, provide empty checkpoint (no SHA)
    git branch -D origin/main
    # Create specs dir but without checkpoint SHA
    mkdir -p "specs/test-spec"
    echo '{}' > "specs/test-spec/.ralph-state.json"
    RALPH_CWD="$FIXTURE_DIR" run "$FIXER_SCRIPT" "nonexistent.txt"
    [ "$status" -eq 3 ]
    [[ "$output" == *"cannot resolve base ref"* ]]
}
