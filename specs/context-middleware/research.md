---
spec: context-middleware
phase: research
date: 2026-05-17
status: complete
---

# Research: Context Middleware (Spec 10)

## Executive Summary

Smart Ralph's coordinator loads ~2,507 lines of reference files every iteration and chat.md grows to 400-1,600+ lines across a spec. By iteration 10-15, total context reaches 5,000-13,000 lines (~20,000-50,000 tokens), risking context overflow and quality degradation. This spec adds a middleware layer (shell scripts + prompt rules) that runs before each LLM call to prevent overflow via proactive condensation, reactive fallback, tool result eviction, and context scoping — replacing the cancelled Spec 2 (prompt-diet-refactor) with a non-disruptive additive approach.

The spec is informed by Deep Agents (LangChain), OpenHands SDK, Anthropic's context engineering guidance, and analysis of 7 real specs' actual file sizes. Additionally, context scoping (selective reference loading) is identified as the single biggest context reduction opportunity the original spec definition missed.

**Feasibility**: HIGH | **Risk**: LOW | **Effort**: M

## Research Questions Answered

### 1. What is the actual context footprint per delegation?

**The spec undercounted by ~18%.** The progress.md claimed "coordinator loads ~2,118 lines of references every iteration." Actual file sizes show:

| File | Lines |
|------|-------|
| coordinator-pattern.md | 1,104 |
| failure-recovery.md | 620 |
| verification-layers.md | 240 |
| phase-rules.md | 433 |
| commit-discipline.md | 110 |
| **Total references** | **2,507** |

Plus implement.md's inline coordinator prompt (643 lines) = **~3,150 lines static per initialization**.

Full delegation context (references + state + task block + .progress.md snippet + spec-executor agent):

| Component | Lines |
|-----------|-------|
| 5 reference files | 2,507 |
| State file + task block | ~50-70 |
| .progress.md context | 50-200 |
| spec-executor.md (agent system prompt) | 425 |
| **Typical delegation** | **~3,030-3,250** |
| **VE task (+e2e skills)** | **+~1,300 → ~4,300-4,550** |

Per-iteration growth estimate:
Formula: `context(N) = static_base + N * (chat_growth_per_task * tasks_per_iteration + progress_growth_per_iteration)`

Where:
- `static_base` = ~3,150 lines (references + implement.md)
- `chat_growth_per_task` = ~10-30 lines per task (verified against 7 real specs)
- `tasks_per_iteration` = 1 (sequential) or up to 5 (parallel batch)
- `progress_growth_per_iteration` = ~5-15 lines per iteration (per-task learnings)

Derived estimates:
- Iteration 0: ~3,150 lines
- Iteration 10: ~4,650-6,650 lines (10 * 150 lines avg growth)
- Iteration 20: ~6,150-9,150 lines (20 * 150 lines avg growth)

### 2. What grows over the spec lifetime?

Verified against 7 real specs:

| Spec | chat.md | .progress.md | Tasks |
|------|---------|-------------|-------|
| pair-debug-auto-trigger | 404 | 243 | ~12-15 |
| bmad-bridge-plugin | 1,122 | 165 | ~8 |
| pre-execution-critic | 1,319 | 282 | ~9 |
| signal-log-and-ci | 1,027 | — | ~12 |
| ralphharness-rename | 1,608 | 64 | ~20 |
| gito-fixes | 156 | 222 | ~8 |

**chat.md** grows linearly with task count (especially with external reviewer), reaching 400-1,600+ lines. **chat.md typically exists** only for specs that use an external reviewer (verified across 30+ specs: specs without external reviewer do not create chat.md; a few edge cases like agent-chat-protocol create it for internal coordination).

**.progress.md** grows inconsistently (64-370 lines), accumulating per-task learnings and progress tracking.

### 3. What is the primary risk not addressed by the original spec?

**Reference loading bloat**: The 2,507 lines of references are loaded once and stay loaded indefinitely. By iteration 10, with ~8,000 lines of conversation, references are 31% of total context. The original spec's condensation at 2,000 lines targets the GROWING part (conversation) but the REFERENCES remain uncompressed.

**Section analysis of coordinator-pattern.md** (1,104 lines, 24 sections):

