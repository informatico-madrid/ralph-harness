---
spec: reviewer-warmup
basePath: specs/reviewer-warmup
phase: requirements
created: 2026-05-17
status: complete
---

# Requirements: reviewer-warmup

## Goal

Eliminate external-reviewer cold-start overhead (~30-40 min of false WARNING→FAIL→DEADLOCK per spec) by (1) emitting an executor liveness heartbeat to `signals.jsonl` the reviewer consults before escalating stagnation, and (2) replacing the reviewer's history-skipping bootstrap with a full spec-state read, packaged as an exportable skill.

## User Stories

### US-1: Executor liveness heartbeat
**As a** spec-executor
**I want to** emit a periodic liveness heartbeat to `signals.jsonl`
**So that** the reviewer can distinguish "executor reading design docs" from "executor stalled" and not raise a false DEADLOCK.

**Acceptance Criteria:**
- [ ] AC-1.1: Executor emits a `type:control` heartbeat event to `signals.jsonl` using the existing `ALIVE`/`STILL` signal vocabulary — NOT a new `READING` kind.
- [ ] AC-1.2: Each heartbeat carries a fresh `timestamp`, an `iteration`, and a `reason`/activity string (e.g. `"reading design.md"`, `"running tests"`).
- [ ] AC-1.3: Heartbeat emission is tied to CONCRETE triggers — at minimum: on entering the Do-steps of a task, and before/around a long Explore or design-doc read — NOT left to agent discretion.
- [ ] AC-1.4: The heartbeat is non-blocking: `active_signal_count()` continues to count only `HOLD|PENDING|URGENT|DEADLOCK`, so `ALIVE`/`STILL` are ignored by the HOLD gate. `lib-signals.sh` is not modified for this.
- [ ] AC-1.5: A heartbeat written through `append_signal()` passes `jq -e` JSON-shape validation and matches the documented `signals.jsonl` schema.
- [ ] AC-1.6: `spec-executor.md` `<flow>` and Signal Emission Contract document the heartbeat emission step and target file.

### US-2: Reviewer gates stagnation on heartbeat freshness
**As an** external-reviewer
**I want to** check the freshness of the newest executor heartbeat before escalating stagnation
**So that** a healthy long-running executor is not falsely escalated to DEADLOCK.

**Acceptance Criteria:**
- [ ] AC-2.1: `external-reviewer.md` Section 4 (Anti-Blockage) and Section 3b Step 6 (progress-real check) gate on heartbeat freshness instead of raw output silence.
- [ ] AC-2.2: A heartbeat newer than the staleness threshold SUPPRESSES a stagnation/DEADLOCK verdict; the reviewer logs that it is deferring escalation due to a fresh heartbeat.
- [ ] AC-2.3: Staleness threshold is TIME-BASED in minutes, with a stated, justified default (~10 min, larger than a realistic long design-doc read). The value is named explicitly so the design phase can refine it.
- [ ] AC-2.4: A genuine stall — the existing 3-round Convergence Detection (`external-reviewer.md` §4) reached with NO fresh heartbeat (newest heartbeat older than threshold) — STILL escalates to DEADLOCK. The freshness gate only suppresses a verdict (and the round is not counted) while the heartbeat is fresh; it never raises the round count needed to escalate.
- [ ] AC-2.5: The reviewer's real-bug detection (FABRICATION-class catches, schema mismatches, wrong version bumps, e2e anti-patterns) is unchanged by this story.

### US-3: Reviewer bootstrap reads full spec state
**As an** external-reviewer
**I want to** read the full existing spec state before review cycle 1
**So that** I start with a mental model instead of warming up over ~8 cycles.

**Acceptance Criteria:**
- [ ] AC-3.1: Before review cycle 1 the reviewer reads `chat.md` IN FULL (not just a HOLD/PENDING/DEADLOCK signal-scan), reads `.progress.md`, and reads recent `git log` / `git diff --stat` since the spec branch point.
- [ ] AC-3.2: The reviewer states a short spec-state mental model (what has happened so far) before starting cycle 1.
- [ ] AC-3.3: The bootstrap STOPS setting `chat.reviewer.lastReadLine` to the full chat.md line count (external-reviewer.md Section 0 line ~30). Existing history is processed (lastReadLine set to 0, or left so cycle 1 reads from the start).
- [ ] AC-3.4: Active HOLD/PENDING/DEADLOCK detection at bootstrap is preserved — those signals still defer or stop the review cycle.

