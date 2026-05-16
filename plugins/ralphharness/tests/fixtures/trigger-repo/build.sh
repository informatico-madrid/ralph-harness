#!/usr/bin/env bash
# Builds a temp git repo for trigger testing
set -e
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p tests
echo "def test_existing(): pass" > tests/test_existing.py
git add .
git commit -q -m "initial"
# Create .ralph-state.json
echo '{"taskIteration":2,"maxTaskIterations":5}' > .ralph-state.json
TASK_START_SHA=$(git rev-parse HEAD)
# Create task_review.md (no FAIL row)
echo '## Reviews' > task_review.md
echo "Trigger-repo fixture built at $TMP_DIR"
