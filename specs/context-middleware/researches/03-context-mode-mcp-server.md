---
spec: context-middleware
sub-research: 03
date: 2026-05-17
source: awesome-harness-engineering (ai-boost/awesome-harness-engineering) + 05-tools-and-frameworks.md, 09-reference-implementations.md
---

# Sub-Research: context-mode MCP Server Pattern

## Source

- [awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) — lists context-mode as a context engineering tool
- `docs/harness-engineering/05-tools-and-frameworks.md` (100 lines)
- `docs/harness-engineering/09-reference-implementations.md` (270 lines)
- `docs/harness-engineering/08-practical-implementation-guide.md` (395 lines, sections 4-5)

## Problem Solved

context-mode is an MCP (Model Context Protocol) server designed to handle tool output that is too large for the LLM's context window. When an agent calls a tool that returns a huge result (e.g., `grep` over a large codebase, `git diff` of thousands of lines), the full result would consume tens of thousands of context tokens.

## Architecture: MCP Server as Context Interceptor

```
Agent → Tool Call → context-mode MCP Server → [If result > threshold] → Return preview + BM25 index
                                    → [If result < threshold] → Pass through
```

### Key Components

**1. Tool Output Interception**
- context-mode sits between the agent and tool execution via the MCP protocol
- Every tool result is intercepted before being sent to the LLM
- If the result exceeds a configurable threshold, it is intercepted

**2. Sandboxing**
- Large tool results are written to disk as files
- The LLM receives a preview: `{tool_name} returned {size} chars. First {n} lines: [preview]`
- The full result is stored in a sandbox directory

**3. BM25 Retrieval Index**
- When a tool result is sandboxed, context-mode indexes it with BM25 (a ranking function for information retrieval)
- The agent can later query the index by natural language: "find the configuration from the grep result about auth"
- This replaces token-consuming full text with on-demand retrieval

**4. Dynamic Context**
- context-mode provides a `context-mode:read` tool that the agent can call to retrieve indexed content
- The agent only loads what it actually needs, not the entire result
- This is a classic RAG (Retrieval-Augmented Generation) pattern applied to tool output

## Pattern: Intercept → Sandboxed → Indexed → Retrieved-on-Demand

This is a 4-stage pipeline:

1. **Intercept**: MCP server catches tool output
2. **Sandbox**: If too large, write to disk, send preview to LLM
3. **Index**: BM25 index the full content for semantic search
4. **Retrieve**: Agent calls `context-mode:read` with a query to get relevant snippets

## Transferable Patterns for Smart Ralph

### What to Borrow
1. **Tool result interception before LLM call** — This is the core insight. Don't let large tool results consume context tokens.
2. **Preview + reference pattern** — Send first N lines as preview, full content on disk. Agent can read if needed.
3. **On-demand retrieval** — Only load tool results that the agent actually needs to reason about.

### What to Adapt
1. **No MCP server needed** — Smart Ralph runs within Claude Code, not via MCP. The interception should happen in:
   - The coordinator prompt (spec-executor.md): instructions for handling large tool results
   - Shell scripts (stop-watcher.sh): tool output truncation before continuation prompt generation
2. **BM25 indexing is overkill** — Smart Ralph's context is structured (specs, tasks, progress). The agent knows what files contain what. Simple file-based reference is sufficient.
3. **Sandbox directory** — Use `.context-cache/` directory in the spec basePath for sandboxed tool results. Cleaned up on spec completion.

### What to Skip
1. **No BM25 index** — Smart Ralph's agent already has semantic understanding. Simple file references with line count previews are sufficient.
2. **No MCP protocol** — This is an internal Claude Code plugin, not an MCP server. Use shell scripts + prompt instructions instead.
3. **No dynamic context API** — The agent doesn't need a special tool to retrieve indexed content. Claude Code's file reading tools are sufficient.

## Comparison: context-mode vs FilesystemMiddleware

| Aspect | context-mode (MCP) | Deep Agents (FilesystemMiddleware) |
|--------|-------------------|-----------------------------------|
| Architecture | MCP server (external process) | Python middleware (intercepting LLM calls) |
| Interception | Protocol-level (MCP) | Code-level (before API call) |
| Retrieval | BM25 semantic search | File read tool |
| Complexity | High (MCP server, index) | Medium (write to disk) |
| Flexibility | High (any MCP tool) | Medium (configured middleware) |

## Risks
- **BM25 indexing adds infrastructure** — Need to maintain an index, query API, etc.
- **MCP adds latency** — Extra round-trip through MCP protocol for every tool call.
- **Over-engineering for Smart Ralph's use case** — Smart Ralph's tool results are mostly file reads, grep results, git diffs. These are structured and the agent knows what to look for.

## Recommendation

**Use the preview + sandbox pattern WITHOUT BM25 indexing.**

Implementation:
1. **In the coordinator prompt** (stop-watcher.sh continuation): When tool results exceed 200 lines, truncate to first 50 lines + summary line count, write full to `.context-cache/`
2. **In spec-executor.md**: Add a rule "Large tool results (>200 lines): read the first 50 lines for context. If you need more, explicitly read the cached file."
3. **No BM25** — The agent knows what files it needs to read. Simple file references are sufficient.
4. **Automatic cleanup** — `.context-cache/` is cleaned up when the spec completes (in stop-watcher.sh or cancel hook).
