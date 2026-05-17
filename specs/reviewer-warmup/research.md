---
spec: reviewer-warmup
phase: research
created: 2026-05-17
status: complete
---

# Research: reviewer-warmup

## Executive Summary

The external-reviewer starts each spec with an empty `chat.md` and no source-of-truth context file (unlike the executor, which has `.progress.md`). It "warms up" by accumulating context over many cycles, producing a measurable ~30-40 min struggle phase per spec. Two of the three proposed fixes are sound and belong here (reviewer bootstrap, READING/heartbeat liveness signal). The third — chat.md trimming — is **already shipped** by the context-middleware spec (`condense-context.sh`) and must NOT be reimplemented; reviewer-warmup only needs to compose with it. Feasibility HIGH, Risk LOW, Effort S-M.

## Problem Statement

External-reviewer cold-start: the reviewer's only context channel (`chat.md`) is empty at spec start. It cannot review effectively until enough messages accumulate. Forensic data (context-middleware, 29 tasks):

- **Struggle phase (cycles 1-8, ~43 min)**: reviewer saw no file output on task 1.3, escalated WARNING → FAIL → INTENT-FAIL → DEADLOCK — an *unnecessary* deadlock caused by inability to distinguish "executor reading design docs" from "executor stalled".
- **Momentum phase (cycles 14+)**: once file output appeared, reviewer reviewed 24+ tasks cleanly and caught REAL bugs (schema FABRICATION: fixture `.state.chat` vs schema root `.chat`; missing cleanup; wrong version bump).

Hypothesis "agents read chat.md poorly cold, well with momentum" is validated.

**Preserve (do not regress)**: reviewer's real-bug detection; DEADLOCK escalation when genuinely stalled 7+ cycles.

## Current-State Analysis (file:line)

### Reviewer bootstrap — `agents/external-reviewer.md`
- **Section 0 (lines 19-33)** is the only bootstrap. It reads `tasks.md`, `task_review.md`, and `chat.md` *only to check for active HOLD/PENDING/DEADLOCK* (lines 26-29). It sets `chat.reviewer.lastReadLine` to the current line count (line 30) — i.e. it **skips all existing chat.md history**, then begins the review cycle.
- Section 1 (line 40) loads `requirements.md`, `design.md`, `tasks.md` at session start — but NOT `.progress.md`, NOT recent git history, NOT a digest of spec state.
- **Gap**: there is no "read spec state, build a mental model" step. The reviewer starts knowing the task list but nothing about *what has happened so far*.

### Review cycle — `external-reviewer.md` Section 6 (lines 430-469)
- The cycle DOES read `.progress.md` for blockage signals (step 6, line 465) and DOES check disk for real git changes (step 3, lines 438-440). So the machinery to read non-chat sources exists — it is just not used at bootstrap.
- `lastReadLine` incremental reads: Section 7 (lines 560-563) — `jq` update of `chat.reviewer.lastReadLine`.

### Stagnation detection — `external-reviewer.md` Section 3b Step 6 (lines 311-339)
- A "progress-real check" already exists **but only for VE/E2E tasks in mid-flight submode**. It detects "same error 2/3 cycles" via `test-results/**/error-context.md`.
- **Gap**: for non-VE tasks (like task 1.3, design-doc reading) there is NO progress-real check. The reviewer has no way to know the executor is alive-but-reading. Section 4 "Anti-Blockage" (lines 352-379) treats `taskIteration >= 3` and "same error twice" as blockage — but a long read phase produces neither; it produces *silence*, which the reviewer wrongly read as stagnation.

### Executor progress reporting — `agents/spec-executor.md`
- Executor updates `.progress.md` only **after** completing a task (`<progress>`, lines 280-294). During a long Do-step (e.g. reading design files) it emits nothing.
- `<flow>` (lines 40-51): no "announce I am in a read/understand phase" step.
- Executor writes `chat.md` only for "architectural decisions, cross-task dependencies, design rationale, task completion notices" (line 150) — not for liveness.
- Executor's only control signal is `INTENT-FAIL` → `signals.jsonl` (Signal Emission Contract, lines 383-392). Collaboration signals incl. `ALIVE`/`STILL` go to chat.md.

