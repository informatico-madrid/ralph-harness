---
spec: pair-debug-auto-trigger
phase: research
created: 2026-05-16T07:00:00Z
---

# Research: pair-debug-auto-trigger

## Executive Summary

Spec 8 ("crown jewel" of engine-roadmap-epic) makes the executor↔reviewer debugging collaboration — which today only works when a human pushes it — fire **automatically**. Spec 6 (collaboration-resolution) already shipped 90% of the *machinery* (HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL signals, the experiment-propose-validate loop, BUG_DISCOVERY fix-task trigger, baseline check). The **delta** Spec 8 adds is purely: (1) a named "pair-debug mode", (2) a mechanical auto-trigger condition, (3) Driver/Navigator role labels, (4) debug logging as a sanctioned executor technique, (5) a coordinator chat.md announcement. No new infrastructure, no new agents. The roadmap is broadly accurate but **stale on two points**: `coordinator-core.md` does NOT exist (Spec 2 was cancelled) and `TASK_START_SHA` already exists.

A deeper technical research pass (see `research-technical.md`) confirmed the design and surfaced three actionable reinforcements now folded into the recommendations below: (a) the Driver/Navigator split has a measured reference implementation — `PairCoder`, 12–162% pass@1 gain — so naming the roles is evidence-based, not cosmetic; (b) `DoVer`'s finding that *log-only hypothesis attribution is ill-posed* sharpens *why* the EXPERIMENT step must stay mandatory (a hypothesis is confirmed by running a test, not by reasoning); (c) known LLM root-cause failure modes (anchoring on the first failed fix, stalled loops) justify a short **anti-anchoring rule** in `pair-debug.md` (≥2 independent hypotheses before committing, evidence-before-ROOT_CAUSE) — the single highest-value new addition. None of this changes the scope or the file count.

## Problem Statement & Real-Evidence Context

In a live spec execution, spec-executor + external-reviewer found a critical bug (duplicate `TripManager` instances → race conditions). The collaboration was textbook — executor instrumented with debug logging, reviewer navigated the diff and named the suspect function, they exchanged hypotheses and converged on root cause. **But it only happened because a human told both agents to "plantear hipótesis y escuchar hipótesis del otro"**, temporarily overriding their rigid roles.

The gap: agents have the *protocol* to collaborate (Spec 6) but no *trigger* to enter the collaborative posture. Today, when a first fix fails, escalation goes to retry or to human — never to "switch to pair mode". The magic is real; it needs a trigger, not a human.

## External Research (Prior Art)

### From harness-engineering docs

| Source | Relevant pattern |
|--------|------------------|
| `11-openhands-deep-dive.md` (§7, §11.2) | OpenHands `CriticMixin` evaluates actions *before* execution; RalphHarness reviews *after*. The doc explicitly notes both are complementary. Relevant to Spec 9, not 8 — but confirms RalphHarness's review-after model, which is why pair mode must be an *escalation* layered on top, not a replacement. |
| `10-deep-agents-deep-dive.md` (§3) | Middleware `wrap_tool_call` hooks intercept actions. Not directly applicable — RalphHarness has no middleware layer; pair-debug must live in prompt/reference text + the stop-watcher hook. |
| `08-practical-implementation-guide.md` (§Multi-Agent) | Anthropic "Building Effective Agents" — multi-agent coordination protocols, layered guardrails. Supports the design: keep roles, add a coordination protocol on top. |

### From web search (May 2026)