| Category | Sections | Approx. Lines | Loaded Every Iteration? |
|----------|----------|---------------|------------------------|
| Always relevant | Role Definition, Read State, Check Completion, Parse Current Task, Pre-Delegation Check, Signal Protocol, Chat Protocol, Task Delegation, Sequential Execution, State Update, Git Push Strategy, Completion Signal | ~385 | YES |
| Conditional: [P] tasks only | Parallel Group Detection, Native Task Sync - Parallel, Progress Merge | ~120 | Only when [P] marker |
| Conditional: VE tasks only | VERIFY Task Detection, Delegation Contract (qa-engineer) | ~85 | Only for [VERIFY] tasks |
| Conditional: nativeSync enabled | Initial Setup, Bidirectional Check, Pre-Delegation, Failure, Post-Verification, Completion, Modification (7 sections) | ~155 | Only when nativeSyncEnabled=true |
| Conditional: PR lifecycle | PR Lifecycle Loop (Phase 5) | ~100 | Only for Phase 5 tasks |
| Conditional: pair-debug | Pair-Debug Mode Announcement | ~30 | Only when trigger fires |
| Conditional: modification handling | Modification Request Handler, Native Task Sync - Modification | ~95 | Only when modification occurs |
| Remaining (headers, transitional text, unclassified) | Section headers, code blocks, cross-references | ~134 | Present always but low-value |

**Assessment**: ~385 lines are relevant for every delegation. The remaining ~719 lines are conditional on task type, phase, or mode. The LLM receives all 1,104 lines every iteration. This is an upper-bound estimate based on section headers and content scan.

### 4. How do Deep Agents handle context?

**Architecture**: Three middleware components run before every LLM call:
- **SummarizationMiddleware**: Condenses at 85% of context window → replaces conversation with compact summary (~10% size)
- **FilesystemMiddleware**: Evicts tool results >20K tokens to disk with preview
- **TruncateArgsMiddleware**: Truncates old tool call arguments, keeps recent ones

**Transferability to Smart Ralph**: PARTIAL. Deep Agents can intercept LLM API calls programmatically. Smart Ralph runs as a Claude Code plugin — the stop-hook outputs a continuation prompt, not a modified conversation. The condensation pattern transfers via shell scripts but must work at the file level (write `.condensed.md` and `.archive.md`) rather than modifying the conversation in-memory.

**Deep Agents went from #30 to #5 on Terminal-Bench** after adding these patterns (13.7 point improvement).

### 5. How does OpenHands handle context?

**Architecture**: Event log (immutable JSONL) + reactive condensation on `context_length_exceeded` error. When overflow occurs:
1. CondensationRequest is sent to LLM with the full event log
2. LLM summarizes: what happened, files modified, current progress, next steps
3. Condensed summary replaces the old conversation
4. Event log preserved for reference

**Transferability to Smart Ralph**: LESS NEEDED. Smart Ralph's structured spec format (research.md, requirements.md, design.md, tasks.md) provides natural context boundaries that OpenHands lacks. Growth patterns are more predictable and bounded. The structured format means much of the "conversation history" that OpenHands struggles with is already structured in Smart Ralph.

**Reactive condensation** is a good fallback for Smart Ralph but should be secondary to proactive condensation.

### 6. What does context-mode MCP server do?

context-mode is an MCP server that intercepts tool output before it reaches the LLM:
1. **Intercept**: MCP server catches tool results
2. **Sandbox**: If too large, write to disk, send preview
3. **Index**: BM25 index for semantic search
4. **Retrieve**: Agent queries by natural language

**Decision: SKIP for Smart Ralph**. Adds unnecessary complexity (MCP server, BM25 index, external process). Smart Ralph's coordinator already controls tool output via continuation prompts. A shell script that truncates large outputs is simpler and equally effective for Smart Ralph's structured use case.

### 7. What does the awesome-harness-engineering catalog suggest?

The catalog (902 stars) lists 50+ projects. Relevant patterns:
- **Microsoft Azure SRE**: Filesystem-based context organized by severity and recency, automatic pruning
- **Stripe Minions**: Tool result filtering before LLM input — only send semantically relevant content
- **AGENTS.md template**: Define what context the agent should consider (context scoping)
- **IMPLEMENT.md template**: Structured execution reduces context bloat

