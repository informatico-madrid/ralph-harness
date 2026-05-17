---
spec: context-middleware
phase: research
date: 2026-05-17
type: gap-analysis
status: complete
---

# Research: Gaps After Engine Roadmap (Spec 10)

## Executive Summary

After completing the Engine Roadmap epic (all 9 specs: 3-9 + signal-log + pre-execution + pair-debug + collaboration), this research identifies **genuinely new harness engineering patterns** discovered through deep analysis of Claude Code v2.1+ documentation, Agent SDK, and current agent harness engineering landscape that were NOT covered by any prior spec or research.

**Feasibility**: HIGH | **Risk**: MEDIUM | **Effort**: M-L (depends on spec selection)

## What's Already Covered (NOT in this report)

The following are confirmed already documented in completed specs or prior research:

| Pattern | Documented In |
|---------|---------------|
| Context condensation (proactive) | `01-deep-agents-proactive-condensation.md`, Spec 10 |
| Context condensation (reactive/compaction) | `02-openhands-reactive-condensation.md`, Spec 10 |
| Context-mode MCP server | `03-context-mode-mcp-server.md` (SKIP) |
| Catalog patterns | `04-catalog-and-anthropic-patterns.md` |
| Subagents | Spec 3 (role-boundaries), Spec 6 |
| Collaboration resolution | Spec 7 |
| Pair-debug auto-trigger | Spec 8 |
| Pre-execution critic | Spec 9 |
| Signal log + CI autodetect | Spec 6 |
| Loop safety | Spec 4 |
| Role boundaries | Spec 3 |
| Prompt diet (cancelled) | Spec 2 (CANCELLED) |

## Gaps Not Yet Documented

### GAP-1: Agent Teams — Parallel Coordination Beyond Subagents

**What it is**: Claude Code v2.1.32+ has **Agent Teams** — a fundamentally different parallel coordination model from subagents. Unlike subagents (which only report results back to the main agent), teammates in a team:

- **Share a task list** with 3 states: pending, in progress, completed
- **Communicate directly** with each other via built-in messaging (mailbox system)
- **Self-claim tasks** with file-locking to prevent race conditions
- **Support task dependencies** (blocked tasks unblock automatically)
- **Have plan approval gates** — teammates must propose plans before implementation
- **Include hooks**: `TeammateIdle`, `TaskCreated`, `TaskCompleted`

**Why it matters**: Smart Ralph's current coordination is hierarchical (coordinator → spec-executor). Agent Teams introduce a **networked coordination** model where workers communicate directly and self-organize. This could replace the current coordinator+spec-executor delegation pattern with something closer to the Deep Agents model.

**Key differences from subagents**:
| | Subagents | Agent Teams |
|---|---|---|
| Context | Own context window; results return to caller | Own context window; fully independent |
| Communication | Report to main agent ONLY | Direct messaging between teammates |
| Coordination | Main agent manages all work | Shared task list, self-coordination |
| Best for | Focused tasks | Complex work requiring collaboration |

**Potential RalphHarness integration**:
- Replace coordinator loop with shared task list + self-claiming pattern
- Use teammate messaging for cross-task communication
- Plan approval gates for risky implementations

### GAP-2: Background Monitors — Persistent Event Streaming

**What it is**: Plugins can define **background monitors** via `monitors/monitors.json` that:

- Start automatically when the plugin is enabled
- Execute long-running commands (e.g., `tail -F ./logs/error.log`)
- Deliver each stdout line to Claude as a **notification during the session**
- Work without any hook or event triggering — they're persistent listeners

**Why it matters**: Current Smart Ralph uses event-driven hooks (fire on tool use, fire on stop). Monitors introduce a **push-based event stream** pattern where external processes can continuously notify the agent. This is fundamentally different from the signal log or hook system.

**Potential RalphHarness integration**:
- Monitor CI pipeline logs and surface failures to coordinator
- Monitor test suite progress and trigger condensation when errors appear
- Monitor git status changes during parallel task execution

### GAP-3: Extended Hook System (Agent SDK)

The Agent SDK exposes a **far richer hook system** than Claude Code's shell command hooks. Several hooks have no equivalent in Smart Ralph:

