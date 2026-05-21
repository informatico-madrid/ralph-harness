---
spec: rag-integration
basePath: specs/rag-integration
phase: requirements
created: 2026-05-20
source: _bmad-output/planning-artifacts/prd.md
---

# Requirements: rag-integration

## Goal

Add an opt-in Retrieval-Augmented Generation (RAG) layer to the RalphHarness
plugin so that every Ralph Loop phase (research, requirements, design, tasks,
execution, review) can retrieve relevant chunks from past specs and execution
memory (chat.md, task_review.md, signals.jsonl) instead of starting from zero
context each time. The MVP scope covers execution-phase retrieval (UC-1, UC-2,
UC-3, UC-4, UC-5); planning-phase retrieval (UC-6–UC-9) is post-MVP.

The integration MUST be backward-compatible: plugins without RAG configuration
continue to work unchanged, and any RAG failure (Qdrant unreachable, FAISS
index missing, embedder timeout) degrades gracefully to "no enrichment" rather
than blocking the loop.

## User Stories

### US-1: Senior Developer recovering past failure context
**As a** developer running a spec-executor task
**I want to** retrieve the root cause + fix from a past failure with the same error signature
**So that** a recurring 3-hour debug becomes a 2-minute resolution (PRD Journey 1, María)

**Acceptance Criteria:**
- [ ] AC-1.1: When a task fails (non-zero exit), the coordinator calls `python -m rag retrieve --query "<error>" --collection execution_memory --top-k 3` before the retry.
- [ ] AC-1.2: Retrieved chunks are injected into the next spec-executor prompt under a `## Past Solutions` block, each tagged with `spec`, `task`, and `commit_sha`.
- [ ] AC-1.3: If retrieval returns zero results or fails, the retry proceeds without enrichment — the loop never blocks on RAG.
- [ ] AC-1.4: Each retrieval appends one JSONL line to `~/.cache/smart-ralph/rag/retrieval-metrics.log` with `ts`, `op`, `spec`, `query_sha256` (NOT the raw query), `collection`, `top_k`, `provider_used`, `embedder_used`, `latency_ms`, `result_count`, `outcome`. Successful retrievals do NOT write to `signals.jsonl` (preserves signal economy — see design.md Observability section). Failed retrievals write to BOTH the log AND emit `RETRIEVAL_FAILED` to `signals.jsonl`.
- [ ] AC-1.5: Cross-project retrieval requires an explicit `rag.allow_cross_project: true` flag in `.ralphharness.local.md`; default is project-only.

### US-2: Junior Developer learning from execution memory
**As a** developer assigned to a task similar to a previously completed one
**I want to** read past task_review.md and chat.md entries surfaced as references
**So that** I can apply proven patterns instead of rediscovering them (PRD Journey 2, Alex)

**Acceptance Criteria:**
- [ ] AC-2.1: Before delegating a task, the coordinator calls `rag retrieve --query "<task description>" --collection specs_tasks --top-k 5`.
- [ ] AC-2.2: Returned chunks include source path (`specs/<name>/task_review.md#row-N` or `chat.md#msg-N`) so the developer can drill into the full context.
- [ ] AC-2.3: A retrieval result includes `relevance_score`; results below `min_relevance_score` (default 0.7) are dropped.
- [ ] AC-2.4: Chunks older than `staleness_threshold_days` (default 365) are still returned but tagged `stale: true` so the prompt can downweight them.

### US-3: DevOps/Platform Engineer deploying with mixed infrastructure
**As a** platform engineer rolling out Smart Ralph to multiple teams
**I want to** keep RAG opt-in per team with provider auto-detection
**So that** teams without Qdrant still get a working plugin and no team has to change workflow (PRD Journey 3, Jordan)

**Acceptance Criteria:**
- [ ] AC-3.1: Default configuration is `rag.enabled: false`; a project with no `rag` block in `.ralphharness.local.md` runs the loop with zero RAG calls and zero added latency.
- [ ] AC-3.2: When `rag.enabled: true` and `provider: qdrant` with no reachable endpoint, the service falls back to `faiss` if `faiss.index_path` exists locally, else returns empty results.
- [ ] AC-3.3: A new command `/ralphharness:rag-doctor` reports: enabled flag, provider, endpoint reachability, embedder availability, last index size, and recommends a config fix when any check fails.
- [ ] AC-3.4: Bulk indexing (`/ralphharness:index-all`) accepts `--dry-run` so an operator can preview what would be indexed without writing to the vector DB.

