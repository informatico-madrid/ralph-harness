# Requirements: Context Middleware (Spec 10)

## Goal

Add an always-on, file-level context management middleware that runs before each coordinator LLM call to prevent context overflow — via proactive condensation, reactive fallback, tool result eviction, and phase-based reference scoping — replacing cancelled Spec 2 (prompt-diet-refactor) with a non-disruptive, additive approach.

## User Stories

### US-1: Proactive Condensation
**As a** Ralph coordinator running a long spec
**I want to** automatically condense chat.md and .progress.md when their combined size exceeds a conservative threshold
**So that** context stays bounded and quality does not degrade across iterations.

**Acceptance Criteria:**
- [ ] AC-1.1: Before each delegation, a script computes the combined line count of `chat.md` + `.progress.md`; if it exceeds 2,000 lines, condensation runs; if not, it is skipped (no-op).
- [ ] AC-1.2: Before any content is modified, a full backup is written to `.archive.<timestamp>.md` (one archive per condensation event).
- [ ] AC-1.3: Condensation is in-place — `chat.md` and `.progress.md` are replaced with condensed content; the coordinator reads the condensed files directly.
- [ ] AC-1.4: After condensation, `chat.md` retains the last 15 messages plus all preserved signals (see FR-5); `.progress.md` retains the stable section (Goal, Learnings) plus the last 3 per-task progress entries.
- [ ] AC-1.5: Condensation never modifies, truncates, or evicts `signals.jsonl`.
- [ ] AC-1.6: Condensation does not desync the chat protocol — all three chat read pointers (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`) in `.ralph-state.json` remain consistent with the condensed `chat.md` so no session re-reads or skips a message.
- [ ] AC-1.7: Each condensation event is appended to `.metrics.jsonl`.
- [ ] AC-1.8: Because the executor and reviewer run in separate sessions and re-read `chat.md` independently, condensation MUST only condense the prefix of `chat.md` strictly older than the minimum of the three read pointers — content any session has not yet read is never condensed. This is the explicit, conservative rule.

### US-2: Reactive Condensation Fallback
**As a** Ralph coordinator hitting a context overflow despite proactive condensation
**I want to** condense as a fallback and retry the delegation
**So that** the loop survives overflow instead of crashing.

**Acceptance Criteria:**
- [ ] AC-2.1: Reactive condensation is triggered by REAL token measurement, not API-error interception: a hook (e.g. `stop-watcher.sh`, which receives `transcript_path` on stdin) reads the last `message.usage` object from the Claude Code transcript JSONL, computes context usage as `(input_tokens + cache_creation_input_tokens + cache_read_input_tokens) / 200000`, and triggers reactive condensation when usage exceeds ~85%.
- [ ] AC-2.2: Reactive condensation applies the same preservation rules as proactive (FR-5), writes an archive (FR-3), and is logged to `.metrics.jsonl` with a `reactive` mode marker.
- [ ] AC-2.3: After reactive condensation, the delegation is retried once with the condensed context.
- [ ] AC-2.4: Reactive condensation preserves current task state and all active signals so execution resumes at the same task.
- [ ] AC-2.5: As a last-resort safety net, the `PreCompact` hook triggers an emergency condensation + archival pass before Claude Code's automatic compaction (~95% of context) can destroy context.
- [ ] AC-2.6: The trigger model is two-gated: the combined line count of `chat.md` + `.progress.md` (>2,000 lines, FR-1 / AC-1.1) is a CHEAP first-pass gate, while the transcript-JSONL token-percentage read (AC-2.1) is the AUTHORITATIVE trigger. The line-count threshold remains as the inexpensive pre-check; it is not replaced by the token read.

### US-3: Tool Result Eviction
**As a** Claude Code agent (that loaded Smart Ralph's prompt rules) producing large tool outputs
**I want** oversized tool results routed through the eviction helper, written to disk, and replaced with a preview
**So that** verbose grep/diff/read/ls output does not bloat the conversation.

**Acceptance Criteria:**
- [ ] AC-3.1: Tool results exceeding per-file-type thresholds are routed through the eviction helper by the agent: grep/rg >100 lines, git diff >200 lines, file read >500 lines, ls/find >300 lines.
- [ ] AC-3.2: Evicted output is written in full to `.tool-results/` with a unique filename; the conversation receives the first 50 lines plus a summary line that includes the on-disk path and total line count.
- [ ] AC-3.3: Tool results below their threshold pass through unchanged.
- [ ] AC-3.4: Pair-debug tool results (debug logging output during pair-debug mode) are never evicted.
- [ ] AC-3.5: Eviction is NOT interception — a shell script cannot intercept a tool call mid-conversation. Eviction is realized as an agent prompt-rule: the agent routes oversized tool output through `evict-tool-result.sh`. It therefore applies only to Claude Code agents that loaded Smart Ralph's prompt rules.

### US-4: Phase-Based Context Scoping
**As a** Ralph coordinator
**I want to** load only the reference files relevant to the current phase and task type
**So that** per-iteration context shrinks for the coordinator session without restructuring shared reference files.

**Acceptance Criteria:**
- [ ] AC-4.1: Reference loading in `implement.md` is conditional on the new `executionPhase` field (enum `poc | refactor | test | quality`) in `.ralph-state.json`.
- [ ] AC-4.2: `executionPhase: poc` loads `coordinator-pattern.md` + `failure-recovery.md`; `executionPhase: refactor` additionally loads `commit-discipline.md`; `executionPhase: test` and `executionPhase: quality` additionally load `verification-layers.md`; `phase-rules.md` is skipped during `poc` and `refactor`.
- [ ] AC-4.3: When `chat.md` contains a `PAIR-DEBUG` marker, the pair-debug reference is additionally loaded.
- [ ] AC-4.4: Scoping is implemented as conditional logic in `implement.md` only — no reference file is split, renamed, or moved.
- [ ] AC-4.5: Always-relevant references are loaded in every phase (no phase ever loses required guidance).
- [ ] AC-4.6: Phase-based scoping affects `implement.md` (coordinator command) only; it does not bound the context of the separate executor or reviewer sessions.
- [ ] AC-4.7: When `.ralph-state.json` has no `executionPhase` field (e.g. a spec created before this feature), `implement.md` loads all reference files — the pre-existing behavior — so scoping never breaks an older spec.

### US-5: Graceful Degradation and Cleanup
**As a** Ralph operator
**I want** the middleware to fail safe and clean up after itself
**So that** it never crashes the loop and never leaves accumulating files.

**Acceptance Criteria:**
- [ ] AC-5.1: If the spec directory is not writable (read-only-agent case, Spec 4), middleware skips condensation/eviction and logs a degradation notice; the loop continues without crashing.
- [ ] AC-5.2: At most 3 `.archive.<timestamp>.md` files are retained; older archives are deleted on each new condensation.
- [ ] AC-5.3: On spec completion, all `.archive.*.md` files and the `.tool-results/` directory are deleted.
- [ ] AC-5.4: Middleware is always-on — it activates automatically once the threshold is crossed, with no opt-in flag and no manual invocation.

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | Pre-delegation check computes combined line count of `chat.md` + `.progress.md` and triggers condensation above 2,000 lines | High | Run on spec >2,000 lines → condensation runs; <2,000 → skipped |
| FR-2 | Proactive condensation replaces `chat.md`/`.progress.md` in place with condensed content | High | Files shrink; coordinator reads condensed files |
| FR-3 | Full backup written to `.archive.<timestamp>.md` before any modification | High | Archive exists and equals pre-condensation content |
| FR-4 | `signals.jsonl` is excluded from all condensation and eviction | High | `signals.jsonl` byte-identical before/after middleware run |
| FR-5 | Condensation preserves control signals (HOLD/PENDING/DEADLOCK/URGENT/ACK/CONTINUE), collaboration signals (HYPOTHESIS, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY), pair-debug markers ("PAIR-DEBUG", "Driver:", "Navigator:"), and stable `.progress.md` sections (Goal, Learnings) | High | All listed markers present in condensed output |
| FR-6 | `.progress.md` is treated as stable (Goal, Learnings — always kept) vs volatile (per-task entries — keep last 3) | High | Stable section intact; only last 3 task entries kept |
| FR-7 | `chat.md` condensation keeps last 15 messages plus all preserved signals | High | Condensed `chat.md` has ≤15 messages + signals |
| FR-8 | Condensation MUST reconcile ALL THREE chat read pointers (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`) in `.ralph-state.json` against the shortened `chat.md`, so no session re-reads or skips a message | High | No message re-read or skipped by any of the three sessions after condensation |
| FR-9 | Reactive condensation triggers on real transcript token measurement (context usage > ~85% of the 200k window, read from the transcript JSONL `message.usage`) and retries the delegation once; the `PreCompact` hook provides an emergency fallback before auto-compaction | High | Transcript `message.usage` shows >85% context → condense → retry succeeds at same task; `PreCompact` hook fires emergency condensation before auto-compaction |
| FR-10 | Tool result eviction by per-file-type threshold (grep >100, git diff >200, file read >500, ls/find >300) | High | Oversized output evicted; smaller output passes through |
| FR-11 | Evicted output written to `.tool-results/`; conversation gets first 50 lines + summary + on-disk path | High | Preview + path present; full content on disk |
| FR-12 | Phase-based selective reference loading in `implement.md` (coordinator session only) keyed off a new `.ralph-state.json` field `executionPhase` (enum `poc | refactor | test | quality`), written by the coordinator at each POC-first phase transition; the existing coarse `phase` field is unchanged and unaffected; does not bound the separate executor/reviewer sessions | High | `executionPhase: poc` omits `verification-layers.md`/`phase-rules.md` |
| FR-13 | Pair-debug reference additionally loaded when `chat.md` contains `PAIR-DEBUG` | Medium | Marker present → pair-debug reference loaded |
| FR-14 | Condensation events logged to `.metrics.jsonl` (proactive and reactive distinguished) | Medium | One JSONL line per event with mode field |
| FR-15 | Archive retention capped at 3; cleanup of archives and `.tool-results/` on spec completion | Medium | ≤3 archives mid-run; 0 archives + no `.tool-results/` after completion |
| FR-16 | Graceful degradation when writes are not permitted (read-only-agent case) | High | Read-only spec dir → middleware skips, loop continues |
| FR-17 | Middleware is always-on with no opt-in flag | Medium | No flag in state or command; activates on threshold |
| FR-18 | Condensation of `chat.md` MUST acquire the same `flock` on `chat.md.lock` (fd 200) used by the reviewer and executor before rewriting the file, so in-place condensation never races a concurrent reader | High | `chat.md` rewrite always occurs while holding `chat.md.lock` (fd 200) |
| FR-19 | The coordinator MUST write the `executionPhase` field (`poc \| refactor \| test \| quality`) to `.ralph-state.json` at each POC-first phase transition, and `schemas/spec.schema.json` MUST define `executionPhase` as an optional enum property. When `executionPhase` is absent (older specs), reference loading falls back to loading all references (safe default, byte-identical to pre-spec behavior). | High | Coordinator writes `executionPhase` at each transition; schema validates the enum; absent field → all references loaded |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Performance — middleware adds minimal latency per iteration | Wall-clock overhead of pre-delegation check | < 1s on a typical spec |
| NFR-2 | Safety — condensation never loses context permanently | Recoverability | 100% of pre-condensation content recoverable from `.archive.<timestamp>.md` |
| NFR-3 | Conservatism — thresholds err toward keeping context | Proactive threshold | 2,000 combined lines (≈75% model-window headroom) |
| NFR-4 | Robustness — middleware never crashes the Ralph loop | Failure mode | All failure paths degrade gracefully (skip + log), never abort |
| NFR-5 | Security — middleware file operations classified LOW risk for pre-execution-critic (Spec 9) | False-positive blocks | 0 — operations documented as LOW risk, writing within spec scope |
| NFR-6 | Observability — every condensation event is auditable | Coverage | 100% of proactive + reactive events logged to `.metrics.jsonl` |
| NFR-7 | Testability — middleware behavior verified deterministically | Test method | bats / shell test commands; no UI/browser tooling |

