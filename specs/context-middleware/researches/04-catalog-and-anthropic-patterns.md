---
spec: context-middleware
sub-research: 04
date: 2026-05-17
source: OpenAI Codex (openai/codex, 83k stars) + awesome-harness-engineering catalog + Anthropic docs
---

# Sub-Research: OpenAI Codex + Awesome-Harness Catalog Context Patterns

## Source

- [openai/codex](https://github.com/openai/codex) — OpenAI's own coding agent (83k stars, 12k forks, actively maintained)
- [awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) (902 stars) — curated catalog of harness engineering patterns
- `docs/harness-engineering/09-reference-implementations.md` — 16 reference projects
- `docs/harness-engineering/08-practical-implementation-guide.md` — sections on AGENTS.md, templates
- Anthropic docs: [Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Harness Design for Long-Running Agents](https://www.anthropic.com/engineering/harness-design-long-running-apps)

## 1. OpenAI Codex Approach

**Codex** is OpenAI's own terminal-based coding agent. From the GitHub repo structure:

```
codex/
├── .codex/          # Configuration directory
├── codex-cli/       # CLI frontend
├── codex-rs/        # Rust core (performance)
├── sdk/             # SDK for programmatic access
├── patches/         # Build patches (V8 sandboxing)
└── scripts/         # CI and tooling
```

### Context Management in Codex

Codex's approach to context is implicit rather than explicit:

1. **Structured configuration via `.codex/`**: Codex uses a `.codex/` directory for configuration that defines what context the agent should consider. This is a form of **context scoping** — only load relevant context, not everything.

2. **CLI-driven input filtering**: The CLI frontend (`codex-cli/`) filters and formats what gets passed to the LLM. This is a form of **pre-processing** — the agent never sees raw, unfiltered output.

3. **Rust core for performance**: The `codex-rs` rewrite is about execution speed, not context management. However, the performance benefit means less time waiting for LLM responses, which indirectly helps with long-running tasks.

4. **No explicit condensation**: Codex does NOT appear to implement proactive or reactive condensation. It relies on the model's built-in context handling and structured prompts.

**Relevance to Smart Ralph**: Codex is the most relevant reference because it's OpenAI's own agent using Claude (Anthropic models). However, Codex runs as a standalone CLI, not as a Claude Code plugin. Its context management is simpler because it has full control over the LLM API call, while Smart Ralph must work within Claude Code's tool call framework.

## 2. Awesome-Harness Catalog Patterns

The awesome-harness-engineering catalog (902 stars) lists 50+ projects organized by category. For context management specifically:

### Context Engineering Tools (from catalog)

| Tool | Type | Context Pattern | Relevance |
|------|------|----------------|-----------|
| **OpenHands** | Agent framework | Event log + condensation | HIGH — reactive condensation |
| **OpenDevin** | OpenHands fork | Same as OpenHands | HIGH — same as above |
| **context-mode** | MCP server | Tool output interception + BM25 | MEDIUM — preview pattern |
| **Semantic Context** | Library | RAG on codebase context | LOW — overkill for spec-driven dev |
| **Memory Bank** | Library | Persistent memory across sessions | LOW — different problem space |

### Filesystem-Based Context (from 09-reference-implementations.md)

**Microsoft Azure SRE** (referenced in 09-reference-implementations.md):
- Uses filesystem-based context management
- Context files organized by severity and recency
- Automatic pruning of old context
- Pattern: `context/{category}/{severity}/{timestamp}.md`

**Stripe Minions** (referenced in 09-reference-implementations.md):
- Multi-agent coordination
- Tool result filtering before LLM input
- Pattern: Only send tool results that are semantically relevant to the current task

### Template-Based Context (from 08-practical-implementation-guide.md)

**AGENTS.md template** (from awesome-harness-engineering):
- Defines what context the agent should consider
- Structured format: goals, constraints, file paths, commands
- Pattern: Pre-load only relevant context, not everything

**IMPLEMENT.md template**:
- Step-by-step execution plan
- Reduces context bloat by providing clear structure
- Pattern: Replace free-form conversation with structured plan

## 3. Anthropic's Own Guidance

### Effective Context Engineering (Anthropic)

Key principles:
1. **Be specific about what context matters** — don't dump everything
2. **Use system prompts for stable context** — model capabilities, rules, constraints
3. **Use conversation for dynamic context** — current task state, progress
4. **Files for large context** — if context > model's comfortable range, put it in files

### Harness Design for Long-Running Agents (Anthropic)

Key patterns:
1. **Checkpoints** — save state to files at regular intervals
2. **Rollback** — ability to restore previous state
3. **Task decomposition** — break long tasks into smaller, verifiable steps
4. **Memory management** — periodic summarization of conversation history

### Effective Harnesses for Long-Running Agents (Anthropic)

Key insight: **The harness (prompt + tools + constraints) is more important than the model.**
- Good harness design can make a smaller model outperform a larger one
- Context management is the #1 factor in long-running agent quality
- Tool design (what gets returned to the agent) is the #2 factor

## Transferable Patterns for Smart Ralph

### What to Borrow
1. **Filesystem as context boundary** — Anthropic's principle: "if context > model's comfortable range, put it in files"
2. **Structured execution templates** — Smart Ralph's spec-driven format is already a form of structured execution. Reinforce this with clear file references.
3. **Checkpoints and rollback** — Smart Ralph already has this via Spec 4 (loop-safety-infra, git checkpoints). Connect context condensation to the same checkpoint system.
4. **Context scoping** — Only load what's relevant to the current task. Don't load all reference files for every LLM call.

### What to Adapt
1. **No separate context files per category** — Smart Ralph's spec format already organizes context well (research.md, requirements.md, design.md, tasks.md).
2. **No RAG on codebase** — The spec format provides structured context. Semantic search is overkill.
3. **No multi-agent coordination** — Smart Ralph uses a coordinator pattern with fresh context per task. Context doesn't need to cross agent boundaries.

### What to Skip
1. **No Semantic Context / Memory Bank** — These solve different problems (codebase search, cross-session memory).
2. **No Microsoft Azure SRE context files** — Too structured for Smart Ralph's use case.
3. **No Stripe Minions tool filtering** — Smart Ralph's coordinator already controls tool usage.

## Recommendation

**Combine two patterns:**
1. **Anthropic's filesystem boundary**: When combined chat.md + .progress.md exceeds 2,000 lines, write a condensed version to disk (`.condensed.md`) and keep only a summary in the conversation.
2. **Anthropic's checkpoint pattern**: Link context condensation to the existing git checkpoint system (from Spec 4). Each condensation event creates a checkpoint entry in `.progress.md`.

This keeps the design simple (file operations + shell script) while following proven patterns from the domain leaders.
