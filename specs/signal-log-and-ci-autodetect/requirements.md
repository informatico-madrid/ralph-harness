# Requirements: Signal Event Log + CI Auto-Detection

> Phase 6 of engine-roadmap-epic. Targets gaps **C2** (HOLD signals ignored — fragile grep over mutable Markdown) and **C4** (executor reports partial verification as complete — task verify vs global CI conflated). Adopts OpenHands' immutable event-log pattern and Deep Agents' marker-based auto-detection.

## Goal

Replace text-based HOLD detection with a mechanically-queryable `signals.jsonl` event log (immutable, append-only, status-explicit), and auto-detect project CI commands from filesystem markers so the engine can track **task-level verification separately from global CI snapshot** with no manual configuration.

---

## User Stories

### US-1 — Mechanical Control-Signal Detection (Gap C2)

**As a** coordinator / stop-watcher
**I want** active control signals queryable by structured field (`status="active"`) instead of grep over Markdown
**So that** HOLD/PENDING/URGENT/DEADLOCK detection is binary and impossible to misread as "no new messages"

**Acceptance Criteria:**
- **AC-1.1** `specs/<name>/signals.jsonl` is the single source of truth for control signals. One JSON object per line. Required fields: `type`, `signal`, `from`, `to`, `task`, `status`, `timestamp`, `reason`. Optional: `iteration`, `severity`.
- **AC-1.2** Active-signal query is the canonical check: `jq -c 'select(.status=="active") | select(.signal=="HOLD" or .signal=="PENDING" or .signal=="URGENT" or .signal=="DEADLOCK")' signals.jsonl`. Exit count > 0 → block delegation.
- **AC-1.3** Resolution is append-only: a follow-up event with same `task`+`signal` and `status="resolved"` supersedes the active one. Original event is never edited (OpenHands inmutability rule).
- **AC-1.4** Concurrent writes use `flock fd 202` on `signals.jsonl.lock`. fd 202 is distinct from chat.md (200) and tasks.md (201). Documented in `references/channel-map.md`.
- **AC-1.5** `signals.lastProcessedLine: integer` (default 0) added to `spec.schema.json` to track coordinator's read cursor — analogous to `chat.executor.lastReadLine`.
- **AC-1.6** If `jq` is unavailable, the engine falls back to `grep -c '"status":"active"' signals.jsonl` with a WARN line in `.progress.md`. Engine never crashes on missing `jq`.

### US-2 — Auto-Detected CI Commands With Category (Gap C4)

**As a** coordinator
**I want** CI commands discovered from project markers at spec start, classified by category (`lint` / `typecheck` / `test` / `build`)
**So that** the global CI snapshot can record per-category state separately from task verify, defeating the C4 fabrication pattern ("tests pass" while ruff/mypy fail)

**Acceptance Criteria:**
- **AC-2.1** `hooks/scripts/detect-ci-commands.sh <spec-path>` runs in `commands/implement.md` Step 3 (pre-loop), after state-integrity validation, before the loop body. Idempotent: re-running on an already-populated state is a no-op unless `--force` is passed.
- **AC-2.2** Marker matrix produces `{command, category}` entries:
  - `pyproject.toml` → `ruff check .` (lint), `ruff format --check .` (lint), `mypy .` (typecheck), `pytest` (test)
  - `package.json` scripts → respective `pnpm/yarn/npm` invocations (lock-file aware), categorized from script name
  - `Makefile` targets `lint:` / `test:` / `check:` → categorized accordingly
  - `Cargo.toml` → `cargo clippy` (lint), `cargo test` (test), `cargo fmt --check` (lint)
  - `go.mod` → `go vet ./...` (lint), `go test ./...` (test)
- **AC-2.3** Composes with existing `hooks/scripts/discover-ci.sh` (workflows + bats). Order: discover-ci → detect-ci → dedupe by `(command, category)` tuple → write.
- **AC-2.4** Every detected command is sanity-checked via `command -v <bin>`. Commands whose binary is missing are dropped with a WARN line; they never reach `.ralph-state.json`.
- **AC-2.5** `ciCommands` schema is upgraded from `string[]` to `array<{command: string, category: enum["lint","typecheck","test","build","other"]}>`. Migration: legacy string entries auto-converted to `{command, category: "other"}` on first read.
- **AC-2.6** If no markers match, the coordinator falls back to the Verification Contract block in `requirements.md`. Behavior is unchanged from current.

### US-3 — Channel Separation: Control vs Collaboration

**As an** external-reviewer / spec-executor / coordinator
**I want** control signals (mechanical, append-only) in `signals.jsonl` and collaboration prose (hypothesis, debate, findings) in `chat.md`
**So that** chat.md stays human-readable for collaboration (Phase 7 prep) while engine control stays machine-readable

