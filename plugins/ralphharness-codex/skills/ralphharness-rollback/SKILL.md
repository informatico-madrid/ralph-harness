---
name: ralphharness-rollback
description: This skill should be used when the user asks to rollback a spec execution to the pre-execution git checkpoint.
metadata:
  surface: helper
  action: rollback
---

# RalphHarness Checkpoint Rollback

You are rolling back the working tree to the pre-execution git checkpoint stored in the spec's state file.

## Contract

- Resolve the target by explicit path, exact name, or `.current-spec`
- Read the spec's `.ralph-state.json` to find the git checkpoint SHA
- Use Bash to restore to that SHA
- Clean up any remaining state files after rollback

## Usage

```
$ralphharness-rollback [spec-name-or-path]
```
