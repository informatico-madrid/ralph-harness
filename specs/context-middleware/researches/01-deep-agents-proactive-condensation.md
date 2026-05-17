---
spec: context-middleware
sub-research: 01
date: 2026-05-17
source: LangChain Deep Agents (code source) + harness-engineering docs 03, 08, 10
---

# Sub-Research: Deep Agents Proactive Condensation + Tool Eviction

## Source

- LangChain blog: [Improving Deep Agents with Harness Engineering](https://www.langchain.com/blog/improving-deagents-with-harness-engineering)
- [Deep Agents source code](https://github.com/langchain-ai/deep-agents) (referenced in 10-deep-agents-deep-dive.md)
- `docs/harness-engineering/10-deep-agents-deep-dive.md` (440 lines)
- `docs/harness-engineering/03-langchain-deep-agents.md` (165 lines)
- `docs/harness-engineering/08-practical-implementation-guide.md` (395 lines, sections 4-5)

## Problem Solved

Deep Agents runs multi-step coding tasks in the terminal. Over many steps (200+), the conversation context grows unbounded, leading to:
- O(cost) — each LLM call grows with conversation history
- OLLM errors — hitting context window limits
- Quality degradation — LLMs perform worse with very long contexts

## Architecture: Composable Middleware Chain

```
LLM Call → [TruncateArgsMiddleware] → [SummarizationMiddleware] → [FilesystemMiddleware] → LLM
```

Three middleware components run in sequence before each LLM API call. Each is independently configurable.

### 1. SummarizationMiddleware (Proactive)

**Trigger**: When conversation exceeds a configurable `max_tokens` threshold (default: ~55,000 tokens, conservatively below model limit).

**Mechanism**:
1. Detects the current conversation is approaching the context limit
2. Sends a `/condense` request to the LLM with:
   - The full conversation history
   - A system instruction to summarize while preserving ALL actionable details
3. Replaces the old conversation with the condensed version
4. Preserves the most recent N messages (configurable, default: 5) at the end

**Key design principle — "summarize, don't delete"**:
- The condensation instruction explicitly says: "Summarize the conversation but preserve ALL specific actionable details, file paths, code snippets, and decisions."
- After condensation, the full original conversation is archived to disk (filesystem) for reference if needed later.

**Threshold strategy**:
- Conservative: condenses at 85% of model context window
- This leaves headroom for the condensation itself (which temporarily doubles context usage)
- The condensed output is typically ~10% of original size

**Result**: Each LLM call after condensation only sees a compact summary (~10% of original) + last 5 messages. Context per call stays bounded.

### 2. FilesystemMiddleware (Tool Result Eviction)

**Trigger**: When a tool result exceeds `max_output_tokens` (default: ~20,000 tokens / ~80,000 characters).

**Mechanism**:
1. Before sending tool result to the LLM, checks its size
2. If too large: writes the full result to a file on disk
3. Sends a reference to the file instead: `See {path/to/file}. The full output is available at {filepath}.`
4. The LLM can later read the file if needed using a read tool

**Key design principle**: Large outputs (long file listings, git diffs, grep results) shouldn't consume conversation tokens. They belong on disk.

### 3. TruncateArgsMiddleware (Argument Truncation)

**Trigger**: Every LLM call, inspects the entire conversation.

**Mechanism**:
1. Scans all previous tool call arguments in the conversation
2. For old tool calls with very large argument values, truncates them
3. Replaces with: `[truncated — was {size} chars]`
4. Keeps the most recent N tool calls intact (configurable)

**Key design principle**: The LLM doesn't need the full content of a tool call that happened 50 steps ago. It needs the most recent ones.

## Performance Impact

- **LangChain measurement**: Deep Agents went from #30 to #5 on Terminal-Bench (13.7 point improvement)
- Context per LLM call: reduced from unbounded (~200k+ tokens for long tasks) to bounded (~55k)
- Cost per task: reduced by 5-10x (fewer tokens per call, no re-reading old history)
- Speed: condensation adds ~1-2 seconds per condensation event, but saves time by avoiding re-reading old context

## Transferable Patterns for Smart Ralph

### What to Borrow
1. **85% threshold for proactive condensation** — conservative, leaves headroom
2. **Summarize not delete** — preserve all actionable details in the summary
3. **Archive to disk** — write full original to `.archive.md` after condensing
4. **Tool result eviction at filesystem boundary** — >200 lines → file on disk with preview
5. **Argument truncation for old calls** — keep recent, truncate old

### What to Adapt
1. Deep Agents uses Python middleware intercepting LLM API calls. Smart Ralph runs in Claude Code, so the middleware is implemented as:
   - Shell script (pre-condensation hook in stop-watcher.sh)
   - spec-executor rules (tool result eviction, argument truncation)
   - NOT Python middleware (wrong execution model)
2. Deep Agents archives to `.txt` files. Smart Ralph should archive to `.condensed.md` and `.archive.md`
3. Deep Agents uses `/condense` command. Smart Ralph should use `context-middleware.sh` script called by coordinator

### What to Skip
1. **No composable middleware chain** — Smart Ralph doesn't need Python-level composition. Shell + spec rules are simpler.
2. **No per-call scanning of all tool arguments** — Smart Ralph's tool results are already bounded by Claude Code's truncation. Focus on proactive condensation of conversation history, which is the primary bloat source.

## Risks
- **Over-aggressive condensation** loses detail. Mitigation: 85% threshold is conservative. Also archive full version.
- **Condensation quality** depends on LLM. Mitigation: use explicit instruction to preserve ALL actionable details.
- **Double context during condensation**: reading full conversation + writing condensed version. Mitigation: 85% threshold leaves room.

## Recommendation

**Use the proactive condensation pattern with these parameters:**
- Threshold: 2,000 lines (chat.md + .progress.md combined) — ~75% of typical model window
- Keep: last 5 task entries in .progress.md, last 20 messages in chat.md
- Archive: full content to `.archive.md` before condensing
- Method: Coordinator calls `context-middleware.sh` before each LLM delegation
- Non-mutating: NEVER modify original files. Write `.condensed.md` and `.archive.md` alongside.