- **Driver/Navigator + role-specialized debugging is established practice.** `AgentFL` decomposes fault localization into Comprehension / Navigation / Confirmation agents — directly mirrors the Navigator (reviewer) role. (arxiv 2503.07693 SEIDR; ACM 3719351)
- **`PairCoder` is the reference Driver/Navigator implementation, with measured gains.** Navigator proposes multiple solution plans; Driver generates code and runs tests; Navigator selects the next iteration from test feedback. Interleaved, this achieves a **12–162% relative pass@1 improvement** over single-agent baselines. The measured benefit comes from the *structured feedback loop*, not merely from having two agents — Navigator must *see* Driver's execution results and refine. This is the strongest empirical case for naming the roles and making the loop explicit, and it directly informs the pair-debug.md role table. (arxiv 2404.04834)
- **Hypothesis-driven debugging is the dominant autonomous pattern.** `AutoSD` generates a bug hypothesis then uses a debugger to verify it; root-cause agents build a *ranked hypothesis list* and correlate symptoms across logs/traces. This validates Spec 6's HYPOTHESIS→EXPERIMENT→FINDING loop and Spec 8's "Driver instruments / Navigator hypothesizes" split. (saulius.io; computer.org)
- **Log-only hypothesis attribution is ill-posed — interventions are required.** `DoVer` (Microsoft Research, Dec 2024) finds that multiple *distinct* interventions can independently fix the same failure, so reasoning from logs alone cannot identify "the" root cause; you must *run an experiment*. DoVer recovers **18–28% of failed multi-agent trials** by injecting targeted interventions mid-run and comparing the progress metric. This is a sharper justification for pair-debug than "two agents are better": the value is the **experiment** the Driver runs against the Navigator's hypothesis, not the hypothesis itself. It validates keeping the EXPERIMENT step mandatory in the loop (Spec 6) rather than letting agents converge on theory alone. (arxiv 2512.06749)
- **LLM root-cause analysis has known, nameable failure modes.** 2025 RCA research documents three recurring pitfalls: **anchoring bias** (the first hypothesis primes all subsequent analysis), **arbitrary evidence selection** (high-confidence tokens overweighted), and **stalled reasoning** (loops with no progress). Documented mitigations: force **early hypothesis diversification** (generate ≥2–3 independent hypotheses before evaluating any), apply **self-consistency** (re-run a hypothesis check and majority-vote), and require **evidence sufficiency** (≥N independent data points before accepting). These are concrete, low-cost rules that `pair-debug.md` should encode so the Navigator does not anchor on the executor's first failed fix. (See requirements recommendation 1b.)
- **Loop detection must be enforced OUTSIDE the model.** "When an agent calls the same tool with nearly the same inputs 2–3 times, the system should stop or switch strategy" — escalation/strategy-switch must be a mechanical rule, not LLM judgment. This is the single strongest argument for the auto-trigger: don't rely on agents noticing they're stuck; count iterations mechanically. (Modexa "The Agent Loop Problem")
- **Every agent loop needs a designed exit: success / fallback / ask / escalate.** Pair-debug is precisely the "fallback / switch-strategy" exit that RalphHarness currently lacks between "retry" and "ask human". (Oracle "AI Agent Loop")

### Cross-check: local harness-engineering docs describe NO explicit pair-mode

A deep pass over `docs/harness-engineering/` (11 docs, curated 2026-05-13) confirms the local literature has **no "Driver/Navigator pair mode" with automatic escalation**. The closest documented patterns are Orchestrator→Workers (sequential delegation), the OpenHands Critic (flags risk, does not switch modes), and Deep Agents middleware (intercepts tool calls, does not handle role transitions). **Implication**: Spec 8's specific mechanism — combining iteration count + test regression + reviewer signal into one mechanical escalation rule — is novel relative to the local corpus. It is well-grounded in external research (PairCoder, DoVer, AutoGen, Magentic-One) but RalphHarness is encoding it explicitly for the first time. This raises the bar on getting the prompt text *operationally distinct* (see Risks: "no behavior change"), since there is no prior in-repo pattern to lean on. Dating note: where the local corpus disagrees, the 2026 production docs (08–11: OpenHands, Deep Agents, practical guide) supersede the 2024 foundational docs (01–02); none of them contradict Spec 8.

## Codebase Analysis — Current-State Verification

Verified against real files in `plugins/ralphharness/` (plugin version **5.2.0**, `.claude-plugin/plugin.json`).

### references/ directory — actual contents

