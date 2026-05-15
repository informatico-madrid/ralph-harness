# RalphHarness — Master Improvement Plan

> **Date**: 2026-04-13
> **Sources**: Brainstorm 1 (Perplexity, 1273 lines) + Brainstorm 2 (Perplexity, ~330 turns) + Full codebase audit + 20-claim verification against real files
> **One flow. One plan. One source of truth. Every claim verified against real code.**

---

## 0. The Single Objective

RalphHarness should be a spec-driven development engine where agents work autonomously for hours and leave branches in **"ready for human review"** state.

The human is always there as final arbiter — but only for **semantic/product judgment**, never for "tests are broken", "coverage is faked", "HOLD signals ignored", or "state is inconsistent". Those problems must be caught **mechanically** before they reach the human.

---

## 1. What We Have (Verified Against Real Code)

### Architecture is Correct

| Component | Status | Verified In |
|-----------|--------|-------------|
| Phased workflow (research → requirements → design → tasks → implement) | ✅ | `skills/spec-workflow/SKILL.md` |
| 10 specialized agents | ✅ | `agents/*.md` (10 files) |
| State file (.ralph-state.json) with schema | ✅ (partial — nativeTaskMap missing from schema) | `schemas/spec.schema.json` |
| External reviewer onboarding | ✅ | `commands/implement.md` Step 4 |
| Epic triage | ✅ | `commands/triage.md`, `agents/triage-analyst.md` |
| Parallel execution ([P] tasks with TeamCreate) | ✅ | `references/coordinator-pattern.md` |
| Recovery mode (fix tasks with fixTaskMap) | ✅ | `references/failure-recovery.md`, `implement.md` |
| 5-layer verification (designed) | ✅ | `references/coordinator-pattern.md` |
| Chat protocol (HOLD/DEADLOCK/SPEC-DEFICIENCY signals) | ✅ | `references/coordinator-pattern.md` |
| Verification Contract with Project type + Entry points | ✅ | `templates/requirements.md` |
| Native Task Sync with graceful degradation (nativeSyncFailureCount >= 3 → disable) | ✅ | `references/coordinator-pattern.md` |
| EXECUTOR_START signal (Layer 0) | ✅ | `references/coordinator-pattern.md` |
| TASK_MODIFICATION_REQUEST handler (SPLIT/PREREQ/FOLLOWUP/ADJUST) | ✅ | `references/coordinator-pattern.md` |
| PR Lifecycle loop (Phase 5, 48h timeout) | ✅ | `references/coordinator-pattern.md` |
| VE-cleanup guarantee with skip-forward pseudocode | ✅ | `references/coordinator-pattern.md` |
| Git Push Strategy (batch push) | ✅ | `references/coordinator-pattern.md` |
| lastReadLine tracking in chat protocol | ✅ | `references/coordinator-pattern.md` |
| stop-watcher hook (666 lines) | ✅ | `hooks/scripts/stop-watcher.sh` |

### But There Are Problems (All Verified)

---

## 2. All Gaps — Single Prioritized List

### From Brainstorm 1: Execution Failures (m401/fix-emhass evidence)

#### C1: Verification Layers Contradiction ⚠️
**What**: `coordinator-pattern.md` says **5 layers**. `verification-layers.md` says **3 layers**. `implement.md` says **3 layers**.

**Verified against real files**:
- `coordinator-pattern.md` line ~617: "Run these 5 verification layers BEFORE advancing taskIndex" → Layers 0-4: EXECUTOR_START, Contradiction, Signal, Anti-fabrication, Artifact review
- `verification-layers.md` line 5: "Three verification layers run BEFORE advancing taskIndex" → Layers 1-3: Contradiction, Signal, Artifact review
- `implement.md` line ~210: "This covers: 3 layers (contradiction detection, TASK_COMPLETE signal, periodic artifact review via spec-reviewer)"

**Impact**: Layer 0 (EXECUTOR_START) and Layer 3 (Anti-fabrication) are NOT active when coordinator follows `verification-layers.md`. The anti-fabrication layer ("NEVER trust pasted output, ALWAYS run verify command independently") exists in coordinator-pattern.md but is missing from the file the coordinator is told to read.

**Real evidence**: Executor claimed "ruff check → All checks passed" when 72 errors existed. Layer 3 should have caught it but wasn't active because the coordinator was following the 3-layer doc.

#### C2: HOLD Signals Ignored ⚠️
**What**: Coordinator reads chat.md in natural language and decides whether HOLD exists. No mechanical grep check forces a binary decision. The model uses "no new messages" reasoning to skip past active HOLDs.

**Verified against real files**: `coordinator-pattern.md` Chat Protocol has the signal rules table (HOLD → DO NOT delegate, PENDING → same, DEADLOCK → HARD STOP, etc.) and `lastReadLine` tracking. But the check is text-based: the LLM reads the file and interprets it.

**Real evidence**: Coordinator said "No new messages in chat.md after the last review cycle, so I can continue" despite 2 active HOLD signals for tasks 2.10, 2.11, 2.13. Later admitted: "That was a grave error on my part."

**Root cause**: The model reasons in natural language ("no new messages after lastReadLine") and misses that HOLD signals exist from prior cycles. `lastReadLine` tracks what's new but not what's **active**.

#### C3: State Drift Undetected
**What**: No pre-loop validation that tasks.md checkmarks match .ralph-state.json taskIndex. The coordinator has **8** (not 6) Native Task Sync sections that can each fail silently.

**Verified against real files**: `coordinator-pattern.md` has 8 Native Task Sync sections:
1. Initial Setup
2. Bidirectional Check
3. Pre-Delegation
4. Parallel
5. Failure
6. Post-Verification
7. Completion
8. Modification

Each follows the same graceful degradation pattern (nativeSyncFailureCount >= 3 → disable). If any fails silently, the map drifts.

**Real evidence**: In fix-emhass-sensor-attributes, tasks.md said "38/38 complete" while task_review.md showed FAIL/WARNING on tasks 4.3-4.5, and reviewer had to recreate .ralph-state.json and reset taskIndex to 29.

**Additional finding**: `nativeTaskMap`, `nativeSyncEnabled`, `nativeSyncFailureCount` are used in implement.md and coordinator-pattern.md but are **NOT in the schema** (`schemas/spec.schema.json`). The schema defines `state` with phase, taskIndex, totalTasks, etc. but omits the native sync fields.

#### C4: Executor Reports Partial Verification as Complete ⚠️
**What**: Executor reports only the positive part of verification ("1441 tests pass, 100% coverage") while hiding the negative part ("Ruff: 1 error, Mypy: 26 errors").

**Verified against real files**: This is a consequence of the verification layer contradiction (C1). If Layer 3 (anti-fabrication) isn't active, there's no check for this.

**Real evidence**: Task 2.17 executor reported "1441 tests pass, 100% coverage maintained" to reviewer while its own reasoning showed "Ruff: 1 error, Mypy: 26 errors". The task's Verify command was only pytest — it didn't cover ruff/mypy.

**Root cause**: Task-level VERIFY commands only verify the specific task scope. Global CI state (ruff/mypy across the whole project) is not tracked separately. The executor's "Verification" summary conflates task-level verification with global CI health.

### From Brainstorm 2: Bmalph Comparison + BMAD Integration

#### I1: Prompt Bloat ⚠️
**What**: Coordinator reads 5 reference files every iteration. Total ~15,000+ tokens. `coordinator-pattern.md` alone is 1,098 lines with 8 sync sections, PR lifecycle, modification handler, git push strategy, etc.