### US-4: On-call Support investigating a stuck execution
**As a** support engineer triaging a blocked spec
**I want to** retrieve past incidents with the same signal pattern (HOLD, DEADLOCK, PENDING) and root cause
**So that** I can identify whether the block has been seen before and how it was resolved (PRD Journey 4, Sam)

**Acceptance Criteria:**
- [ ] AC-4.1: A new command `/ralphharness:rag-search <query>` runs an interactive retrieval against all collections (specs_tasks, execution_memory, reviews) and prints results ranked by score.
- [ ] AC-4.2: Signal entries in `signals.jsonl` are indexable: the bulk indexer extracts `type`, `reason`, `taskIndex`, and `resolution` (if known) per signal event.
- [ ] AC-4.3: A retrieval against `signals.jsonl` returns the surrounding chat.md message (±2 messages) so the operator sees the conversation context, not just the signal.

### US-5: Plugin Maintainer adding new retrieval trigger
**As a** RalphHarness maintainer
**I want to** add a retrieval call from any agent via a single bash function `rag_retrieve`
**So that** new trigger points (e.g. pre-task, on-error, on-review) can be added without re-implementing the integration each time

**Acceptance Criteria:**
- [ ] AC-5.1: `lib-rag.sh` exposes a `rag_retrieve <query> <collection> <top_k>` function that wraps `python -m rag retrieve`, parses JSON, returns chunks on stdout as `path\tscore\tcontent\n`.
- [ ] AC-5.2: `rag_retrieve` enforces a 2-second hard timeout (configurable via `rag.retrieval.timeout_seconds`); on timeout it returns 0 chunks and logs WARN, never errors out.
- [ ] AC-5.3: The function is callable from any agent prompt via `$(rag_retrieve "$query" specs_tasks 5)` — no need to know which provider is active.

### US-6: New user installing RAG dependencies
**As a** developer enabling RAG for the first time
**I want to** run an interactive onboarding command that detects, explains, and helps me install each dependency
**So that** I don't have to read multiple docs to understand what's needed — I learn the architecture by installing it

**Acceptance Criteria:**
- [ ] AC-6.1: `/ralphharness:rag-onboard` runs an interactive step-by-step flow covering each dependency in order: Python 3.10+, Python packages (`qdrant-client`, `faiss-cpu`, `pyyaml`, `sentence-transformers`, `openai`), vector DB choice (Qdrant via Docker or FAISS local file), embedder choice (local / openai / azure), `.ralphharness.local.md` config, initial index, and final `rag-doctor` verification.
- [ ] AC-6.2: Each step (a) **detects** current state and prints `[OK]` / `[MISSING]` / `[UNKNOWN]`, (b) **explains** in one paragraph what the tool is and why RAG needs it, (c) prints the **exact install command** that would run, (d) **waits for user confirmation** (`[y]es / [n]o-skip / [r]etry-detect / [a]bort`) — no command runs without explicit `y`.
- [ ] AC-6.3: Onboarding is **idempotent** — on a second run where all components are already present, the flow prints `[OK]` for every step, prompts the user **zero times**, and exits within **5 seconds wall-clock**.
- [ ] AC-6.4: At the end, the flow runs `/ralphharness:rag-doctor` and displays the tiered report so the user sees a final pass/fail summary.
- [ ] AC-6.5: A failed step does **NOT** abort the flow — the loop auto-continues past a failed `verify()` and records `failed: <step-name> (reason)` in the final summary block. A step is **failed** when either (i) `verify()` returns False after the install command ran, OR (ii) the install command itself exited non-zero. The user may pre-emptively decline a step with `[n]` before any install is attempted (recorded as `skipped`, not `failed`). The user-facing prompt set is exactly `[y]es / [n]o-skip / [r]etry-detect / [a]bort`; there is no separate post-failure keystroke.
- [ ] AC-6.6: NO `sudo` commands are auto-suggested. System-package installs (e.g. Python itself) print a plain-text instruction telling the user to install manually using their distribution's package manager, without offering to execute it.

## Functional Requirements