`pair-debug.md` does **NOT** exist (confirmed — must be created). 22 files present. **`coordinator-core.md` does NOT exist** — the roadmap's "(or `coordinator-core.md` after Spec 2)" is stale; Spec 2 was cancelled (ENGINE_ROADMAP §8 criteria 6 & 7 both marked "❌ Spec 2 cancelled"). The file is and remains **`coordinator-pattern.md`** (46 KB).

### collaboration-resolution.md (Spec 6, NEW — 58 lines)

Provides, fully shipped:
- **Cross-branch regression investigation** workflow (4 steps, git-diff-driven) — covers ANY regression, not just E2E.
- **Experiment-propose-validate** workflow with a 5-signal loop: `HYPOTHESIS → EXPERIMENT → FINDING → ROOT_CAUSE → FIX_PROPOSAL`, including emitter conventions ("reviewer hypothesizes, executor experiments") and a loop bound (escalate after >3 cycles).
- Ambiguous-baseline cross-reference to the reviewer baseline check.

This is essentially the pair-debug *protocol body* — already written. What it lacks: a **name** ("pair-debug mode"), a **trigger** (it says "Entry condition: a failing task whose cause is ambiguous" — descriptive, not mechanical), and **Driver/Navigator labels**.

### failure-recovery.md (594 lines, modified by Spec 6)

- **Max Retries** (non-recovery, lines 71–84): increments `taskIteration`; stops when `taskIteration > maxTaskIterations`.
- **Recovery Mode** (lines 86–147): generates fix tasks `X.Y.N [FIX X.Y]`, inserts after original, tracks `fixTaskMap`.
- **`BUG_DISCOVERY` Fix-Task Trigger** (lines 546–594, Spec 6): a `task_review.md` row with `status: BUG_DISCOVERY` triggers the same fix-task machinery; `fix_type: bug_discovery`; dedup rule; reuses limits/depth checks verbatim.
- **No mention of "pair-debug", "pair mode", or pre-existing-test distinction.** The fix-task path treats all failures identically. Spec 8's change #4 ("first fix failed → escalate to pair") must be added here as a new branch before fix-task generation.
- ⚠️ `taskIteration` semantics: it starts at 1 (`.ralph-state.json` confirms `"taskIteration": 1`), incremented on each failed retry. "taskIteration >= 2" therefore means "at least one fix attempt has failed" — consistent with roadmap change #1(b) and plan.md AC#2. Confirmed feasible.

### coordinator-pattern.md (46 KB)

- **Signal Protocol** (§lines 163–199): control signals (HOLD/PENDING/URGENT/DEADLOCK/INTENT-FAIL/SPEC-ADJUSTMENT/SPEC-DEFICIENCY) → `signals.jsonl` via `lib-signals.sh`. Collaboration markers → `chat.md`.
- **Chat Protocol** (§lines 203–289): coordinator MUST read chat.md + write announcements before every delegation. Has atomic-append blocks for ACK / task-announce / completion-notice — the **PAIR-DEBUG announcement reuses this exact append pattern**.
- **`TASK_START_SHA` ALREADY EXISTS** (line 345): *"Before delegating any task, record `TASK_START_SHA=$(git rev-parse HEAD)`"* — currently used by Layer 4 artifact review. The roadmap's trigger condition (a) `git diff $TASK_START_SHA..HEAD -- tests/` is **directly feasible with the existing variable** — no new SHA tracking needed. This is the single most important verification result.
- No `ciSnapshot` reference in coordinator-pattern.md (CLAUDE.md mentions ciSnapshot, but it lives in `commands/implement.md`, `schemas/spec.schema.json`, `hooks/scripts/write-metric.sh`).
- No "pair", "driver", "navigator" anywhere in coordinator-pattern.md (confirmed via grep).

### agents/spec-executor.md (v-prefix, ~400 lines)

- `<explore>` block (lines 270–278): Explore subagent preferred over Glob/Grep.
- `<exit_code_gate>` (lines 212–227) + `<stuck>` (lines 229–240): on non-0 exit, attributes failure, runs cross-branch check, references `collaboration-resolution.md` workflow A. `<stuck>` already says "3+ fails with DIFFERENT errors → STOP, false-fix loop".
- **No "debug logging" / `_LOGGER` / `console.log` as a sanctioned technique anywhere.** Investigation techniques today = `rg`/`grep`, Explore subagent, `.progress.md` learnings, framework docs (WebFetch). Roadmap change #3 must add a debug-logging block.
- `<role>` and `## DO NOT Edit — Role Boundaries` (line 377) define hard boundaries; the Driver role must be additive and not loosen these.