## Glossary

- **Condensation**: Replacing verbose conversation/progress content with a compact summary while preserving required signals and sections.
- **Proactive condensation**: Condensation triggered by a line-count threshold before an overflow occurs.
- **Reactive condensation**: Condensation triggered as a fallback when real transcript token measurement shows context usage exceeding ~85% of the 200k window.
- **Transcript JSONL**: The Claude Code session log at `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`, one JSON object per line; an assistant-message line's `message.usage` field (`input_tokens` + `cache_creation_input_tokens` + `cache_read_input_tokens`) gives the real context-window token count at that turn.
- **PreCompact hook**: A Claude Code hook that fires before automatic context compaction (~95% of context), used here as a last-resort emergency condensation + archival trigger.
- **Tool result eviction**: Writing an oversized tool output to disk and replacing it in-conversation with a short preview.
- **Context scoping**: Loading only the reference files relevant to the current phase/task type.
- **Archive**: Timestamped full backup of `chat.md`/`.progress.md` written before condensation (`.archive.<timestamp>.md`).
- **Stable section** (`.progress.md`): Goal and Learnings — always preserved during condensation.
- **Volatile section** (`.progress.md`): Per-task progress entries — condensable, last 3 kept.
- **Chat read pointers** (`lastReadLine` set): `.ralph-state.json` holds THREE independent chat read positions — `chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, and `chat.reviewer.lastReadLine`. Each session (coordinator, the separate spec-executor session, the separate external-reviewer session) advances its own pointer as it incrementally reads `chat.md`.
- **Preserved signals**: Control signals (HOLD/PENDING/DEADLOCK/URGENT/ACK/CONTINUE), collaboration signals (HYPOTHESIS, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY), pair-debug markers — never dropped by condensation.
- **`.tool-results/`**: Directory holding full evicted tool outputs.
- **`.metrics.jsonl`**: Append-only metrics log shared with Spec 4 (loop-safety) loop metrics.
- **`executionPhase`**: Fine-grained POC-first sub-phase (`poc | refactor | test | quality`) stored in `.ralph-state.json`, written by the coordinator, distinct from the coarse `phase` field; drives phase-based reference scoping.

## Out of Scope

Deferred to v0.2 (explicitly NOT in this spec):
- **Adaptive thresholds** — scaling the condensation threshold by `totalTasks` count.
- **Context budget accounting** — per-task token-budget tracking instead of line counts.
- **Tool argument truncation** — truncating old tool-call arguments (redundant with Claude Code's own truncation).
- **Splitting `coordinator-pattern.md`** into base + extension files (`coordinator-base.md`, `coordinator-parallel.md`, etc.) — no reference file restructuring in v0.1.
- **context-mode MCP server** — tool-output interception via an external MCP process.
- **BM25 indexing** of evicted content for semantic search.
- **RAG on the codebase**.
- **Signal-based degradation detection** — triggering condensation from rising HOLD/PENDING/DEADLOCK rate.
- **Tool-result eviction for a non-Claude `external-reviewer`** — a foreign agent does not load Smart Ralph prompt rules and will not invoke `evict-tool-result.sh`; its context is not managed by v0.1 middleware.
- **Bounding the context of the parallel `external-reviewer` or `spec-executor` sessions** — v0.1 middleware (hooks + shell scripts) runs only in the coordinator's Claude Code session. Those sessions, and any non-Claude reviewer, are NOT context-managed by this spec; the only cross-session contract v0.1 guarantees is filesystem-format and pointer correctness of `chat.md` / `signals.jsonl` / `.ralph-state.json`.

## Dependencies

- **Spec 3 (role-boundaries)** — `.condensed`/`.archive` files and `.tool-results/` are within spec scope; spec-executor may read but not modify middleware-managed files. Middleware operations respect role contracts.
- **Spec 4 (loop-safety-infra)** — condensation events logged to the shared `.metrics.jsonl`; middleware must handle the read-only-agent case gracefully (skip + log, never crash).
- **Spec 6 (signal-log-and-ci-autodetect)** — `signals.jsonl` MUST be excluded from condensation/eviction; `lastReadLine` semantics MUST be preserved.
- **Spec 7 (collaboration-resolution)** — collaboration signals (HYPOTHESIS, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY) MUST survive condensation.
- **Spec 8 (pair-debug-auto-trigger)** — pair-debug markers ("PAIR-DEBUG", "Driver:", "Navigator:") MUST survive condensation; pair-debug tool results MUST NOT be evicted.
- **Spec 9 (pre-execution-critic)** — middleware file operations MUST be documented as LOW risk to avoid security false-positive blocks.
- **agent-chat-protocol (multi-session relationship)** — `chat.md` is read incrementally by three independent sessions: the coordinator, the separate `spec-executor` session, and the separate `external-reviewer` session (which may be a non-Claude agent and runs only Smart Ralph's filesystem FORMAT, not its prompt rules or scripts). `.ralph-state.json` carries one read pointer per session (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`); the reviewer and executor take `flock` on `chat.md.lock` (fd 200) when writing `chat.md`. Condensation MUST honor all three pointers and acquire the same lock. No new spec dependency — this restates the existing cross-session contract the middleware must not break.