### 8. What does Anthropic recommend?

From Anthropic's own context engineering guidance:
1. **"Files for large context"**: If context exceeds comfortable range, put it in files → Smart Ralph already does this (references are files, not in system prompt)
2. **"Use system prompts for stable context"**: Model capabilities, rules, constraints → Smart Ralph's implement.md serves this role
3. **"Use conversation for dynamic context"**: Current task state, progress → Smart Ralph's chat.md serves this
4. **"Be specific about what context matters"**: Don't dump everything → Smart Ralph's biggest gap. It loads ALL 5 references every iteration regardless of phase or task type.

**Improvement opportunity**: Load references progressively based on phase. During POC phase, skip verification-layers.md. During quality phase, skip commit-discipline.md.

### 9. What patterns should be added to the spec?

Based on the gap analysis, 5 patterns should be added:

| # | Pattern | Priority | Rationale |
|---|---------|----------|-----------|
| 1 | **Context scoping** (selective reference loading) | HIGH | Biggest context reduction opportunity. Reduces per-iteration context by 30-50%. |
| 2 | **Condensation event logging** to `.metrics.jsonl` | HIGH | Observability needed to validate middleware effectiveness. |
| 3 | **Signal-based degradation detection** | MEDIUM | Behavior-driven trigger: if HOLD/PENDING/DEADLOCK rate increases, trigger condensation before line threshold. |
| 4 | **Adaptive thresholds** based on spec size | LOW | Scale threshold by totalTasks count. Small specs condense later, large specs condense earlier. |
| 5 | **Context budget accounting** | LOW (v0.2) | Track per-task context budget instead of line counts. More accurate but more complex. |

### 10. What patterns should be removed or deferred?

| Pattern | Action | Rationale |
|---------|--------|-----------|
| **Tool argument truncation** | **DEFER to v0.2** | Claude Code already truncates tool output at the platform level. The plugin cannot modify how Claude Code handles tool arguments. Sub-research #05 (synthesis) recommended this pattern as "in-scope with caveats," but the gap analysis (`.research-gaps.md`) confirmed it is partially redundant with Claude Code's own truncation. Skip until overflow persists after implementing other patterns. |
| **context-mode MCP server** | SKIP (confirmed) | All sub-research documents agree. Shell scripts + prompt instructions are simpler. |
| **BM25 indexing** | SKIP (confirmed) | Overkill. Smart Ralph's agent knows what files to read. |
| **RAG on codebase** | SKIP (confirmed) | Structured spec format provides context boundaries. |

### 11. How does the middleware interact with existing specs?

| Spec | Interaction | Risk | Recommendation |
|------|-------------|------|----------------|
| **Spec 3 (role-boundaries)** | LOW | Middleware creates files (`.condensed.md`, `.archive.md`) in spec directory. Role contracts don't apply to shell scripts. | Add `.condensed.md`/`.archive.md` to files spec-executor can read but not modify. |
| **Spec 4 (loop-safety)** | STRONG | Must integrate with metrics logging, circuit breaker, git checkpoints, read-only detection. | Log condensation events to `.metrics.jsonl`. Handle read-only case gracefully. |
| **Spec 6 (signals)** | CRITICAL | signals.jsonl MUST NOT be condensed. Chat.md condensation must preserve `lastReadLine` metadata. | **EXCLUDE signals.jsonl from condensation. Preserve lastReadLine.** |
| **Spec 7 (collaboration)** | MODERATE | Collaboration signals (HYPOTHESIS, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY) must survive condensation. | Preserve these signal names during chat.md condensation. |
| **Spec 8 (pair-debug)** | MODERATE | PAIR-DEBUG MODE announcement, Driver/Navigator roles, debug logging tool results must survive. | Preserve "PAIR-DEBUG", "Driver:", "Navigator:" lines. Don't evict pair-debug tool results. |
| **Spec 9 (pre-execution-critic)** | LOW | Middleware file operations are LOW risk (write within spec scope). | Document middleware operations as LOW risk in security-risk-levels.md. |