### agents/external-reviewer.md (~790 lines)

- **Tools FORBIDDEN** (line 52–53): *"Never modify: implementation files, .ralph-state.json"*; restated line 753, 780. The Navigator role must **preserve** this — reviewer still cannot write code.
- **Section 3a — Baseline Check Before Modifying a Test** (lines 202–214): the 3-condition `git diff main...HEAD` check from Spec 6.
- No "pair", "navigator" reference.

### templates/chat.md

- Signal Legend already lists all six collaboration markers `HYPOTHESIS / EXPERIMENT / FINDING / ROOT_CAUSE / FIX_PROPOSAL / BUG_DISCOVERY` (lines 31–36, added by Spec 6). **No new signal is needed for pair-debug** — the announcement is a coordinator message, not a new signal type. Optionally add a one-line note that a `### PAIR-DEBUG MODE ACTIVATED` header may appear.

### Roadmap discrepancies (flag)

| Roadmap claim | Reality |
|---------------|---------|
| `coordinator-pattern.md` "(or `coordinator-core.md` after Spec 2)" | `coordinator-core.md` does NOT exist. Spec 2 cancelled. Use `coordinator-pattern.md`. |
| Implies `TASK_START_SHA` may need to be introduced | Already exists (coordinator-pattern.md:345). Trigger condition (a) is free. |
| Spec 8 "3-condition trigger" | plan.md says "4-condition" (adds "reviewer didn't mark FAIL" as separate). Reconcile in requirements — roadmap's (c) already covers the reviewer-FAIL condition, so 3 vs 4 is a counting choice, not a substantive conflict. |

## The Precise Delta: Spec 6 vs Spec 8

| Capability | Spec 6 (shipped) | Spec 8 (this spec) |
|------------|------------------|--------------------|
| Hypothesis/experiment signals | ✅ HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL in chat.md legend + collaboration-resolution.md | reused as-is |
| Collaboration workflow body | ✅ experiment-propose-validate loop, cross-branch workflow | reused; *named* "pair-debug mode" |
| BUG_DISCOVERY → fix task | ✅ failure-recovery.md §546 | reused as-is |
| Baseline check | ✅ external-reviewer.md §3a | reused as-is |
| **Named "pair-debug mode"** | ❌ | ✅ NEW `references/pair-debug.md` |
| **Mechanical auto-trigger** | ❌ (entry is descriptive: "cause is ambiguous") | ✅ 3-condition check evaluated by coordinator |
| **Driver/Navigator role labels** | ❌ | ✅ Driver=executor, Navigator=reviewer |
| **Debug logging sanctioned** | ❌ | ✅ spec-executor.md addition |
| **Coordinator pair announcement** | ❌ | ✅ `### PAIR-DEBUG MODE ACTIVATED` in chat.md |
| **"first fix failed → pair" branch** | ❌ (failure-recovery treats all failures identically) | ✅ new branch in failure-recovery.md |

**Bottom line**: Spec 8 is a thin orchestration layer. It writes one new reference file and appends to three existing files. The hard collaboration logic already exists.

## Feasibility Assessment of the 3-Condition Trigger

Trigger fires when ALL hold:

| Condition | Mechanism | Feasibility |
|-----------|-----------|-------------|
| **(a) A green test is now red AND test file unchanged this spec** | `git diff $TASK_START_SHA..HEAD -- tests/` returns empty (test unchanged) + non-0 exit on a test the spec didn't author | HIGH for "test unchanged" — `TASK_START_SHA` exists. MEDIUM for "was green is now red": no per-test green/red snapshot is stored. Practical proxy: the failing test is **pre-existing** (not authored by this spec, i.e. not introduced in `git diff $TASK_START_SHA..HEAD` and not a `[RED]`-tagged task output). "Pre-existing test fails" ≈ "was green" because pre-existing tests are assumed green at spec start. plan.md AC#2 already phrases it as "pre-existing test fails" — adopt that phrasing. |
| **(b) ≥1 fix attempt failed** | `taskIteration >= 2` from `.ralph-state.json` | HIGH — `taskIteration` is mechanically incremented in failure-recovery.md (line 76) and coordinator-pattern.md (line 606). Trivial `jq` read. |
| **(c) Reviewer has NOT marked task FAIL** | absence of a FAIL row for `taskIndex` in `task_review.md`; coordinator already reads task_review.md pre-delegation (coordinator-pattern.md §127) | HIGH — coordinator already parses task_review.md FAIL rows. |

**Green→red detection — recommendation**: Do NOT build a per-test snapshot. Use the "pre-existing test" proxy: a test is "pre-existing" if its file is unchanged since `$TASK_START_SHA` (covered by condition a) AND it is not the product of a `[RED]` task in this spec. This is mechanically checkable and matches plan.md's wording. Note for requirements: there is no full per-test CI snapshot infra (ciSnapshot is per-category lint/test/build, not per-test) — so true "was green" cannot be proven; the pre-existing proxy is the pragmatic and correct choice.

**Verdict**: Trigger is **HIGH feasibility**. The only soft spot (green→red) is resolved by the pre-existing-test proxy already implied by plan.md.

## Recommendation: Where the Trigger Logic Lives

**Recommendation: the coordinator prompt (`coordinator-pattern.md` + `failure-recovery.md`), NOT the stop-watcher hook.**