### Signal infrastructure — `lib-signals.sh`, `templates/signals.jsonl`, `chat.md`
- `signals.jsonl` schema (`signals.jsonl` line 2): `type=control, signal, from, to, task, status, timestamp, iteration, reason`. **Open enum** — `append_signal()` validates only that the line is valid JSON (`lib-signals.sh:15`), not the `signal` value. A new signal kind needs no schema migration.
- `active_signal_count()` (`lib-signals.sh:25-30`) hard-codes the *blocking* set: `HOLD|PENDING|URGENT|DEADLOCK`. A new non-blocking `READING` kind would be ignored by this gate automatically — good (it should not block).
- `chat.md` legend (`chat.md:24-37`) already defines collaboration markers `ALIVE` ("heartbeat") and `STILL` ("still alive/active, no progress but not dead"). Coordinator treats `ALIVE`/`STILL` as "Ignore, do not block" (`coordinator-pattern.md:246`).
- **Finding**: a liveness signal partially exists conceptually (`STILL`/`ALIVE`) but (a) is a chat.md marker not a `signals.jsonl` event, (b) is never emitted by the executor during read phases, (c) the reviewer never consults it to suppress a stagnation verdict.

### chat.md growth & trimming — ALREADY SOLVED by context-middleware
- `condense-context.sh` (shipped, in `hooks/scripts/`) condenses `chat.md` + `.progress.md` when combined > 2000 lines; proactive/reactive/emergency modes; archives to `.archive.<ts>.md`.
- context-middleware **AC-1.4**: keeps last 15 messages + all preserved signals. **AC-1.6/AC-1.8**: condensation only touches the prefix older than `min(coordinator, executor, reviewer lastReadLine)` — it provably never desyncs the reviewer's read pointer.
- **Conclusion**: deficiency #3 ("chat.md grows unbounded, 966 lines") is the exact problem context-middleware fixed. A reviewer-warmup "trimming" feature would duplicate or conflict with it.

## Feasibility Assessment of the 3 Proposed Solutions

### Solution 1 — Reviewer bootstrap phase — FEASIBLE, IN SCOPE
Reviewer reads full spec state at start instead of skipping chat.md history.

| Aspect | Assessment |
|--------|------------|
| Viability | HIGH — pure prompt change to `external-reviewer.md` Section 0/1 |
| Cost | S — add a bootstrap step: read `chat.md` fully (not just signal-scan), read `.progress.md`, read recent `git log`/`git diff --stat`, summarize into a mental model before cycle 1 |
| Interaction | Composes cleanly with context-middleware: at spec start chat.md is short, so full read is cheap; later, condensation keeps it bounded so full re-read stays cheap |
| Risk | LOW |

Two variants to decide in requirements:
- **(a) Read chat.md fully + .progress.md + git** at bootstrap (no new file). Simplest. Recommended baseline.
- **(b) Seed `task_review.md` (or a new digest) with spec state.** `task_review.md` already exists as the reviewer-owned file (`role-contracts`); a `<!-- bootstrap-context -->` block could be seeded by the coordinator in implement.md Step 2.5/4. Adds a file-lifecycle concern. Only worth it if (a) proves insufficient.

Recommendation: ship (a). The reviewer already reads `.progress.md` and git mid-cycle (Section 6) — bootstrap just moves that to cycle 0 and stops the `lastReadLine = linecount` skip.

### Solution 2 — READING / liveness signal — FEASIBLE, IN SCOPE (the highest-value fix)
Executor signals when in a read/understand phase so the reviewer does not mistake silence for stagnation.

| Aspect | Assessment |
|--------|------------|
| Viability | HIGH — `signals.jsonl` enum is open; `append_signal()` needs no change |
| Cost | M — touches executor (emit), reviewer (consume), and the legend in `chat.md` + `coordinator-pattern.md` |
| Interaction | Must be NON-blocking. `active_signal_count()` only counts `HOLD/PENDING/URGENT/DEADLOCK`, so a new `READING`/heartbeat signal is ignored by the HOLD gate automatically — no coordinator change needed |
| Risk | LOW-MEDIUM — risk is the executor forgetting to emit it; mitigate by tying emission to a concrete trigger (entering Do-steps / before a long Explore) rather than agent discretion |