**Acceptance Criteria:**
- **AC-3.1** Control signals routed to `signals.jsonl` (exclusive): HOLD, PENDING, URGENT, DEADLOCK, INTENT-FAIL, SPEC-ADJUSTMENT, SPEC-DEFICIENCY.
- **AC-3.2** Collaboration markers stay in `chat.md` (existing behavior): ACK, CONTINUE, OVER, CLOSE, ALIVE, STILL.
- **AC-3.3** `commands/implement.md` HOLD check (currently `grep -c '^\[HOLD\]$\|^\[PENDING\]$\|^\[URGENT\]$' chat.md`) is replaced by the AC-1.2 `jq` check. The replacement is **Verification Layer 2 (Signal)** in the canonical 5-layer pipeline (`references/verification-layers.md`).
- **AC-3.4** `hooks/scripts/stop-watcher.sh` reads `signals.jsonl` (not chat.md) for its HOLD gate — so the engine's two entry points (coordinator + stop hook) agree by construction.
- **AC-3.5** Agent contracts updated so each agent emits its own signals only: `external-reviewer` writes HOLD/PENDING/SPEC-ADJUSTMENT/SPEC-DEFICIENCY; `spec-executor` writes INTENT-FAIL; `coordinator` writes URGENT/DEADLOCK. Enforced via `references/coordinator-pattern.md` and each agent's `.md`.
- **AC-3.6** Legacy `[HOLD]` markers in existing chat.md files keep working via grep fallback for one release cycle. Migration note added to `templates/chat.md` signal legend pointing to signals.jsonl.

### US-4 — Auditability & Replay

**As a** developer reviewing a failed spec
**I want** the full ordered history of signals (emit + resolve + supersede)
**So that** I can replay the engine's control decisions without re-running the loop

**Acceptance Criteria:**
- **AC-4.1** `signals.jsonl` is append-only. Tests assert that any edit to existing lines fails review.
- **AC-4.2** Every event has `timestamp` in ISO-8601 UTC and `iteration` (global iteration count from `.ralph-state.json`). This makes "what did the engine see at iteration N?" trivially answerable.
- **AC-4.3** A helper `hooks/scripts/replay-signals.sh <spec-path> [--at-iteration N]` prints the active signal set as it stood at a given iteration — used in incident review.

---

## Functional Requirements

| ID    | Requirement                                                                                       | Priority | Maps To       |
|-------|---------------------------------------------------------------------------------------------------|----------|---------------|
| FR-1  | Create `templates/signals.jsonl` — header comment + example active/resolved pair                  | High     | AC-1.1        |
| FR-2  | Replace grep HOLD check in `commands/implement.md` with the AC-1.2 `jq` query                     | High     | AC-1.2, AC-3.3 |
| FR-3  | Create `hooks/scripts/detect-ci-commands.sh` (marker scan + `command -v` filter)                  | High     | AC-2.1–2.4    |
| FR-4  | Update `schemas/spec.schema.json`: add `signals.lastProcessedLine`; upgrade `ciCommands` shape    | High     | AC-1.5, AC-2.5 |
| FR-5  | Update `references/channel-map.md`: add `signals.jsonl` row (fd 202, writers, readers)            | High     | AC-1.4        |
| FR-6  | Update `references/verification-layers.md`: Layer 2 (Signal) now reads `signals.jsonl`            | High     | AC-3.3        |
| FR-7  | Update `hooks/scripts/stop-watcher.sh`: HOLD gate reads `signals.jsonl` via `jq` (grep fallback)  | High     | AC-3.4, AC-1.6 |
| FR-8  | Update agent `.md` contracts (`external-reviewer`, `spec-executor`, `coordinator-pattern`) for signal emission per AC-3.5 | High | AC-3.5 |
| FR-9  | Update `templates/chat.md` signal legend: control → `signals.jsonl`, collaboration stays          | Medium   | AC-3.2, AC-3.6 |
| FR-10 | Atomic-append snippet in `references/coordinator-pattern.md` using fd 202                         | High     | AC-1.4        |
| FR-11 | Compose `detect-ci-commands.sh` with existing `discover-ci.sh` (dedupe by tuple)                  | High     | AC-2.3        |
| FR-12 | CI snapshot consumer in coordinator records per-category result (lint/typecheck/test/build) in `.ralph-state.json` under `ciSnapshot` | High | AC-2.5, Gap C4 |
| FR-13 | Create `hooks/scripts/replay-signals.sh` for incident review                                      | Low      | AC-4.3        |
| FR-14 | `jq` availability check at engine bootstrap with grep fallback path                               | High     | AC-1.6        |

---

## Non-Functional Requirements

| ID     | Property         | Metric / Target                                                                       |
|--------|------------------|---------------------------------------------------------------------------------------|
| NFR-1  | Performance      | `jq` active-signal query < 50 ms for 1 000-line signals.jsonl                          |
| NFR-2  | Reliability      | HOLD false-positive rate = 0 (status-field filter, not text match)                    |
| NFR-3  | Portability      | Engine boots on systems without `jq` (grep fallback path, WARN logged once per run)   |
| NFR-4  | Auditability     | Replay `replay-signals.sh --at-iteration N` produces deterministic output             |
| NFR-5  | Concurrency      | No interleaved/torn writes under simultaneous coordinator + reviewer append           |
| NFR-6  | Backward compat  | Existing specs with legacy chat.md `[HOLD]` markers continue to be respected one release cycle |
| NFR-7  | Determinism      | `detect-ci-commands.sh` output is stable across runs (sorted, deduped)                |

