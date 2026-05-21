# RalphHarness Changelog

All notable changes to this project are documented here.

## [5.9.1] - 2026-05-21

### Fixed
- **Collection naming alignment**: Renamed collections (`past_research` → `specs_research`, `past_requirements` → `specs_requirements`, `past_design` → `specs_design`) to match canonical design.md specification (L205-212).
- **Stop-watcher hook stability**: Tightened VERIFICATION signal detection regex from word-boundary to line-anchored pattern (`^VERIFICATION_(FAIL|PASS|DEGRADED)[[:space:]]*$`). Prevents hook from re-firing on signal token mentions in prose, which trapped sessions in infinite escalation loops.
- **Deadlock resolution**: Removed stale `.ralph-state.json` to sync with completed tasks (74/74 [x]). Appended `DEADLOCK_RESOLVED` signal to signals.jsonl for audit trail.

### Changed
- Verified all 5 stale WARNINGs in task_review.md: sentence-transformers installed (v5.5.1), shellcheck absence noted as env constraint, full pytest suite green (54 passed, 3 skipped).

---

## [5.9.0] - 2026-05-20

### Added
- **Complete RAG integration (Phase 6)**: Retrieval-augmented generation layer enriches execution context with past spec data.
  - `QdrantProvider` (primary) + `FAISSProvider` (fallback) for vector storage.
  - Embedder chain: local (sentence-transformers) → OpenAI → Azure with graceful degradation.
  - Pre-task retrieval in stop-watcher; post-task async indexing via `post-task-rag.sh`.
  - Pre-phase retrieval in research, requirements, design commands.
  - On-error retrieval in repair loop; on-review retrieval in external-reviewer.
- **New commands**:
  - `/ralphharness:rag-onboard` — Interactive 7-step RAG installer with Qdrant/FAISS setup, embedder auto-detection, fallback chain configuration.
  - `/ralphharness:rag-doctor` — Tiered health check (OK/WARN/FAIL) for RAG config, vector DB connectivity, embedder availability.
  - `/ralphharness:rag-search` — Human-operator triage tool, queries across all collections, colored ranked output with source paths.
  - `/ralphharness:index-all` — Bulk indexing for all 6 canonical collections (specs_research, specs_requirements, specs_design, specs_tasks, execution_memory, reviews) with flock rate-limiting (1/min).
- **Security & observability**:
  - SHA-256 hashed queries in telemetry (raw queries never logged).
  - Content sanitization against security allowlist patterns.
  - Per-call metrics in retrieval-metrics.log with provider/embedder source tracking.
  - Append-only signal event log (signals.jsonl) with RETRIEVAL_FAILED, INDEXING_QUEUED signals.
- **Configuration**: RAG config via `.ralphharness.local.md` with nested YAML (provider, embeddings, vector_db, faiss blocks).

### Changed
- Plugin version: 5.8.0 → 5.9.0.
- Graceful degradation: when RAG disabled or unavailable, zero overhead; loop functions identically.

### Tests
- 54 pytest tests (Phase 6.D integration test against real Qdrant, per-spec signal emission, YAML nested config, telemetry).
- bats e2e wiring test for harness integration.
- 100% pass rate; 3 skipped (VE submode deferred).

---

## [5.8.0] - Earlier

Initial stable release of core spec-driven workflow (research, requirements, design, tasks, autonomous execution, epic triage). RAG integration not yet added.

---

### Notes

- **RAG is opt-in**: Disabled by default. Enable via `/ralphharness:rag-onboard` or manual config.
- **Collection naming**: Six canonical collections per design.md (specs_*: research, requirements, design, tasks, execution_memory, reviews).
- **Telemetry**: Metrics logged to retrieval-metrics.log (anonymized). Rejections logged to sanitization-rejections.log.