**Design question for requirements: new signal kind vs progress-heartbeat.**
- A discrete `READING` event marks *entering* a phase but goes stale — if the executor crashes mid-read, an old `READING` looks alive forever.
- A **progress-heartbeat** (periodic `ALIVE` with a monotonically-updated `iteration`/timestamp + a short `activity` string) lets the reviewer compute *staleness* (heartbeat age) and distinguish "reading, fresh heartbeat 30s ago" from "no heartbeat in 10 min → genuinely stuck".
- Recommendation: model it as a **heartbeat** — reuse the existing `ALIVE`/`STILL` vocabulary, emitted to `signals.jsonl` as `type:control, signal:ALIVE, reason:"<activity>"`, refreshed each executor turn. The reviewer's stagnation logic (Section 4 + 3b Step 6) then gates on heartbeat freshness, not on output silence. This subsumes a bare `READING` flag and is robust to crashes.

This is the fix that directly prevents the unnecessary DEADLOCK — it is the core deliverable.

### Solution 3 — chat.md trimming/compaction — OUT OF SCOPE (redundant)
Already delivered by context-middleware (`condense-context.sh`, AC-1.1–AC-1.8). Re-implementing it would duplicate logic and risk pointer desync that context-middleware specifically engineered against (AC-1.6/AC-1.8). reviewer-warmup should **depend on** it, not rebuild it.

The only adjacent concern worth a note: the reviewer's *bootstrap full read* (Solution 1) interacts with condensation — once condensed, a "full read" of chat.md reads the condensed file, which is correct and intended. No new work; just document the dependency.

## Interaction / Conflict Analysis

| Spec | Relationship | mayNeedUpdate | Notes |
|------|--------------|---------------|-------|
| context-middleware | HIGH — owns chat.md condensation | No | Solution 3 redundant with it. reviewer-warmup composes; do not touch `condense-context.sh`. Reviewer bootstrap must read whatever chat.md currently is (condensed or not). |
| agent-chat-protocol | HIGH — owns chat.md format + ALIVE/STILL legend | Yes (minor) | If a heartbeat signal is added, the `chat.md`/legend and `signals.jsonl` schema comment need a new-row update. |
| signal-log-and-ci-autodetect | MEDIUM — owns `signals.jsonl` + `lib-signals.sh` | Possibly | New signal kind rides the existing open enum; `active_signal_count()` deliberately stays unchanged so heartbeat is non-blocking. Confirm no migration needed. |
| collaboration-resolution | MEDIUM — owns HOLD/PENDING/DEADLOCK resolution | No | reviewer-warmup reduces *false* DEADLOCKs; genuine DEADLOCK path unchanged. |
| pair-debug-auto-trigger | LOW | No | Heartbeat could feed pair-debug triggers later; out of scope now. |
| loop-safety-infra / pre-execution-critic / role-boundaries | LOW | No | No overlap. |

**No hard conflicts.** The one constraint: do not add a second condensation path for chat.md.

## Prior-Art Summary