## Success Criteria

- A 30+ task spec stays under the condensation threshold every iteration after the middleware activates (verified via `.metrics.jsonl`).
- No loop crash attributable to context overflow across a full execution run.
- 100% of pre-condensation content is recoverable from archives during the run.
- `signals.jsonl` is byte-identical before and after every middleware run.
- After spec completion, no `.archive.*.md` files and no `.tool-results/` directory remain.
- Pre-execution-critic raises zero false-positive blocks against middleware file operations.

## Verification Contract

**Project type**: cli

**Entry points**:
- `condense-context.sh` (new) — proactive condensation script invoked before delegation by the Ralph loop.
- `evict-tool-result.sh` (new) — tool-result eviction helper invoked when oversized output is produced.
- `stop-watcher.sh` (modified) — pre-delegation check invokes condensation; reads `transcript_path` from stdin and computes context token usage from the transcript JSONL `message.usage`; triggers reactive condensation when usage exceeds ~85%.
- `PreCompact` hook (new) — last-resort emergency condensation + archival pass firing before Claude Code's automatic context compaction (~95%).
- `implement.md` (modified) — phase-based conditional reference-loading logic in the "Read these references" section, keyed off `executionPhase`.
- `schemas/spec.schema.json` (modified) — adds `executionPhase` as an optional enum property (`poc | refactor | test | quality`); the `chat.coordinator`/`chat.reviewer` pointer objects remain defined here.
- `.metrics.jsonl` — append target for condensation events (shared with Spec 4).
- `.archive.<timestamp>.md`, `.tool-results/` — files/dirs created and cleaned up by the middleware.

