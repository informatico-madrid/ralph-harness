# Phase Transitions

Detailed flow for spec-driven development phases.

## Phase Order

```
new/start -> research -> requirements -> design -> tasks -> implement
```

## Phase Details

### 1. Research Phase

**Command**: `/ralphharness:research`
**Agent**: research-analyst
**Output**: `./specs/<name>/research.md`

Activities:
- Web search for best practices
- Codebase analysis for existing patterns
- Related specs discovery
- Quality command discovery
- Feasibility assessment
- **Note project type signals** (has frontend? API-only? CLI tool?) — pass as context to requirements phase

Ends with: `awaitingApproval: true`

### 2. Requirements Phase

**Command**: `/ralphharness:requirements`
**Agent**: product-manager
**Output**: `./specs/<name>/requirements.md`

Activities:
- User stories creation
- Acceptance criteria definition
- Functional requirements table
- Non-functional requirements
- Out of scope items
- **MANDATORY: document `Project type` in Verification Contract** (`fullstack` | `frontend` | `api-only` | `cli` | `library`)
  - If unclear: ask the user before closing the phase
  - This field gates all VE task generation and e2e skill loading downstream

Ends with: `awaitingApproval: true`

### 3. Design Phase

**Command**: `/ralphharness:design`
**Agent**: architect-reviewer
**Output**: `./specs/<name>/design.md`

Activities:
- Architecture diagrams (mermaid)
- Component definitions
- Interface specifications
- Data flow documentation
- Technical decisions table
- Test strategy

Ends with: `awaitingApproval: true`

### 4. Tasks Phase

**Command**: `/ralphharness:tasks`
**Agent**: task-planner
**Output**: `./specs/<name>/tasks.md`

Activities:
- POC-first task breakdown
- 4-phase structure (POC, Refactor, Test, Quality)
- Verify commands for each task
- Commit messages
- Quality checkpoints every 2-3 tasks
- **Read `Project type` from requirements.md before generating VE tasks:**
  - `fullstack` / `frontend` → include VE0 (ui-map-init) + VE1..N (Playwright)
  - `api-only` → VE tasks via WebFetch/curl only, no VE0
  - `cli` / `library` → VE tasks via test/build commands only, no VE0

Ends with: `awaitingApproval: true`

### 5. Execution Phase

**Command**: `/ralphharness:implement`
**Agent**: spec-executor (via Ralph Loop)
**State**: `phase: "execution"`

Activities:
- Task-by-task execution
- Verification after each task
- Commit after verified completion
- Progress tracking in `.progress.md`
- **For VE tasks**: load e2e skills in order — `playwright-env` → `mcp-playwright` → `playwright-session` → `ui-map-init` (VE0 only)
- **Only load e2e skills when project type is `fullstack` or `frontend`**

Ends with: State file deleted on completion

## Quick Mode

With `--quick` flag:
- All phases run automatically using the same agents as normal mode
- Interviews, walkthroughs, and awaitingApproval skipped
- spec-reviewer validates each artifact (max 3 iterations)
- Auto-transitions to execution
- Project type must be inferable from codebase — if not, quick mode pauses and asks

## State File Transitions

| Phase | State Value |
|-------|-------------|
| Research | `"research"` |
| Requirements | `"requirements"` |
| Design | `"design"` |
| Tasks | `"tasks"` |
| Execution | `"execution"` |

## Phase Skipping

Not recommended but possible:
- `/ralphharness:tasks` can be run after minimal research
- Quality may suffer without full spec phases
- Use `--fresh` to restart from any phase
- **Warning**: skipping requirements means `Project type` may be missing → task-planner will need to infer or ask

## Subagent Timeout and Recovery Protocol

When a subagent (spec-executor, qa-engineer) does not respond or appears stuck:

1. **Detection**: If a delegated task produces no output for 5+ minutes, the coordinator should assume the subagent is stuck.
2. **First retry**: Re-delegate the same task with a more constrained prompt (reduce scope, be more specific about expected output).
3. **Second retry**: If still no response, log to `.progress.md`:
   ```markdown
   ### [TIMEOUT] Task $taskIndex: $title
   - Status: TIMEOUT after 2 attempts
   - Action: Skipping to next task. Will retry later if blocking.
   ```
4. **Mark as blocked**: Set task status to `[ ] [TIMEOUT]` in tasks.md — do NOT mark as complete.
5. **Continue**: Move to the next task. Do NOT block the entire sprint for one stuck subagent.
6. **Post-sprint retry**: After completing remaining tasks, revisit `[TIMEOUT]` tasks with a more targeted prompt incorporating learnings from subsequent tasks.

**Important**: Never fabricate output for a timed-out subagent. Either retry with better context or escalate.
