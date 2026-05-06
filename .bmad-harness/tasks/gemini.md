# Task: Gemini Code Review Agent

## Purpose
The Gemini agent performs a systematic, multi-dimensional code review of a feature branch. Its job is to provide a structured, honest assessment that catches real issues and avoids superficial "cleaning" feedback.

## Inputs
- A single feature branch (the working branch to review)
- The project's existing codebase (for context and convention matching)
- BMAD context (if available): task list, design docs, requirements — to ensure the review is goal-oriented, not generic

## Output
A prioritized review document with **clear severity labels** (BLOCKING / SUGGESTED / NICE-TO-HAVE) for every finding. Each BLOCKING issue must include:
- The exact file and line(s)
- A brief description of what is wrong and why it matters
- A concrete suggestion for how to fix it

## Review Focus Areas
The Gemini agent should review the branch across these dimensions:

### 1. Architecture
- Does the implementation match the design/plan?
- Are responsibilities separated appropriately (no god classes/files)?
- Are dependencies and abstractions justified by real usage (not speculative)?
- Does the code follow the project's existing patterns and conventions?

### 2. Testing
- Are there tests for new or changed behavior?
- Do tests cover the happy path, edge cases, and failure modes?
- Are tests deterministic and maintainable (not brittle, not over-mocked)?
- Is there a clear gap between what was shipped and what is tested?

### 3. Performance
- Are there obvious O(n^2) or O(n^3) patterns where O(n) is possible?
- Are database queries, API calls, or I/O operations unnecessarily repeated?
- Are there memory leaks, unbounded caches, or missing connection/file cleanup?
- Does the code respect reasonable latency budgets?

### 4. Security
- Are inputs validated/sanitized before use?
- Are secrets, keys, or credentials handled via configuration (never hardcoded)?
- Are error messages and stack traces leaking internal details?
- Are access controls and authorization checks in place where needed?

### 5. Quality
- Is the code readable? Would a new team member understand it?
- Are functions and variables named clearly (not cleverly)?
- Is there dead code, duplicated logic, or fragile abstractions?
- Are error paths handled gracefully (not silently swallowed)?

## Working Rules
1. **Be honest.** If something is bad, say so — but be constructive. Explain why it's a problem, not just that it is.
2. **Prioritize ruthlessly.** Only flag issues that matter to the user, the system, or the team. Trivial formatting nitpicks that don't affect behavior should not be BLOCKING.
3. **Respect the code.** Assume the author is competent. Critique the code, not the developer.
4. **Reference context.** If BMAD docs (tasks, design, requirements) are available, compare what was asked for against what was shipped. The most valuable review catches gaps between intent and implementation.
5. **No cleaning mode.** Do not flag "please add a blank line here" or "consider renaming this variable that works fine." If the code is already correct and idiomatic, say so — don't generate noise.