**Verified against real files**:
| File | Lines | Loaded Every Iteration? |
|------|-------|------------------------|
| `coordinator-pattern.md` | 1,098 | ✅ (implement.md #1) |
| `failure-recovery.md` | ~400 | ✅ (implement.md #2) |
| `verification-layers.md` | ~200 | ✅ (implement.md #3) |
| `phase-rules.md` | ~300 | ✅ (implement.md #4) |
| `commit-discipline.md` | ~120 | ✅ (implement.md #5) |
| **Total** | **~2,118** | |

Plus duplications:
- **Quality checkpoint rules**: in `quality-checkpoints.md`, `phase-rules.md` (Quality Checkpoint Rules section), `task-planner.md` (Intermediate Quality Gate Checkpoints section)
- **VE task definitions**: in `task-planner.md`, `phase-rules.md`, `quality-checkpoints.md`
- **E2E anti-patterns**: in `e2e-anti-patterns.md`, inline in `coordinator-pattern.md` (VE delegation contract + standard delegation contract)
- **Test integrity / false-complete**: in `test-integrity.md` AND `quality-checkpoints.md` (Critical Anti-Pattern section)
- **Intent classification**: in `intent-classification.md`, `task-planner.md` (Workflow Selection section), `skills/reality-verification/SKILL.md` (Goal Detection section)

**Templates are JS/Node focused**: `templates/tasks.md` mentions `pnpm check-types`, `pnpm test`, `pnpm lint`, `pnpm test:e2e`. This is fine for JS projects but means Python/HA specs need manual adaptation.

#### I2: Role Boundary Violations
**What**: External reviewer edits .ralph-state.json, resets taskIndex, unmarks tasks in tasks.md. No mechanical prevention.

**Verified against real files**: No file-access constraints exist in any agent file. `agents/external-reviewer.md` does not say "DO NOT edit .ralph-state.json". The coordinator-pattern.md defines what the coordinator does but doesn't define what others cannot do.

**Real evidence**: In fix-emhass-sensor-attributes, reviewer recreated .ralph-state.json and reset taskIndex to 29 for Phase 4.

#### I3: Missing Bmalph-Style Safety Infra
**What**: RalphHarness has no git checkpoint, circuit breaker, or loop metrics. Bmalph has all three.

**Verified**: RalphHarness has `maxTaskIterations` (per-task retry limit) and `maxGlobalIterations` (total loop limit) in implement.md, but no:
- Pre-loop git checkpoint (rollback safety)
- Circuit breaker (stop after N consecutive failures, not just total iterations)
- Metrics append (per-task performance data)
- Read-only detection (heartbeat write check)
- Test failure injection (put specific test failures in executor context)

#### I4: Schema Incompleteness
**What**: `schemas/spec.schema.json` does NOT define `nativeTaskMap`, `nativeSyncEnabled`, `nativeSyncFailureCount` — yet these fields are used in implement.md and coordinator-pattern.md.

**Verified**: Schema defines `state` with phase, taskIndex, totalTasks, taskIteration, failedStory, originTaskIndex, maxTaskIterations, recoveryMode, maxFixTasksPerOriginal, fixTaskMap, maxFixTaskDepth, globalIteration, maxGlobalIterations, awaitingApproval, modificationMap, maxModificationsPerTask, maxModificationDepth, repairIteration.

But **missing**: `nativeTaskMap`, `nativeSyncEnabled`, `nativeSyncFailureCount`, `chat.executor.lastReadLine` (referenced in chat protocol), `recoveryMode` (present in schema but not in state definition — it IS in the schema, verified).

Wait — re-checking: `recoveryMode` IS in the schema. `nativeTaskMap`, `nativeSyncEnabled`, `nativeSyncFailureCount` are NOT.

### Strategic Gaps (Future)

#### S1: No BMAD Integration
BMAD generates excellent rigid specs for large features. No bridge to ralphharness format exists.

#### S2: Unused speckit Plugin
`plugins/ralph-speckit/` exists (47 files) but is not referenced in any command or skill.

#### S3: No Spec Surface Map
No index relating high-level features/user flows to which specs/tasks cover them (Kitchen Loop "spec surface" concept). `specs/.index/` exists (via `update-spec-index.sh`) but only tracks spec names and status, not feature coverage.

---

## 3. Root Cause — Single Sentence

**Critical rules (HOLD, anti-fabrication, state integrity) are enforced through text interpretation instead of mechanical checks.**

Bmalph avoids this by putting complexity in **infra** (git commands, exit codes, counters) rather than in **agent coordination** (text-based rules, chat protocols). RalphHarness does the opposite.

**The solution**: Move critical rules from text to mechanics, borrow Bmalph's safety infra, add BMAD as a spec generator, and fix the verification layer contradiction.

---

## 4. What to Keep vs. Simplify vs. Add vs. Remove

### KEEP ✅ (This complexity is correct)
- Phased spec workflow (research → requirements → design → tasks → implement)
- 10 specialized agents with distinct roles
- 5-layer verification (once unified — currently contradictory)
- External reviewer with parallel review via chat.md/task_review.md
- Epic triage with _epics/ structure
- Recovery mode with fixTaskMap and depth limits
- Parallel execution ([P] tasks with TeamCreate/TaskCreate)
- TASK_MODIFICATION_REQUEST handler (SPLIT/PREREQ/FOLLOWUP/ADJUST)
- VE-cleanup guarantee with skip-forward
- Native Task Sync with graceful degradation (the pattern is correct, just needs schema update)
- Verification Contract with Project type + Entry points
- PR Lifecycle loop (Phase 5 with gh commands)

### SIMPLIFY ❌ (This complexity is fragile)
| What | Why | How |
|------|-----|-----|
| Text-based HOLD check | LLM reasons past the rule | Replace with `grep -c "\[HOLD\]\|\[PENDING\]\|\[URGENT\]"` + exit code |
| 5-reference coordinator context (~2,118 lines) | Model loses attention | ❌ CANCELLED — addressed via Specs 3-5 instead |
| 8 Native Task Sync sections (duplicated pattern) | Each can fail silently, same logic repeated 8x | Consolidate to 2: "before delegation" and "after completion" |
| Verification layers defined in 2 contradictory files | Anti-fabrication not always active | Single canonical source |
| Quality checkpoint rules in 3 files | Divergence risk | Single source |
| E2E anti-patterns inline in coordinator + in reference | Divergence risk | Only in reference |
| Detailed bash/jq scripts in agent context | Human documentation, not LLM execution need | Move to hooks/scripts/, reference by name |
| PR lifecycle inline in coordinator | Rarely used, adds context | Separate reference |
| Modification handler inline in coordinator | Rarely used, adds context | Separate reference |
| Git push strategy inline in coordinator | Implementation detail, not delegation logic | Separate reference |

### ADD ➕ (Missing infra)
- Pre-loop git checkpoint (rollback safety) — from Bmalph
- Circuit breaker (stop after N consecutive failures) — from Bmalph
- Loop metrics append (per-task performance data) — from Bmalph
- Read-only detection (heartbeat write check) — from Bmalph
- Role contract file (who can write what) — from brainstorm analysis
- BMAD bridge plugin (structural mapper) — from brainstorm analysis
- Schema fields for nativeTaskMap, nativeSyncEnabled, nativeSyncFailureCount, chat.executor.lastReadLine

### REMOVE 🗑️ (Dead code / contradictions)
- The 3-layer definition in `verification-layers.md` (replace with 5-layer unified)
- The 3-layer reference in `implement.md` (update to 5)
- Duplicated quality checkpoint rules (keep only in `quality-checkpoints.md`)
- Duplicated VE task definitions (keep only in `quality-checkpoints.md`)
- Duplicated E2E anti-patterns inline (keep only in `e2e-anti-patterns.md`)
- `ralph-speckit/` — either integrate or remove (decision needed)
- Schema incompleteness (add missing fields)

---

## 5. The Single Improvement Flow

```
┌─────────────────────────────────────────────────────┐
│  PHASE 1: Fix Critical Gaps                         │
│  Spec: engine-state-hardening                       │
│                                                     │
│  1. Unify verification layers → single source (5)   │
│  2. Mechanical HOLD check → grep + exit code        │
│  3. State integrity validation → pre-loop check     │
│  4. Schema update → add missing fields              │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  PHASE 2: Reduce Bloat ❌ CANCELLED                  │
│  Spec: prompt-diet-refactor (ABANDONED)             │
│                                                     │
│  1. Split coordinator-pattern.md → modular refs     │
│  2. Eliminate duplications → single source each     │
│  3. Remove dead text from agent context             │
│  4. Consolidate 8 sync sections → 2                 │
│  ⚠️ CANCELLED 2026-05-13: Risks > Benefits          │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 3: Enforce Role Boundaries ✅ DONE │
│ Spec: role-boundaries (completed 2026-04-27) │
│ │
│ 1. Role contract file → who can write what ✅ │
│ 2. File-access constraints in all agent files ✅ │
│ 3. State integrity hook → detect unauthorized edits ✅ │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 4: Add Bmalph-Style Safety ✅ DONE │
│ Spec: loop-safety-infra (completed 2026-04-27) │
│ │
│ 1. Pre-loop git checkpoint → rollback safety ✅ │
│ 2. Circuit breaker → stop after N failures/hours ✅ │
│ 3. Metrics append → iterations, fabrications, time ✅ │
│ 4. Read-only detection → heartbeat write check ✅ │
│ 5. CI snapshot → separate task verify from global ✅ │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 5: Extend with BMAD Bridge ✅ DONE │
│ Spec: bmad-bridge-plugin (completed 2026-04-28) │
│ │
│ 1. BMAD → ralphharness spec mapper (structural) ✅ │
│ 2. Plugin: plugins/ralph-bmad-bridge/ ✅ │
│ 3. Entry: /ralph-bmad:import <path> <spec-name> ✅ │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 6: Signal Event Log + CI Auto-Detection       │
│ Spec: signal-log-and-ci-autodetect                  │
│                                                      │
│ 1. signals.jsonl → immutable event log for control  │
│ 2. chat.md → rich collaboration only                │
│ 3. detect-ci-commands.sh → auto from project markers│
│ 4. Upgrade HOLD check from grep to jq on JSONL      │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 7: Agent Collaboration Protocol │
│ Spec: collaboration-resolution │
│                                                     │
│  1. Cross-branch regression investigation workflow   │
│  2. Experiment-propose-validate pattern in chat     │
│  3. Auto-fix-task for discovered bugs (not failures)│
│  4. Standard chat signals extension                 │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 8: Pair Debug Trigger │
│ Spec: pair-debug-auto-trigger │
│ │
│ 1. Auto-detect condition → enter pair mode │
│ 2. Driver/Navigator role split (no human push) │
│ 3. Debug logging as first-class technique │
│ 4. "First fix failed → escalate to pair" pattern │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 9: Pre-Execution Critic                        │
│ Spec: pre-execution-critic                           │
│                                                      │
│ 1. Security risk levels per tool call                │
│ 2. Pre-execution hook → block HIGH/CRITICAL          │
│ 3. Confirmation policy for risky operations          │
│ 4. Mechanical enforcement of role contracts           │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ PHASE 10: Context Middleware                          │
│ Spec: context-middleware                              │
│ (Replaces cancelled Spec 2 with middleware approach)  │
│                                                      │
│ 1. Proactive condensation → threshold-based          │
│ 2. Reactive condensation → on context overflow       │
│ 3. Tool result eviction → large outputs to filesystem│
│ 4. Tool argument truncation → old calls compressed   │
└─────────────────────────────────────────────────────┘
```

**Execution order is strict.** Each phase depends on the previous.

---

## 6. Spec Briefs (One Per Phase)

### Spec 1: `engine-state-hardening` ✅ COMPLETED

**Targets**: C1, C2, C3, C4, I4 (partial)

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Unify verification to 5 layers** | `references/verification-layers.md` | Make this the **canonical source** with all 5 layers (0: EXECUTOR_START, 1: Contradiction, 2: Signal, 3: Anti-fabrication, 4: Artifact review). Update `implement.md` to say "5 layers". Update `coordinator-pattern.md` to reference this file instead of defining layers inline. |
| 2 | **Mechanical HOLD check** | `commands/implement.md` (coordinator prompt) | Before delegation, coordinator MUST check for active HOLD signals mechanically. **Design detail**: Use a convention where resolved signals are marked `[HOLD:resolved]` or moved under a `## Resolved Signals` section. The grep only looks for unresolved signals: `grep -c "^\[HOLD\]\|^\[PENDING\]\|^\[URGENT\]" "$SPEC_PATH/chat.md"` (matches signals at start of line, not resolved ones). Exit code > 0 → block delegation, log to .progress.md, stop iteration. Exit code 0 → proceed. This prevents old resolved HOLDs from blocking execution. The existing chat protocol (announce, completion notice, signal processing) remains unchanged. |
| 3 | **State integrity validation** | `commands/implement.md` (Step 3, before loop) | Before loop starts: count [x] in tasks.md, compare with taskIndex in .ralph-state.json. If taskIndex is ahead of last [x] → correct it. If taskIndex is behind first incomplete → advance to correct position. Log to .progress.md. |
| 4 | **Schema update** | `schemas/spec.schema.json` | Add missing fields: `nativeTaskMap`, `nativeSyncEnabled`, `nativeSyncFailureCount`, `chat.executor.lastReadLine`. |
| 5 | **CI snapshot separation (conceptual rule only)** | `commands/implement.md` (coordinator prompt) | Add rule: executor must report task-level verification separately from global CI state. Task verification = what the task's Verify command checks. CI snapshot = overall project health. One cannot mask the other. **Note**: CI command discovery (which commands to run per project type) is planned for a future spec (see "Spec 4: loop-safety-infra" below). This spec only adds the conceptual separation rule with generic wording — no hardcoded ruff/mypy. |

**NOT in scope**: Don't restructure coordinator. Don't split files. Don't add new references. Don't change agent files. Minimal, targeted changes only.

---

### Spec 2: `prompt-diet-refactor` ❌ **CANCELLED**

> **Cancellation Date**: 2026-05-13
> **Decision**: Analysis determined that the risks of this refactoring outweigh the benefits. The complexity of splitting coordinator-pattern.md into 5 modular references, consolidating 8 Native Task Sync sections, and eliminating duplications presented too much risk of introducing regressions and breaking existing functionality. The spec was **not executed** and is **formally abandoned**.

**Targets**: I1

| # | Change | Detail |
|---|--------|--------|
| 1 | ~~**Split coordinator-pattern.md**~~ | ~~(1,098 lines → ~150 lines core + references)~~ |
| 2 | ~~**Consolidate 8 Native Task Sync sections → 2**~~ | ~~"Before delegation" and "After completion"~~ |
| 3 | ~~**Single source of truth** for duplicated content~~ | ~~Quality checkpoints, VE definitions, E2E anti-patterns~~ |
| 4 | ~~**Move dead text out of agent context**~~ | ~~Bash/jq scripts → hooks/scripts/~~ |
| 5 | ~~**Update implement.md reference list**~~ | ~~Modular loading never implemented~~ |

**Cancellation Rationale**:
- Risk of regressions in coordinator logic too high
- Splitting 1,098-line file into 5 references risks breaking existing coordination patterns
- 8 Native Task Sync sections have proven stable in practice
- Token context problem was addressed partially via other means (specs 3-5)
- Cost/benefit analysis: high complexity for uncertain gain

---

### Spec 3: `role-boundaries` ✅ COMPLETED (2026-04-27)

**Targets**: I2

| # | Change | Detail |
|---|--------|--------|
| 1 | **Role contract file** | `references/role-contracts.md` — matrix of who can read/write/edit which files during execution |
| 2 | **Update all agent files** | Add "See role-contracts.md for file access rules" + explicit "DO NOT edit" lists to: `agents/spec-executor.md`, `agents/external-reviewer.md`, `agents/qa-engineer.md`, `agents/spec-reviewer.md` |
| 3 | **State integrity hook** | Detect when .ralph-state.json is modified outside coordinator's state update flow. Log to .progress.md with "UNAUTHORIZED STATE MODIFICATION DETECTED". |

**Role contract** (summary):

| Agent | Can Write | Cannot Touch |
|-------|-----------|-------------|
| spec-executor | code, tests, .progress.md, tasks.md (checkmarks only) | .ralph-state.json, task_review.md, chat.md |
| external-reviewer | task_review.md, chat.md, .progress.md (review comments only) | .ralph-state.json, tasks.md |
| coordinator | .ralph-state.json, tasks.md (structure only), .progress.md (status only), chat.md | code, tests, task_review.md |
| qa-engineer | test files, .progress.md (verification results) | .ralph-state.json, tasks.md, task_review.md |
| spec-reviewer | .progress.md (review results) | code, tests, .ralph-state.json, tasks.md, task_review.md |

---

### Spec 4: `loop-safety-infra` ✅ COMPLETED (2026-04-27)

**Targets**: I3, C4 (CI snapshot part)

| # | Feature | Implementation |
|---|---------|---------------|
| 1 | **Pre-loop git checkpoint** | Before execution: `git add -A && git commit -m "checkpoint: before $spec execution"`. Store SHA in .ralph-state.json. If catastrophic failure: `git reset --hard <SHA>` restores repo. |
| 2 | **Circuit breaker** | Stop after N consecutive task failures (configurable, default 5) OR after N hours (configurable, default 48h). Log to .progress.md. Track consecutive failures in .ralph-state.json. |
| 3 | **Metrics append** | After each task: append to `specs/<name>/.metrics.jsonl`: `{"taskIndex": 5, "iteration": 1, "verifyTime": 12.3, "fabricationDetected": false, "timestamp": "..."}` |
| 4 | **Read-only detection** | At loop start: attempt small write to .progress.md. If fails → exit with "Repository is read-only". |
| 5 | **CI snapshot tracking** | Separate from task verification: after each quality checkpoint task, record global CI state (ruff exit code, mypy exit code, coverage %) in .ralph-state.json. This is different from per-task verify results. **Includes CI command discovery**: coordinator auto-detects project CI commands from Verification Contract in requirements.md (Project type + CI commands field) or from project config files (package.json scripts, pyproject.toml lint config, Makefile targets). Stores discovered commands in `.ralph-state.json` as `ciCommands: string[]` (schema field added in Spec 1). The conceptual separation rule was added in Spec 1; this spec adds the mechanical discovery and tracking. |

**Borrowed from Bmalph**: These are proven features. Adapt to ralphharness's architecture, don't copy blindly.

---

### Spec 5: `bmad-bridge-plugin` ✅ COMPLETED (2026-04-28)

**Targets**: S1

**Implementation**: `plugins/ralph-bmad-bridge/` — 985-line bash+jq structural mapper with 13 tests. Maps PRD→requirements.md, epics→tasks.md, architecture→design.md. Input sanitization with path traversal protection and spec name regex validation.

> **Note**: The BMAD→SSD mapping below is a **v1**. It should be validated and adjusted once you have a real BMAD PRD in hand. Don't over-engineer the mapping before seeing real data.

| Component | Detail |
|-----------|--------|
| **Plugin** | `plugins/ralph-bmad-bridge/` following standard plugin structure (plugin.json, commands/, scripts/) |
| **Mapper** | Structural (not AI prompts). Read BMAD artifacts → map to ralphharness spec format. |
| **Entry point** | `/ralph-bmad:import <bmad-project-path> <spec-name>` |
| **Mapping**: | |

| BMAD Artifact | RalphHarness Target |
|---------------|-------------------|
| PRD / Product Brief | requirements.md → User Stories + FR/NFR |
| User Stories + Acceptance Criteria | requirements.md → Verification Contract |
| Architecture Decision Records | design.md → Architecture section |
| Epic / Feature Breakdown | tasks.md → Phase breakdown |
| Test Scenarios | tasks.md → Verify commands |

**NOT in scope**: Agent prompts, execution logic, prompt engineering, micro-rules. This is a structural mapper only.

---

### Spec 6: `signal-log-and-ci-autodetect`

**Targets**: C2 (upgrade from grep to JSONL), C4 (CI auto-detection), new gaps from harness engineering research

**Context**: Spec 1 (engine-state-hardening) implemented a grep-based HOLD check on `chat.md` and a conceptual CI snapshot rule. The harness engineering research (OpenHands SDK + Deep Agents) revealed better approaches: an **immutable signal event log** (JSONL) for control signals, and **auto-detection of CI commands** from project markers. This spec upgrades both — without re-executing Spec 1.

**What currently exists (verified against real code)**:
- ✅ Spec 1 grep-based HOLD check: `grep -c "^\[HOLD\]\|^\[PENDING\]\|^\[URGENT\]" "$SPEC_PATH/chat.md"` (implemented)
- ✅ Spec 1 CI snapshot conceptual rule: executor reports task verification + CI snapshot separately (implemented)
- ✅ Spec 4 CI command discovery from Verification Contract in requirements.md (implemented)
- ✅ chat.md bidirectional communication with atomic append (flock-based)
- ❌ **No signal event log** — control signals (HOLD, PENDING, DEADLOCK) are text in chat.md, requiring LLM interpretation
- ❌ **No auto-detection of CI commands** — CI commands must be manually specified in Verification Contract
- ❌ **No separation of control vs collaboration** — chat.md mixes control signals with rich collaboration

**Key design decisions**:
- **Complexity**: LOW-MEDIUM. Adding a new file format (signals.jsonl) and a detection script. No restructuring of existing files.
- **Benefit**: HIGH. (a) HOLD check becomes truly mechanical (jq on JSONL, not grep on text). (b) CI commands auto-discovered — no manual specification. (c) chat.md freed for rich collaboration (prerequisite for Spec 7).
- **Approach**: Add signals.jsonl alongside chat.md. Migrate control signals to JSONL. Keep chat.md for collaboration. Add detect-ci-commands.sh for auto-discovery.

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Signal event log (signals.jsonl)** | NEW `templates/signals.jsonl` | **Separation of concerns**: Control signals (HOLD, PENDING, DEADLOCK, URGENT, ACK, CONTINUE, OVER, CLOSE) move from `chat.md` to an **immutable event log** (`signals.jsonl`). Each signal is a JSON line with `type`, `signal`, `from`, `task`, `status` (active/resolved), `timestamp`. `chat.md` remains for **rich collaboration** — pair programming, hypothesis exchange, context sharing, experiment results. **Source**: OpenHands SDK uses immutable event log with typed events (see `docs/harness-engineering/11-openhands-deep-dive.md` section 4). |
| 2 | **Upgrade HOLD check from grep to jq** | `commands/implement.md` (coordinator prompt) | Replace Spec 1's grep-based check with: `jq -r 'select(.signal=="HOLD" or .signal=="PENDING" or .signal=="DEADLOCK") | select(.status=="active")' "$SPEC_PATH/signals.jsonl" | wc -l`. Count > 0 → block delegation. Count == 0 → proceed. **Why JSONL is better than grep on chat.md**: (a) No LLM interpretation — structured data, not text. (b) `status: active/resolved` is explicit, not inferred from text markers. (c) Immutable — signals are appended, never edited. (d) chat.md stays clean for collaboration. |
| 3 | **Skills auto-detection** | NEW `hooks/scripts/detect-ci-commands.sh` | At spec start, auto-discover CI commands from project markers: `pyproject.toml` → ruff/mypy/pytest, `package.json` → pnpm lint/check-types/test, `Makefile` → make lint/test, `Cargo.toml` → cargo clippy/test. Store discovered commands in `.ralph-state.json` as `ciCommands: string[]`. This extends Spec 4's CI command discovery (from Verification Contract) with **automatic detection** — no manual specification needed. **Source**: OpenHands SDK auto-detects skills from project markers like `uv.lock`, `deno.json` (see `docs/harness-engineering/11-openhands-deep-dive.md` section 9). |
| 4 | **Update agent files for signal migration** | `agents/spec-executor.md`, `agents/external-reviewer.md` | Update signal emission instructions: control signals (HOLD, PENDING, DEADLOCK) → append to `signals.jsonl`. Collaboration content (hypotheses, findings, experiments) → append to `chat.md`. This is the migration path from Spec 1's grep-based approach. |

**NOT in scope**: Don't re-execute or modify Spec 1's completed work. Don't change the coordinator's core loop. Don't add LLM-based summarization. Don't modify existing chat.md content.

---

### Spec 7: `collaboration-resolution`

**Targets**: New gap from Brainstorm 3 — agents collaborating to solve regressions without escalating to human.

**Context from real evidence**: In a live spec execution, spec-executor and external-reviewer successfully collaborated via chat.md to diagnose an E2E regression. They used git diff (main vs HEAD), proposed hypotheses, ran experiments (timeout changes), and found the root cause (a renamed method that lost cache population). This is exactly the autonomous behavior desired — but it happened **ad hoc**, not by following explicit rules. The system needs to make this pattern **reliable and repeatable**, not dependent on agents improvising.

**What currently exists (verified against real code)**:
- ✅ chat.md bidirectional communication with atomic append (flock-based)
- ✅ Signal protocol: HOLD, PENDING, URGENT, DEADLOCK, INTENT-FAIL, SPEC-DEFICIENCY, ACK, CONTINUE, OVER, CLOSE, ALIVE, STILL
- ✅ External-reviewer can investigate code (Read, Bash, Grep, LSP tools granted)
- ✅ Spec-executor reads task_review.md before each task (External Review Protocol)
- ✅ Reviewer can produce FAIL with `fix_hint` suggestions
- ✅ Fix task mechanism exists (from failure-recovery.md) for executor failures
- ❌ **No cross-branch comparison workflow** (main vs HEAD for regression investigation)
- ❌ **No "experiment-propose-validate" pattern** in the chat protocol
- ❌ **No mechanism for reviewer to create a fix task for a discovered bug** (fix tasks only fire on executor non-completion)
- ❌ **No explicit "e2e regression investigation" workflow** (tests that passed on main but fail on HEAD)

**Key design decisions**:
- **Complexity**: LOW. This is about adding rules to the existing chat protocol and agent prompts, not building new infrastructure.
- **Benefit**: HIGH. Prevents unnecessary human escalation when agents can solve the problem themselves.
- **Approach**: Encode the successful pattern from the real E2E case as explicit rules, not as micro-rules. Focus on the workflow, not on prescribing every step.

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Cross-branch regression investigation workflow** | `references/collaboration-resolution.md` (NEW) | When a test that passed on main fails on HEAD and neither test nor fixture has changed: (a) executor runs `git diff main...HEAD` on the code path of the failing test, (b) identifies the semantic change that broke the test, (c) proposes a fix, (d) runs the test to verify. This is a **first-class workflow**, not an ad hoc investigation. |
| 2 | **Experiment-propose-validate pattern in chat** | `references/collaboration-resolution.md` | Formalize the pattern: reviewer proposes hypothesis → executor runs experiment → both compare results → converge on root cause. Add standard chat signals for this: `HYPOTHESIS` (propose root cause theory), `EXPERIMENT` (run test to validate), `FINDING` (report result), `ROOT_CAUSE` (confirmed bug), `FIX_PROPOSAL` (suggest concrete fix). These extend the existing signal protocol — they don't replace it. |
| 3 | **Auto-fix-task for discovered bugs** | `references/failure-recovery.md` (extend) | Currently fix tasks are only generated when the executor fails to complete a task. Extend to support: when the external-reviewer discovers a bug (via investigation, not via task failure), they can write a `BUG_DISCOVERY` entry to `task_review.md` with evidence and fix suggestion. The coordinator reads this and generates a fix task (same format as failure-recovery fix tasks). This is a **new trigger** for fix task generation, separate from executor failure. |
| 4 | **Standard chat signals extension** | `templates/chat.md` (update) | Add the new collaboration signals to the signal legend: `HYPOTHESIS`, `EXPERIMENT`, `FINDING`, `ROOT_CAUSE`, `FIX_PROPOSAL`, `BUG_DISCOVERY`. Update `agents/spec-executor.md` and `agents/external-reviewer.md` to reference the collaboration-resolution rules. |
| 5 | **"Before modifying tests, check baseline" rule** | `agents/external-reviewer.md` (add) | Hard rule: "Before modifying any E2E test that passed on main, verify: (a) the test file hasn't changed in this spec (`git diff main...HEAD -- tests/e2e/`), (b) the fixture/environment hasn't changed, (c) the backend code path is different. If all three are unchanged, the problem is environmental — DO NOT modify the test." |

**NOT in scope**: Don't change the coordinator's core loop. Don't add new agent types. Don't create E2E diagnostics scripts (that would be a separate infra effort). This spec is about **encoding the collaboration pattern** that already works in practice.

---

### Spec 8: `pair-debug-auto-trigger`

**Targets**: Critical gap — collaboration emerges with human push, needs to emerge automatically.

**Context from real evidence**: In a live spec execution, spec-executor and external-reviewer successfully collaborated to find a critical bug (duplicate TripManager instances causing race conditions). But this required a **human push**: the user explicitly told both agents to "plantear hipótesis y escuchar hipótesis del otro", temporarily stripping their rigid roles. Once pushed, the collaboration was textbook: executor instrumented (debug logging), reviewer navigated (read diff, identified suspect function), they exchanged hypotheses, and converged on root cause. **The magic is real — but it needs a trigger, not a human.**

**What currently exists (verified against real code)**:
- ✅ External-reviewer can propose fixes but NOT write code (forbidden from modifying implementation files)
- ✅ Spec-executor can investigate via `rg`/`grep`, Explore subagent, `.progress.md` learnings
- ✅ Chat protocol supports bidirectional turn-taking (ACK, HOLD, OVER, CONTINUE, etc.)
- ✅ Fix task mechanism exists for executor failures
- ❌ **No Driver/Navigator role concept** — no agent file mentions these roles
- ❌ **No "pair debug mode"** — no named mode exists anywhere
- ❌ **No auto-trigger condition** — no rule says "when X happens, enter pair mode"
- ❌ **Debug logging not listed** as an investigation technique in spec-executor.md
- ❌ **No "first fix failed → escalate to pair" pattern** — escalation only goes to human or retry

**Key design decisions**:
- **Complexity**: LOW-MEDIUM. This is about adding a trigger condition and role adjustment to the existing agent protocol. No new infrastructure.
- **Benefit**: CRITICAL. This is the difference between "agents need a human push to collaborate" and "agents autonomously enter pair mode when stuck."
- **Approach**: Encode the trigger as a simple 3-condition check. Encode the role split as Driver (executor) / Navigator (reviewer). Preserve the separation — reviewer still doesn't write code.

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Auto-detect condition for pair mode** | `references/pair-debug.md` (NEW) | Enter pair-debug mode when ALL three conditions are met: (a) A test that was green is now red AND the test file has NOT changed in this spec (`git diff $TASK_START_SHA..HEAD -- tests/` returns empty), (b) At least one fix attempt has been tried and failed (taskIteration >= 2), (c) The external-reviewer has NOT already marked the task as FAIL (to avoid double-escalation). When triggered: coordinator announces pair mode in chat.md, both agents switch to hypothesis-driven debugging. |
| 2 | **Driver/Navigator role split** | `references/pair-debug.md` | In pair-debug mode: **Driver** = spec-executor (unique agent that writes code, runs commands, applies fixes, adds debug logging). **Navigator** = external-reviewer (reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings). Both share the instruction: "Formulate hypotheses, respond to the other's hypotheses, do NOT escalate to human unless you identify an explicit product/design decision." This preserves role separation (reviewer still doesn't write code) while enabling collaboration. |
| 3 | **Debug logging as first-class technique** | `agents/spec-executor.md` (add) | Add debug logging to the list of allowed investigation techniques. Rule: "When in pair-debug mode, you MAY add temporary `_LOGGER.warning()` or `console.log()` statements to instrument code paths. These MUST be removed before marking the task complete (or converted to proper tests). This is the Driver's primary investigation tool." |
| 4 | **"First fix failed → escalate to pair" pattern** | `references/failure-recovery.md` (extend) | Current: when taskIteration >= 2, generate fix task and retry. New: when taskIteration >= 2 AND the failing test is a pre-existing test (not a new test from this spec), announce pair-debug mode in chat.md before generating the fix task. The fix task becomes the Driver's first action in pair mode, with the Navigator providing hypothesis input. |
| 5 | **Coordinator announces pair mode** | `references/coordinator-pattern.md` (or `coordinator-core.md` after Spec 2) | When the 3-condition trigger fires, coordinator writes to chat.md: `"### PAIR-DEBUG MODE ACTIVATED\nDriver: spec-executor | Navigator: external-reviewer\nTrigger: [condition summary]\nBoth: formulate hypotheses, exchange findings, converge on root cause. Do not escalate to human unless product decision required."` This replaces the normal delegation pattern for this task. |

**NOT in scope**: Don't create new agent types. Don't change the reviewer's fundamental prohibition on writing code. Don't make pair mode the default — it's an escalation path, not a replacement for normal execution. Don't add micro-rules about how to debug — only the trigger and role split.

---

### Spec 9: `pre-execution-critic`

**Targets**: I2 (mechanical enforcement of role boundaries), new gap from harness engineering research

**Context**: Spec 3 (role-boundaries) added file-access constraints as **rules in agent prompts** ("DO NOT edit .ralph-state.json"). But rules in prompts are text interpretation — the LLM can still violate them. OpenHands SDK solves this with a **CriticMixin** that evaluates actions **before** execution, blocking dangerous operations mechanically. This spec adds the same capability to RalphHarness.

**What currently exists (verified against real code)**:
- ✅ Role contracts in `references/role-contracts.md` (Spec 3)
- ✅ "DO NOT edit" lists in agent files (Spec 3)
- ✅ State integrity hook that detects unauthorized edits after the fact (Spec 3)
- ❌ **No pre-execution evaluation** — actions are only checked after they execute
- ❌ **No security risk levels** — all write operations treated equally
- ❌ **No confirmation policy** — no mechanism to pause before risky operations

**Key design decisions**:
- **Complexity**: LOW. This is about adding a hook that checks tool calls before execution, not building new infrastructure.
- **Benefit**: HIGH. Converts role boundaries from "prompt rules" to "mechanical constraints" — exactly the pattern the roadmap identifies as the root solution (Section 3: "Move critical rules from text to mechanics").
- **Approach**: Add a pre-execution check script that the coordinator runs before delegating to the executor. The script evaluates the proposed action against role contracts and risk levels. HIGH/CRITICAL risk actions require explicit coordinator approval.

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Security risk level classification** | `references/security-risk-levels.md` (NEW) | Define risk levels for tool call types: `LOW` (read-only: ls, read, grep, glob), `MEDIUM` (write within spec scope: edit files in spec paths), `HIGH` (write outside spec scope: edit files not covered by spec), `CRITICAL` (destructive: delete files, force push, reset state). Map each tool to its default risk level. |
| 2 | **Pre-execution check script** | `hooks/scripts/pre-execution-check.sh` (NEW) | Before each tool call delegation, coordinator runs this script. Input: tool name, target file/path, agent role. Output: risk level + allow/block decision. Logic: (a) check role contracts for forbidden operations → block, (b) classify risk level → if HIGH/CRITICAL, require confirmation, (c) if LOW/MEDIUM, allow. |
| 3 | **Confirmation policy in coordinator** | `references/coordinator-pattern.md` (extend) | When pre-execution check returns HIGH or CRITICAL: coordinator pauses delegation, logs to .progress.md with "PRE-EXECUTION CHECK: HIGH risk operation detected — [details]", and waits for explicit human approval or rejection. This is the same pattern as OpenHands's confirmation policy. |
| 4 | **Mechanical role contract enforcement** | `hooks/scripts/pre-execution-check.sh` | Integrate role contracts from `references/role-contracts.md` into the pre-execution check. If the agent's role forbids writing to a file, the check blocks it mechanically — no LLM interpretation needed. This makes Spec 3's role contracts **enforced by code**, not just by prompt rules. |

**Source**: OpenHands SDK `CriticMixin` + `SecurityRisk` enum + confirmation policy (see `docs/harness-engineering/11-openhands-deep-dive.md` sections 7 and 8).

**NOT in scope**: Don't create new agent types. Don't change the execution loop structure. Don't add LLM-based critic evaluation (the check is deterministic, based on rules). Don't block read-only operations.

---

### Spec 10: `context-middleware`

**Targets**: I1 (prompt bloat / context overflow), replacement for cancelled Spec 2

**Context**: Spec 2 (`prompt-diet-refactor`) was cancelled because splitting coordinator-pattern.md into modular files carried too much regression risk. But the underlying problem remains: the coordinator reads ~2,118 lines of references every iteration, and as specs grow (30+ tasks), context overflows. Deep Agents and OpenHands solve this with **middleware/condensation** — intercepting and transforming the context before it reaches the LLM, without restructuring the source files.

**What currently exists (verified against real code)**:
- ✅ Circuit breaker stops runaway loops (Spec 4)
- ✅ Metrics tracking per task (Spec 4)
- ❌ **No context size management** — coordinator loads all references every iteration
- ❌ **No tool result eviction** — large tool outputs stay in context forever
- ❌ **No condensation** — no mechanism to compact history when context grows
- ❌ **No argument truncation** — old tool call arguments stay at full size

**Key design decisions**:
- **Complexity**: MEDIUM. This requires a new layer between the coordinator and the LLM, but it's **additive** — no existing files are restructured.
- **Benefit**: HIGH. This is the difference between "coordinator works for 10 tasks" and "coordinator works for 50+ tasks without context overflow."
- **Approach**: Add a context management layer that runs before each LLM call. It doesn't restructure source files — it transforms what the LLM sees. This is the **middleware pattern** from Deep Agents, not the **file split pattern** from cancelled Spec 2.

| # | Change | File | Detail |
|---|--------|------|--------|
| 1 | **Proactive condensation** | `hooks/scripts/condense-context.sh` (NEW) | Before each coordinator iteration, estimate context size (word count of references + chat.md + .progress.md). If exceeds threshold (configurable, default ~80% of model window): (a) archive .progress.md entries older than last 5 tasks to `.progress.archive.md`, (b) truncate chat.md to last N messages (archive full chat.md to `chat.archive.md`), (c) log condensation to .progress.md. **Source**: Deep Agents `SummarizationMiddleware` proactive threshold (see `docs/harness-engineering/10-deep-agents-deep-dive.md` section 4.2). |
| 2 | **Reactive condensation** | `hooks/scripts/stop-watcher.sh` (extend) | When coordinator LLM call fails with context overflow error: (a) archive full chat.md to `chat.archive.md`, (b) create condensed chat.md with only current task context, (c) archive .progress.md to `.progress.archive.md`, (d) create minimal .progress.md with current task status, (e) retry iteration. **Source**: OpenHands `CondensationRequest` reactive pattern (see `docs/harness-engineering/11-openhands-deep-dive.md` section 6.3). |
| 3 | **Tool result eviction** | `references/context-middleware.md` (NEW) | Rule for spec-executor: when a tool result exceeds N lines (configurable, default 200), write full result to `specs/<name>/.tool-results/<task-index>-<tool-call-id>.txt` and replace in context with preview (first 5 + last 5 lines + reference path). **Source**: Deep Agents `FilesystemMiddleware` eviction (see `docs/harness-engineering/10-deep-agents-deep-dive.md` section 5.3). |
| 4 | **Tool argument truncation** | `references/context-middleware.md` | Rule for coordinator: when constructing context for LLM call, truncate arguments of tool calls from completed tasks (keep only first 50 + last 50 chars of each arg). Active task tool calls remain at full size. **Source**: Deep Agents `TruncateArgsSettings` (see `docs/harness-engineering/10-deep-agents-deep-dive.md` section 4.3). |

**Why this replaces Spec 2 without its risks**:
- Spec 2 tried to **restructure source files** (split coordinator-pattern.md into 5 files) → high regression risk
- Spec 9 adds a **transformation layer** that doesn't modify source files → low regression risk
- If the middleware breaks, you can disable it and the coordinator works as before (just with larger context)
- The middleware is **opt-in** — it only activates when context exceeds thresholds

**NOT in scope**: Don't restructure any existing files. Don't add LLM-based summarization (too expensive per iteration). Don't change the coordinator's core loop. Don't modify agent prompts.

---

## 7. Master File Change List

| File | Change | Spec |
|------|--------|------|
| `schemas/spec.schema.json` | Add nativeTaskMap, nativeSyncEnabled, nativeSyncFailureCount, chat.executor.lastReadLine | 1 |
| `references/verification-layers.md` | **Canonical source** — update to 5 layers (add Layer 0 EXECUTOR_START, Layer 3 Anti-fabrication) | 1 |
| `references/coordinator-pattern.md` | Reference unified verification, add mechanical HOLD check | 1 |
| `commands/implement.md` | State validator, mechanical HOLD check, CI snapshot rule, checkpoint, circuit breaker, update reference list after split | 1 + 4 + 2 |
| NEW: `templates/signals.jsonl` | Signal event log template (JSONL format for HOLD/PENDING/DEADLOCK signals) | 6 |
| NEW: `hooks/scripts/detect-ci-commands.sh` | Auto-detect CI commands from project markers (pyproject.toml, package.json, Makefile, Cargo.toml) | 6 |
| `references/quality-checkpoints.md` | Keep as canonical. Remove duplicated test integrity section. | 2 |
| `references/phase-rules.md` | Remove duplicated quality checkpoint rules and VE definitions | 2 |
| `agents/task-planner.md` | Remove duplicated intent classification, VE definitions, quality checkpoint rules | 2 |
| `agents/external-reviewer.md` | Add role contract ref, file restrictions | 3 |
| `agents/spec-executor.md` | Add role contract ref, file restrictions | 3 |
| `agents/qa-engineer.md` | Add role contract ref, file restrictions | 3 |
| `agents/spec-reviewer.md` | Add role contract ref | 3 |
| `hooks/stop-watcher.sh` | Add circuit breaker, state integrity check | 4 |
| NEW: `references/coordinator-core.md` | Slim coordinator prompt (~150 lines: role, FSM, critical rules, signal protocol) | 2 |
| NEW: `references/ve-verification-contract.md` | VE task delegation rules (skills loading, anti-patterns reference) | 2 |
| NEW: `references/task-modification.md` | Modification request handling (SPLIT/PREREQ/FOLLOWUP/ADJUST, reindexing) | 2 |
| NEW: `references/pr-lifecycle.md` | Phase 5 PR management (gh commands, CI monitoring, review check) | 2 |
| NEW: `references/git-strategy.md` | Commit/push strategy (when to push, batch logic) | 2 |
| NEW: `references/role-contracts.md` | File access boundaries matrix | 3 |
| NEW: `references/loop-safety.md` | All safety rules (checkpoint, circuit breaker, metrics, read-only detection) | 4 |
| NEW: `hooks/scripts/checkpoint.sh` | Git checkpoint utilities | 4 |
| NEW: `plugins/ralph-bmad-bridge/` | BMAD bridge plugin | 5 |
| NEW: `references/collaboration-resolution.md` | Cross-branch regression workflow, experiment pattern, chat signals | 7 |
| `references/failure-recovery.md` | Extend fix task generation to support BUG_DISCOVERY trigger | 7 |
| `templates/chat.md` | Add collaboration signals (HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY) | 7 |
| `agents/external-reviewer.md` | Add "before modifying tests, check baseline" rule, reference collaboration-resolution | 7 |
| `agents/spec-executor.md` | Reference collaboration-resolution for cross-branch investigation | 7 |
| NEW: `references/pair-debug.md` | Auto-trigger condition, Driver/Navigator roles, pair mode announcement | 8 |
| `references/failure-recovery.md` | Extend to announce pair-debug mode before fix task (pre-existing test failures) | 8 |
| `agents/spec-executor.md` | Add debug logging as first-class investigation technique (in pair mode) | 8 |
| `references/coordinator-pattern.md` (or `coordinator-core.md`) | Add pair-debug mode announcement to signal handling | 8 |
| NEW: `references/security-risk-levels.md` | Risk level classification for tool calls (LOW/MEDIUM/HIGH/CRITICAL) | 9 |
| NEW: `hooks/scripts/pre-execution-check.sh` | Pre-execution check: role contract enforcement + risk level evaluation | 9 |
| `references/coordinator-pattern.md` | Add confirmation policy for HIGH/CRITICAL risk operations | 9 |
| NEW: `references/context-middleware.md` | Context management rules: eviction, truncation, condensation thresholds | 10 |
| NEW: `hooks/scripts/condense-context.sh` | Proactive condensation: archive old .progress.md and chat.md when context exceeds threshold | 10 |
| `hooks/stop-watcher.sh` | Add reactive condensation on context overflow error | 10 |

---

## 8. Success Criteria (Measurable)

| # | Criteria | How to Verify |
|---|----------|--------------|
| 1 | **No verification contradictions** | `grep -c "layer" references/verification-layers.md references/coordinator-pattern.md commands/implement.md` — all reference 5 layers |
| 2 | **HOLD cannot be missed** | Signal event log (`signals.jsonl`) check: `jq` filter for active HOLD/PENDING/DEADLOCK returns count > 0 → blocks delegation. No LLM interpretation involved. Test: append HOLD signal to signals.jsonl, start execution, verify it blocks. |
| 3 | **State drift detected at start** | Pre-loop validation: if tasks.md [x] count ≠ taskIndex, log to .progress.md and correct before proceeding. Test: manually change taskIndex, run implement, verify correction. |
| 4 | **Schema complete** | All fields used in implement.md and coordinator-pattern.md are defined in spec.schema.json. Test: JSON schema validation passes for real .ralph-state.json files. |
| 5 | **CI snapshot separated from task verify** | Executor reports task verification AND CI snapshot separately. One cannot mask the other. Test: create task where verify passes but ruff fails — both must be reported. |
| 6 | ~~**Coordinator context < 5,000 tokens**~~ | ❌ Spec 2 cancelled — **replaced by Spec 9** (context-middleware) with middleware approach instead of file split. |
| 7 | ~~**No duplicated rules**~~ | ❌ Spec 2 cancelled — dedup work deferred. Current duplication remains as acceptable technical debt. |
| 8 | **No reviewer editing state files** | After Spec 3: role contract in all agent files. Test: ask reviewer to edit .ralph-state.json — it must refuse. |
| 9 | **Rollback available** | After Spec 4: pre-loop checkpoint SHA stored in .ralph-state.json. Test: run spec, intentionally break code, `git reset --hard <SHA>` restores. |
| 10 | **Circuit breaker stops runaway loops** | After Spec 4: after N consecutive failures, execution stops with error. Test: create spec with failing tasks, verify stop. |
| 11 | **Metrics visible** | After Spec 4: `.metrics.jsonl` file exists after execution with per-task entries. |
| 12 | **BMAD specs accepted** | After Spec 5: `/ralph-bmad:import` produces valid spec in `specs/<name>/` that `/ralphharness:implement` can execute. |
| 13 | **Human escalation only for judgment** | Problems like "tests broken", "coverage faked", "state inconsistent" caught by engine. Only semantic/product decisions reach human. |
| 14 | **Cross-branch regression solved autonomously** | After Spec 7: when a test passes on main but fails on HEAD (with no test/fixture changes), agents follow the collaboration workflow to find root cause without human escalation. Test: intentionally break code in a spec, verify agents investigate via git diff and find the bug. |
| 15 | **BUG_DISCOVERY creates fix tasks** | After Spec 7: reviewer can write BUG_DISCOVERY to task_review.md, coordinator generates a fix task from it. Test: reviewer discovers a bug, verify fix task is created and executed. |
| 16 | **Pair-debug auto-triggers without human push** | After Spec 8: when a pre-existing test fails and first fix attempt fails (taskIteration >= 2), coordinator announces pair-debug mode in chat.md automatically. No human instruction needed. Test: intentionally break code, let agents attempt fix, verify pair mode activates on second iteration. |
| 17 | **Driver/Navigator collaboration produces root cause** | After Spec 8: in pair-debug mode, Driver (executor) instruments code, Navigator (reviewer) analyzes diff/architecture, they exchange hypotheses and converge on root cause. Test: verify chat.md shows hypothesis exchange pattern, not just sequential fix attempts. |
| 18 | **Debug logging added and cleaned up** | After Spec 8: debug logging is used as investigation tool in pair mode, and is removed (or converted to tests) before task completion. Test: verify no orphan debug logging remains after pair-debug session completes. |
| 19 | **Pre-execution critic blocks forbidden operations** | After Spec 9: when spec-executor attempts a write operation forbidden by role contracts, the pre-execution check blocks it mechanically before the file is modified. Test: instruct executor to edit .ralph-state.json, verify the operation is blocked by pre-execution-check.sh. |
| 20 | **Security risk levels active** | After Spec 9: every tool call delegation includes a risk level (LOW/MEDIUM/HIGH/CRITICAL). HIGH/CRITICAL operations require coordinator confirmation. Test: create a task that writes outside spec scope, verify coordinator pauses for confirmation. |
| 21 | **Proactive condensation prevents overflow** | After Spec 10: when context exceeds threshold, .progress.md and chat.md are automatically archived and condensed. Test: run a 30+ task spec, verify condensation triggers before context overflow. |
| 22 | **Reactive condensation recovers from overflow** | After Spec 10: when coordinator LLM call fails with context overflow, condensation runs automatically and the iteration retries. Test: artificially inflate context, verify recovery without human intervention. |
| 23 | **Tool result eviction works** | After Spec 10: tool results exceeding 200 lines are evicted to filesystem with preview + reference. Test: run a task that produces large grep output, verify eviction to .tool-results/ directory. |
| 24 | **CI commands auto-detected** | After Spec 6: `detect-ci-commands.sh` discovers lint/test/typecheck commands from project markers (pyproject.toml, package.json, Makefile). Test: run in a Python project with pyproject.toml, verify ruff/mypy/pytest are discovered and stored in .ralph-state.json. |
| 25 | **Signal event log replaces grep-based HOLD check** | After Spec 6: `signals.jsonl` exists with typed JSON entries. HOLD check uses `jq` filter on JSONL, not `grep` on chat.md. Test: append HOLD signal to signals.jsonl, start execution, verify it blocks. Verify chat.md contains no control signals. |

---

## 9. Execution Rules

1. **Sequential only**: Each spec depends on the previous. Do not skip or parallelize.
2. **Use ralphharness's own workflow**: Each spec goes through research → requirements → design → tasks → implement.
3. **Tasks must have concrete Verify commands**: grep, file existence, content validation. Not "verify quality".
4. **Show tasks.md for review before implementing**.
5. **No breaking changes**: Existing specs must continue to work after each spec.
6. **Minimal scope per spec**: One spec = one problem cluster. Don't bleed into other specs.
7. **Every claim verified against real code**: If a brainstorm claim doesn't match reality, adjust the plan based on what the code actually does.
8. **Spec 7 is special**: It encodes a pattern that already works in practice (agent collaboration via chat). The goal is to make it reliable and repeatable, not to invent new behavior.
9. **Spec 8 is the crown jewel**: It encodes the trigger that makes pair-debug happen automatically, without human push. This is the difference between "agents that collaborate when told to" and "agents that collaborate when stuck."

---

## 10. What Changed From Previous Versions

This document differs from earlier versions in these ways (after full codebase audit):

| Previous Claim | Correction |
|----------------|------------|
| "6 Native Task Sync sections" | **8 sections** (Initial Setup, Bidirectional, Pre-Delegation, Parallel, Failure, Post-Verification, Completion, Modification) |
| "Schema defines all state fields" | **Schema is missing**: nativeTaskMap, nativeSyncEnabled, nativeSyncFailureCount, chat.executor.lastReadLine |
| "verification-layers.md has 3 layers" | **Confirmed** — but coordinator-pattern.md has 5. This is the contradiction. |
| "implement.md says 3 layers" | **Confirmed** — line ~210: "This covers: 3 layers". Must update to 5. |
| "templates are JS/Node focused" | **Confirmed** — `templates/tasks.md` has pnpm commands. Python/HA specs need manual adaptation. |
| "E2E anti-patterns duplicated" | **Confirmed** — in e2e-anti-patterns.md AND inline in coordinator-pattern.md (2 places) |
| "Quality checkpoints in 3 files" | **Confirmed** — quality-checkpoints.md, phase-rules.md, task-planner.md |
| "Coordinator reads 5 references" | **Confirmed** — coordinator-pattern, failure-recovery, verification-layers, phase-rules, commit-discipline |

### From Brainstorm 3 (Agent Collaboration)

| Idea | Veredicto | Acción |
|------|-----------|--------|
| "Agentes debaten hipótesis por chat.md" | ✅ **Ya funciona en práctica** — pero ad hoc, no por reglas explícitas | Spec 7: codificar el patrón exitoso |
| "git diff main vs HEAD para encontrar root cause" | ✅ **Parcialmente** — spec-executor puede hacer git diff, pero no como workflow first-class | Spec 7: cross-branch regression workflow |
| "Experimentos (subir timeout) para validar hipótesis" | ✅ **Ad hoc** — no hay patrón formal experiment-propose-validate | Spec 7: formalize en chat protocol |
| "BUG_DISCOVERY → auto fix task" | ❌ **No existe** — fix tasks solo se generan por executor failure | Spec 7: extend failure-recovery.md |
| "Before modifying tests, check baseline en main" | ❌ **No existe** — ninguna regla previene cambios a tests sin verificar baseline | Spec 7: hard rule en external-reviewer |
| "E2E diagnostics script" | ❌ Descartado — no es infra prioritaria, es patrón de colaboración | No action (podría ser spec futura separada) |

### From Brainstorm 4 (Pair Programming — CRÍTICO)

| Idea | Veredicto | Acción |
|------|-----------|--------|
| "Colaboración emerge con empujón humano" | ✅ **Confirmado en práctica** — Spec 7 lo codifica, pero necesita trigger automático | Spec 8: auto-trigger sin humano |
| "Driver/Navigator roles" | ❌ **No existen** — ningún agent file menciona estos roles | Spec 8: codificar en pair-debug.md |
| "Modo pair-debug automático" | ❌ **No existe** — no hay named mode ni trigger condition | Spec 8: 3-condition trigger |
| "Debug logging como técnica de investigación" | ❌ **No está** en spec-executor.md como técnica explícita | Spec 8: add to investigation techniques |
| "First fix failed → escalate to pair" | ❌ **No existe** — escalation va a retry o humano | Spec 8: extend failure-recovery.md |
| "3-condition trigger: test no cambió + fix falló + reviewer no FAILO" | ❌ **No existe** | Spec 8: pair-debug.md trigger logic |

**Insight clave del Brainstorm 4**: Lo que funcionó no fue quitarle roles al revisor, sino darles a **ambos** la misma instrucción de "plantear hipótesis y escuchar hipótesis del otro". El revisor naturalmente se fue a Navigator (analizar diff, arquitectura, proponer experimentos) y el executor se quedó como Driver (instrumentar, aplicar fixes). **La separación de roles se mantiene — lo que cambia es el modo de interacción.**

### From Harness Engineering Research (2026-05-13)

| Idea | Source | Veredicto | Acción |
|------|--------|-----------|--------|
| "Event log inmutable para signals" | OpenHands SDK | ✅ **Probado en producción** — OpenHands usa EventLog inmutable con eventos tipados | Spec 6: signals.jsonl + chat.md para colaboración |
| "Critic pre-execution" | OpenHands SDK | ✅ **Probado** — CriticMixin evalúa acciones antes de ejecutar | Spec 9: pre-execution-critic |
| "Middleware componible" | Deep Agents (LangChain) | ✅ **Probado** — wrap_model_call intercepta y transforma requests | Spec 10: context-middleware (reemplaza Spec 2 cancelado) |
| "Skills auto-detection por marcadores" | OpenHands SDK | ✅ **Probado** — AgentContext detecta uv.lock, deno.json | Spec 6: detect-ci-commands.sh |
| "Proactive condensation con threshold" | Deep Agents (LangChain) | ✅ **Probado** — SummarizationMiddleware a 85% de ventana | Spec 10: condense-context.sh |
| "Reactive condensation on overflow" | OpenHands SDK | ✅ **Probado** — CondensationRequest on LLMContextWindowExceedError | Spec 10: stop-watcher.sh extension |
| "Tool result eviction to filesystem" | Deep Agents (LangChain) | ✅ **Probado** — FilesystemMiddleware evicta ToolMessages > 20K tokens | Spec 10: context-middleware.md rule |
| "Tool argument truncation" | Deep Agents (LangChain) | ✅ **Probado** — TruncateArgsSettings trunca args de tool calls viejos | Spec 10: context-middleware.md rule |
| "Security risk levels (LOW/MEDIUM/HIGH/CRITICAL)" | OpenHands SDK | ✅ **Probado** — SecurityRisk enum + confirmation policy | Spec 9: security-risk-levels.md |
| "Confirmation policy for risky operations" | OpenHands SDK | ✅ **Probado** — HIGH/CRITICAL requieren aprobación | Spec 9: coordinator-pattern.md extension |

**Documentación de referencia**: `docs/harness-engineering/` — 11 documentos con deep dives en OpenHands SDK y Deep Agents (LangChain), incluyendo implementación concreta extraída del código fuente.

---

## 11. Next Action

**This document is frozen as the source of truth for the ralphharness engine.**
Location: `docs/ENGINE_ROADMAP.md`

**To create the next spec, give this to your VS Code agent:**

> Create spec `signal-log-and-ci-autodetect` using ralphharness's own workflow.
> Use `docs/ENGINE_ROADMAP.md` as the single source of truth for gaps and requirements.
> Follow the Spec 6 brief in Section 6. Read `plugins/ralphharness/templates/` for format.
> Show me tasks.md for review before implementing.
