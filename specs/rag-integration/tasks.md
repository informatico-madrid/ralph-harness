---
spec: rag-integration
basePath: specs/rag-integration
phase: tasks
created: 2026-05-20
granularity: fine
total_tasks: 54
---

# Tasks: rag-integration

Add an opt-in Python RAG layer to the bash plugin via a CLI boundary
(`python -m rag …`). POC-first 5-phase plan. The plugin remains fully
functional with RAG disabled at every step — every task in Phase 1 must
satisfy that invariant. Each phase ends with a `[VERIFY] Phase X exit gate`
that the existing harness-enforcement-gates infrastructure picks up.

## Phase 1: Make It Work (POC)

Goal: a working `rag_retrieve` round-trip from bash through Python to a
running Qdrant, returning a chunk; with FAISS fallback and the
embedder fallback chain in place. Skip dedicated test suites — verify
with direct shell smoke tests against ad-hoc fixtures.

- [x] 1.1 Scaffold `plugins/ralphharness/rag/` Python module
  - **Do**:
    1. Create directory `plugins/ralphharness/rag/` with `__init__.py` (empty) and `__main__.py` (argparse skeleton with `retrieve`, `index`, `index-all`, `doctor`, `search`, `onboard` subcommands that each print `{"stub": true}` and exit 0).
    2. Add module docstring referencing `specs/rag-integration/design.md` (Components 1–9).
  - **Files**: `plugins/ralphharness/rag/__init__.py`, `plugins/ralphharness/rag/__main__.py`
  - **Done when**: `python -m plugins.ralphharness.rag retrieve --query x --collection y --top-k 1` prints `{"stub": true}` and exits 0.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag doctor 2>&1 | grep -q '"stub": true' && echo PASS`
  - **Commit**: `feat(rag): scaffold python rag module with CLI stubs`
  - _Requirements: FR-1_
  - _Design: Component 2_

- [x] 1.2 Implement `rag/config.py` with `RAGConfig.load()`
  - **Do**:
    1. `RAGConfig` dataclass mirroring the YAML schema in design.md (Interfaces section).
    2. `RAGConfig.load(path: Path | None) -> RAGConfig` parses the YAML frontmatter from `.ralphharness.local.md`; returns default-disabled config if file absent or no `rag:` block.
    3. `RAGConfig.enabled` property is the single source of truth.
  - **Files**: `plugins/ralphharness/rag/config.py`
  - **Done when**: With no `.ralphharness.local.md`, `RAGConfig.load().enabled == False`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.config import RAGConfig; print(RAGConfig.load().enabled)" | grep -q False && echo PASS`
  - **Commit**: `feat(rag): RAGConfig with default-disabled semantics`
  - _Requirements: FR-1, NFR-6_
  - _Design: Component 3, Interfaces — Configuration_

- [x] 1.3 Wire `doctor` subcommand to print real config
  - **Do**:
    1. In `__main__.py doctor`, instantiate `RAGConfig.load()` and print a tiered YAML report (`OK`/`WARN`/`FAIL` per check) covering `enabled`, `provider`, `embeddings.provider`, `endpoints_present`.
    2. Exit 0 always (doctor is informational).
  - **Files**: `plugins/ralphharness/rag/__main__.py`
  - **Done when**: `python -m … doctor` prints `enabled: false` for a project with no config.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag doctor | grep -q 'enabled: false' && echo PASS`
  - **Commit**: `feat(rag): doctor subcommand reports real config`
  - _Requirements: FR-10_
  - _Design: Component 2_

- [x] 1.4 [VERIFY] Phase 1.A checkpoint: Python module bootstraps clean
  - **Do**: Run `python -m … doctor`, `retrieve`, `index`, `index-all`, `search`, `onboard` once each; confirm all exit 0 and produce parseable output.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && for cmd in doctor "retrieve --query x --collection y --top-k 1" "index --source /dev/null --collection y --spec-name z" "index-all --dry-run" "search --query x" "onboard --non-interactive"; do PYTHONPATH=. python -m plugins.ralphharness.rag $cmd >/dev/null || exit 1; done && echo PASS`
  - **Done when**: All six subcommands exit 0.
  - **Commit**: `chore(rag): pass phase 1.A checkpoint`

- [x] 1.5 Define ABCs (`VectorDBProvider`, `Embedder`) and `Chunk` type
  - **Do**:
    1. `rag/providers/base.py` — `VectorDBProvider` ABC with `retrieve`, `index`, `health_check`.
    2. `rag/embedder/base.py` — `Embedder` ABC with `embed`, `embed_batch`, `dimensions` property; `EmbedderError` class.
    3. `rag/types.py` — `Chunk` dataclass matching the JSON shape in design.md Component 2 (id, content_hash, content, score, source_path, source_line_start/end, spec_name, indexed_at, staleness_days, embedder_model, stale).
  - **Files**: `rag/providers/base.py`, `rag/embedder/base.py`, `rag/types.py`
  - **Done when**: ABCs cannot be instantiated; `Chunk` fields match design.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.providers.base import VectorDBProvider; VectorDBProvider()" 2>&1 | grep -q 'abstract' && echo PASS`
  - **Commit**: `feat(rag): VectorDBProvider and Embedder ABCs + Chunk type`
  - _Requirements: FR-2, FR-3, FR-9_
  - _Design: Components 4, 5_

- [x] 1.6 Implement `LocalEmbedder` over sentence-transformers
  - **Do**:
    1. `rag/embedder/local.py` — `LocalEmbedder` with lazy import of `sentence_transformers`.
    2. Default model `BAAI/bge-small-en-v1.5` (384-dim).
    3. `embed_batch` chunks input into batches of 32; cache model load in `__init__`.
  - **Files**: `rag/embedder/local.py`
  - **Done when**: `LocalEmbedder().embed("hello")` returns a 384-element list of floats.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.embedder.local import LocalEmbedder; v = LocalEmbedder().embed('hello'); print(len(v))" | grep -q 384 && echo PASS` (skip if sentence-transformers missing: exit 0 with WARN)
  - **Commit**: `feat(rag): LocalEmbedder via sentence-transformers (lazy)`
  - _Requirements: FR-3_
  - _Design: Component 5_

