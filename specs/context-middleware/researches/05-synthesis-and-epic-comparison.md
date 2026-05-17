---
spec: context-middleware
sub-research: 05
date: 2026-05-17
source: Epic definition (ENGINE_ROADMAP.md Section 10) + all sub-research above
---

# Sub-Research: Synthesis — Patterns vs Epic Recommendations

## Source

- `docs/ENGINE_ROADMAP.md` — Section 10: Context Middleware spec definition
- `specs/_epics/engine-roadmap-epic/epic.md` — Spec 10 in epic context
- All 4 sub-research documents above

## Epic Definition of Spec 10

The epic defines Spec 10 (context-middleware) with 4 changes:

| Change | Description | Source Pattern |
|--------|-------------|---------------|
| 1 | Proactive condensation at threshold | Deep Agents SummarizationMiddleware |
| 2 | Reactive condensation on overflow | OpenHands CondensationRequest |
| 3 | Tool result eviction (>200 lines → disk) | Deep Agents FilesystemMiddleware |
| 4 | Tool argument truncation for old calls | Deep Agents TruncateArgsMiddleware |

**Goal**: Prevent coordinator context overflow when running 30+ task specs (~15,000-30,000 tokens per iteration).

## Pattern Comparison Matrix

| Pattern | Source | Proactive? | Complexity | Reliability | Recommended? |
|---------|--------|-----------|------------|-------------|--------------|
| **Proactive condensation at threshold** | Deep Agents | Yes | Low (shell script) | High | YES |
| **Reactive condensation on overflow** | OpenHands | No | Low (inline handler) | Medium | YES (fallback) |
| **Tool result eviction** | Deep Agents | Always | Low (spec-executor rule) | High | YES |
| **Tool argument truncation** | Deep Agents | Always | Low (spec-executor rule) | Medium | YES |
| **context-mode MCP interception** | MCP ecosystem | Always | High (MCP server) | High | NO (overkill) |
| **BM25 indexing of tool output** | context-mode | Always | High (indexing) | High | NO (overkill) |

## Decision: What to Use

### Layer 1: Proactive Condensation (DEEP AGENTS PATTERN) — USE

**Why**: This is the primary defense against context overflow. It prevents the problem before it happens.

**Parameters** (from Deep Agents, adapted for Smart Ralph):
- Threshold: 2,000 lines combined (chat.md + .progress.md)
- Keep: last 5 task entries in .progress.md, last 20 messages in chat.md
- Archive: full content to `.archive.md` before condensing
- Method: shell script called by coordinator

**Implementation**:
- Script: `hooks/scripts/context-middleware.sh`
- Called by: stop-watcher.sh (before generating continuation prompt)
- Not a new hook type — just a function at the end of stop-watcher.sh

### Layer 2: Reactive Condensation (OPENHANDS PATTERN) — USE AS FALLBACK

**Why**: Edge cases exist. If proactive threshold is exceeded (e.g., unusual task generates massive output), we need a safety net.

**Parameters**:
- Trigger: LLM returns context_length_exceeded error
- Handler: inline in stop-watcher.sh continuation prompt generation
- Recovery: condense chat.md, regenerate continuation prompt

**Implementation**:
- Inline in stop-watcher.sh (same script as proactive)
- Only activates when error is detected in tool result
- Should rarely, if ever, trigger in normal operation

### Layer 3: Tool Result Eviction (DEEP AGENTS PATTERN) — USE

**Why**: Tool results from grep, git diff, file reads are the largest single consumer of context tokens.

**Parameters**:
- Threshold: 200 lines per tool result
- Method: Write full result to `.context-cache/<tool>_<timestamp>.md`, send first 50 lines + line count
- Cleanup: `.context-cache/` on spec completion

**Implementation**:
- In the coordinator prompt (stop-watcher.sh): when generating continuation, check if any tool result exceeds 200 lines
- Truncate to first 50 lines, write full to `.context-cache/`, add reference
- NOT a new hook — just a modification to how continuation prompts are generated