### US-4: Reviewer rules exported as a skill
**As a** user running the external-reviewer in a foreign runtime (Roo Code / Qwen / Cursor)
**I want to** receive the reviewer bootstrap + heartbeat-freshness rules as an exportable skill
**So that** the reviewer behaves correctly even though it runs in a different Claude Code runtime.

**Acceptance Criteria:**
- [ ] AC-4.1: The bootstrap rules (US-3) and the reviewer-side heartbeat-freshness rules (US-2) are packaged as a single exportable SKILL.
- [ ] AC-4.2: The skill is the CANONICAL bootstrap doc; `external-reviewer.md` references it and stays consistent with it (single source of truth).
- [ ] AC-4.3: The export follows the existing pair-debug pattern (implement.md ~lines 375-382, `pair-debug.md` §Section 5): at onboarding/implementation time the user is offered (a) the absolute source path to copy manually, and (b) an "automatic copy" option that copies the skill into the foreign runtime's skills folder, resolving destinations from a runtime→path map.
- [ ] AC-4.4: On destination conflict, automatic copy prompts overwrite/skip per file (idempotent re-run). Unknown runtime falls back to manual print.

### US-5: Heartbeat documented consistently
**As a** maintainer
**I want to** the heartbeat usage documented in the chat legend, signals schema, and coordinator pattern
**So that** the new heartbeat behavior is discoverable and consistent.

**Acceptance Criteria:**
- [ ] AC-5.1: `chat.md` legend rows for `ALIVE`/`STILL` reflect their use as the executor liveness heartbeat in `signals.jsonl`.
- [ ] AC-5.2: The `signals.jsonl` schema comment documents heartbeat events (`signal:ALIVE`/`STILL`, `reason` = activity string).
- [ ] AC-5.3: `coordinator-pattern.md` signal table includes a heartbeat row noting it is non-blocking (ignored by the HOLD gate).

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | Executor emits `ALIVE`/`STILL` heartbeat to `signals.jsonl` on concrete triggers (enter Do-steps, before long reads) with timestamp/iteration/reason | High | AC-1.1–AC-1.3, AC-1.6 |
| FR-2 | Heartbeat events validate against `signals.jsonl` schema and remain non-blocking (`active_signal_count` unchanged) | High | AC-1.4, AC-1.5 |
| FR-3 | Reviewer stagnation logic (Section 4, Section 3b Step 6) gates on time-based heartbeat freshness | High | AC-2.1–AC-2.3 |
| FR-4 | Genuine stalls (existing 3-round Convergence Detection) with stale heartbeat still escalate to DEADLOCK | High | AC-2.4 |
| FR-5 | Reviewer bootstrap reads chat.md full + .progress.md + git; states mental model; stops the lastReadLine skip | High | AC-3.1–AC-3.4 |
| FR-6 | Bootstrap + heartbeat-freshness rules packaged as an exportable skill, canonical over external-reviewer.md | High | AC-4.1, AC-4.2 |
| FR-7 | Skill export reuses the pair-debug export pattern (manual path / automatic copy, runtime map, conflict prompt) | Medium | AC-4.3, AC-4.4 |
| FR-8 | Documentation updates: chat.md legend, signals.jsonl schema comment, coordinator-pattern.md table | Medium | AC-5.1–AC-5.3 |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Cold-start overhead reduction | False DEADLOCK escalations during early cycles | 0 false escalations when heartbeat fresh |
| NFR-2 | Heartbeat non-interference | HOLD gate behavior | Byte-identical: `active_signal_count` logic unchanged |
| NFR-3 | Single source of truth | Bootstrap rule divergence | external-reviewer.md and skill consistent; skill canonical |
| NFR-4 | No regression in detection | Real-bug catches (FABRICATION, schema, version) | Unaffected |
| NFR-5 | No build step | Artifact type | Markdown + shell only; `bash -n` clean on modified scripts |