---

## Glossary

- **signals.jsonl** — append-only JSON-Lines control event log per spec. Fields: `type`, `signal`, `from`, `to`, `task`, `status`, `timestamp`, `iteration`, `reason`.
- **Control signal** — engine-affecting marker (HOLD/PENDING/URGENT/DEADLOCK/INTENT-FAIL/SPEC-ADJUSTMENT/SPEC-DEFICIENCY). Lives in `signals.jsonl`.
- **Collaboration marker** — human-affordance markers (ACK/CONTINUE/OVER/CLOSE/ALIVE/STILL). Stays in `chat.md`.
- **CI snapshot** — global project health (per-category lint/typecheck/test/build results), recorded after each quality checkpoint, **distinct from** per-task verify.
- **Marker** — filesystem signal of toolchain (`pyproject.toml`, `package.json`, `Makefile`, `Cargo.toml`, `go.mod`).
- **discover-ci.sh** (existing) — extracts commands from `.github/workflows/*.yml` and `tests/*.bats`.
- **detect-ci-commands.sh** (new) — extracts commands from local project markers.

---

## Out of Scope

- chat.md deprecation or migration of legacy markers beyond the one-cycle grace window (Phase 7).
- Executing CI commands (only discovery + categorization here; running is Spec 4 territory).
- Signal condensation / archival to `.signals-archive/` — deferred (FR-13 is replay only).
- New collaboration signals (HYPOTHESIS, EXPERIMENT, etc.) — Phase 7 scope.

---

## Dependencies

- **Spec 1 (engine-state-hardening)** ✅ — supplies the grep-based HOLD check we replace and the schema we extend.
- **Spec 3 (role-boundaries)** ✅ — supplies the agent role contracts updated by AC-3.5.
- **Spec 4 (loop-safety-infra)** ✅ — supplies `ciCommands` field and CI-snapshot tracking we upgrade.

---

## Verification Contract

> Coordination protocol — engine-level. Project type: CLI tool / Coordination engine.

**Entry points**: `commands/implement.md` (Step 3 pre-loop + delegation gate), `hooks/scripts/stop-watcher.sh`, `signals.jsonl`, `.ralph-state.json`.

**Observable PASS**:
- `signals.jsonl` exists per active spec; `jq` active-signal count matches manual inspection.
- `.ralph-state.json.ciCommands` is non-empty for any project with at least one marker, every entry has `{command, category}`, every `command -v` succeeds.
- `ciSnapshot` in `.ralph-state.json` records per-category state after each quality checkpoint.
- Coordinator and stop-watcher reach the **same** HOLD verdict on the same spec state (no divergence).

**Observable FAIL**:
- `grep '^\[HOLD\]$' chat.md` finds active markers but `jq` reports 0 active (channel drift).
- Detected CI command's binary is absent on PATH yet present in `ciCommands`.
- `signals.jsonl` line edited in place (line N hash changes between iterations).
- Coordinator delegates while an active HOLD exists.

**Hard invariants**:
- `signals.jsonl` is append-only — any line whose hash mutates is a test failure.
- fd 202 is reserved exclusively for `signals.jsonl.lock`.
- Control signals never appear in `chat.md`; collaboration markers never appear in `signals.jsonl`.

**Seed data**: `templates/signals.jsonl` (empty file with explanatory header comment + one active/resolved example pair, commented out).

**Dependency map**: `chat.md` ↔ collaboration only; `signals.jsonl` ↔ engine control; `.ralph-state.json` ↔ `signals.lastProcessedLine` + `ciCommands` + `ciSnapshot`; `schemas/spec.schema.json` defines all three.

**Escalate if**: Malformed JSON line detected in `signals.jsonl` → emit DEADLOCK signal (in signals.jsonl, of course), block loop, require human to repair.

---

## Risks

| Risk                                                            | Likelihood | Impact | Mitigation                                                              |
|-----------------------------------------------------------------|-----------|--------|-------------------------------------------------------------------------|
| `jq` missing on host                                            | Low       | High   | NFR-3: grep fallback path; bootstrap warn                                |
| Agent writes malformed JSON                                     | Medium    | Medium | Template example; append helper validates with `jq -e .` before write   |
| Race on signals.jsonl (coordinator + reviewer)                  | Low       | Medium | flock fd 202 (FR-10)                                                     |
| `detect-ci-commands.sh` lists tool not installed                | Medium    | Low    | AC-2.4 `command -v` filter                                               |
| signals.jsonl grows unbounded on long specs                     | Low       | Low    | FR-13 replay-only; archival deferred                                     |
| Coordinator and stop-watcher disagree on HOLD                   | Low       | High   | Shared single source of truth (signals.jsonl) — by construction          |