- [x] 1.7 Implement `OpenAIEmbedder`
  - **Do**:
    1. `rag/embedder/openai.py` — `OpenAIEmbedder(api_key, model)` with lazy import of `openai`.
    2. Default model `text-embedding-3-small` (1536-dim).
    3. Raise `EmbedderError` on auth/rate-limit/network failure (caught by fallback chain).
  - **Files**: `rag/embedder/openai.py`
  - **Done when**: With invalid key, `embed("hello")` raises `EmbedderError` (not a network exception).
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.embedder.openai import OpenAIEmbedder; from plugins.ralphharness.rag.embedder.base import EmbedderError
try: OpenAIEmbedder('bad-key', 'text-embedding-3-small').embed('x')
except EmbedderError: print('PASS')" | grep -q PASS && echo PASS`
  - **Commit**: `feat(rag): OpenAIEmbedder with EmbedderError normalisation`
  - _Requirements: FR-3_
  - _Design: Component 5, Decision #5_

- [x] 1.8 Implement `AzureOpenAIEmbedder` (stub if endpoint unset)
  - **Do**:
    1. `rag/embedder/azure.py` — `AzureOpenAIEmbedder(endpoint, deployment_name, api_key)`.
    2. If `endpoint == ""`, `embed()` raises `EmbedderError("azure not configured")` immediately (fallback chain skips it silently).
    3. Otherwise wraps `openai.AzureOpenAI`.
  - **Files**: `rag/embedder/azure.py`
  - **Done when**: With empty endpoint, `embed("hello")` raises `EmbedderError`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.embedder.azure import AzureOpenAIEmbedder; from plugins.ralphharness.rag.embedder.base import EmbedderError
try: AzureOpenAIEmbedder('', '', '').embed('x')
except EmbedderError: print('PASS')" | grep -q PASS && echo PASS`
  - **Commit**: `feat(rag): AzureOpenAIEmbedder with silent-skip when unconfigured`
  - _Requirements: FR-3_
  - _Design: Component 5, Decision #5_

- [x] 1.9 Implement `EmbedderChain` (fallback per `[local, openai, azure]`)
  - **Do**:
    1. `rag/embedder/chain.py` — `EmbedderChain(order: list[Embedder])`.
    2. `embed`/`embed_batch` try each embedder in order; on `EmbedderError`, log WARN and try next; all exhausted raises `EmbedderError("chain exhausted")`.
    3. Wire `from_config(config)` factory to build the chain from `rag.embeddings.fallback_order`.
  - **Files**: `rag/embedder/chain.py`
  - **Done when**: Chain with `[OpenAIEmbedder(bad-key), LocalEmbedder()]` returns a vector via local fallback.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.embedder.chain import EmbedderChain; from plugins.ralphharness.rag.embedder.openai import OpenAIEmbedder; from plugins.ralphharness.rag.embedder.local import LocalEmbedder; print(len(EmbedderChain([OpenAIEmbedder('bad', 'text-embedding-3-small'), LocalEmbedder()]).embed('x')))" | grep -qE '^[0-9]+$' && echo PASS`
  - **Commit**: `feat(rag): EmbedderChain with [local, openai, azure] fallback`
  - _Requirements: FR-3, NFR-5_
  - _Design: Component 5, Decision #5_

- [x] 1.10 [VERIFY] Phase 1.B checkpoint: embedder fallback chain works
  - **Do**: Import chain, assert exhaustion raises.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.embedder.chain import EmbedderChain; from plugins.ralphharness.rag.embedder.base import EmbedderError
try: EmbedderChain([]).embed('x')
except EmbedderError: print('PASS')" | grep -q PASS && echo PASS`
  - **Done when**: Empty chain raises `EmbedderError`.
  - **Commit**: `chore(rag): pass phase 1.B checkpoint`

- [x] 1.11 Implement `QdrantProvider` (health_check first)
  - **Do**:
    1. `rag/providers/qdrant.py` — `QdrantProvider(endpoint, api_key, prefix)`.
    2. `health_check()` performs `qdrant_client.QdrantClient.get_collections()`; True on success, False on any exception.
    3. Real `retrieve`/`index` stubs in this task; full impl in 1.13.
  - **Files**: `rag/providers/qdrant.py`
  - **Done when**: `QdrantProvider("http://localhost:9999", "", "smart-ralph-test-").health_check()` returns False when no Qdrant is running.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.providers.qdrant import QdrantProvider; print(QdrantProvider('http://localhost:9999', '', 'smart-ralph-test-').health_check())" | grep -q False && echo PASS`
  - **Commit**: `feat(rag): QdrantProvider with health_check`
  - _Requirements: FR-2_
  - _Design: Component 4_