| Hook | Purpose | RalphHarness equivalent |
|------|---------|------------------------|
| `PostToolUseFailure` | Fires on tool execution failure | None — currently no hook for failures |
| `PreCompact` | Fires before conversation compaction | Condensation scripts run manually |
| `UserPromptSubmit` | Fires on user prompt submission | Could inject context before every delegation |
| `SubagentStart` / `SubagentStop` | Track subagent lifecycle | No lifecycle tracking for spec-executor tasks |
| `PermissionRequest` | Intercepts permission dialogs | None |
| `Notification` | Forward agent status to external services | Could send signals to Slack/Teams |
| `PostToolBatch` | Fires after a batch of tool calls (TS only) | None |

**Key hook capabilities**:
- **Permission decisions**: `allow`, `deny`, `ask`, `defer` (4 options, not just allow/deny)
- **Async outputs**: Return `{async: true}` to continue immediately without waiting for hook
- **Multiple parallel hooks**: All matching hooks run in parallel; deny takes priority over defer, which takes priority over ask, which takes priority over allow
- **Input modification**: Hooks can rewrite tool arguments (`updatedInput`) before execution

**Potential RalphHarness integration**:
- `PostToolUseFailure` → automatic retry or escalation on test failures
- `PreCompact` → archive current spec state before compaction
- `UserPromptSubmit` → inject progress context before each delegation
- `PermissionRequest` → programmatic permission policy

### GAP-4: Path-Specific Rules — Dynamic Context Loading

**What it is**: Claude Code v2.1+ supports **path-specific rules** via `.claude/rules/` with YAML frontmatter:

```yaml
---
paths:
  - "src/api/**/*.ts"
---
```

These rules **only load when Claude reads matching files**, not at session start. This is a **conditional context loading** mechanism.

**Why it matters**: Spec 10 research identified "context scoping" as the biggest context reduction opportunity (30-50% reduction). Claude Code natively supports this via path-scoped rules. Smart Ralph's context scoping (selective reference loading) would benefit from studying this pattern.

**Key insight**: Smart Ralph currently loads ALL 5 reference files every iteration. Claude Code proves that loading context only when the relevant files are accessed is a working pattern at scale.

### GAP-5: Context Window Composition Details

From the official context window documentation, several optimization details were missing from Spec 10 research:

| Mechanism | What survives compaction | Impact on Smart Ralph |
|-----------|-------------------------|----------------------|
| Project CLAUDE.md | Re-injected from disk | References survive compaction |
| Rules with `paths:` | **Lost** until matching file read again | Conditional refs need special handling |
| Invoked skills | Re-injected, capped at 5K/skill, 25K total | **Oldest dropped first** |
| Skill descriptions | NOT re-injected after compaction | Only invoked skills preserved |
| Nested CLAUDE.md | Lost until subdirectory file read | Phase-specific refs may be lost |

**Compaction summary behavior**: Replaces conversation with structured summary keeping:
- User requests and intent
- Key technical concepts
- Files examined/modified with important code snippets
- Errors and how they were fixed
- Pending tasks and current work
- **But NOT** exact tool outputs or intermediate reasoning

**Token reduction**: Summary ≈ 12% of pre-compaction tokens (from ~13K → ~1.5K in the example).

### GAP-6: Subagent Context Optimization Patterns

**Built-in subagents skip CLAUDE.md**: The Explore and Plan built-in agents explicitly skip loading CLAUDE.md for a smaller context window. Only custom subagents load CLAUDE.md.

**Subagent memory**: Subagents can maintain their own `MEMORY.md` via the `memory` frontmatter field (`user`, `project`, or `local`). This is cross-session learning at the subagent level.

**Isolation mode**: Subagents can run in temporary git worktrees via `isolation: worktree`, giving them an isolated copy of the repository with automatic cleanup.

**Preloaded skills**: Subagents can preload specific skills at startup via the `skills` field, not just rely on the skill description index.