**Observable signals**:
- PASS looks like:
  - After condensation, `wc -l chat.md` + `wc -l .progress.md` is well below the 2,000-line threshold.
  - `.archive.<timestamp>.md` exists and `diff` against the pre-condensation snapshot is empty.
  - `signals.jsonl` `md5sum` is unchanged before/after a middleware run.
  - Condensed `chat.md`/`.progress.md` still `grep`-match all preserved signal/marker strings and the `Goal`/`Learnings` headings.
  - All three `.ralph-state.json` chat read pointers (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`) are within bounds of condensed `chat.md` line count.
  - `.metrics.jsonl` has a new line with `event: condensation` and a `mode` field.
  - Reactive condensation fires when the transcript JSONL `message.usage` shows >85% context usage of the 200k window.
  - Evicted tool output: conversation text contains a `.tool-results/` path + line count; full file exists on disk.
  - After completion: `ls .archive.*.md` returns nothing; `.tool-results/` does not exist.
  - With `executionPhase: poc`, `implement.md` does not load `verification-layers.md` or `phase-rules.md`.
- FAIL looks like:
  - `signals.jsonl` modified or removed.
  - Any of the three chat read pointers points past the end of (or before valid content in) condensed `chat.md`.
  - A preserved signal/marker or the `Goal`/`Learnings` section missing after condensation.
  - No archive written before condensation, or archive content differs from pre-condensation state.
  - Ralph loop aborts when the spec directory is read-only.
  - Archives accumulate beyond 3, or archives/`.tool-results/` survive spec completion.
  - `chat.md` rewritten without holding `chat.md.lock`.

**Hard invariants**:
- `signals.jsonl` is NEVER condensed, evicted, truncated, or deleted by the middleware.
- The chat protocol never desyncs — all three pointers (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`) stay consistent with condensed `chat.md`; no message re-read or skipped by any session.
- All preserved signals/markers and stable `.progress.md` sections survive every condensation.
- The Ralph loop never crashes due to the middleware — read-only / write-failure paths degrade gracefully.
- No reference file is split, renamed, or moved (v0.1 scoping is conditional loading only).
- In-place condensation MUST keep `chat.md` byte-format-compatible with the chat protocol so a separately-running reviewer/executor session — including a non-Claude `external-reviewer` — can continue incremental reads. The `chat.md` rewrite and all three `.ralph-state.json` pointer updates happen atomically.
- Condensation MUST hold the `flock` on `chat.md.lock` (fd 200) — the same lock taken by the reviewer and executor — for the entire `chat.md` rewrite; in-place condensation never races a concurrent reader.

