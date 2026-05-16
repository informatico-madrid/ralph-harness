# Gito Review Context: pair-debug-auto-trigger (Spec 8)

## Spec Overview
- **Spec**: pair-debug-auto-trigger (Spec 8 of engine-roadmap-epic)
- **Branch**: spec/collaboration-resolution-real
- **Base**: main
- **Goal**: Add automatic pair-debug mode trigger with 3-condition check and Driver/Navigator role split for autonomous debugging collaboration

## Implementation Summary
The spec adds an "escalation posture" (not code state) where the coordinator mechanically detects 3 conditions and writes a `PAIR-DEBUG MODE ACTIVATED` header to chat.md. Two existing agents (spec-executor, external-reviewer) adopt distinct Driver/Navigator roles.

### Key Changes
1. **3-condition trigger** (in `failure-recovery.md`):
   - (a) pre-existing test failing + test file unchanged (`git diff TASK_START_SHA..HEAD -- tests/`)
   - (b) `taskIteration >= 2` (persisted in `.ralph-state.json`)
   - (c) no reviewer FAIL row in `task_review.md`

2. **Driver/Navigator roles** (NEW `references/pair-debug.md`):
   - Driver = spec-executor (instruments code, runs experiments)
   - Navigator = external-reviewer (proposes >=2 independent hypotheses)

3. **Two-instance exportable role files** (NEW `agents/pair-debug-driver.md` and `agents/pair-debug-navigator.md`):
   - Section 0 Bootstrap (self-discovery pattern from external-reviewer.md)
   - Filesystem-only coordination (no Task-tool delegation)
   - Runnable by foreign runtimes (Roo Code, Qwen, Cursor)

4. **Debug logging** (appended to `agents/spec-executor.md`):
   - PAIR-DEBUG: marker for temporary logs
   - Mechanical cleanup verification (grep for PAIR-DEBUG: returns empty)

5. **Placement step** (appended to `commands/implement.md`):
   - Onboarding asks where to run pair-debug roles
   - Three branches: same instance / second instance / foreign runtime

6. **Loop bound** (value change in `references/collaboration-resolution.md:53`):
   - Raised from >3 to >10 hypothesis cycles

7. **Version bump** 5.2.0 -> 5.3.0

## Intentional Patterns (NOT bugs)
- **Append-only edits**: All edits to existing files are append-only. Only exception is one value change in collaboration-resolution.md line 53.
- **No new subagent_type**: Role files are prompt markdown, not executable agents.
- **No new state fields**: All state lives in `chat.md` and `signals.jsonl`.
- **Filesystem-only coordination**: Atomic-append protocol (flock fd 200/202).
- **Role files self-contained**: No references to `CLAUDE_PLUGIN_ROOT`. Inlined flock blocks.
- **Anti-anchoring rule**: Navigator MUST propose >=2 hypotheses BEFORE first EXPERIMENT.
- **Loop bound >10**: Raised from >3 per user override.

## Files Under Review
### Production/Plugin Files
- NEW: `references/pair-debug.md`, `agents/pair-debug-driver.md`, `agents/pair-debug-navigator.md`
- APPENDED: `agents/spec-executor.md`, `commands/implement.md`, `references/collaboration-resolution.md`, `references/coordinator-pattern.md`, `references/failure-recovery.md`, `templates/chat.md`
- VERSION BUMP: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

### Test Files
- 8 bats test files in `plugins/ralphharness/tests/`
- 3 test fixture directories