| FR ID | Capability |
|-------|------------|
| FR-1 | A Python module `plugins/ralphharness/rag/` exposes a CLI `python -m rag <command>` with subcommands `retrieve`, `index`, `index-all`, `doctor`, `search`. |
| FR-2 | The `RAGService` class implements `retrieve(query, collection, top_k)` and `index(chunks, collection)` over a `VectorDBProvider` ABC. Concrete providers: `QdrantProvider`, `FAISSProvider`. |
| FR-3 | The `Embedder` ABC supports concrete implementations `OpenAIEmbedder`, `LocalEmbedder` (sentence-transformers), `AzureOpenAIEmbedder`. Provider chosen via config, with fallback chain. |
| FR-4 | Six logical collections exist with stable IDs: `specs_tasks`, `specs_requirements`, `specs_design`, `specs_research`, `execution_memory`, `reviews`. Collection names get a project-level prefix configured via `rag.qdrant.collection_prefix`. |
| FR-5 | Two control signals — `RETRIEVAL_FAILED` (with a `phase: "retrieval" \| "indexing"` payload field to disambiguate) and `INDEXING_QUEUED` — are appended to `signals.jsonl` via `lib-signals.sh`. Success retrievals do NOT emit signals; per-call telemetry is written to `~/.cache/smart-ralph/rag/retrieval-metrics.log` instead (see AC-1.4). |
| FR-6 | `/ralphharness:index-all [--force] [--dry-run]` scans `specs/` and indexes by chunking each artifact, streaming batches of 50 specs at a time. |
| FR-7 | Bash hook entry point `hooks/scripts/lib-rag.sh` exposes `rag_retrieve` (used by agent prompts and coordinator), `rag_index_task` (called post-task-complete), `rag_health_check` (called on session start). |
| FR-8 | A `SecurityLayer` scans chunks before indexing and rejects any chunk containing values matched by an allowlist of structured patterns (e.g. `AWS_ACCESS_KEY=`, `ssh-rsa`, `Bearer <token>`). |
| FR-9 | Each indexed chunk carries metadata: `spec_name`, `source_path`, `source_line_start`, `source_line_end`, `indexed_at` (ISO 8601), `content_hash` (sha256), `embedder_model`, `staleness_days`. |
| FR-10 | The `/ralphharness:rag-doctor` command verifies config validity, embedder reachability, vector DB reachability, last index timestamps, and prints a tiered report (OK/WARN/FAIL) per check. |
| FR-11 | A new `/ralphharness:rag-onboard` slash command runs an interactive step-by-step onboarding flow that detects, explains, and (with explicit per-step user confirmation) installs each RAG dependency. The flow ends by running `rag-doctor` and printing a summary block (`installed: N | skipped: M | already_present: K | failed: F`). |
| FR-12 | `rag/onboarding.py` exposes an `OnboardingStep` ABC with `detect() -> DetectionResult`, `explain() -> str`, `install_command() -> list[str] \| None` (argv list, NOT a shell string — passed directly to `subprocess.run(argv, shell=False)`), and `verify() -> bool` methods. `DetectionResult` is a dataclass `{state: DetectionState, detail: str}` where `DetectionState ∈ {OK, MISSING, UNKNOWN}`. Concrete steps in order: `PythonStep`, `PythonDepsStep`, `VectorDBStep`, `EmbedderStep`, `ConfigStep`, `IndexBootstrapStep`, `DoctorStep`. |

## Non-Functional Requirements