- [ ] 1.12 Implement `FAISSProvider` (read-only fallback)
  - **Do**:
    1. `rag/providers/faiss.py` — `FAISSProvider(index_dir, allow_write=False)`.
    2. `retrieve(query_vec, collection, top_k)` loads `index_dir/{project}/{collection}.index` + `.metadata.jsonl` if present; returns top-k by cosine; empty if missing.
    3. `index()` raises `NotImplementedError` unless `allow_write=True` (MVP read-only per Decision #4).
    4. `health_check()` returns True if `index_dir` is readable.
  - **Files**: `rag/providers/faiss.py`
  - **Done when**: `FAISSProvider("/nonexistent")` `retrieve` returns `[]`; `index(...)` raises `NotImplementedError`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.providers.faiss import FAISSProvider; p = FAISSProvider('/tmp/nope-$$'); assert p.retrieve([0.1]*384, 'c', 3) == []; print('PASS')" | grep -q PASS && echo PASS`
  - **Commit**: `feat(rag): FAISSProvider read-only fallback`
  - _Requirements: FR-2, NFR-5_
  - _Design: Component 4, Decision #4_

- [ ] 1.13 Implement `RAGService` facade with graceful retrieve
  - **Do**:
    1. `rag/service.py` — `RAGService(config)` builds provider (Qdrant primary; falls back to FAISS on Qdrant `health_check==False`) + embedder chain.
    2. `retrieve(query, collection, top_k)` — embed → `provider.retrieve` → return list. Catch ALL exceptions, log WARN, return `[]`.
    3. `from_config()` classmethod returns instance or `None` when `enabled==False`.
  - **Files**: `rag/service.py`
  - **Done when**: `RAGService.from_config()` returns `None` with no config; instance does not raise on `retrieve()` even if provider unreachable.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.service import RAGService; print(RAGService.from_config())" | grep -q None && echo PASS`
  - **Commit**: `feat(rag): RAGService facade with Qdrant→FAISS fallback`
  - _Requirements: FR-2, NFR-5, NFR-6_
  - _Design: Component 3, Decision #4_

- [ ] 1.14 Write per-call telemetry to `retrieval-metrics.log` (Python)
  - **Do**:
    1. `rag/observability.py` — `record_metric(op, spec, query, collection, top_k, provider, embedder, latency_ms, result_count, outcome)`.
    2. Hashes `query` with sha256 (NEVER logs raw query); appends one JSONL line to `~/.cache/smart-ralph/rag/retrieval-metrics.log`.
    3. Wire into `RAGService.retrieve()` (timed call) and `RAGService.index()`.
  - **Files**: `rag/observability.py`, `rag/service.py`
  - **Done when**: One successful retrieve appends one JSONL line with `outcome: "ok"` and `query_sha256` (not the raw query) to the metrics log.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && XDG_CACHE_HOME=/tmp/rag-metrics-$$ PYTHONPATH=. python -c "from plugins.ralphharness.rag.observability import record_metric; record_metric('retrieve', 'rag-integration', 'hello', 'execution_memory', 3, 'qdrant', 'local', 142, 3, 'ok')" && grep -q '"query_sha256"' /tmp/rag-metrics-$$/smart-ralph/rag/retrieval-metrics.log && ! grep -q '"hello"' /tmp/rag-metrics-$$/smart-ralph/rag/retrieval-metrics.log && echo PASS`
  - **Commit**: `feat(rag): retrieval-metrics.log telemetry (query hashed, never raw)`
  - _Requirements: AC-1.4, FR-5_
  - _Design: Observability section_

- [ ] 1.15 Wire `retrieve` subcommand end-to-end
  - **Do**:
    1. In `__main__.py retrieve`: instantiate `RAGService.from_config()`; if None or `service.retrieve(...)` empty, print `[]` and exit 0.
    2. Otherwise print JSON envelope `{provider_used, embedder_used, latency_ms, results: [Chunk...]}`.
  - **Files**: `plugins/ralphharness/rag/__main__.py`
  - **Done when**: `python -m … retrieve --query x --collection y --top-k 1` prints `[]` (no Qdrant) and exits 0.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag retrieve --query x --collection y --top-k 1 | grep -q '^\[\]$' && echo PASS`
  - **Commit**: `feat(rag): retrieve subcommand returns [] gracefully when disabled`
  - _Requirements: FR-1, NFR-5_
  - _Design: Component 2, Flow 2_

- [ ] 1.16 Create `lib-rag.sh` with `rag_enabled` + `rag_retrieve` + disabled-path metrics
  - **Do**:
    1. `plugins/ralphharness/hooks/scripts/lib-rag.sh` — shebang, `set -euo pipefail`.
    2. `rag_enabled()` caches result in `RAG_ENABLED_CACHE` env var; reads `.ralphharness.local.md` once per shell.
    3. `rag_retrieve QUERY COLLECTION TOP_K`:
       - If disabled, write one JSONL line `{"op":"retrieve","outcome":"disabled",...,"query_sha256":<sha256>}` to `~/.cache/smart-ralph/rag/retrieval-metrics.log` (no raw query), echo nothing, return 0.
       - If enabled: `timeout 2s python -m … retrieve …`; on timeout/error echo nothing.
    4. Parse JSON envelope via `jq` into TSV `path\tscore\tcontent\n`.
  - **Files**: `plugins/ralphharness/hooks/scripts/lib-rag.sh`
  - **Done when**: With no config, `rag_retrieve x y 1` echoes nothing, returns 0, AND writes a `"disabled"` line to the metrics log.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && XDG_CACHE_HOME=/tmp/rag-bash-$$ bash -c 'source plugins/ralphharness/hooks/scripts/lib-rag.sh && rag_retrieve x y 1; grep -q "\"outcome\":\"disabled\"" /tmp/rag-bash-$$/smart-ralph/rag/retrieval-metrics.log && echo PASS'`
  - **Commit**: `feat(rag): lib-rag.sh entry point with disabled-path telemetry`
  - _Requirements: FR-7, NFR-1, NFR-5, AC-1.4_
  - _Design: Component 1, Observability section_

- [ ] 1.17 [VERIFY] Phase 1 exit gate: end-to-end disabled path, zero signals
  - **Do**: Confirm a full Ralph Loop iteration with NO `.ralphharness.local.md` makes zero `python -m rag` subprocess calls and zero new signals.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && bash -c 'source plugins/ralphharness/hooks/scripts/lib-rag.sh && start_sig=$(wc -l < specs/rag-integration/signals.jsonl 2>/dev/null || echo 0); for i in 1 2 3; do rag_retrieve "q$i" specs_tasks 5 >/dev/null; done; end_sig=$(wc -l < specs/rag-integration/signals.jsonl 2>/dev/null || echo 0); test "$start_sig" = "$end_sig" && echo PASS'`
  - **Done when**: Zero signals emitted; all retrievals return empty.
  - **Commit**: `chore(rag): pass phase 1 exit gate`

## Phase 2: Refactoring

Goal: clean up the POC. Extract chunker, add security layer, centralise
signal emission with the `phase` field. No new functionality.

- [ ] 2.1 Extract `rag/chunker.py` with per-artifact strategies
  - **Do**:
    1. `Chunker.chunk(source_path, content) -> list[Chunk]` dispatches by file extension / name (design.md Component 7 table).
    2. Markdown chunker splits on `^## ` and `^### ` boundaries, 800-token target, 100-token overlap, **using the active embedder's tokenizer** (per Decision #11).
    3. JSONL chunker emits one chunk per line.
    4. Each chunk carries accurate `source_line_start`/`source_line_end`.
  - **Files**: `rag/chunker.py`
  - **Done when**: Chunker produces non-empty chunks for `specs/rag-integration/requirements.md`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.chunker import Chunker; chunks = Chunker().chunk('specs/rag-integration/requirements.md', open('specs/rag-integration/requirements.md').read()); print(len(chunks))" | grep -qE '^[1-9]' && echo PASS`
  - **Commit**: `refactor(rag): Chunker with per-artifact splitters + embedder tokenizer`
  - _Requirements: FR-9_
  - _Design: Component 7, Decision #11_

- [ ] 2.2 Add `SecurityLayer` with allowlist sanitisation
  - **Do**:
    1. `rag/security_allowlist.yaml` — initial patterns from design Component 6 (AWS, SSH, Bearer, Slack, GitHub PAT).
    2. `rag/security.py` — `SecurityLayer.sanitize(chunk) -> SanitizationResult`.
    3. Rejection log path: `~/.cache/smart-ralph/rag/sanitization-rejections.log` (NEVER stdout, NEVER signals).
  - **Files**: `rag/security.py`, `rag/security_allowlist.yaml`
  - **Done when**: A chunk containing `AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE` is rejected; secret never appears in stdout or return value.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.security import SecurityLayer; from plugins.ralphharness.rag.types import Chunk; c = Chunk(id='x', content_hash='h', content='AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE', score=0, source_path='', source_line_start=0, source_line_end=0, spec_name='', indexed_at='', staleness_days=0, embedder_model='', stale=False); r = SecurityLayer().sanitize(c); print(r.accepted)" 2>&1 | grep -q False && echo PASS`
  - **Commit**: `refactor(rag): SecurityLayer with allowlist + offline rejection log`
  - _Requirements: FR-8, NFR-7_
  - _Design: Component 6_

- [ ] 2.3 Centralise signal emission in `rag/signals.py` (with `phase` field)
  - **Do**:
    1. `rag/signals.py` — `emit_retrieval_failed(spec_path, reason, phase)` where `phase: Literal["retrieval", "indexing"]`; and `emit_indexing_queued(spec_path, spec_name, chunk_count)`.
    2. Both shell out to `bash -c "source lib-signals.sh && append_signal …"` to reuse the existing helper.
    3. `RAGService.retrieve()` calls `emit_retrieval_failed(..., phase="retrieval")` on exception path; `RAGService.index()` calls `emit_indexing_queued` on success and `emit_retrieval_failed(..., phase="indexing")` on failure.
  - **Files**: `rag/signals.py`, `rag/service.py`
  - **Done when**: A failed retrieve under an active spec appends one `RETRIEVAL_FAILED` line with `"phase":"retrieval"` to that spec's `signals.jsonl`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && SPEC=rag-integration && PYTHONPATH=. python -c "from plugins.ralphharness.rag.signals import emit_retrieval_failed; emit_retrieval_failed('specs/'+'$SPEC', 'test', 'retrieval')" && tail -1 "specs/$SPEC/signals.jsonl" | grep -q '"phase":"retrieval"' && echo PASS`
  - **Commit**: `refactor(rag): RAG signals carry phase field (retrieval|indexing)`
  - _Requirements: FR-5_
  - _Design: Component 3, Decision #8, Flow 1, Flow 2_

- [ ] 2.4 [VERIFY] Phase 2 exit gate: refactor leaves disabled path unchanged
  - **Do**: Re-run Phase 1.17 smoke. Confirm `lib-rag.sh` still emits 0 signals when disabled and the metrics log still records `"disabled"`.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && bash -c 'source plugins/ralphharness/hooks/scripts/lib-rag.sh && rag_retrieve x y 1; PYTHONPATH=. python -m plugins.ralphharness.rag retrieve --query x --collection y --top-k 1 | grep -q "^\[\]$" && echo PASS'`
  - **Done when**: Disabled path still returns `[]` instantly; zero signals.
  - **Commit**: `chore(rag): pass phase 2 exit gate`

## Phase 3: Testing

Goal: unit tests for each component, an integration test against a real
Qdrant (skipped if unavailable), and bats suites for `lib-rag.sh` and
the post-task helper.

- [ ] 3.1 Create `conftest.py` with shared fixtures
  - **Do**:
    1. `rag/tests/conftest.py` with fixtures: `fake_qdrant_client` (in-memory dict-backed fake matching `QdrantClient`'s `get_collections`, `recreate_collection`, `upsert`, `search`); `stub_embedder` (hash-derived deterministic vector); `sample_chunks` (5 per collection); `sample_signals_jsonl` (one of each signal type + `RETRIEVAL_FAILED` placeholder); `xdg_cache_tmp` (autouse, redirects `XDG_CACHE_HOME` to `tmp_path`).
  - **Files**: `rag/tests/__init__.py`, `rag/tests/conftest.py`
  - **Done when**: `pytest --fixtures` lists all five fixtures by name.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && out=$(PYTHONPATH=. python -m pytest --fixtures plugins/ralphharness/rag/tests/ 2>&1) && for fx in fake_qdrant_client stub_embedder sample_chunks sample_signals_jsonl xdg_cache_tmp; do echo "$out" | grep -q "$fx" || { echo "MISSING fixture: $fx"; exit 1; }; done && echo PASS`
  - **Commit**: `test(rag): conftest.py with shared fixtures`
  - _Design: Test Strategy — Fixtures_

- [ ] 3.2 Unit tests for `RAGConfig`
  - **Do**: `rag/tests/test_config.py` — default-disabled when no config, partial config merge, malformed YAML raises `ConfigurationError`, `enabled` property single source of truth.
  - **Files**: `rag/tests/test_config.py`
  - **Done when**: 4+ test cases, all pass.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_config.py -q && echo PASS`
  - **Commit**: `test(rag): RAGConfig coverage`
  - _Design: Test Strategy — Test Coverage Table_

- [ ] 3.3 Unit tests for `Chunker`
  - **Do**: `rag/tests/test_chunker.py` — per-artifact strategies produce non-empty chunks; line ranges accurate; JSONL emits one chunk per line; markdown splits at 800-token boundary using embedder tokenizer.
  - **Files**: `rag/tests/test_chunker.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_chunker.py -q && echo PASS`
  - **Commit**: `test(rag): Chunker coverage`

- [ ] 3.4 Unit tests for `SecurityLayer`
  - **Do**: `rag/tests/test_security.py` — each allowlist pattern matches a known-bad fixture; secret content NEVER appears in return value or stdout; rejection log written to `XDG_CACHE_HOME/smart-ralph/rag/sanitization-rejections.log` (uses `xdg_cache_tmp` fixture).
  - **Files**: `rag/tests/test_security.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_security.py -q && echo PASS`
  - **Commit**: `test(rag): SecurityLayer rejection coverage + log path assertion`

- [ ] 3.5 Unit tests for `RAGService` (graceful + telemetry + signal phase)
  - **Do**: `rag/tests/test_service.py` — `retrieve()` returns `[]` on `ProviderError`/`EmbedderError`/`TimeoutError`; success path emits NO `signals.jsonl` entry; failure path emits exactly one `RETRIEVAL_FAILED` with correct `phase` field; per-call telemetry written to `retrieval-metrics.log` with `query_sha256` (not raw query); `from_config()` returns None when disabled.
  - **Files**: `rag/tests/test_service.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_service.py -q && echo PASS`
  - **Commit**: `test(rag): RAGService graceful-degradation + telemetry + phase coverage`
  - _Design: Test Strategy, Observability_

- [ ] 3.6 [VERIFY] Phase 3.B checkpoint: core-module unit tests green
  - **Do**: Run pytest across the config/chunker/security/service test cluster; all must pass.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_config.py plugins/ralphharness/rag/tests/test_chunker.py plugins/ralphharness/rag/tests/test_security.py plugins/ralphharness/rag/tests/test_service.py -q && echo PASS`
  - **Done when**: Four test files pass; rollback granularity intact before adding provider/embedder/bats tests.
  - **Commit**: `chore(rag): pass phase 3.B checkpoint (core-module coverage green)`

- [ ] 3.7 Unit tests for providers (`Qdrant`, `FAISS`)
  - **Do**: `rag/tests/test_providers.py` — Against `fake_qdrant_client`: `retrieve` round-trips vectors, `index` writes chunks with metadata, `health_check` returns False on connection error. Dimension mismatch raises `ProviderError` with remediation hint. FAISS: read-only `index()` raises `NotImplementedError` unless `allow_write=True`; `retrieve` against a tmp index returns top-k by cosine.
  - **Files**: `rag/tests/test_providers.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_providers.py -q && echo PASS`
  - **Commit**: `test(rag): QdrantProvider + FAISSProvider coverage`

- [ ] 3.8 Unit tests for embedders + fallback chain
  - **Do**: `rag/tests/test_embedder.py` — `LocalEmbedder` with stubbed `SentenceTransformer` batches 32, dim 384. `OpenAIEmbedder` with stubbed `openai` returns 1536-dim; rate-limit triggers fallback. `AzureOpenAIEmbedder` raises immediately when endpoint empty. `EmbedderChain([local, openai, azure])` — first failure tries next; all exhausted raises `EmbedderError`.
  - **Files**: `rag/tests/test_embedder.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_embedder.py -q && echo PASS`
  - **Commit**: `test(rag): embedders + fallback chain coverage`

- [ ] 3.9 bats suite for `lib-rag.sh`
  - **Do**: `plugins/ralphharness/tests/test_lib_rag.bats` — disabled path emits no subprocess but writes one `"disabled"` line to metrics log; enabled-but-no-python is graceful; 2s timeout enforced with a slow Python stub; JSON envelope parsed into TSV.
  - **Files**: `plugins/ralphharness/tests/test_lib_rag.bats`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && bats plugins/ralphharness/tests/test_lib_rag.bats && echo PASS`
  - **Commit**: `test(rag): bats suite for lib-rag.sh`

- [ ] 3.10 bats suite for `post-task-rag.sh` integration
  - **Do**: `plugins/ralphharness/tests/test_post_task_rag.bats` — when `rag_enabled=false`, helper is a no-op; when true, the backgrounded invocation does NOT block `stop-watcher.sh` for more than **20 ms**. (Threshold per design Test Coverage Table.)
  - **Files**: `plugins/ralphharness/tests/test_post_task_rag.bats`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && bats plugins/ralphharness/tests/test_post_task_rag.bats && echo PASS`
  - **Commit**: `test(rag): bats suite for post-task-rag.sh (20 ms threshold)`
  - _Design: Test Strategy — Test Coverage Table_

- [ ] 3.11 Unit tests for `OnboardingStep` framework
  - **Do**: `rag/tests/test_onboarding.py` — for each concrete step (`PythonStep`, `PythonDepsStep`, `VectorDBStep`, `EmbedderStep`, `ConfigStep`, `IndexBootstrapStep`, `DoctorStep`):
    1. `detect()` returns each `DetectionState` value (`OK`, `MISSING`, `UNKNOWN`) under controlled fixtures (mocked `subprocess.run` for `pip show`, mocked `curl` for Qdrant healthz, etc.).
    2. `PythonStep.install_command()` is `None` (NFR-9). `ConfigStep.install_command()` and `DoctorStep.install_command()` are `None` (write via `_append_with_flock()` / read-only doctor pass).
    3. For every step whose `install_command()` is NOT `None`: assert it returns a `list[str]` (`isinstance(cmd, list) and all(isinstance(x, str) for x in cmd)`) — NEVER a `str`. The dispatcher's `subprocess.run` call is invoked with **the exact list returned by `install_command()`** AND `shell=False`: `mock_run.call_args.args[0] == step.install_command()` and `mock_run.call_args.kwargs.get('shell', False) is False`. (This catches the design-blocker regression where someone string-joins the argv.)
    4. AC-6.5 failure path: when `verify()` returns False after install, the step is recorded as `failed: <name>` (NOT `installed`, NOT `skipped`), AND the next step's `detect()` is invoked (loop continues, no abort). The user-facing prompt set remains exactly `[y/n/r/a]` — no separate `[s]` keystroke is exposed.
    5. AC-6.3 idempotency: re-running after a successful step returns `OK` for every step, prompts zero times (assert mocked stdin not consulted), AND wall-clock from `onboard()` entry to summary print is `< 5 s` (measure with `time.monotonic()`).
    6. Prompt outcomes — mocked stdin returning each of `y` / `n` / `r` / `a` produces the documented summary entries (`installed` / `skipped` reason=`user-declined` / re-detect-loop / abort-with-summary-still-printed).
    7. `EmbedderStep` openai/azure secret-hygiene: after running with a fake key `sk-fake-leakage-canary`, assert the literal `sk-fake-leakage-canary` does NOT appear in: (a) any `subprocess.run` call argv (across all calls), (b) any line written to `XDG_CACHE_HOME/smart-ralph/rag/retrieval-metrics.log`, (c) any line written to `signals.jsonl`, (d) captured stdout. (NFR-9 secret-handling assertion.)
  - **Files**: `rag/tests/test_onboarding.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_onboarding.py -q && echo PASS`
  - **Commit**: `test(rag): OnboardingStep framework coverage (argv list + secret hygiene + idempotency)`
  - _Requirements: AC-6.2, AC-6.3, AC-6.5, AC-6.6, NFR-9_
  - _Design: Component 9, Test Strategy — Test Coverage Table_

- [ ] 3.12 [VERIFY] Phase 3.C checkpoint: all unit + bats tests green
  - **Do**: Run pytest + both bats suites together; all must pass.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/ -q && bats plugins/ralphharness/tests/test_lib_rag.bats plugins/ralphharness/tests/test_post_task_rag.bats && echo PASS`
  - **Done when**: All suites green.
  - **Commit**: `chore(rag): pass phase 3.C checkpoint`

- [ ] 3.13 Integration test: real Qdrant (skipped if no `QDRANT_URL`)
  - **Do**: `rag/tests/test_qdrant_integration.py` — `pytest.skip` if `QDRANT_URL` missing; else create test collection, index 3 chunks, retrieve top-1, assert content match, clean up in `teardown`.
  - **Files**: `rag/tests/test_qdrant_integration.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/test_qdrant_integration.py -q && echo PASS`
  - **Commit**: `test(rag): Qdrant integration (skippable)`

- [ ] 3.14 [VERIFY] Phase 3 exit gate: coverage + skip-marker discipline
  - **Do**: Verify ≥18 individually collected test items exist across the suite; integration test correctly skips when `QDRANT_URL` absent (does not error).
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && count=$(PYTHONPATH=. python -m pytest --collect-only -q plugins/ralphharness/rag/tests/ 2>/dev/null | grep -cE '::test_'); test "$count" -ge 18 && echo PASS`
  - **Done when**: ≥18 collected `::test_*` items; integration test skips cleanly.
  - **Commit**: `chore(rag): pass phase 3 exit gate`

## Phase 4: Quality Gates

Goal: lint, type-check, slash commands (including onboarding), surgical
stop-watcher hook, and a real Ralph Loop iteration with RAG enabled.

- [ ] 4.1 Shellcheck `lib-rag.sh` and (placeholder) `post-task-rag.sh`
  - **Do**: Fix any shellcheck SC errors; add `# shellcheck disable=` only with a comment explaining why.
  - **Files**: `plugins/ralphharness/hooks/scripts/lib-rag.sh`, `plugins/ralphharness/hooks/scripts/post-task-rag.sh`
  - **Verify**: `shellcheck plugins/ralphharness/hooks/scripts/lib-rag.sh plugins/ralphharness/hooks/scripts/post-task-rag.sh && echo PASS`
  - **Commit**: `chore(rag): shellcheck clean`

- [ ] 4.2 `ruff` + `mypy` clean on `rag/`
  - **Do**: `ruff check plugins/ralphharness/rag/` and `mypy plugins/ralphharness/rag/`; fix until clean. Type-annotate every public function.
  - **Files**: any in `rag/` that fail.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && ruff check plugins/ralphharness/rag/ && mypy plugins/ralphharness/rag/ && echo PASS`
  - **Commit**: `chore(rag): ruff + mypy clean`

- [ ] 4.3 Implement `/ralphharness:index-all` command + flock rate limit
  - **Do**:
    1. `commands/index-all.md` — slash command that shells `python -m plugins.ralphharness.rag index-all "$@"`.
    2. In `__main__.py index-all`: acquire flock on `~/.cache/smart-ralph/rag/index-all.lock` with `LOCK_EX | LOCK_NB`; if locked, exit 1 with `another index-all is in progress`. Additionally reject if lock-mtime is < 60 s old (soft rate limit, NFR-8).
    3. Stream per-spec progress as JSON lines.
  - **Files**: `plugins/ralphharness/commands/index-all.md`, `rag/__main__.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag index-all --dry-run | head -5 | grep -q '"spec"' && echo PASS`
  - **Commit**: `feat(rag): /ralphharness:index-all with flock + 1/min rate limit`
  - _Requirements: FR-6, NFR-8_
  - _Design: Component 8, Flow 3, Edge Cases_

- [ ] 4.4 Implement `/ralphharness:rag-doctor` command
  - **Do**:
    1. `commands/rag-doctor.md` — slash command that shells `python -m plugins.ralphharness.rag doctor`.
    2. `doctor` subcommand performs: config valid, embedder reachable, vector DB reachable, last index time per collection, **embedder dimension match per collection** (Edge Cases).
    3. Output is tiered YAML report — `OK`/`WARN`/`FAIL` per check.
  - **Files**: `plugins/ralphharness/commands/rag-doctor.md`, `rag/__main__.py`
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag doctor | grep -qE '^(OK|WARN|FAIL):' && echo PASS`
  - **Commit**: `feat(rag): /ralphharness:rag-doctor with tiered report`
  - _Requirements: FR-10_
  - _Design: Component 8, Edge Cases_

- [ ] 4.5 Implement `/ralphharness:rag-search` command (US-4 triage)
  - **Do**:
    1. `commands/rag-search.md` — slash command that shells `python -m plugins.ralphharness.rag search --query "$@"`.
    2. In `__main__.py search`: default `--all-collections`, `--top-k 10`; runs `RAGService.retrieve()` per collection (`specs_tasks`, `execution_memory`, `reviews`); merges + reranks by score.
    3. Output is a colored TTY ranked list with `rank`, `source_path:source_line_start`, `score`, and a `±2-line` excerpt. **Read-only — never appends to `signals.jsonl`, never updates `.progress.md`.**
  - **Files**: `plugins/ralphharness/commands/rag-search.md`, `rag/__main__.py`
  - **Done when**: `python -m … search --query "deadlock" --all-collections --top-k 3` exits 0 and prints a ranked list (or `(no results)` when disabled).
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag search --query "deadlock at task 5" --all-collections --top-k 3 2>&1 | grep -qE '(no results|^[0-9]+\.|score:)' && echo PASS`
  - **Commit**: `feat(rag): /ralphharness:rag-search human-operator triage tool`
  - _Requirements: AC-4.1, AC-4.2, AC-4.3_
  - _Design: Component 8, Flow 5_

- [ ] 4.6 [VERIFY] Phase 4.B checkpoint: all three retrieval-side slash commands green
  - **Do**: Smoke-run each of `rag-doctor`, `index-all --dry-run`, `rag-search "x"` end-to-end; assert each exits 0.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m plugins.ralphharness.rag doctor >/dev/null && PYTHONPATH=. python -m plugins.ralphharness.rag index-all --dry-run >/dev/null && PYTHONPATH=. python -m plugins.ralphharness.rag search --query x --all-collections --top-k 1 >/dev/null && echo PASS`
  - **Done when**: All three commands exit 0 under disabled config (graceful empty output).
  - **Commit**: `chore(rag): pass phase 4.B checkpoint`

- [ ] 4.7 Implement `OnboardingStep` framework + 7 concrete steps
  - **Do**:
    1. `rag/onboarding.py` — `DetectionState` enum (`OK` / `MISSING` / `UNKNOWN`), `DetectionResult` dataclass `{state, detail}`, `OnboardingStep` ABC with `detect() -> DetectionResult`, `explain() -> str`, `install_command() -> list[str] | None` (argv LIST, NEVER a string), `verify() -> bool`.
    2. Concrete steps in order: `PythonStep` (`install_command()` returns `None` per NFR-9), `PythonDepsStep` (returns `["pip", "install", "qdrant-client", "faiss-cpu", "pyyaml"]`), `VectorDBStep` (Qdrant + docker → `["docker", "run", "-d", "--name", "smart-ralph-qdrant", "-p", "6333:6333", "qdrant/qdrant:1.7.0"]`; FAISS or no-docker → `None`), `EmbedderStep` (local → `["pip", "install", "sentence-transformers"]`; openai/azure → `None`, prints env-var hint; **NEVER writes keys to disk**), `ConfigStep` (`install_command() == None`; writes via dedicated `_append_with_flock()` under advisory `flock` on `.ralphharness.local.md`, aborts if mtime changed since `detect()`), `IndexBootstrapStep` (first `["python", "-m", "rag", "index-all", "--dry-run"]`, then `["python", "-m", "rag", "index-all"]`; rate-limit error → `verify()` False with `detail` "rate-limited; rerun in <N>s"), `DoctorStep` (`install_command() == None`; runs `rag-doctor`).
    3. Safety invariants: dispatcher calls `subprocess.run(step.install_command(), shell=False, check=False)` — the **exact argv list** from `install_command()` is what gets executed; no string-rejoin in between; no `sudo` ever auto-prepended; API keys collected by `EmbedderStep` are written only to `.ralphharness.local.md` via `ConfigStep._append_with_flock()`, never to logs/signals/stdout.
    4. Idempotency: each step's `detect()` short-circuits to `OK` if already installed; on re-run, all `OK` steps are skipped with zero prompts.
  - **Files**: `rag/onboarding.py`
  - **Done when**: All seven step classes importable; each implements all four abstract methods; `PythonStep.install_command()` returns `None`; `PythonDepsStep.install_command()` returns a `list[str]` (NOT a `str`).
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -c "from plugins.ralphharness.rag.onboarding import PythonStep, PythonDepsStep, VectorDBStep, EmbedderStep, ConfigStep, IndexBootstrapStep, DoctorStep, OnboardingStep
for s in [PythonStep, PythonDepsStep, VectorDBStep, EmbedderStep, ConfigStep, IndexBootstrapStep, DoctorStep]:
    assert issubclass(s, OnboardingStep), s
assert PythonStep().install_command() is None
deps_cmd = PythonDepsStep().install_command()
assert isinstance(deps_cmd, list) and all(isinstance(x, str) for x in deps_cmd), f'expected list[str], got {type(deps_cmd)}: {deps_cmd!r}'
print('PASS')" | grep -q PASS && echo PASS`
  - **Commit**: `feat(rag): OnboardingStep framework + 7 concrete steps (argv list contract)`
  - _Requirements: FR-11, FR-12, AC-6.1, AC-6.2, AC-6.3, AC-6.6, NFR-9_
  - _Design: Component 9_

- [ ] 4.8 Wire `onboard` subcommand + `/ralphharness:rag-onboard` slash command
  - **Do**:
    1. `__main__.py onboard` — instantiate the seven steps in order; for each: print the structured block (`[i/7] name`, `Detect:`, `Why:`, `Would run:`), read stdin for `y`/`n`/`r`/`a`, dispatch, record outcome. Accumulate a summary block at the end and run `rag-doctor`.
    2. Add a `--non-interactive` flag (read-only mode: prints the plan without prompting; used by 1.4 smoke and CI). In non-interactive mode all `MISSING` steps are recorded as `skipped`.
    3. `commands/rag-onboard.md` — slash-command markdown with frontmatter; body instructs the agent to walk the user through `python -m rag onboard` conversationally, reading each `Why:` paragraph aloud and waiting for the user's `y`/`n`/`r`/`a` answer before passing it to stdin.
  - **Files**: `plugins/ralphharness/commands/rag-onboard.md`, `rag/__main__.py`
  - **Done when**: `python -m … onboard --non-interactive` runs all seven steps without blocking, prints a summary block with **all four counters** (`installed:`, `already_present:`, `skipped:`, `failed:`), and exits 0.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && out=$(PYTHONPATH=. python -m plugins.ralphharness.rag onboard --non-interactive 2>&1) && for k in 'Onboarding summary' 'installed:' 'already_present:' 'skipped:' 'failed:'; do echo "$out" | grep -q "$k" || { echo "MISSING counter: $k"; exit 1; }; done && echo PASS`
  - **Commit**: `feat(rag): /ralphharness:rag-onboard interactive installer (US-6)`
  - _Requirements: FR-11, AC-6.1, AC-6.4, AC-6.5_
  - _Design: Component 8 (commands table), Component 9, Flow 6_

- [ ] 4.9 Create `post-task-rag.sh` helper (separate file)
  - **Do**:
    1. New file `plugins/ralphharness/hooks/scripts/post-task-rag.sh`.
    2. Sources `lib-rag.sh`; defines a single function `post_task_rag_hook <spec> <task_index>` that calls `rag_index_task` in the background (`& disown`).
    3. Guarded internally so all calls are no-ops when `rag_enabled() == "false"`.
  - **Files**: `plugins/ralphharness/hooks/scripts/post-task-rag.sh`
  - **Done when**: Sourcing the helper and calling `post_task_rag_hook test-spec 0` with no config completes in <20 ms and emits no signals.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && bash -c 'source plugins/ralphharness/hooks/scripts/post-task-rag.sh && start=$(date +%s%N); post_task_rag_hook rag-integration 0; end=$(date +%s%N); test $(( (end-start)/1000000 )) -lt 20 && echo PASS'`
  - **Commit**: `feat(rag): post-task-rag.sh helper (surgical stop-watcher hook)`
  - _Requirements: FR-7_
  - _Design: Internal Dependencies, File Structure_

- [ ] 4.10 Surgically wire `post-task-rag.sh` into `stop-watcher.sh` (2 lines)
  - **Do**: Add exactly two lines to `stop-watcher.sh` at the end of the existing post-`TASK_COMPLETE` block: one to `source` the helper, one to invoke `post_task_rag_hook` behind `if rag_enabled; then …; fi`. **No edits to any existing line.** Per CLAUDE.md "Surgical Changes".
  - **Files**: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**: `git diff HEAD --` on stop-watcher.sh shows ≤4 added lines and 0 removed lines.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && grep -q post_task_rag_hook plugins/ralphharness/hooks/scripts/stop-watcher.sh && bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && stats=$(git diff --numstat HEAD -- plugins/ralphharness/hooks/scripts/stop-watcher.sh) && added=$(echo "$stats" | awk '{print $1}') && removed=$(echo "$stats" | awk '{print $2}') && test "$added" -le 4 && test "$removed" -eq 0 && echo PASS`
  - **Commit**: `feat(rag): surgical 2-line stop-watcher post-task hook`
  - _Requirements: FR-7_
  - _Design: Internal Dependencies (CLAUDE.md Surgical Changes)_

- [ ] 4.11 [VERIFY] Phase 4 exit gate: real Ralph Loop iteration with RAG enabled
  - **Do**: Create a minimal `.ralphharness.local.md` with `rag.enabled: true` + `provider: faiss` and a writable FAISS path; run one synthetic spec-executor task end-to-end. Assert: `INDEXING_QUEUED` signal appears after task completes.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && mkdir -p /tmp/rag-e2e-$$ && bash -c 'printf -- "---\nrag:\n  enabled: true\n  provider: faiss\n  faiss:\n    index_dir: /tmp/rag-e2e-'$$'\n    allow_write: true\n---\n" > .ralphharness.local.md.test && source plugins/ralphharness/hooks/scripts/post-task-rag.sh && SPEC=rag-integration; start_sig=$(grep -c INDEXING_QUEUED "specs/$SPEC/signals.jsonl" 2>/dev/null || echo 0); post_task_rag_hook "$SPEC" 0; sleep 2; end_sig=$(grep -c INDEXING_QUEUED "specs/$SPEC/signals.jsonl" 2>/dev/null || echo 0); rm -f .ralphharness.local.md.test; test "$end_sig" -gt "$start_sig" && echo PASS'`
  - **Done when**: At least one `INDEXING_QUEUED` signal appended after the hook fires.
  - **Commit**: `chore(rag): pass phase 4 exit gate`

## Phase 5: PR Lifecycle (with autonomous E2E verification)

Goal: docs, version bump, autonomous E2E verification (VE1/VE2/VE3), PR.

- [ ] 5.1 [VE1] Startup: prepare autonomous E2E test environment
  - **Do**:
    1. Ensure Python deps installed (`pip install -e ./plugins/ralphharness/rag/`) and `bats` available.
    2. Start an ephemeral Qdrant container if `docker` is available (`docker run -d --name rag-e2e-qdrant -p 6333:6333 qdrant/qdrant:1.7.0`); else skip integration.
    3. Export `QDRANT_URL=http://localhost:6333` and `XDG_CACHE_HOME=$(mktemp -d)` for hermetic test runs.
  - **Files**: (none — runtime setup)
  - **Done when**: `python -c "import qdrant_client, pytest, sentence_transformers"` succeeds and `bats --version` prints a version.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && python -c "import qdrant_client, pytest" >/dev/null 2>&1 && bats --version >/dev/null 2>&1 && echo PASS`
  - **Commit**: (no commit — runtime setup; record outcome in `.progress.md`)

- [ ] 5.2 [VE2] Check: run full E2E suite (pytest + bats + integration)
  - **Do**: Run pytest (unit + integration if `QDRANT_URL` set) + both bats suites; assert all green. On failure, surface output to `.progress.md`.
  - **Files**: (test files exercised, not edited)
  - **Done when**: Both pytest and bats exit 0; ≥18 pytest tests collected; ≥6 bats tests collected.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && PYTHONPATH=. python -m pytest plugins/ralphharness/rag/tests/ -q && bats plugins/ralphharness/tests/test_lib_rag.bats plugins/ralphharness/tests/test_post_task_rag.bats && echo PASS`
  - **Commit**: `chore(rag): VE2 autonomous E2E green`

- [ ] 5.3 [VE3] Cleanup: tear down ephemeral E2E environment
  - **Do**:
    1. Remove ephemeral Qdrant container if started in VE1 (`docker rm -f rag-e2e-qdrant`).
    2. Clean up `XDG_CACHE_HOME` temp dirs.
    3. Remove any leftover `.ralphharness.local.md.test` fixture files.
  - **Files**: (cleanup only)
  - **Done when**: No `rag-e2e-qdrant` container running; no `.ralphharness.local.md.test` in repo root.
  - **Verify**: `cd /mnt/bunker_data/ai/smart-ralph && ! docker ps 2>/dev/null | grep -q rag-e2e-qdrant && ! test -f .ralphharness.local.md.test && echo PASS`
  - **Commit**: (no commit — runtime cleanup; record outcome in `.progress.md`)

- [ ] 5.4 Update `CLAUDE.md` with RAG configuration section
  - **Do**: Add a `## RAG (optional)` section under "Architecture" explaining the opt-in model, the four new commands (rag-doctor, index-all, rag-search, **rag-onboard**), how `signals.jsonl` is extended (RETRIEVAL_FAILED with phase, INDEXING_QUEUED), and the `retrieval-metrics.log` telemetry file. Reference design.md for full detail.
  - **Files**: `CLAUDE.md`
  - **Verify**: `grep -q '## RAG' CLAUDE.md && grep -q rag-onboard CLAUDE.md && grep -q rag-search CLAUDE.md && echo PASS`
  - **Commit**: `docs: RAG configuration overview in CLAUDE.md`

- [ ] 5.5 Update plugin README with RAG section (including onboarding entry point)
  - **Do**: Add `## RAG Integration (opt-in)` to `plugins/ralphharness/README.md`. Cover: enable flag, **`/ralphharness:rag-onboard` as the recommended way to enable**, the other three commands, providers (Qdrant + FAISS), embedder fallback chain, security model.
  - **Files**: `plugins/ralphharness/README.md`
  - **Verify**: `grep -q 'RAG Integration' plugins/ralphharness/README.md && grep -q rag-onboard plugins/ralphharness/README.md && grep -q rag-search plugins/ralphharness/README.md && echo PASS`
  - **Commit**: `docs(rag): README section`

- [ ] 5.6 Bump plugin version (minor)
  - **Do**:
    1. Bump `plugins/ralphharness/.claude-plugin/plugin.json` version: `5.7.0` → `5.8.0` (new feature).
    2. Bump matching entry in `.claude-plugin/marketplace.json`.
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Verify**: `grep -q '"version": "5.8.0"' plugins/ralphharness/.claude-plugin/plugin.json && grep -q '"version": "5.8.0"' .claude-plugin/marketplace.json && echo PASS`
  - **Commit**: `chore: bump plugin to 5.8.0 (RAG integration)`

- [ ] 5.7 Open PR via `gh pr create`
  - **Do**: Create PR titled `feat: opt-in RAG integration (Qdrant + FAISS, sentence-transformers + OpenAI, interactive onboarding)`. Body links to this spec, the BMAD PRD, and the design doc.
  - **Verify**: `gh pr view --json url -q .url | grep -q github && echo PASS`
  - **Commit**: (no commit — gh action)

- [ ] 5.8 [VERIFY] Phase 5 exit gate: CI green, ready for review
  - **Do**: Wait for CI; confirm all checks pass. If lint/type/test fail, fix and push.
  - **Verify**: `gh pr checks --watch && echo PASS`
  - **Done when**: All CI checks green; PR ready for review.
  - **Commit**: `chore(rag): pass phase 5 exit gate`