### Layer 4: Tool Argument Truncation (DEEP AGENTS PATTERN) — USE WITH CAVEATS

**Why**: Old tool call arguments in the conversation consume tokens but aren't needed.

**Parameters**:
- Keep: last 10 tool call arguments intact
- Truncate: older tool call arguments to "[truncated — was {size} chars]"
- Only truncate arguments >100 lines (small arguments are fine)

**Implementation**:
- In the coordinator prompt (stop-watcher.sh): before sending continuation, scan for large old tool arguments
- Truncate and replace with compact reference
- Caveat: Claude Code's own tool output truncation already limits what we see. This pattern mainly applies to conversation history that's already in the context.

## Decision: What NOT to Use

### context-mode MCP Server — SKIP

**Why**: Adds unnecessary complexity (MCP server, BM25 index, external process). Smart Ralph's coordinator already controls tool output via continuation prompts. A shell script that truncates large outputs before they enter the context is simpler and equally effective.

### BM25 Indexing — SKIP

**Why**: The agent already knows what files to read and what content to look for. BM25 is for cases where the agent doesn't know what it's looking for. Smart Ralph's tasks are structured and specific.

### RAG on Codebase — SKIP

**Why**: Smart Ralph's spec format (research.md, requirements.md, design.md, tasks.md) provides structured context. Semantic search is overkill for this structured format.

## Architecture: Final Design

```
Each LLM Call
  │
  ├── 1. Check: chat.md + .progress.md combined lines?
  │     ├── >2000: Proactive condensation (write .archive.md, keep summary)
  │     └── ≤2000: Skip
  │
  ├── 2. Generate continuation prompt
  │     ├── Large tool results? Truncate to 50 lines, write full to .context-cache/
  │     └── Old tool args >100 lines? Truncate to [truncated — {size} chars]
  │
  ├── 3. Send to LLM
  │     └── If context_length_exceeded error?
  │           └── Reactive condensation (fallback)
  │
  └── 4. Receive response
        └── Continue loop
```

## Risk Assessment

| Risk | Likelihood | Severity | Mitigation |
|------|-----------|----------|------------|
| Over-aggressive condensation loses detail | Low | High | 85% threshold, archive full version |
| Condensation adds latency | Low | Low | 1-2 seconds per condensation event |
| Archive files fill up disk | Very Low | Low | Clean up .archive.md on spec completion |
| Reactive condensation never triggers | High | Low | Good — means proactive works perfectly |

## Comparison to Cancelled Spec 2 (prompt-diet-refactor)

Spec 2 was cancelled because "file restructuring was too risky." The context-middleware approach is:

| Aspect | Spec 2 (prompt-diet) | Spec 10 (context-middleware) |
|--------|---------------------|-----------------------------|
| Approach | Restructure spec files | Non-mutating middleware |
| Risk | Modifying originals | NEVER modifying originals |
| Rollback | Difficult (files changed) | Trivial (delete .condensed.md + .archive.md) |
| Impact on existing specs | Could break any spec | Only affects context delivery, not spec content |
| Agent awareness | Agents see different file structure | Agents see same files, just trimmed context |

**Verdict**: Middleware is the correct approach. It's additive (never modifying existing files) and reversible (just delete cache files).

## Summary of Recommendations

1. **YES** — Proactive condensation at 2000 lines (Deep Agents pattern, adapted to shell)
2. **YES** — Reactive condensation as fallback (OpenHands pattern, inline in stop-watcher.sh)
3. **YES** — Tool result eviction >200 lines (Deep Agents pattern, in continuation prompt generation)
4. **YES** — Tool argument truncation >100 lines, >10 steps old (Deep Agents pattern, in continuation prompt generation)
5. **NO** — context-mode MCP server (overkill, shell approach is sufficient)
6. **NO** — BM25 indexing (agent knows what to read, simple file references are enough)
7. **NO** — RAG on codebase (structured spec format, no semantic search needed)