| NFR ID | Metric | Target |
|--------|--------|--------|
| NFR-1 | Retrieval latency (p95) | < 2.0 s end-to-end (bash call → JSON to stdout) |
| NFR-2 | Index update latency (p95) | < 5.0 s per task, asynchronous (does not block loop) |
| NFR-3 | Retrieval relevance | > 70% of top-3 results judged relevant. Measurement plan: maintainer samples 20 retrievals per release from `retrieval-metrics.log`, scores manually (relevant / not-relevant) against the original task or error. Documented in `specs/rag-integration/.progress.md` as a release-gate ritual. |
| NFR-4 | Memory ceiling | Bulk index never exceeds 4 GB resident RAM on a host with 8 GB free |
| NFR-5 | Graceful degradation | Any failure (timeout, connection error, embedder error) returns 0 chunks; the loop continues unchanged |
| NFR-6 | Backward compatibility | A spec with no `rag` config block runs with 0 extra subprocess calls and 0 extra signals emitted |
| NFR-7 | Security | Sanitization rejects chunks containing patterns from `rag/security_allowlist.yaml`; rejected chunks are logged but not indexed |
| NFR-8 | Rate limit | `/ralphharness:index-all` is bounded to 1 invocation per minute per project (file-lock based) |
| NFR-9 | Onboarding safety | Onboarding NEVER auto-executes destructive or `sudo` commands. Every install command requires an explicit `y` keystroke per step. System-package installs (e.g. Python itself) are described as manual instructions, not executable commands. **Secret handling:** OpenAI / Azure API keys collected during the embedder step are NEVER written to logs, NEVER echoed to stdout after entry, NEVER appended to `signals.jsonl`, NEVER appear in `retrieval-metrics.log`. Keys are stored only in `.ralphharness.local.md` (the existing per-project config file) and only when the user explicitly confirms the `ConfigStep` append. Assertion target: `grep -rE 'sk-[A-Za-z0-9]+' ~/.cache/smart-ralph/ specs/*/signals.jsonl` finds nothing after a full onboarding run with an OpenAI key. |
| NFR-10 | Onboarding UX | Onboarding completes in < 10 minutes on a **clean machine** with normal network. "Clean machine" is defined as: Ubuntu 22.04 (or equivalent) with Python 3.10 preinstalled, no Python packages installed in the active venv, no Docker images cached, network bandwidth ≥ 10 Mbps. Excludes the first-time `sentence-transformers` model download, which is shown to the user as an informational notice with the model name and approximate download size before the install prompt. |

## Out of Scope

- **UC-6 to UC-9 (planning-phase retrieval)** — pre-research, pre-requirements, pre-design, pre-tasks. Deferred to post-MVP because their value depends on having execution-memory volume first.
- **Cross-project retrieval beyond opt-in flag** — no team-level or org-level collection management. Each project has its own collection prefix.
- **Agentic RAG / autonomous retrieval decisions** — the MVP retrieves at fixed trigger points; the LLM does not decide when to retrieve.
- **HMAC-signed FAISS index files** — listed in PRD C-6 but deferred; the MVP relies on filesystem permissions + sanitization at index time.
- **Web UI / dashboard for RAG metrics** — out of scope for a CLI plugin; observability is via `signals.jsonl` and `rag-doctor`.
- **Reranking / query expansion** — vanilla top-k cosine similarity is the MVP; reranking is post-MVP.
- **Knowledge graph or relational metadata** — chunks are flat documents with metadata, not edges.

## Dependencies

### External services (optional, per config)
- **Qdrant server** — primary vector DB. Tested against Qdrant ≥ 1.7. Connection: HTTP REST + API key.
- **OpenAI embeddings API** — primary embedder if `provider: openai`. Model defaults to `text-embedding-3-small`.
- **Azure OpenAI** — alternative embedder if `provider: azure`. Requires endpoint, deployment name, and key.

### Python libraries
- `qdrant-client >= 1.7.0`
- `faiss-cpu >= 1.7.4` (or `faiss-gpu` if CUDA available)
- `sentence-transformers >= 2.5.0` (only loaded if `provider: local`)
- `pyyaml >= 6.0`
- `openai >= 1.0` (only loaded if `provider: openai`)

### Internal Smart Ralph dependencies
- `signals.jsonl` protocol (existing) — RAG signals reuse the schema and `lib-signals.sh` helpers.
- `lib-signals.sh` (existing) — `append_signal` function used for `RETRIEVAL_FAILED` and `INDEXING_QUEUED`.
- `.ralphharness.local.md` (existing pattern) — RAG config lives under a new `rag:` block; no migration of existing settings.
- `stop-watcher.sh` (existing) — RAG hooks attach via a new post-task helper, no edits to existing flow.

### Toolchain
- `python >= 3.10` available on `PATH` (the loop already requires `bash`, `jq`, `git`)
- `jq` (already required by plugin)
- `docker` — **optional**, used by `rag-onboard` to suggest running Qdrant locally (`docker run -d --name smart-ralph-qdrant -p 6333:6333 qdrant/qdrant:1.7.0`). If absent, onboarding falls through to the FAISS local-file path. The plugin never auto-installs Docker.
