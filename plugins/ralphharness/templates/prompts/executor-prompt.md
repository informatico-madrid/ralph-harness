# Executor Dispatch Template

> Used by: implement.md coordinator
> Placeholders: {SPEC_NAME}, {TASK_TEXT}, {TASK_INDEX}, {CONTEXT}, {PROGRESS}, {DESIGN_DECISIONS}, {ANTI_PATTERNS}, {REQUIRED_SKILLS}, {SUCCESS_CRITERIA}

## Task Tool Parameters

- **subagent_type:** `spec-executor`
- **description:** `Execute task {TASK_INDEX} for {SPEC_NAME}`

> **Note on subagent_type naming**: use the bare agent name `spec-executor` (not
> `ralph-harness:spec-executor`). The plugin-qualified form can cause routing failures
> in some Claude Code versions when the plugin is already the active context.
> Consistent bare names match the pattern used by all other agent delegations
> in this plugin (`qa-engineer`, `spec-reviewer`, `research-analyst`).

## Prompt

You are executing task {TASK_INDEX} for spec `{SPEC_NAME}`.

## Task

{TASK_TEXT}

## Context

{CONTEXT}

## Progress So Far

{PROGRESS}

## Delegation Contract

### Design Decisions
{DESIGN_DECISIONS}

### Anti-Patterns (DO NOT)
{ANTI_PATTERNS}

### Required Skills
{REQUIRED_SKILLS}

### Success Criteria
{SUCCESS_CRITERIA}

## Instructions

1. Read the full task description carefully
2. Read any referenced spec files for additional context
3. **Before writing ANY test or verification code**: read design.md → ## Test Strategy for mock boundaries, test conventions, and runner configuration
4. **Before writing ANY E2E test**: load all skills listed in Required Skills above. Read each skill file BEFORE writing code — they contain anti-patterns that will save you from common failures
5. **Verify source of truth**: for selectors, auth flows, and navigation patterns, ALWAYS consult the skill files and ui-map.local.md FIRST — never invent selectors from memory
6. Implement exactly what is specified — no more, no less
7. Verify your implementation works in the real environment
8. Commit changes with a descriptive conventional commit message
9. Update the task checkmark in tasks.md (mark as `- [x]`)
10. Update .progress.md with what you did and any learnings
11. Output TASK_COMPLETE when done

If you encounter issues you cannot resolve, output a detailed error description instead of TASK_COMPLETE.
