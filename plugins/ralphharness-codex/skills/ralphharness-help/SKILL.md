---
name: ralphharness-help
description: This skill should be used only when the user explicitly asks to use `$ralphharness-help`, or explicitly asks RalphHarness in Codex for help or command guidance.
metadata:
  surface: helper
  action: help
---

# RalphHarness Help

Use this to explain the RalphHarness surface in Codex.

## Cover

- Primary skill: `$ralphharness`
- Helper skills: `$ralphharness-start`, `$ralphharness-triage`, `$ralphharness-research`, `$ralphharness-requirements`, `$ralphharness-design`, `$ralphharness-tasks`, `$ralphharness-implement`, `$ralphharness-status`, `$ralphharness-switch`, `$ralphharness-cancel`, `$ralphharness-index`, `$ralphharness-refactor`, `$ralphharness-feedback`, `$ralphharness-help`
- Normal flow: start, stop, research, approval, requirements, approval, design, approval, tasks, approval, implement
- Large effort flow: triage, then start each unblocked spec
- Quick mode: generate missing artifacts and continue into implementation in one run only when the user explicitly asks for quick or autonomous flow
- Disk contract: `./specs` or configured roots, `.current-spec`, optional `.current-epic`, per-spec markdown files, `.ralph-state.json`

## Guidance

- Recommend `$ralphharness` as the default entrypoint.
- Recommend `$ralphharness-triage` when the user describes a large, multi-part, or dependency-heavy effort.
- Mention helper skills when the user wants explicit phase control.
- Explain that Ralph does not self-advance by default. The user must approve the current artifact, request changes, or explicitly continue to the next step.
- Mention optional bootstrap assets only when the user wants repo-local guidance.