Rationale:
- The 3 conditions require reading `tasks.md` (is the failing test pre-existing? is task `[RED]`?), `task_review.md` (FAIL rows), and running `git diff` on a *specific failing test path* extracted from executor output. The stop-watcher hook (`stop-watcher.sh`) is a thin `jq`-on-state-file mechanism — it has the transcript tail and `.ralph-state.json`, but does NOT parse tasks.md / task_review.md / executor failure output. Pushing this into bash would duplicate logic the coordinator already does.
- The natural insertion point is the **failure-recovery path**: when a task fails and `taskIteration >= 2`, before generating the fix task, evaluate conditions (a) and (c) and — if all hold — write the pair announcement. This is roadmap change #4's exact location.
- Condition (b) is the cheapest gate and is already a `jq` read the coordinator does. Conditions (a)/(c) reuse parsing the coordinator already performs.
- Keeps Spec 8 within "don't change the coordinator's core loop" — it's an added branch, not a loop change.
- The coordinator announcement itself (change #5) reuses the existing atomic chat.md append block (coordinator-pattern.md §255–270).

So: `failure-recovery.md` evaluates the trigger and announces; `coordinator-pattern.md` documents the pair-mode delegation variant; `pair-debug.md` is the reference both point to for the protocol + roles.

## Feasibility Assessment

| Aspect | Assessment | Notes |
|--------|------------|-------|
| Technical Viability | High | All conditions mechanically checkable with existing state/files. `TASK_START_SHA` already exists. |
| Effort Estimate | S–M | 1 new reference file (~80–120 lines), 3 append-only edits to existing files. No code, no hooks, no schema change. |
| Risk Level | Low–Medium | Main risk is false triggers / not changing behaviour (see Risks). |

## Recommendations for Requirements

1. **Create `references/pair-debug.md`** — sections: (a) the 3-condition auto-trigger (use plan.md "pre-existing test" wording); (b) Driver = spec-executor / Navigator = external-reviewer role table with the shared instruction "formulate hypotheses, respond to the other's, do not escalate to human unless a product/design decision is required"; (c) pointer to `collaboration-resolution.md` for the actual HYPOTHESIS→FIX_PROPOSAL loop body — DO NOT re-document the loop, reference it.

   **1b. Add a short anti-anchoring rule to `pair-debug.md`.** External RCA research names three LLM failure modes that pair-debug is specifically exposed to — anchoring on the executor's already-failed first fix, overweighting one piece of evidence, and stalled-loop reasoning. Encode three lightweight counter-rules (these cost almost nothing and are the highest-value *new* finding from the technical research): (i) the Navigator MUST propose **≥2 independent hypotheses** before the pair commits to investigating one — explicitly not anchored on the executor's prior fix attempt; (ii) a hypothesis is only `ROOT_CAUSE` once an EXPERIMENT produced **direct evidence** (not after reasoning alone — consistent with the DoVer "log-only attribution is ill-posed" finding); (iii) reuse collaboration-resolution.md's existing ">3 cycles → escalate" bound as the stalled-loop exit (no new mechanism — just point to it).
2. **Reconcile 3 vs 4 conditions** — roadmap says 3, plan.md says 4. The "reviewer didn't mark FAIL" is roadmap condition (c); they are the same set, counted differently. Pick one number and state it once.
3. **Append to `failure-recovery.md`** — new branch: when `taskIteration >= 2` AND failing test is pre-existing AND no reviewer FAIL → announce pair-debug mode before generating the fix task. The fix task becomes the Driver's first action.
4. **Append to `coordinator-pattern.md`** — document the `### PAIR-DEBUG MODE ACTIVATED` chat.md announcement (Driver/Navigator/Trigger/instruction), using the existing atomic-append block. State that pair mode replaces the normal delegation announcement for that one task only.
5. **Append to `agents/spec-executor.md`** — add debug logging to sanctioned investigation techniques, scoped to pair-debug mode: temporary `_LOGGER.warning()` / `console.log()` allowed; MUST be removed or converted to tests before TASK_COMPLETE. Two refinements from the technical research worth encoding in the rule text: (i) **agentic debug logs should capture the decision path, not just outcomes** — log the *suspect variable / code path being tested and the hypothesis it validates*, not a bare "got here", so the Navigator can read the log and judge the hypothesis directly; (ii) make the cleanup obligation **mechanically checkable** — require a consistent tag/prefix on every temporary log (e.g. a `PAIR-DEBUG:` marker in the message) so a `grep` before TASK_COMPLETE proves none remain. This makes roadmap acceptance criterion 18 ("no orphan debug logging") a one-line mechanical check instead of a manual review.
6. **Optionally** add a one-line note to `templates/chat.md` that a `### PAIR-DEBUG MODE ACTIVATED` coordinator message may appear (no new signal needed).
7. **Do NOT touch `external-reviewer.md`'s prohibitions** — Navigator role is additive; reviewer still cannot write code.
8. Acceptance test (roadmap criteria 16–18): intentionally break code, let first fix fail, verify pair mode activates on iteration 2, verify chat.md shows hypothesis exchange, verify no orphan debug logging remains.

## Related Specs

| Spec | Relationship | mayNeedUpdate |
|------|--------------|---------------|
| Spec 6 collaboration-resolution | **High** — Spec 8 sits directly on top; reuses its signal loop, BUG_DISCOVERY trigger, baseline check. pair-debug.md must reference collaboration-resolution.md, not duplicate it. | false (Spec 8 only references it) |
| Spec 3 role-boundaries | **Medium** — Driver/Navigator roles must not loosen `role-contracts.md` boundaries. Reviewer-cannot-write-code is load-bearing. | false |
| Spec 9 pre-execution-critic | **Low** — orthogonal (before-execution mechanical check). Debug logging added by Spec 8 must not be blocked by Spec 9's risk levels (temporary log edits inside spec scope = MEDIUM, allowed). FYI for Spec 9. | false |

## Risks & Open Questions

**Risks**
- **False triggers**: a genuinely flaky test or an env issue could repeatedly fail and spuriously enter pair mode. Mitigation: condition (a)'s "test file unchanged" + cross-branch check filters most env cases; pair mode is harmless overhead if wrongly triggered (it just adds hypothesis exchange).
- **No behavior change**: the biggest risk is that the announcement is written but agents don't actually behave differently — the prompts must make pair mode *operationally distinct* (Driver instruments, Navigator hypothesizes), not just a label.
- **Debug-logging orphans**: temporary logs left in code. Mitigation: explicit "remove before TASK_COMPLETE" rule + roadmap criterion 18 acceptance test.
- **Loop bound**: collaboration-resolution.md already escalates after >3 hypothesis cycles; ensure pair mode inherits this so it doesn't run forever.

**Open Questions (for requirements)**
- 3 vs 4 conditions — confirm the canonical count (see recommendation 2).
- "Was green is now red": confirm the team accepts the **pre-existing-test proxy** (no per-test snapshot infra exists). Recommended: yes.
- Should pair mode set a flag in `.ralph-state.json` (e.g. `pairDebugMode: true`) for observability/metrics, or stay purely chat.md-driven? Roadmap implies chat.md only; a state flag would help acceptance testing (criterion 16) but adds a schema field. Lean: chat.md only, keep it minimal.

## NOT in Scope

- No new agent types (Driver/Navigator are *roles* of existing executor/reviewer, not new agents).
- Reviewer's prohibition on writing code is **unchanged** — Navigator reads, hypothesizes, proposes; never edits implementation files.
- Pair mode is an **escalation path**, not the default execution mode.
- No micro-rules on *how* to debug — only the trigger + role split. The debugging loop body already lives in collaboration-resolution.md.
- No changes to the coordinator core loop, no new hooks, no schema changes (unless the optional state flag is approved).
- No E2E diagnostics scripts.

## Sources

- `docs/ENGINE_ROADMAP.md` §Spec 8 (lines 504–535), §success criteria 16–18 (lines 670–672), §file-change table (lines 638–641), §8 criteria 6–7 (Spec 2 cancelled).
- `plugins/ralphharness/references/collaboration-resolution.md` (full, 58 lines).
- `plugins/ralphharness/references/failure-recovery.md` (lines 71–147, 546–594).
- `plugins/ralphharness/references/coordinator-pattern.md` (lines 127–199, 203–289, 343–345).
- `plugins/ralphharness/agents/spec-executor.md` (lines 1–80, 200–278, 377).
- `plugins/ralphharness/agents/external-reviewer.md` (lines 52–53, 202–214, 743–780).
- `plugins/ralphharness/templates/chat.md` (signal legend, lines 31–36).
- `plugins/ralphharness/.claude-plugin/plugin.json` (version 5.2.0).
- `docs/harness-engineering/11-openhands-deep-dive.md`, `10-deep-agents-deep-dive.md`, `08-practical-implementation-guide.md`.
- [Fully Autonomous Programming using Iterative Multi-Agent Debugging (arxiv 2503.07693)](https://arxiv.org/abs/2503.07693)
- [PairCoder: A Pair Programming Framework for LLM-based Code Generation (arxiv 2404.04834)](https://arxiv.org/abs/2404.04834) — Driver/Navigator reference implementation, measured 12–162% pass@1 gain.
- [DoVer: Intervention-Driven Auto Debugging for LLM Multi-Agent Systems (arxiv 2512.06749)](https://arxiv.org/html/2512.06749v1/) — "log-only hypothesis attribution is ill-posed"; 18–28% failed-trial recovery via interventions.
- [Magentic-One: A Generalist Multi-Agent System (arxiv 2411.04468)](https://arxiv.org/abs/2411.04468) — orchestrator escalation patterns; corroborates iteration-count escalation.
- [The Agent Loop Problem: When "Smart" Won't Stop (Modexa)](https://medium.com/@Modexa/the-agent-loop-problem-when-smart-wont-stop-ccbf8489180f)
- [Automatic Debugging and Failure Detection in AI Agent Systems (saulius.io)](https://saulius.io/blog/automatic-debugging-and-failure-detection-in-ai-agent-systems)
- [What Is the AI Agent Loop? (Oracle)](https://blogs.oracle.com/developers/what-is-the-ai-agent-loop-the-core-architecture-behind-autonomous-ai-systems)
- [Autonomous Observability: AI Agents That Debug AI (IEEE Computer Society)](https://www.computer.org/publications/tech-news/community-voices/autonomous-observability-ai-agents)