**Seed data**:
- A spec with `chat.md` + `.progress.md` exceeding 2,000 combined lines, containing at least one each of: a control signal, a collaboration signal, a pair-debug marker, and the `Goal`/`Learnings` sections.
- `.ralph-state.json` with a valid `phase` field and all three chat read pointers (`chat.coordinator.lastReadLine`, `chat.executor.lastReadLine`, `chat.reviewer.lastReadLine`) populated.
- A spec directory in read-only mode (separate fixture) to verify graceful degradation.
- Tool-output fixtures: a grep result >100 lines, a git diff >200 lines, a file read >500 lines, an ls/find >300 lines, plus one below-threshold sample of each.

**Dependency map**:
- Shares `.metrics.jsonl` with Spec 4 (loop-safety-infra).
- Reads/respects `signals.jsonl` and the three chat read pointers from Spec 6 (signal-log-and-ci-autodetect).
- Touches `stop-watcher.sh` and `implement.md` — also modified by Specs 4, 6, 8; regression-sweep these.
- Middleware-managed files (`.archive.*`, `.tool-results/`) interact with Spec 3 role contracts and Spec 9 risk classification.
- `executionPhase` is a new coordinator-owned state field in `.ralph-state.json` (enum `poc | refactor | test | quality`), defined as an optional property in `schemas/spec.schema.json`; written only by the coordinator, read by `implement.md` for reference scoping.