## Verification Contract

**Project type**: `cli` — Claude Code plugin (markdown + shell artifacts; no UI, no HTTP endpoints, no build step). Per research §Verification Tooling, skip all VE/E2E tasks.

**Entry points**:
- `plugins/ralphharness/agents/spec-executor.md` — heartbeat emission step in `<flow>` + Signal Emission Contract.
- `plugins/ralphharness/agents/external-reviewer.md` — Section 0/1 bootstrap, Section 4 + Section 3b Step 6 stagnation gating; references the skill.
- New exportable reviewer skill (bootstrap + heartbeat-freshness rules).
- `plugins/ralphharness/commands/implement.md` — onboarding step offering the skill export (manual path / automatic copy).
- `signals.jsonl` — `ALIVE`/`STILL` heartbeat events.
- Docs: `templates/chat.md` legend, `templates/signals.jsonl` schema comment, `references/coordinator-pattern.md` signal table.

**Observable signals**:
- PASS looks like:
  - `signals.jsonl` contains `type:control`, `signal:ALIVE`/`STILL` events with fresh `timestamp`, `iteration`, `reason`; each line passes `jq -e`.
  - grep on `spec-executor.md` finds the heartbeat emission step tied to concrete triggers.
  - grep on the reviewer skill + `external-reviewer.md` finds the full-read bootstrap step AND the heartbeat-freshness gate with the named time threshold.
  - Scripted simulation: a `signals.jsonl` sequence with a heartbeat newer than threshold → reviewer suppresses stagnation; a sequence with the newest heartbeat older than threshold + 3 convergence rounds → reviewer escalates DEADLOCK.
  - `bash -n` clean on any modified `.sh`; `active_signal_count()` unchanged.
- FAIL looks like:
  - A new `READING` signal kind introduced (decision violated).
  - `active_signal_count()` modified to count `ALIVE`/`STILL` (heartbeat became blocking).
  - Bootstrap still sets `lastReadLine` to full line count (cold-start root cause not fixed).
  - Reviewer escalates DEADLOCK while a fresh heartbeat exists.
  - Reviewer fails to escalate after 3 convergence rounds with stale heartbeat.

**Hard invariants**:
- The HOLD gate (`active_signal_count`) NEVER counts the heartbeat — it stays non-blocking.
- Genuine stalls still reach DEADLOCK via the existing 3-round Convergence Detection.
- Reviewer real-bug detection (FABRICATION, schema mismatch, wrong version bump, e2e anti-patterns) unaffected.
- No second condensation path for `chat.md` is introduced.
- Active HOLD/PENDING/DEADLOCK detection at reviewer bootstrap preserved.

**Seed data**:
- A spec in `execution` phase with `tasks.md`, `.progress.md`, `chat.md`, `signals.jsonl`, `.ralph-state.json`.
- A `signals.jsonl` fixture with a sequence of `ALIVE`/`STILL` heartbeat events at known timestamps (one fresh, one stale) for the simulation.
- For bootstrap verification: a non-empty `chat.md` with prior history and a few git commits since branch point.

**Dependency map**:
- `context-middleware` — owns `chat.md`/`.progress.md` condensation (`condense-context.sh`, `lib-context.sh`). Reviewer full-read consumes whatever `chat.md` is (condensed or not). Shared file: `chat.md`.
- `agent-chat-protocol` — owns `chat.md` format + `ALIVE`/`STILL` legend. Shared file: `templates/chat.md`.
- `signal-log-and-ci-autodetect` — owns `signals.jsonl` + `lib-signals.sh`. Heartbeat rides the existing open enum; no migration. Shared files: `templates/signals.jsonl`, `lib-signals.sh`.
- `collaboration-resolution` — owns DEADLOCK resolution; this spec only reduces FALSE DEADLOCKs, genuine path unchanged.

**Escalate if**:
- The pair-debug runtime→path map cannot resolve a destination for a requested runtime (fall back to manual print, do not guess a path).
- A change would require modifying `active_signal_count()` or `condense-context.sh` (out of scope — stop and ask).
- The staleness threshold cannot be made larger than observed long-read durations without risking real-stall masking.