### 12. What risks are not considered by the original spec?

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Archive file accumulation** | HIGH | Name with timestamps. Delete on spec completion. Keep max 3 archives. |
| **Condensation during critical operations** | MEDIUM | Check for active file writes before condensing. Use lock file. |
| **Condensation quality depends on LLM** | MEDIUM | Use `.archive.md` as authoritative source. Agent can reference archive for details. |
| **.progress.md learnings loss** | MEDIUM | Split `.progress.md` into stable (Learnings, Goal) and volatile (per-task progress) sections. Always preserve stable section. |
| **Line-count vs token mismatch** | LOW | Add rough token estimation: `wc -c < file | awk '{print $1/4}'` |

### 13. What is the recommended architecture?

```
Each Coordinator Iteration
  │
  ├── 0. Context Scoping (selective reference loading)
  │     ├── Phase 1 (POC): load coordinator-pattern.md, failure-recovery.md
  │     ├── Phase 2 (Refactor): + commit-discipline.md
  │     ├── Phase 3-4 (Test/Quality): + verification-layers.md
  │     └── Pair-debug mode: + pair-debug.md
  │
  ├── 1. Proactive Condensation (DEEP AGENTS PATTERN)
  │     ├── Check: chat.md + .progress.md combined lines
  │     ├── > threshold? Condense:
  │     │     ├── Preserve: signals (HOLD/PENDING/DEADLOCK), pair-debug, collaboration signals
  │     │     ├── Preserve: stable .progress.md sections (Goal, Learnings)
  │     │     ├── Keep: last 3 task entries in .progress.md, last 15 messages in chat.md
  │     │     ├── Archive full to .archive.<timestamp>.md
  │     │     ├── Replace chat.md/.progress.md with condensed versions
  │     │     └── Log event to .metrics.jsonl
  │     └── ≤ threshold? Skip
  │
  ├── 2. Tool Result Eviction (DEEP AGENTS PATTERN)
  │     ├── Per-file-type thresholds:
  │     │     ├── grep/rg results: >100 lines → evict
  │     │     ├── git diff: >200 lines → evict
  │     │     ├── file reads: >500 lines → evict
  │     │     └── ls/find: >300 lines → evict
  │     └── Eviction method: write full to .tool-results/, send first 50 lines + summary
  │
  ├── 3. Send to LLM
  │     └── If context_length_exceeded error?
  │           └── Reactive Condensation (OPENHANDS FALLBACK)
  │                 ├── Condense chat.md
  │                 ├── Restore: task state, active signals, recent learnings
  │                 └── Retry delegation
  │
  └── 4. Completion
        └── Cleanup: .tool-results/, .archive.*.md, .condensed.md
```

### 14.1 Context Scoping Implementation Sketch

**Phase-to-reference mapping** (modification to implement.md):
```bash
# POC (Phase 1): only coordinator-pattern, failure-recovery
# Refactor (Phase 2): + commit-discipline
# Test/Quality (Phase 3-4): + verification-layers
# Skip phase-rules.md for Phase 1-2 (it only constrains Phase 3-4)
```

**Task-type-based loading** (pseudocode):
```bash
# In implement.md's "Read these references" section:
case "$PHASE" in
  "execution")
    # Phase check from .ralph-state.json → phase field
    # Use phase-rules.md only after POC phase completes
    ;;
  *)
    # Research phase: skip phase-rules.md, verification-layers.md
    ;;
esac

# Pair-debug: load pair-debug.md additionally
if grep -q "PAIR-DEBUG" chat.md 2>/dev/null; then
  load references/pair-debug.md
fi
```

**Long-term**: Split coordinator-pattern.md into:
- `coordinator-base.md` (~385 lines) — always loaded
- `coordinator-parallel.md` (~120 lines) — loaded for [P] tasks
- `coordinator-ve.md` (~85 lines) — loaded for [VERIFY] tasks
- `coordinator-native-sync.md` (~155 lines) — loaded when nativeSyncEnabled
- `coordinator-pr-lifecycle.md` (~100 lines) — loaded for Phase 5
- `coordinator-modifications.md` (~95 lines) — loaded on modification
- `coordinator-pair-debug.md` (~30 lines) — loaded in pair-debug mode

