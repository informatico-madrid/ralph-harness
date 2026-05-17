---
spec: context-middleware
sub-research: 02
date: 2026-05-17
source: OpenHands SDK (code source) + harness-engineering docs 09, 11
---

# Sub-Research: OpenHands SDK Reactive Condensation Pattern

## Source

- OpenHands SDK: [docs.openhands.dev](https://docs.openhands.dev/) (referenced in docs/harness-engineering)
- `docs/harness-engineering/11-openhands-deep-dive.md` (654 lines)
- `docs/harness-engineering/09-reference-implementations.md` (270 lines)
- `specs/pre-execution-critic/research.md` (218 lines — includes OpenHands condenser analysis)

## Problem Solved

OpenHands is an autonomous AI software engineer that runs for hours, generating thousands of tool calls. The conversation context grows unbounded until:
1. The LLM hits a context window error (overflow)
2. The LLM's performance degrades with very long contexts
3. API costs become excessive from sending huge histories

## Architecture: Event Log + Reactive Condensation

```
Tool Call → Record to Event Log → (Overflow?) → CondensationRequest → Replace History
```

### How It Works

**Event Log (Immutable Record)**:
- Every tool call, result, and conversation turn is recorded to an immutable event log
- The event log is the single source of truth — never modified, never deleted
- Format: JSONL (one JSON object per line), append-only
- Includes: action type, target, result, metadata, timestamps

**Reactive Condensation (On Overflow)**:
1. When a `context_length_exceeded` error is received from the LLM API
2. The system intercepts the error and triggers a condensation routine
3. The condenser receives the event log + conversation history
4. It creates a `CondensationRequest` — a structured prompt asking the LLM to:
   - Summarize what happened so far
   - List files modified
   - Note current progress and next steps
   - Preserve ALL decisions and conclusions
5. The condensed summary replaces the old conversation
6. The event log is preserved for reference (can be queried later)

**Key difference from proactive**: OpenHands does NOT condense proactively. It waits for the overflow error, then recovers. This means:
- Pro: No risk of over-aggressive condensation losing detail
- Con: The overflow error itself causes a failed API call (wasted tokens)
- Con: The agent stops mid-task, which can cause state inconsistency

### CondensationRequest Structure

```json
{
  "type": "condensation_request",
  "request": "Summarize this conversation. Focus on: what was accomplished, files modified, current state, next steps.",
  "preserve": ["file_paths", "decisions", "error_messages", "current_task"],
  "max_length": 4096
}
```

### Event Log as Reference

After condensation:
- The condensed summary goes into the conversation (what the LLM sees)
- The full event log stays on disk as `.openhands-state/events.jsonl`
- If the LLM needs details from before condensation, it can re-read the event log

## Comparison: Proactive vs Reactive

| Aspect | Deep Agents (Proactive) | OpenHands (Reactive) |
|--------|------------------------|---------------------|
| When | Before overflow (85% threshold) | After overflow (error) |
| Cost | Small overhead per condensation | Failed API call + wasted tokens |
| Safety | Never loses detail (archives full) | Risk of losing in-flight state |
| Complexity | Requires monitoring token count | Simpler (just catch error) |
| Reliability | Higher — no failed calls | Lower — relies on error recovery |

## Transferable Patterns for Smart Ralph

### What to Borrow
1. **Event log as immutable record** — Smart Ralph's signals.jsonl pattern is already similar. Could extend to log all context operations.
2. **Reactive condensation as safety net** — Even with proactive condensation, having a reactive handler for edge cases is prudent.
3. **Condensation preserves file paths and decisions** — Key for spec-driven development where decisions matter more than conversation fluff.

### What to Adapt
1. **Combine proactive + reactive** — Smart Ralph should use BOTH: proactive at 85% threshold (from Deep Agents) AND reactive as fallback (from OpenHands).
2. **Integration with stop-watcher.sh** — The reactive handler should be inline in the continuation prompt generation: if the LLM returns an error, check if it's a context error and trigger condensation.
3. **No event log needed** — Smart Ralph already has `.progress.md` as a structured record. Extending it to be append-only with timestamps is sufficient.

### What to Skip
1. **No CondensationRequest JSON structure** — Smart Ralph is shell-based, not Python-based. Use shell script + markdown instead.
2. **No full event log** — The `.progress.md` + `.ralph-state.json` already serve as the state record.

## Risks
- **Reactive condensation loses in-flight state**: The LLM error means the current task is interrupted. The agent needs to recover task state.
- **Failed API call cost**: The overflow error wastes tokens on the failed call plus the condensation call.
- **Mitigation**: Proactive condensation prevents most overflows. Reactive is only for edge cases.

## Recommendation

**Use reactive condensation ONLY as a fallback** — not as the primary strategy.

The primary strategy should be proactive condensation (from Deep Agents pattern). Reactive condensation should be:
- An inline handler in stop-watcher.sh that detects LLM context errors
- A last resort, not expected to trigger in normal operation
- The condensation instruction should focus on recovering task state (which task, what was the last action, what's the next step)