**Tool restrictions per subagent**: Each subagent can have `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `effort` independently configured.

### GAP-7: Hook JSON Output — additionalContext vs stdout

From the context window visualization:
- **Plain stdout** on exit 0 from hooks → written to debug log only, NOT in context
- **`additionalContext`** in JSON output → enters Claude's context window
- **Exit code 2** on PostToolUse → surfaces stderr as error but cannot block

This means hooks need to output JSON with `additionalContext` to influence agent behavior, not just print to stdout. Smart Ralph's hook system already does this correctly, but it's worth documenting as a design constraint.

### GAP-8: Monitor Tool (Agent SDK)

The Agent SDK includes a **Monitor tool** that watches background scripts and reacts to each output line as an event. This is different from background monitors (which are plugin-level). The Monitor tool is invoked by the agent itself during execution.

**Potential RalphHarness integration**: Agent-based monitoring during spec execution — watch test output, CI logs, or build progress in real-time during task execution.

### GAP-9: Configurable Tool Search (MCP)

Claude Code supports `ENABLE_TOOL_SEARCH=auto` (load schemas upfront when they fit within 10% of context) or `ENABLE_TOOL_SEARCH=false` (load everything). Default is deferred — tool schemas stay out of context until needed.

**Potential RalphHarness integration**: Context-aware reference loading — only load full reference content when it actually fits within the context budget.

## Cross-Cutting Insights

### 1. Hook Types Evolution

Claude Code hooks have evolved from simple shell commands to a full callback system:

| Era | Hook Type | Examples |
|-----|-----------|----------|
| Plugin hooks | Shell commands | PreToolUse, PostToolUse, Stop |
| Agent SDK hooks | Callback functions | +PostToolUseFailure, PreCompact, UserPromptSubmit, Notification, SubagentStart/Stop |
| Agent Teams hooks | Team-specific | +TeammateIdle, TaskCreated, TaskCompleted |

**Smart Ralph position**: Currently at "Plugin hooks" era. Agent SDK hooks offer significant opportunities for automated error recovery and lifecycle management.

### 2. Context Management Layers

Claude Code manages context through 5 layers:

| Layer | Mechanism | Token Cost |
|-------|-----------|------------|
| System prompt | Core instructions, always loaded | ~4,200 |
| Startup | CLAUDE.md, auto memory, MCP names, skills | ~3,500 |
| Conversation | User prompts + Claude responses | Variable |
| Subagent | Separate context, results summarized back | Offloaded |
| Post-compaction | Structured summary (~12% of pre-compaction) | Reduced |

**Smart Ralph position**: Only manages Layer 1-3. Does not leverage subagent context isolation, post-compaction summaries, or configurable tool search.

### 3. Parallel Execution Models

| Model | Communication | Coordination | Smart Ralph Status |
|-------|---------------|--------------|-------------------|
| Sequential (current) | chat.md | Coordinator | ✅ Implemented |
| Subagent delegation | Results back to caller | Main agent | ✅ Implemented |
| Agent Teams | Direct messaging | Shared task list | ❌ Gap 1 |
| Background monitors | Event stream | Persistent listeners | ❌ Gap 2 |

## Recommendations

### High Priority (M-L effort)
1. **Agent Teams integration** — Replace hierarchical coordination with self-organizing task list model. This is the single biggest architectural shift possible.
2. **Extended hooks (SDK)** — Add PostToolUseFailure for automatic retry/escalation, PreCompact for spec state archival.

### Medium Priority (M effort)
3. **Background monitors** — Add CI/test monitoring during spec execution.
4. **Context scoping via path rules** — Study Claude Code's path-specific rules pattern to refine Spec 10's context scoping.

### Low Priority (L effort, speculative)
5. **Subagent context patterns** — Use Explore-like subagents for reference-heavy research phases.
6. **Configurable tool search** — Context-aware reference loading based on remaining budget.

## Sources

- [Claude Code Plugins documentation](https://code.claude.com/docs/en/plugins) — Monitors, plugin structure
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — Full hook system with all event types
- [Claude Code Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview) — PostToolUseFailure, PreCompact, UserPromptSubmit hooks
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents) — Model selection, tool restrictions, memory, isolation
- [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) — Shared task lists, direct messaging, plan approval
- [Claude Code Context Window](https://code.claude.com/docs/en/context-window) — Token costs, compaction, what survives
- [Claude Code Memory](https://code.claude.com/docs/en/memory) — CLAUDE.md hierarchy, path-specific rules, auto memory
- [awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering) — 50+ project catalog