**Escalate if**:
- Condensation would drop content not covered by the preservation rules and the LLM is uncertain whether it is load-bearing.
- An overflow persists after reactive condensation + retry (indicates v0.2 patterns may be needed).
- A chat read pointer inconsistency (any of the three) cannot be reconciled with the condensed `chat.md`.
- `signals.jsonl` exclusion cannot be guaranteed for a given code path.
- Spec-completion cleanup would delete files outside the spec directory.

## Unresolved Questions

- RESOLVED (design interview + research): reactive trigger = transcript-JSONL `message.usage` token measurement + `PreCompact` hook fallback; not API-error interception. `stop-watcher.sh` reads `transcript_path` from stdin, tails the transcript JSONL, and computes `(input_tokens + cache_creation_input_tokens + cache_read_input_tokens) / 200000`; reactive condensation fires above ~85%.
- `.metrics.jsonl` event schema: exact field names for the condensation event line should align with the Spec 4 metrics schema — confirm during design.
- RESOLVED (design + user decision): the coarse `phase` field is insufficient; a new coordinator-written `executionPhase` enum field is added (FR-19). User-approved scope addition.
- Three-pointer reconciliation: condensing only messages older than `min(coordinator, executor, reviewer)` is safe but may rarely fire if one session lags far behind. Confirm in design whether a lagging-session policy (e.g. force-advancing a stale reviewer pointer) is needed, or whether the conservative min-prefix rule is sufficient for v0.1.

## Next Steps

1. User approves these requirements.
2. Run `/ralphharness:design` to produce the technical design (condensation algorithm, archive naming, eviction script interface, phase→reference mapping, reactive-trigger detection, `.metrics.jsonl` schema).
3. Run `/ralphharness:tasks` to break the design into POC-first tasks.
4. Run `/ralphharness:implement` to execute.

<!-- Changed: multi-session honesty pass — three-pointer chat-read reconciliation (FR-8, AC-1.6/1.8), eviction-as-prompt-rule (AC-3.5), coordinator-only scope qualifiers (FR-12, AC-4.6), chat.md.lock flock invariant (FR-18), and Out-of-Scope clauses for non-Claude/foreign-session context management. Corrections for honesty/correctness only; no scope expansion. -->
<!-- Changed: reactive-trigger correctness amendment — reactive condensation now triggered by real transcript-JSONL `message.usage` token measurement (>85% of 200k) plus a `PreCompact` hook fallback, replacing the unimplementable `context_length_exceeded` API-error interception (AC-2.1, AC-2.5, AC-2.6, FR-9, Verification Contract, Glossary). Two-gate model documented. Trigger mechanism corrected; reactive condensation feature scope unchanged. -->
<!-- Changed: authorization amendment — phase-based reference scoping now keyed off a new coordinator-written `executionPhase` enum field (`poc | refactor | test | quality`) instead of the coarse `phase` field (FR-12, AC-4.1, AC-4.2); added FR-19 + AC-4.7 for the field's coordinator-write contract, schema definition, and absent-field fallback; Verification Contract, Glossary, and Unresolved Questions updated. User-approved scope addition; no other scope expansion. -->