- **OpenAI Codex Issue #16900** — "Long-running healthy subagents can be prematurely treated as stalled, causing duplicate work, wasted tokens, parent context bloat." This is *exactly* deficiency #2: a parent/observer needs a parent-visible liveness signal for long single-turn work. Validates the heartbeat approach.
- **Heartbeat pattern** (MindStudio) — periodic pulse confirming a process is alive, borrowed from systems programming; each beat is an observe/reason/act opportunity. Supports modeling liveness as a recurring signal with freshness, not a one-shot flag.
- **Context bootstrapping / cold-start** (Atlan) — agents need an initial context layer drafted up-front rather than accumulated; mirrors Solution 1 (seed the reviewer's model before cycle 1).
- **Scratchpad + verifier pattern** (Masood) — a verifier/reviewer agent works from a shared scratchpad of prior thoughts/actions; when the scratchpad is empty the verifier has nothing to verify against. The fix is to give the reviewer the executor's state digest (`.progress.md` + git) as its scratchpad substitute.
- **Sliding-window async summarization** (Google ADK / context-engineering) — standard practice: summarize older events on a threshold and write the summary back. Confirms context-middleware's condensation is the industry-standard answer to deficiency #3 — no need to reinvent it.

## Recommendations for Requirements

1. **In scope — Reviewer bootstrap (Solution 1, variant a).** Add a bootstrap step to `external-reviewer.md` Section 0/1: before cycle 1, read `chat.md` in full, read `.progress.md`, read `git log`/`git diff --stat` since spec branch point; build and state a short spec-state model. Stop setting `chat.reviewer.lastReadLine` to the full line count at bootstrap (or set it to 0 so cycle 1 actually processes existing history).
2. **In scope — Executor liveness heartbeat (Solution 2, as heartbeat not bare flag).** Executor emits a periodic `ALIVE` heartbeat to `signals.jsonl` (with `reason`/activity + fresh timestamp) on entering Do-steps and before/around long Explore or design-doc reads. Reviewer's stagnation logic (Section 4, Section 3b Step 6) gates on **heartbeat freshness** instead of output silence. Keep it non-blocking (rides past `active_signal_count`).
3. **Out of scope — chat.md trimming (Solution 3).** Redundant with context-middleware. Requirements should explicitly state reviewer-warmup *depends on* `condense-context.sh` and adds no new condensation.
4. **Suggested ordering:** (1) heartbeat signal first — it directly prevents the unnecessary DEADLOCK and is the highest-value fix; (2) reviewer bootstrap second — reduces warm-up time; (3) doc updates to `chat.md` legend / `signals.jsonl` schema comment / `coordinator-pattern.md` for the heartbeat row.
5. Preserve regression guards: an explicit acceptance criterion that genuine 7+-cycle stalls still escalate to DEADLOCK, and that real-bug detection (FABRICATION-class catches) is unaffected.

## Open Questions (for requirements phase)

- Bootstrap variant (a) full-read vs (b) seeded digest file — recommend (a); confirm it is sufficient or fall back to (b).
- Heartbeat cadence: every executor turn? every N seconds? Tie to a concrete trigger (entering Do-steps / before Explore) to avoid relying on agent discretion.
- Staleness threshold: how old a heartbeat (minutes? cycles?) before the reviewer is allowed to escalate stagnation? Must be > a realistic long design-doc read.
- Should the heartbeat carry the current Do-step index / activity label so the reviewer can also see *forward motion* (step 2→3), not just liveness?
- Reuse `ALIVE`/`STILL` vocabulary vs introduce a distinct `READING`/`HEARTBEAT` kind — naming/legend decision.
- Does the coordinator need to emit/relay heartbeats, or is executor→signals.jsonl→reviewer sufficient? (Reviewer reads `signals.jsonl` directly, so likely sufficient.)

## Quality Commands

No `package.json`, `Makefile`, or CI workflow with build/test scripts in repo root — this is a Claude Code plugin (markdown + shell), not a built project.

| Type | Command | Source |
|------|---------|--------|
| Lint | Not found | — |
| TypeCheck | Not found | — |
| Test | Not found | — (shell scripts; ad-hoc `bash` execution) |
| Build | Not found | — (no build step; CLAUDE.md states "No build step required") |

[VERIFY] tasks should rely on: `jq` JSON validation of state/signals files, `bash -n` syntax checks on any modified `.sh`, and grep-based assertions on agent/reference markdown.

## Verification Tooling

No UI, no E2E tooling. The "product" is plugin markdown/shell consumed by Claude Code.

**UI Present**: No
**Browser Automation Installed**: No (`playwright` MCP available in env, but project is not a web app)
**Project Type**: Claude Code plugin (CLI/config artifacts)
**VE Task Strategy**: Skip VE tasks
**Verification Strategy**: `bash -n` on modified scripts; `jq -e` validation of signals.jsonl/.ralph-state.json shapes; grep assertions that agent prompts contain the new bootstrap step and heartbeat rules; manual/scripted simulation of a signals.jsonl heartbeat sequence.

## Sources

- plugins/ralphharness/agents/external-reviewer.md (Sections 0, 1, 3b, 4, 6, 7)
- plugins/ralphharness/agents/spec-executor.md (flow, progress, Signal Emission Contract)
- plugins/ralphharness/commands/implement.md (Step 2.5, HOLD-GATE, coordinator behaviors)
- plugins/ralphharness/hooks/scripts/lib-signals.sh
- plugins/ralphharness/hooks/scripts/condense-context.sh, lib-context.sh
- plugins/ralphharness/templates/signals.jsonl, chat.md, task_review.md
- plugins/ralphharness/references/coordinator-pattern.md (Signal Protocol)
- specs/context-middleware/{research,requirements}.md (AC-1.1–AC-1.8)
- https://github.com/openai/codex/issues/16900 — long-running subagents treated as stalled
- https://www.mindstudio.ai/blog/agentic-os-heartbeat-pattern-proactive-ai-agent
- https://atlan.com/know/context-bootsrapping/
- https://medium.com/@adnanmasood/engineering-trustworthy-lm-agents-with-scratchpads-and-verifiers-5c1084533be7
- https://developers.googleblog.com/architecting-efficient-context-aware-multi-agent-framework-for-production/