### 14. What are the recommended thresholds?

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Proactive condensation | 2,000 lines (default) | ~75% of model window headroom. Conservative. |
| Adaptive threshold | >30 tasks: 1,500 lines; ≤15 tasks: 2,500 lines | Small specs don't need early condensation |
| Keep after condense (.progress.md) | Last 3 task entries | More than enough for continuity |
| Keep after condense (chat.md) | Last 15 messages + all preserved signals | Signals are more important than message count |
| Tool eviction (grep) | 100 lines | grep results are the most verbose |
| Tool eviction (git diff) | 200 lines | Diffs have semantic density |
| Tool eviction (file read) | 500 lines | Agent knows file path, easy to re-read |
| Tool eviction (ls/find) | 300 lines | Usually short and structured |
| Max archives kept | 3 | Prevents unbounded accumulation |

### 15. Implementation Order

```
1. Proactive condensation + context-aware archival (core)
   ├── Preserve signals, decisions, pair-debug announcements
   ├── Exclude signals.jsonl from condensation
   ├── Integrate with Spec 4 metrics (.metrics.jsonl)
   └── Archive cleanup on spec completion

2. Tool result eviction (immediate context reduction)
   ├── Configurable per-file-type thresholds
   ├── .tool-results/ directory
   └── Cleanup on spec completion

3. Reactive condensation (safety net)
   ├── Inline handler in stop-watcher.sh
   ├── State recovery protocol
   └── Circuit breaker interaction

4. Context scoping (selective reference loading)
   ├── Phase-based reference loading in implement.md
   ├── Task-type-based reference loading
   └── Split coordinator-pattern.md into base + extensions (long-term)

5. Adaptive thresholds (nice-to-have)
   ├── Scale by totalTasks count
   └── Token estimation layer

6. Tool argument truncation (deferred to v0.2)
   └── Only if overflow persists after 1-4
```

## Sources

- `docs/ENGINE_ROADMAP.md` — Spec 10 definition, gap analysis, Brainstorm findings
- `specs/_epics/engine-roadmap-epic/epic.md` — Dependency graph, shared files
- `docs/harness-engineering/03-langchain-deep-agents.md` — Deep Agents blog post
- `docs/harness-engineering/05-tools-and-frameworks.md` — Tool ecosystem
- `docs/harness-engineering/08-practical-implementation-guide.md` — AGENTS.md, RAG, context engineering
- `docs/harness-engineering/09-reference-implementations.md` — 16 reference projects
- `docs/harness-engineering/10-deep-agents-deep-dive.md` — Deep Agents source code deep dive
- `docs/harness-engineering/11-openhands-deep-dive.md` — OpenHands SDK deep dive
- `specs/context-middleware/researches/01-05.md` — All 5 sub-research documents
- `specs/pre-execution-critic/research.md` — Pre-execution critic research (context for Spec 9 interaction)
- [LangChain Deep Agents](https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering) — Proactive condensation, FilesystemMiddleware
- [OpenHands SDK](https://docs.openhands.dev/) — Reactive condensation, event log, critic
- [awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) — 50+ project catalog
- [Anthropic: Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Context engineering principles
- [Anthropic: Harness Design for Long-Running Agents](https://www.anthropic.com/engineering/harness-design-long-running-apps) — Checkpoints, memory management
- [OpenAI Codex](https://github.com/openai/codex) — 83k stars, terminal coding agent

## Related Specs

| Spec | Name | Relationship |
|------|------|--------------|
| 2 | prompt-diet-refactor | CANCELLED — this spec replaces it with non-mutating approach |
| 3 | role-boundaries | Context middleware creates files within spec scope (LOW risk per role contracts) |
| 4 | loop-safety-infra | STRONG integration: metrics logging, circuit breaker, checkpoints, read-only handling |
| 6 | signal-log-and-ci-autodetect | CRITICAL: signals.jsonl excluded from condensation, lastReadLine preserved |
| 7 | collaboration-resolution | Collaboration signals preserved during condensation |
| 8 | pair-debug-auto-trigger | Pair-debug mode announcements preserved |
| 9 | pre-execution-critic | Middleware operations marked LOW risk to avoid false positive blocks |