## Glossary

- **Cold-start**: the reviewer's ~30-40 min struggle phase at spec start, caused by reviewing with empty/skipped `chat.md` context.
- **Heartbeat**: a periodic `type:control` `ALIVE`/`STILL` event in `signals.jsonl` carrying a fresh timestamp + activity string, proving the executor is alive.
- **Heartbeat freshness / staleness**: the age (in minutes) of the newest heartbeat; below the threshold = fresh, above = stale.
- **Staleness threshold**: time-based cutoff (~10 min default) above which the reviewer is allowed to escalate stagnation.
- **HOLD gate**: the coordinator's mechanical `active_signal_count()` check that blocks delegation on active `HOLD/PENDING/URGENT/DEADLOCK`.
- **Bootstrap**: the reviewer's pre-cycle-1 phase (external-reviewer.md Section 0/1).
- **Exportable skill**: a skill artifact copied into a foreign runtime's skills folder via the pair-debug export pattern.
- **Genuine stall**: the existing 3-round Convergence Detection (`external-reviewer.md` §4) reached with no fresh heartbeat — a real, escalation-worthy block.

## Out of Scope

- `chat.md` trimming/compaction — ALREADY shipped by `context-middleware` (`condense-context.sh`, `lib-context.sh`, AC-1.1–AC-1.8). This spec DEPENDS ON it; it does not reimplement or modify it.
- Any change to `condense-context.sh` / `lib-context.sh`.
- Any change to `active_signal_count()` in `lib-signals.sh` — kept unchanged so the heartbeat stays non-blocking.
- Introducing a new `READING` signal kind — decided against; reuse `ALIVE`/`STILL`.
- A seeded digest/bootstrap file (variant b) — bootstrap is variant (a): full read of `chat.md` + `.progress.md` + git.
- The implementer-skip onboarding bug — already fixed in commit c62d964.
- Feeding the heartbeat into pair-debug auto-trigger logic — possible future work, not now.

## Dependencies

- **context-middleware** (shipped) — `chat.md`/`.progress.md` condensation. Bootstrap full-read composes with it; do not duplicate.
- **agent-chat-protocol** (shipped) — `chat.md` format and `ALIVE`/`STILL` legend; this spec updates the legend rows.
- **signal-log-and-ci-autodetect** (shipped) — `signals.jsonl` open enum + `lib-signals.sh` append/count helpers; heartbeat rides the existing enum, no migration.
- Existing pair-debug export pattern (`implement.md` ~lines 375-382, `references/pair-debug.md` §Section 5) — reused for the reviewer skill export.

## Success Criteria

- Zero false DEADLOCK escalations during early review cycles when the executor is alive and emitting heartbeats.
- Reviewer states a spec-state mental model before cycle 1 (no ~8-cycle warm-up).
- Genuine stalls still escalate to DEADLOCK via the existing 3-round Convergence Detection (regression guard holds).
- Heartbeat never affects the HOLD gate; `active_signal_count()` unchanged.
- Reviewer skill exports correctly via manual-path and automatic-copy modes; `external-reviewer.md` stays consistent with it.

## Unresolved Questions

- Exact heartbeat cadence within a long read phase (one per turn vs every N minutes) — design phase to pick; AC-1.3 only requires concrete triggers.
- Whether the heartbeat `reason` should also carry the current Do-step index so the reviewer can observe forward motion, not just liveness — recommended, design to confirm.
- Exact staleness threshold value — requirements set ~10 min as the justified default; design may refine after measuring real long-read durations.
- Skill naming and the precise runtime→path map entries to reuse from `pair-debug.md` §Section 5 — design phase.

## Next Steps

1. Approve requirements; proceed to `/ralphharness:design`.
2. Design the heartbeat event shape, emission triggers, and the reviewer freshness-gate algorithm.
3. Design the exportable reviewer skill structure and its reference relationship to `external-reviewer.md`.
4. Plan tasks with heartbeat (US-1/US-2) first, bootstrap + skill (US-3/US-4) second, docs (US-5) last; skip VE tasks.
