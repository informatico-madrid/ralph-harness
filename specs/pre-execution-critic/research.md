---
spec: pre-execution-critic
phase: research
date: 2026-05-16
status: complete
---

# Research: Pre-Execution Critic

## Executive Summary

This spec adds mechanical pre-execution evaluation of agent actions to RalphHarness, converting Spec 3's role-boundary rules from "prompt text" to "enforced by code." The pattern comes directly from OpenHands SDK's CriticMixin + SecurityRisk + Confirmation Policy system, which provides a battle-tested model for blocking dangerous operations before they execute.

**Feasibility**: HIGH | **Risk**: LOW | **Effort**: S-M

## Research Questions Answered

### 1. What is the CriticMixin pattern?

In OpenHands SDK, the security system is a multi-layer evaluation pipeline that runs **before** each tool call executes:

```
ActionEvent -> SecurityAnalyzer -> SecurityRisk -> ConfirmationPolicy -> Allow/Block
```

Source: [docs.openhands.dev/sdk/arch/security.md](https://docs.openhands.dev/sdk/arch/security.md)

**Key components**:
- `SecurityAnalyzerBase` — abstract interface defining `security_risk()` contract
- `LLMSecurityAnalyzer` — inline risk assessment (zero overhead, no extra LLM calls)
- `PatternSecurityAnalyzer` — regex on shell patterns (known threats: rm -rf, eval, curl|sh)
- `PolicyRailSecurityAnalyzer` — deterministic rules (composed threats like `pip | exec`)
- `EnsembleSecurityAnalyzer` — takes worst-case across all child analyzers
- `NoOpSecurityAnalyzer` — passthrough for development/trusted environments

### 2. What are the SecurityRisk levels?

Four levels defined in `SecurityRisk` enum:

| Level | Characteristics | Examples |
|-------|----------------|----------|
| **LOW** | Read-only, no state changes | File reading, directory listing, search |
| **MEDIUM** | Modifies user data | File editing, creating files, API calls |
| **HIGH** | Dangerous operations | File deletion, system commands, privilege escalation |
| **UNKNOWN** | Not analyzed or indeterminate | Complex commands, ambiguous operations |

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

### 3. How does Confirmation Policy work?

Three policy implementations map risk levels to confirmation requirements:

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `AlwaysConfirm()` | Requires confirmation for ALL actions | Maximum safety, interactive workflows |
| `NeverConfirm()` | Never requires confirmation | Fully autonomous agents, trusted environments |
| `ConfirmRisky()` | Configurable risk-based policy (default threshold=HIGH) | Balanced approach, production use |

`ConfirmRisky` configuration:
- `threshold`: Risk level at/above which confirmation is required (default: HIGH)
- `confirm_unknown`: Whether UNKNOWN risk requires confirmation (default: True)

Default confirmation rules with `ConfirmRisky(threshold=HIGH)`:
- LOW: Allow
- MEDIUM: Allow
- HIGH: Require confirmation
- UNKNOWN: Require confirmation

**Confirm, don't block**: The analyzers return a risk level. The confirmation policy decides what happens. The analyzer does not prevent execution — it classifies risk for the policy layer to act on.

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

### 4. What is the Hooks system?

OpenHands SDK hooks run at key lifecycle events and use **exit codes** to signal decisions:

| Hook | When it runs | Can block? |
|------|-------------|------------|
| **PreToolUse** | Before tool execution | Yes (exit 2) |
| PostToolUse | After tool execution | No |
| UserPromptSubmit | Before processing user message | Yes (exit 2) |
| Stop | When agent tries to finish | Yes (exit 2) |
| SessionStart | When conversation starts | No |
| SessionEnd | When conversation ends | No |

**Exit codes**:
- `0` — success. Operation proceeds. stdout parsed as JSON for structured output.
- `2` — block. Operation denied. For PreToolUse this rejects the action. stderr/reason surfaced as feedback.
- Other non-zero — non-blocking error. success=False, error logged, operation still proceeds.

**CRITICAL**: Only exit code 2 blocks. Exit code 1 (conventional Unix failure) is treated as non-blocking error. A hook intended to enforce a policy MUST exit with code 2.

Source: [docs.openhands.dev/sdk/guides/hooks.md](https://docs.openhands.dev/sdk/guides/hooks.md)

### 5. What is the Critic (Experimental)?

A separate but related feature: an LLM-based evaluator that analyzes agent actions and conversation history to predict quality/success probability (0.0-1.0 score). Provides:
- Quality scores during agent execution (not just at completion)
- Iterative refinement: automatic retry with follow-up prompts when scores below threshold
- Custom follow-up prompts via subclassing `CriticBase`

This is a **different pattern** from the security analyzer — the Critic evaluates post-execution quality, while the security analyzer evaluates pre-execution risk. For Spec 9, the **security analyzer + hooks** pattern is the relevant one, not the experimental Critic.

Source: [docs.openhands.dev/sdk/guides/critic.md](https://docs.openhands.dev/sdk/guides/critic.md)

### 6. What is Defense-in-Depth?

OpenHands SDK provides composable analyzers:

| Analyzer | What it catches | How it works |
|----------|----------------|--------------|
| `PatternSecurityAnalyzer` | Known threat signatures (rm -rf, eval, curl|sh) | Regex on two corpora: shell patterns scan executable fields only; injection patterns scan all fields |
| `PolicyRailSecurityAnalyzer` | Composed threats (fetch piped to exec, raw disk writes, catastrophic deletes) | Deterministic rules evaluated per-segment |
| `EnsembleSecurityAnalyzer` | Combines others, takes highest concrete risk | Takes worst-case across all child analyzers |

Key design principles:
- **Two corpora, not one**: Shell patterns only see what will actually execute; injection patterns target instruction-following
- **Max-severity, not averaging**: Highest concrete risk wins (simpler and more auditable)
- **UNKNOWN means "I don't know," not "safe"**: Default triggers confirmation

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

### 7. What are the known limitations?

| Limitation | Why | What would fix it |
|------------|-----|-------------------|
| No hard-deny at analyzer boundary | SDK analyzers return SecurityRisk, not block/allow | Hook-based enforcement |
| `execute_tool()` bypasses checks | Direct tool execution skips conversation loop | Hooks |
| No Cyrillic/homoglyph detection | NFKC maps compatibility forms, not cross-script confusables | Unicode TR39 confusable tables |
| Content past 30k chars invisible | Hard cap prevents regex DoS | Raise cap (increases ReDoS exposure) |
| `thinking_blocks` not scanned | Scanning model reasoning risks false positives | Separate injection-only CoT scan |

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

**Relevance to Spec 9**: The "No hard-deny at analyzer boundary" limitation confirms that **hooks** are the right mechanism for mechanical enforcement — the analyzer classifies risk, the hook enforces the decision.

### 8. What is the Custom Security Analyzer pattern?

Custom analyzers inherit from `SecurityAnalyzerBase` and implement `security_risk(action: ActionEvent) -> SecurityRisk`:

```python
class CustomSecurityAnalyzer(SecurityAnalyzerBase):
    def security_risk(self, action: ActionEvent) -> SecurityRisk:
        action_str = str(action.action.model_dump()).lower()
        if any(p in action_str for p in ['rm -rf', 'sudo', 'chmod 777']):
            return SecurityRisk.HIGH
        if any(p in action_str for p in ['curl', 'wget', 'git clone']):
            return SecurityRisk.MEDIUM
        return SecurityRisk.LOW
```

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

### 9. How does Configurable Security Policy work?

Agents accept a custom security policy template (Jinja2 .j2 file) that gets rendered into the agent's system prompt. This guides the LLM's risk assessment of its own actions. The default policy template defines LOW/MEDIUM/HIGH guidelines.

Source: [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md)

## Mapping to RalphHarness

### What exists today (Spec 3)
- Role contracts in `references/role-contracts.md` (access matrix)
- "DO NOT edit" lists in agent files (prompt rules)
- State integrity hook (detects unauthorized edits **after** they happen)

### What's missing (Spec 9)
- **No pre-execution evaluation** — actions only checked after execution
- **No security risk levels** — all writes treated equally
- **No confirmation policy** — no mechanism to pause before risky operations
- **No PreToolUse hook** — nothing blocks tool calls before they happen

### What we borrow from OpenHands SDK

| OpenHands SDK | RalphHarness equivalent |
|--------------|------------------------|
| `SecurityAnalyzerBase` + `SecurityRisk` enum | `references/security-risk-levels.md` — define risk levels for Ralph's tool calls |
| `LLMSecurityAnalyzer` (inline, zero overhead) | Deterministic rules in shell script (no extra LLM call) |
| `ConfirmationPolicy` (AlwaysConfirm/NeverConfirm/ConfirmRisky) | Confirmation gate in coordinator prompt |
| Hooks (PreToolUse with exit code 2) | `hooks/scripts/pre-execution-check.sh` — runs BEFORE delegation, exits 2 to block |
| Role contract enforcement | Integrate `references/role-contracts.md` into the check script |
| Defense-in-depth ensemble | Pattern-based checks (deterministic) + policy rules |

## Design Recommendations

1. **Pre-execution check is a shell script** (not Python). The coordinator runs it before delegating tasks. Input: tool name, target file/path, agent role. Output: risk level + allow/block decision + exit code 2 for block.

2. **Two layers of checks**:
   - **Layer 1 (Pattern)**: Deterministic rules from role-contracts.md — if agent role forbids writing to a file, block immediately.
   - **Layer 2 (Risk)**: Classify action risk level. HIGH/CRITICAL requires explicit coordinator approval (pause delegation, log to .progress.md).

3. **No LLM-based evaluation**. Spec 9's goal is mechanical enforcement, not LLM judgment. Keep it deterministic and fast.

4. **Exit code contract**: The pre-execution check script must exit 0 for allow, 2 for block (matching OpenHands SDK's hook contract).

5. **Confirmation is in the coordinator prompt**, not a new hook type. When the check returns HIGH/CRITICAL, the coordinator pauses delegation and waits for human approval (same pattern as OpenHands's ConfirmRisky).

6. **Ignore the experimental Critic**. The Critic is about post-execution quality evaluation (iterative refinement). Spec 9 is about pre-execution risk blocking. They're complementary but orthogonal.

## Related Patterns in RalphHarness

- **Spec 3 (role-contracts)**: Adds role files and file-access constraints. Spec 9 makes those constraints mechanically enforced.
- **Spec 4 (signal-log-and-ci-autodetect)**: signals.jsonl pattern — could be extended to include security decision logs.
- **Existing state integrity hook**: Currently runs AFTER execution. Pre-execution check runs BEFORE. Together they form defense-in-depth.

## Sources

- [docs.openhands.dev/sdk/guides/critic.md](https://docs.openhands.dev/sdk/guides/critic.md) — Critic (Experimental) documentation
- [docs.openhands.dev/sdk/guides/security.md](https://docs.openhands.dev/sdk/guides/security.md) — Security & Action Confirmation documentation
- [docs.openhands.dev/sdk/arch/security.md](https://docs.openhands.dev/sdk/arch/security.md) — Security architecture documentation
- [docs.openhands.dev/sdk/guides/hooks.md](https://docs.openhands.dev/sdk/guides/hooks.md) — Hooks system documentation
- [docs.openhands.dev/sdk/guides/iterative-refinement.md](https://docs.openhands.dev/sdk/guides/iterative-refinement.md) — Iterative refinement patterns
- [docs.openhands.dev/llms.txt](https://docs.openhands.dev/llms.txt) — Complete documentation index
- `docs/harness-engineering/11-openhands-deep-dive.md` — Local OpenHands deep dive (sections 7-8)
- `docs/harness-engineering/10-deep-agents-deep-dive.md` — Deep Agents middleware patterns
- `plugins/ralphharness/references/role-contracts.md` — Current role contracts (Spec 3)
- `docs/ENGINE_ROADMAP.md` — Spec 9 definition and design decisions
