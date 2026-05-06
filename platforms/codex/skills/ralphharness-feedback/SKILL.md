---
name: ralphharness-feedback
description: This skill should be used only when the user explicitly asks to use `$ralphharness-feedback`, or explicitly asks RalphHarness in Codex to draft or submit feedback.
metadata:
  surface: helper
  action: feedback
---

# RalphHarness Feedback

Use this to capture product feedback or bug reports for RalphHarness.

## Action

1. Summarize the issue, request, or missing behavior.
2. Gather the minimum reproducible context, affected files, commands, environment details, and whether the issue is on the Codex package or Claude plugin surface.
3. If `gh` is available and the user wants submission, create a GitHub issue.
4. If `gh` is unavailable or the user only wants a draft, produce a ready-to-paste issue body and the repository issue URL.

## Output

Keep the report concrete. Include expected behavior, actual behavior, reproduction steps, and any relevant state files or logs.
