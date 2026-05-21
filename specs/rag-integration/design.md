---
spec: rag-integration
basePath: specs/rag-integration
phase: design
created: 2026-05-20
source: _bmad-output/planning-artifacts/architecture.md
---

# Design: rag-integration

## Overview

Bolt a Python-based RAG service onto the Bash-and-Markdown plugin via a thin
CLI boundary. The plugin already shells out to scripts (e.g.
`detect-ci-commands.sh`, `verify-fix-present.sh`); the RAG layer is one more
such subprocess — `python -m rag <command>` — invoked from `lib-rag.sh`.

Three architectural pillars hold the design together:

1. **Strategy pattern at every boundary.** `VectorDBProvider` and `Embedder`
   are abstract base classes; `QdrantProvider`/`FAISSProvider` and
   `OpenAIEmbedder`/`LocalEmbedder`/`AzureOpenAIEmbedder` are concrete
   implementations chosen by config.
2. **Graceful degradation as a hard invariant.** Any RAG call returns
   `[]` on failure. The Ralph Loop NEVER errors due to RAG.
3. **Signal economy.** Only two new signals — `RETRIEVAL_FAILED` and
   `INDEXING_QUEUED`. Success retrievals do not pollute `signals.jsonl`.

## Component Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                    RalphHarness Plugin (Bash + MD)                 │
│                                                                    │
│  agents/*.md  commands/*.md  hooks/scripts/*.sh  signals.jsonl     │
│         │             │              │                              │
│         └─────────────┴──────────────┘                              │
│                       │                                             │
│                       ▼                                             │
│             ┌─────────────────────┐                                 │
│             │  hooks/scripts/     │   bash → python boundary        │
│             │  lib-rag.sh         │   (only place that knows        │
│             │                     │   "RAG might be enabled")       │
│             └─────────┬───────────┘                                 │
│                       │                                             │
│                       ▼                                             │
│     ┌──────────────────────────────────────────────┐               │
│     │  plugins/ralphharness/rag/  (Python module)  │               │
│     │  ────────────────────────                    │               │
│     │  __main__.py    CLI dispatch                 │               │
│     │  service.py     RAGService (facade)          │               │
│     │  config.py      .ralphharness.local.md parse │               │
│     │  security.py    allowlist sanitization       │               │
│     │  signals.py     emits RAG control signals    │               │
│     │  chunker.py     artifact → chunks            │               │
│     │  providers/     QdrantProvider, FAISSProvider│               │
│     │  embedder/      OpenAI, Local, Azure         │               │
│     └────────┬─────────────────────────────────────┘               │
│              │                                                      │
│              ▼                                                      │
│   ┌─────────────────────┐   ┌─────────────────────┐                │
│   │  Qdrant (HTTP)      │   │  FAISS (local file) │                │
│   │  primary            │   │  fallback           │                │
│   └─────────────────────┘   └─────────────────────┘                │
└────────────────────────────────────────────────────────────────────┘
```

## Technical Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | MVP scope | Execution phases only (UC-1 … UC-5) | Validate value with minimum risk; planning-phase value depends on having execution-memory volume first. |
| 2 | Implementation language for RAG module | Python | Native bindings for `qdrant-client`, `faiss`, `sentence-transformers`; bash equivalents are immature. |
| 3 | Bash ↔ Python boundary | Subprocess CLI (`python -m rag …`) returning JSON to stdout | Mirrors existing plugin pattern (`detect-ci-commands.sh`, etc.); no in-process coupling. |
| 4 | Vector DB strategy | Qdrant primary + FAISS read-only cache (synced from Qdrant) | Avoids two-writer sync problem; FAISS exists only as a fallback for offline / Qdrant-down scenarios. |
| 5 | Embedder strategy | Strategy pattern: `local` (default) → `openai` → `azure` | Different teams have different cost/privacy/availability constraints; local default keeps data on machine. |
| 6 | Code location | `plugins/ralphharness/rag/` | Co-located with plugin for distribution as a single artifact; separate from `hooks/` to keep the Python/Bash split visible. |
| 7 | Config location | `.ralphharness.local.md` under a new `rag:` YAML block | Reuses the established plugin-settings pattern; per-project not global. |
| 8 | Signal volume | Minimal — only `RETRIEVAL_FAILED` and `INDEXING_QUEUED` | `signals.jsonl` is append-only and is read often; success signals would dominate volume with no operational value. Note: `INDEXING_QUEUED` is emitted *after* indexing completes (semantics: "a completed indexing was written to the collection"). The name reflects its role in the signal queue — it tells the coordinator "indexing reached done state" — rather than implying pre-execution. |
| 9 | Security model | Allowlist + structured parsing | Regex denylist misses obfuscated secrets; allowlist (e.g. `AWS_ACCESS_KEY=…`, `Bearer …`, PEM headers) rejects known-bad shapes deterministically. |
| 10 | Failure semantics | Always return `[]` from `retrieve()` on any exception | Hard invariant: the Ralph Loop must never error because of RAG. |
| 11 | Chunking strategy | Per-artifact recursive splitter, 800-token chunks with 100-token overlap, semantic boundaries (markdown headings, task IDs, signal entries). Token count uses the **active embedder's tokenizer** (e.g. `BAAI/bge-small-en-v1.5`'s tokenizer for `local`, `tiktoken`'s `cl100k_base` for `openai`). | Empirically good for technical text; preserves source line ranges for source-path tagging. Using the embedder's own tokenizer avoids over/under-shooting the model's true context window. |
| 12 | Cross-project retrieval | Opt-in via `rag.allow_cross_project: true`; default project-only via collection prefix | Default-safe: prevents accidental leakage between team projects. |
| 13 | Onboarding | Interactive `/ralphharness:rag-onboard` — step-by-step with explanations, **explicit per-step user confirmation**, idempotent | Plugin distribution constraint (F-2): dependencies and provider choice vary per user, so a one-shot installer fails for most users. A guided flow reduces support burden, makes the architecture visible (users *learn* what RAG depends on by installing it), and keeps install actions safe by never auto-running anything. |

## Component Details

### Component 1 — `lib-rag.sh` (Bash entry point)

**Path:** `plugins/ralphharness/hooks/scripts/lib-rag.sh`

**Responsibilities:**
- Sole bash entry point to the RAG layer. Agents and the coordinator NEVER call `python -m rag` directly.
- Enforces the 2-second hard timeout on retrieval.
- Detects whether RAG is enabled (reads `.ralphharness.local.md`); if disabled, returns immediately with no subprocess call.
- Parses JSON results from the Python CLI and emits TSV (`path\tscore\tcontent\n`) on stdout for downstream `awk`/`while read` consumers.

**Public functions:**
```bash
rag_enabled            # echo "true"|"false"; cached per-shell via env var
rag_retrieve QUERY COLLECTION TOP_K     # echo TSV of chunks; 0 chunks on failure/timeout
rag_index_task SPEC_NAME TASK_INDEX     # called after TASK_COMPLETE; non-blocking (background)
rag_health_check                         # echo "OK"|"DEGRADED"|"DISABLED" on stdout
```

**Failure handling:**
- `timeout 2s python -m rag retrieve …` — on non-zero exit OR timeout, append `RETRIEVAL_FAILED` to `signals.jsonl` and emit 0 lines.
- `python` missing on PATH ⇒ log WARN once per session, return 0 lines.

### Component 2 — `rag/__main__.py` (Python CLI)

**Path:** `plugins/ralphharness/rag/__main__.py`

**Subcommands:**

| Command | Args | Output (stdout) | Exit codes |
|---------|------|-----------------|------------|
| `retrieve` | `--query`, `--collection`, `--top-k`, `--min-score` | JSON array of `Chunk` objects | 0 always (graceful degradation) |
| `index` | `--source <path>`, `--collection`, `--spec-name` | JSON `{indexed, skipped, errors}` | 0 on success, 1 on hard config error |
| `index-all` | `--force`, `--dry-run` | streaming progress JSON lines | 0 on success, 1 on hard config error |
| `doctor` | (none) | YAML report with OK/WARN/FAIL per check | 0 if all OK, 1 if any FAIL |
| `search` | `--query`, `--all-collections`, `--top-k` | colored, human-readable ranked list with source paths | 0 always |

The `search` subcommand is the backend for the `/ralphharness:rag-search` slash command (human-operator triage, see Component 8). Agents NEVER invoke `search` — they use `lib-rag.sh`'s `rag_retrieve` directly.

**JSON response envelope (all subcommands that return chunks):**
```json
{
  "provider_used": "qdrant",
  "embedder_used": "local",
  "latency_ms": 142,
  "results": [ /* Chunk objects */ ]
}
```
The envelope carries telemetry (latency, provider, embedder) so `lib-rag.sh` can log without having to inspect individual chunks. Used by the retrieval-metrics log (see Observability section).

**JSON `Chunk` shape (per FR-9):**
```json
{
  "id": "qdrant-point-uuid",
  "content_hash": "sha256:abc123...",
  "content": "...",
  "score": 0.87,
  "source_path": "specs/auth/task_review.md",
  "source_line_start": 42,
  "source_line_end": 71,
  "spec_name": "auth",
  "indexed_at": "2026-05-19T10:23:11+00:00",
  "staleness_days": 31,
  "embedder_model": "BAAI/bge-small-en-v1.5",
  "stale": false
}
```

| Field | Purpose |
|-------|---------|
| `id` | Vector DB primary key (UUID generated at index time). |
| `content_hash` | `sha256:` of the chunk content. Distinct from `id` — used to detect content changes (re-index trigger) and verify integrity (FR-9 data integrity). |
| `indexed_at` | ISO 8601 timestamp when the chunk was last indexed. |
| `staleness_days` | Computed at retrieval time as `(now - indexed_at).days`. The `stale: bool` field is `True` when `staleness_days > config.retrieval.staleness_threshold_days`. |
| `embedder_model` | The embedder model that produced this chunk's vector. Used by `rag-doctor` to detect dimension mismatch (Edge Cases). |

### Component 3 — `rag/service.py` (RAGService facade)

**Class `RAGService`:**
```python
class RAGService:
    def __init__(self, config: RAGConfig): ...
    def retrieve(self, query: str, collection: str, top_k: int = 5) -> list[Chunk]: ...
    def index(self, chunks: list[Chunk], collection: str) -> IndexResult: ...
    def health_check(self) -> HealthReport: ...
    @classmethod
    def from_config(cls) -> "RAGService": ...
```

**Invariants:**
- `retrieve()` never raises; on any exception logs WARN and returns `[]`.
- `index()` may raise `IndexingError`; the caller (CLI) catches and prints an error payload.
- `RAGService` is stateless after construction; safe to instantiate per CLI invocation.

### Component 4 — `rag/providers/` (Vector DB strategy)

**ABC:**
```python
class VectorDBProvider(ABC):
    @abstractmethod
    def retrieve(self, query_vec: list[float], collection: str, top_k: int) -> list[Chunk]: ...
    @abstractmethod
    def index(self, chunks: list[Chunk], collection: str) -> IndexResult: ...
    @abstractmethod
    def health_check(self) -> bool: ...
```

**Concrete: `QdrantProvider`:**
- Wraps `qdrant-client.QdrantClient`.
- Collection name = `{collection_prefix}{project}-{collection_id}` (e.g. `smart-ralph-rag-integration-specs_tasks`); `collection_prefix` defaults to `smart-ralph-`.
- Cosine distance, 1536-dim default (matches OpenAI `text-embedding-3-small`); 384-dim if `local_model: BAAI/bge-small-en-v1.5`.

**Concrete: `FAISSProvider`:**
- Read-only by default in MVP. `index()` raises `NotImplementedError` unless `faiss.allow_write: true` is set.
- Stores index file at `~/.cache/smart-ralph/faiss/{project}/{collection}.index` plus a sidecar `.metadata.jsonl`.

**Logical collections (FR-4):**

| Collection ID | Source artifact(s) | Chunk granularity | Used by |
|---------------|--------------------|---------------------|---------|
| `specs_tasks` | `specs/<spec>/tasks.md` | Per task block (`- [ ] N.M`) | US-2 pre-task retrieval (Flow 4) |
| `specs_requirements` | `specs/<spec>/requirements.md` | Per `## ` and `### US-` section | Post-MVP (UC-7); not retrieved in MVP, only indexed for future use |
| `specs_design` | `specs/<spec>/design.md` | Per `## ` section | Post-MVP (UC-8) |
| `specs_research` | `specs/<spec>/research.md` | Per `## ` section | Post-MVP (UC-6) |
| `execution_memory` | `specs/<spec>/chat.md` + `specs/<spec>/task_review.md` + `specs/<spec>/signals.jsonl` | Per message / per row / per signal event | US-1 on-error retrieval (Flow 2); US-4 rag-search (Flow 5) |
| `reviews` | `specs/<spec>/.review/*.md` (when present) | Per review document | UC-5 on-review retrieval (post-MVP retrieval, indexed in MVP) |

The full vector-DB collection name is `{prefix}{collection_id}` — e.g. `smart-ralph-rag-integration-execution_memory`. The `{prefix}` is `{collection_prefix}{project}-` so collections are project-scoped by default. With `rag.allow_cross_project: true`, the prefix becomes just `{collection_prefix}` (shared across the team).

**MVP indexing scope:** all six collections are populated by `index-all` (FR-6 requires the full set indexed). **MVP retrieval scope:** only `specs_tasks` and `execution_memory` are actively queried by agents; `reviews` is queryable via `rag-search` for triage but no automatic agent uses it.

### Component 5 — `rag/embedder/` (Embedding strategy)

**ABC:**
```python
class Embedder(ABC):
    @abstractmethod
    def embed(self, text: str) -> list[float]: ...
    @abstractmethod
    def embed_batch(self, texts: list[str]) -> list[list[float]]: ...
    @property
    @abstractmethod
    def dimensions(self) -> int: ...
```

**Concrete:**
- `OpenAIEmbedder` — model from config (default `text-embedding-3-small`, 1536-dim).
- `LocalEmbedder` — `sentence-transformers` (default `BAAI/bge-small-en-v1.5`, 384-dim). Lazy-loaded.
- `AzureOpenAIEmbedder` — requires `endpoint`, `deployment_name`, `api_key`.

**Fallback chain** (config: `rag.embeddings.fallback_order: [local, openai, azure]`; users may shorten/reorder):
- Try primary; on failure (timeout, auth error, missing dep), try next.
- `azure` only attempted when `embeddings.azure.endpoint` is configured; otherwise skipped silently.
- All providers exhausted ⇒ retrieval returns `[]`.

### Component 6 — `rag/security.py` (Sanitization)

**Class `SecurityLayer`:**
- Loads `rag/security_allowlist.yaml` at startup (versioned with the plugin).
- Each pattern has `id`, `regex`, `severity` (`block` | `warn`).
- `sanitize(chunk) -> SanitizationResult` — returns `accepted: bool`, `matched_patterns: list[str]`.

**Allowlist examples (initial set):**
- `AWS_ACCESS_KEY_ID\s*=\s*AKIA[0-9A-Z]{16}` → block
- `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----` → block
- `(?i)bearer\s+[a-z0-9._-]{20,}` → block
- `xox[bp]-[0-9a-zA-Z-]{20,}` → block (Slack)
- `ghp_[A-Za-z0-9]{36}` → block (GitHub PAT)

**Logged rejections** are written to `~/.cache/smart-ralph/rag/sanitization-rejections.log` (NEVER to `signals.jsonl` — the rejection itself might contain the secret).

### Component 7 — `rag/chunker.py` (Artifact splitter)

**Per-artifact strategies:**

| Artifact | Strategy |
|----------|----------|
| `tasks.md` | Split by `^### Story` or `^- \[ \] N.M` boundaries; preserve task ID in metadata. |
| `requirements.md` | Split by `^## ` and `^### US-` boundaries. |
| `design.md` | Split by `^## ` boundaries. |
| `research.md` | Split by `^## ` boundaries. |
| `chat.md` | One chunk per message (delimiter is the per-turn frontmatter block). |
| `task_review.md` | One chunk per row. |
| `signals.jsonl` | One chunk per JSON line; concatenate `type`, `reason`, `taskIndex`, surrounding `chat.md` ±2 messages. |

Each chunk carries `source_line_start`/`source_line_end` so the retrieving agent can quote the exact original lines.

### Component 8 — Slash commands (`commands/rag-doctor.md`, `commands/index-all.md`, `commands/rag-search.md`, `commands/rag-onboard.md`)

Four new slash commands. **All four are human-operator surfaces** — agents do not invoke slash commands. Autonomous agent retrievals always go through `lib-rag.sh`'s `rag_retrieve` function (see Component 1, Flows 2 and 4).

| Command | Audience | Backend | Purpose |
|---------|----------|---------|---------|
| `/ralphharness:rag-doctor` | Platform engineer (US-3, Jordan) | `python -m rag doctor` | Health check + remediation hints; optionally writes report to `specs/<current>/.progress.md`. |
| `/ralphharness:index-all` | Platform engineer (US-3) | `python -m rag index-all` | Bulk index of all specs. Flags: `--force` (re-index existing), `--dry-run` (list chunks without writing). Concurrent-invocation lock via flock at `~/.cache/smart-ralph/rag/index-all.lock`; a soft rate limit additionally rejects invocations whose lock-mtime is < 60s old (NFR-8). |
| `/ralphharness:rag-search <query>` | On-call / support engineer (US-4, Sam) | `python -m rag search` | Interactive triage retrieval across all collections. Output is a colored, human-readable ranked list with `source_path`, `score`, and a `±2 lines` excerpt. Defaults to `--all-collections`; pass `--collection <id>` to scope. |
| `/ralphharness:rag-onboard` | First-time RAG user (US-6) | `python -m rag onboard` | Interactive step-by-step installer for RAG dependencies. Detects, explains, and (with explicit per-step `y` confirmation) installs each dependency. Idempotent. See Component 9 + Flow 6. |

**Important:** `/ralphharness:rag-search` and `/ralphharness:rag-doctor` are read-only and never modify state — they do not append to `signals.jsonl`, do not update `.progress.md`. `/ralphharness:rag-onboard` writes to `.ralphharness.local.md` (with user confirmation) and may invoke `pip install` and `docker run` (each behind a `y` prompt).

### Component 9 — Onboarding (`commands/rag-onboard.md` + `rag/onboarding.py`)

**Surface:** `/ralphharness:rag-onboard` — a human-driven, agent-explained, step-by-step interactive installer for RAG dependencies. Resolves US-6 (Pat) and is the canonical answer to "how do I enable RAG?".

**Path:** `plugins/ralphharness/commands/rag-onboard.md` (slash-command frontmatter + shell wrapper) + `plugins/ralphharness/rag/onboarding.py` (step framework and concrete steps).

**Class `OnboardingStep` (ABC, FR-12):**
```python
class DetectionState(Enum):
    OK = "ok"                 # already installed/configured
    MISSING = "missing"       # not present; can be installed
    UNKNOWN = "unknown"       # cannot determine (e.g. network down)

@dataclass
class DetectionResult:
    state: DetectionState
    detail: str               # what was found / why it's missing

class OnboardingStep(ABC):
    name: str                 # e.g. "python-deps"
    @abstractmethod
    def detect(self) -> DetectionResult: ...
    @abstractmethod
    def explain(self) -> str: ...          # one paragraph: what + why
    @abstractmethod
    def install_command(self) -> list[str] | None: ...
    # argv LIST (not a shell string). Passed directly to subprocess.run(argv, shell=False).
    # Returning a single string would force shell=True (injection-prone) OR an attempt
    # to exec a binary literally named "pip install qdrant-client …" (FileNotFoundError).
    # None ⇒ no auto-install (e.g. PythonStep) — show manual instruction instead.
    @abstractmethod
    def verify(self) -> bool: ...          # post-install re-detect; True if step now OK
```

**Concrete steps** (run in this order; this *is* the onboarding journey):

| # | Step | `detect()` | `install_command()` (argv list) |
|---|------|-----------|--------------------------------|
| 1 | `PythonStep` | `python3 --version >= 3.10` via `subprocess.run`. | `None` — prints a plain-text instruction to install via the user's system package manager (`apt install python3.10`, `brew install python@3.11`, etc.). **NEVER auto-installs Python** (NFR-9). |
| 2 | `PythonDepsStep` | For each of `qdrant-client`, `faiss-cpu`, `pyyaml`: `pip show <pkg>` returns 0. `sentence-transformers` + `openai` are lazy — checked only if the relevant embedder is later chosen. | `["pip", "install", "qdrant-client", "faiss-cpu", "pyyaml"]` — only confirmed packages; lazy deps deferred to `EmbedderStep`. |
| 3 | `VectorDBStep` | Interactive prompt: `Qdrant` or `FAISS`? If Qdrant: `curl -fsSL http://localhost:6333/healthz` succeeds (or `docker ps` shows a `qdrant/qdrant` container). If FAISS: nothing to install. | If Qdrant + `docker` available: `["docker", "run", "-d", "--name", "smart-ralph-qdrant", "-p", "6333:6333", "qdrant/qdrant:1.7.0"]`. If Qdrant + no Docker: `None` (manual Docker-install instruction). If FAISS: `None`. |
| 4 | `EmbedderStep` | Interactive prompt: `local` / `openai` / `azure`? For `local`: lazy-import `sentence_transformers`; show model name + approx download size (NFR-10). For `openai`: check `OPENAI_API_KEY` env var. For `azure`: check `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_DEPLOYMENT` + `AZURE_OPENAI_API_KEY`. | For `local`: `["pip", "install", "sentence-transformers"]` if not present. For `openai` / `azure`: `None` (prints env-var export hint; **NEVER writes API keys to disk**, NFR-9). |
| 5 | `ConfigStep` | Parse `.ralphharness.local.md` and check for a `rag:` block reflecting the choices made in steps 3 + 4. **Concurrency:** the file is read at `detect()` time; the snippet is built in memory; on `[y]` the file is re-read + appended in a single critical section under an advisory `flock` on the file (the same primitive `lib-signals.sh` uses for `signals.jsonl`). If the file mtime changed between `detect()` and the `[y]` confirmation, the step aborts with `verify() == False` and `detail: "file changed since detect; re-run rag-onboard"`. | `None` (config writes go through a dedicated `ConfigStep._append_with_flock()` method, not a generic `subprocess.run`). Offers (a) view snippet, (b) append-under-flock with confirmation, (c) skip and paste manually. |
| 6 | `IndexBootstrapStep` | Call `python -m rag doctor` and inspect "last index timestamp per collection" — if all empty, step is `MISSING`. The `--dry-run` invocation in this step does NOT acquire the `index-all` flock (lock applies only to write paths per Flow 3). | First: `["python", "-m", "rag", "index-all", "--dry-run"]` (preview chunk counts). Then on a second `y`: `["python", "-m", "rag", "index-all"]` (real write). **Rate-limit interaction:** if the real invocation returns the NFR-8 rate-limit error (flock mtime < 60 s), `verify()` returns `False` with `detail: "rate-limited; rerun in <N>s"` and the step is recorded as `failed: index-bootstrap (rate-limited)`. Re-running `rag-onboard` after the cooldown re-attempts cleanly. |
| 7 | `DoctorStep` | Always re-runs `python -m rag doctor` at the very end. | `None` — informational; on `FAIL`, the summary points back at the failing step. |

**Interaction protocol** (per step):
```
[1/7] python-deps
  Detect: [MISSING] qdrant-client not installed
  Why:    Smart Ralph's RAG layer indexes execution memory into Qdrant
          (or FAISS as fallback) for fast vector retrieval. qdrant-client
          is the official Python SDK used by QdrantProvider.
  Would run: pip install qdrant-client faiss-cpu pyyaml
  Run this? [y]es / [n]o-skip / [r]etry-detect / [a]bort → _
```

The agent (the slash-command handler in Claude Code) is responsible for **reading aloud the explanation** and pausing for the user — the Python backend prints the structured block, and the command markdown instructs the agent to walk the user through it conversationally. This is what makes the flow "agent-driven with human-in-the-loop" rather than a silent shell installer.

**Output:** streaming per-step lines, ending with:
```
== Onboarding summary ==
  installed:        3   (qdrant-client, faiss-cpu, pyyaml)
  already_present:  1   (python3)
  skipped:          2   (azure-embedder, config-file)
  failed:           0
Final check: /ralphharness:rag-doctor → OK
```

**Safety invariants (NFR-9):**
- `install_command()` returns an **argv list** (`list[str]`), never a shell string. The dispatcher calls `subprocess.run(step.install_command(), shell=False, check=False)` — passing a list with `shell=False` is the only safe combination (no shell expansion, no injection).
- A test assertion (see Test Coverage Table) checks that the **exact list** returned by `install_command()` is what gets passed to `subprocess.run`, not a derived form. This catches a regression where someone joins the list back into a string.
- No `sudo` ever auto-prepended. If a step's install requires elevated privileges, `install_command()` returns `None` and the step prints a plain-text manual instruction.
- API keys collected by `EmbedderStep` are never written to disk by onboarding — only env-var hints are printed. The keys go ONLY into `.ralphharness.local.md` via `ConfigStep._append_with_flock()`, never into logs, `signals.jsonl`, or `retrieval-metrics.log`.
- The user can `[a]bort` at any step; the loop breaks and the summary block still prints (the `print summary` line is *after* the `for` loop in Flow 6, so `break` exits to it cleanly).

**Idempotency (AC-6.3):**
- `detect()` is the gate. Re-running `rag-onboard` after a successful install returns `OK` for every completed step and the flow short-circuits to the next `MISSING` step (or to `DoctorStep` if all are `OK`).

## Data Flow

### Flow 1 — Post-task indexing (US-1, FR-7)

```
spec-executor emits TASK_COMPLETE
        │
        ▼
stop-watcher.sh receives stop event
        │ (advances taskIndex; emits metric)
        ▼
stop-watcher.sh calls rag_index_task <spec> <task_index> &
        │ (background, non-blocking)
        ▼
lib-rag.sh: timeout 5s python -m rag index --source specs/<spec>/task_review.md --spec-name <spec>
        │
        ▼
RAGService.index(): chunker → security → embedder → provider
        │
        ▼
On success: append INDEXING_QUEUED signal {spec, chunks_indexed}
On failure: append RETRIEVAL_FAILED signal {phase: "indexing", error}, log WARN
```

> **Signal taxonomy note.** Per Decision #8, we keep two signals — but each carries a `phase` field (`"retrieval"` or `"indexing"`) so triage can distinguish where the failure happened without adding a third signal name. `RETRIEVAL_FAILED` is the generic "RAG subsystem failed" signal; the `phase` field disambiguates.

### Flow 2 — On-error retrieval (US-1)

```
spec-executor task fails (non-zero exit)
        │
        ▼
coordinator: chunks=$(rag_retrieve "$error_message" execution_memory 3)
        │
        ▼ (in lib-rag.sh)
timeout 2s python -m rag retrieve --query "$error" --collection execution_memory --top-k 3
        │
        ├── success ⇒ JSON parsed, TSV emitted on stdout (no signal); telemetry → retrieval-metrics.log
        └── timeout/error ⇒ 0 lines emitted, RETRIEVAL_FAILED signal appended ({phase: "retrieval"})
        ▼
coordinator injects chunks into spec-executor retry prompt under "## Past Solutions"
```

### Flow 3 — Bulk index (US-3, FR-6)

```
/ralphharness:index-all [--force] [--dry-run]
        │
        ▼
acquire flock on ~/.cache/smart-ralph/rag/index-all.lock (1/min rate limit)
        │
        ▼
scan specs/ — for each spec, for each artifact:
    chunker → security → embedder → provider
    progress to stdout: {"spec": "...", "artifact": "...", "chunks": N}
        │
        ▼
streaming batches of 50 specs (NFR-4: memory ceiling)
        │
        ▼
emit summary: {"total_specs": N, "total_chunks": M, "errors": K, "duration_s": T}
```

### Flow 4 — Pre-task retrieval (US-2)

```
coordinator about to delegate task to spec-executor
        │
        ▼
coordinator: chunks=$(rag_retrieve "$task_description" specs_tasks 5)
        │
        ▼ (in lib-rag.sh — short-circuits to empty if rag_enabled=false)
timeout 2s python -m rag retrieve --query "$task" --collection specs_tasks --top-k 5 --min-score 0.7
        │
        ├── success ⇒ TSV of chunks emitted; each chunk = "path\tscore\tcontent"
        │             telemetry → retrieval-metrics.log
        ├── below-min-score ⇒ chunks filtered server-side; possibly 0 results
        └── timeout/error ⇒ 0 lines emitted, RETRIEVAL_FAILED signal appended ({phase: "retrieval"})
        ▼
coordinator injects chunks into spec-executor delegation prompt under "## Similar Past Tasks"
        │  (tagged with spec_name + source_path + score; stale chunks downweighted)
        ▼
spec-executor runs the task with enriched context (or no enrichment if 0 chunks)
```

### Flow 5 — Interactive search (US-4, rag-search)

```
on-call operator: /ralphharness:rag-search "deadlock at task 5"
        │
        ▼
command md shells: python -m rag search --query "deadlock at task 5" --all-collections --top-k 10
        │
        ▼
RAGService.retrieve() per collection (specs_tasks, execution_memory, reviews)
        │
        ▼
merge + rerank by score, format as colored TTY output with:
  - rank
  - source_path:line_start
  - score
  - ±2-line excerpt
        │
        ▼ (no signals emitted — read-only triage tool)
operator opens source_path:line_start in editor to drill in
```

### Flow 6 — Interactive onboarding (US-6, rag-onboard)

```
first-time user: /ralphharness:rag-onboard
        │
        ▼
command md instructs the agent: walk the user through python -m rag onboard,
        reading each step's "Why:" block conversationally before the prompt
        │
        ▼
python -m rag onboard
        │
        ▼
for step in [PythonStep, PythonDepsStep, VectorDBStep, EmbedderStep,
             ConfigStep, IndexBootstrapStep, DoctorStep]:
    result = step.detect()
    print(f"[{i}/7] {step.name}\n  Detect: [{result.state}] {result.detail}")
    print(f"  Why:    {step.explain()}")
    if result.state == OK:
        record("already_present", step.name); continue
    if result.state == UNKNOWN:
        record("skipped", step.name, reason="detection unknown"); continue
    argv = step.install_command()              # list[str] | None — NEVER a shell string
    if argv is None:
        print(f"  Manual: {step.manual_instruction()}")
        record("skipped", step.name, reason="manual install required")
        continue
    print(f"  Would run: {' '.join(shlex.quote(a) for a in argv)}")   # display only
    choice = prompt("[y/n/r/a]")
    if choice == 'y':
        subprocess.run(argv, shell=False, check=False)   # safety: argv list + shell=False
        if step.verify():
            record("installed", step.name)
        else:
            # AC-6.5: failed step does NOT abort — loop continues to next step.
            # detail carries the failure reason (e.g. "rate-limited; rerun in 42s").
            record("failed", step.name, reason=step.detect().detail)
    elif choice == 'n': record("skipped", step.name, reason="user-declined")
    elif choice == 'r': re-run step.detect()    # re-loop the same step
    elif choice == 'a': break                   # abort flow
        │
        ▼
# Summary still prints — line is after the for-loop, [a]bort breaks here cleanly.
print summary block (installed | already_present | skipped | failed)
        │
        ▼
run python -m rag doctor and display the tiered report
        │  (no signals emitted; onboarding is interactive, not autonomous)
```

## Interfaces

### Bash → Python contract

**Command:** `python -m rag retrieve --query "<text>" --collection <name> --top-k <int> --min-score <float>`

**Stdout (success):** JSON array of `Chunk` objects (see Component 2).

**Stdout (failure):** `[]`

**Stderr:** Diagnostic only; never parsed by callers.

**Exit code:** Always 0 from `retrieve` (graceful degradation). Other subcommands use exit codes per CLI table.

### Configuration (`.ralphharness.local.md`)

```yaml
---
rag:
  enabled: true
  provider: qdrant         # qdrant | faiss
  allow_cross_project: false
  qdrant:
    endpoint: "http://localhost:6333"
    api_key: ""
    collection_prefix: "smart-ralph-"
  faiss:
    index_dir: "~/.cache/smart-ralph/faiss"
    allow_write: false
  embeddings:
    provider: local        # local | openai | azure
    fallback_order: [local, openai, azure]  # azure skipped silently if endpoint unset
    local_model: "BAAI/bge-small-en-v1.5"
    openai_model: "text-embedding-3-small"
    azure:
      endpoint: ""
      deployment_name: ""
  retrieval:
    default_top_k: 5
    min_relevance_score: 0.7
    timeout_seconds: 2
    staleness_threshold_days: 365
---
```

## Observability

Per-call telemetry (latency, top_k, provider, embedder, result_count) MUST NOT be written to `signals.jsonl` — that file is read on every coordinator iteration and would balloon with retrieval volume (PRD F-5, Winston's signal-volume concern). Instead, every retrieval and indexing call appends one JSONL line to:

```
~/.cache/smart-ralph/rag/retrieval-metrics.log
```

Schema (one JSON object per line):
```json
{
  "ts": "2026-05-20T11:42:13+00:00",
  "op": "retrieve",                    // "retrieve" | "index" | "index-all"
  "spec": "rag-integration",
  "query_sha256": "abc123…",           // hash of query, NOT the query (query may contain sensitive task text)
  "collection": "execution_memory",
  "top_k": 3,
  "provider_used": "qdrant",
  "embedder_used": "local",
  "latency_ms": 142,
  "result_count": 3,
  "outcome": "ok"                      // "ok" | "timeout" | "provider_error" | "embedder_error" | "disabled"
                                       // "disabled": written by lib-rag.sh (bash) when rag_enabled=false;
                                       //   Python is never invoked on this path — bash writes the log entry directly.
}
```

- Log file is **append-only** with file-rotation handled externally (e.g. logrotate); plugin does not rotate.
- **Failures still emit `RETRIEVAL_FAILED` to `signals.jsonl`** (operationally significant for triage) AND append to this log.
- **Successful retrievals only write to this log**, never to `signals.jsonl` (FR-5, Decision #8).
- `rag-doctor` reads this log to report "last successful retrieve" timestamps per collection.

This resolves the apparent contradiction between AC-1.4 (wants per-call telemetry) and FR-5/Decision #8 (signal economy). AC-1.4 was amended in `requirements.md` to read "Each retrieval is logged to `~/.cache/smart-ralph/rag/retrieval-metrics.log`" — see [requirements.md](requirements.md) AC-1.4.

## Error Handling

| Error class | Where raised | Caller behavior |
|-------------|--------------|-----------------|
| `RAGError` (base) | Any internal failure | Logged WARN; bubble up. |
| `ProviderError` | `QdrantProvider`, `FAISSProvider` | Caught in `RAGService.retrieve()` → return `[]`; emit `RETRIEVAL_FAILED` signal with `phase: "retrieval"` field. |
| `IndexingError` | `RAGService.index()` | Emit `RETRIEVAL_FAILED` signal with `phase: "indexing"` field; the indexer task fails but the Ralph Loop continues (indexing is background). |
| `EmbedderError` | Any embedder | Try next provider in fallback chain; all exhausted ⇒ `ProviderError`. |
| `ConfigurationError` | `RAGConfig.load()` | Raised only by `doctor` and `index-all` subcommands; `retrieve` swallows it and returns `[]`. |
| `SanitizationRejected` | `SecurityLayer.sanitize()` | NOT an exception — returned as `SanitizationResult.accepted=False`. The chunk is skipped at index time. |
| Timeout (2s retrieve, 5s index) | `lib-rag.sh` via `timeout` | Emit `RETRIEVAL_FAILED` with `phase` matching the timed-out operation; 0 chunks returned. |

**Hard invariant:** `rag_retrieve` always exits 0 with TSV (possibly empty). The Ralph Loop NEVER fails because of RAG.

## Edge Cases

- **Empty index.** `retrieve` returns `[]`. Coordinator proceeds without enrichment. No signal emitted (an empty result is not a failure).
- **Python not on PATH.** `lib-rag.sh` logs WARN once per session, caches `rag_available=false` in env, all subsequent `rag_retrieve` calls return 0 lines instantly.
- **Embedder dimension mismatch.** `QdrantProvider` collection was created with 1536-dim, embedder now returns 384-dim. Provider raises `ProviderError`; `rag-doctor` reports `FAIL: dimension mismatch in collection <name>` with a remediation hint (`/ralphharness:index-all --force`).
- **Concurrent bulk indexes.** Second `/ralphharness:index-all` fails to acquire flock; prints `ERROR: another index-all is in progress` and exits non-zero.
- **Rate-limit short-circuit (NFR-8).** Even after the previous run finishes, if `index-all.lock` mtime is younger than 60 s, the new invocation exits with `ERROR: rate-limited; last index-all completed <N>s ago, wait <60-N>s` (this enforces the *rate*, not just mutual exclusion).
- **Memory pressure during bulk index (NFR-4).** Chunker yields lazily (generator); the bulk-index loop holds one batch (50 specs × ~50 chunks ≈ 2 500 chunks) in RAM at a time. If `resource.getrusage(RUSAGE_SELF).ru_maxrss` crosses a `rag.indexing.memory_ceiling_mb` threshold (default 4 096 MB), the loop reduces `batch_size` to half for the next batch and logs WARN; sustained pressure aborts with `ConfigurationError` (operator must lower `batch_size`).
- **Sanitization rejection of source file.** All chunks from a source rejected ⇒ source skipped entirely; `index` summary reports `skipped: N`.
- **Cross-project query without flag.** Collection prefix scopes the query; chunks from other projects are filtered server-side by collection name, so opt-out is implicit.
- **Staleness.** Chunks older than `staleness_threshold_days` are returned with `stale: true`; coordinator prompt downweights them ("treat as historical hint, verify against current code").
- **OpenAI rate limit during bulk index.** Fallback chain catches the error and retries with `local` embedder; chunks are tagged with whichever embedder ultimately succeeded (`embedder_model` metadata).

## Dependencies

### External services (optional)
- Qdrant ≥ 1.7
- OpenAI API (or Azure OpenAI)

### Python packages
- `qdrant-client >= 1.7`
- `faiss-cpu >= 1.7.4`
- `sentence-transformers >= 2.5` (lazy)
- `openai >= 1.0` (lazy)
- `pyyaml >= 6.0`

### Internal
- `lib-signals.sh` — reused for `RETRIEVAL_FAILED` and `INDEXING_QUEUED`.
- `.ralphharness.local.md` parser pattern.
- `stop-watcher.sh` — extended via a new `post-task-rag.sh` helper sourced at the end of the existing post-`TASK_COMPLETE` block. The helper is invoked behind an `if rag_enabled; then …; fi` guard; **`stop-watcher.sh` itself receives a 2-line addition (source + invocation), no edits to existing logic**. Per CLAUDE.md "Surgical Changes" rule.

## File Structure

```
plugins/ralphharness/
├── hooks/
│   └── scripts/
│       ├── lib-rag.sh                   # NEW — bash entry point (sole rag CLI consumer)
│       └── post-task-rag.sh             # NEW — helper sourced from stop-watcher.sh
├── commands/
│   ├── index-all.md                     # NEW — /ralphharness:index-all
│   ├── rag-doctor.md                    # NEW — /ralphharness:rag-doctor
│   ├── rag-search.md                    # NEW — /ralphharness:rag-search (US-4 triage)
│   └── rag-onboard.md                   # NEW — /ralphharness:rag-onboard (US-6 install flow)
├── rag/                                  # NEW — Python module
│   ├── __init__.py
│   ├── __main__.py                      # CLI dispatch
│   ├── service.py                       # RAGService facade
│   ├── config.py                        # RAGConfig (parses .ralphharness.local.md)
│   ├── security.py                      # SecurityLayer (allowlist sanitization)
│   ├── security_allowlist.yaml          # versioned secret patterns
│   ├── signals.py                       # emits RETRIEVAL_FAILED / INDEXING_QUEUED
│   ├── observability.py                 # retrieval-metrics.log writer (Python side)
│   ├── onboarding.py                    # NEW — OnboardingStep ABC + 7 concrete steps
│   ├── chunker.py                       # artifact → chunks
│   ├── providers/
│   │   ├── __init__.py
│   │   ├── base.py                      # VectorDBProvider ABC
│   │   ├── qdrant.py
│   │   └── faiss.py
│   ├── embedder/
│   │   ├── __init__.py
│   │   ├── base.py                      # Embedder ABC
│   │   ├── openai.py
│   │   ├── local.py
│   │   └── azure.py
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py                  # shared fixtures (fake_qdrant_client, stub_embedder, …)
│       ├── test_config.py
│       ├── test_service.py
│       ├── test_providers.py
│       ├── test_embedder.py
│       ├── test_chunker.py
│       ├── test_security.py
│       ├── test_onboarding.py           # NEW — step framework with mocked detectors
│       └── test_qdrant_integration.py   # skippable when QDRANT_URL absent
└── tests/
    ├── test_lib_rag.bats                # NEW — bats for bash entry point
    └── test_post_task_rag.bats          # NEW — bats for stop-watcher integration helper
```

## Test Strategy

### Test double policy

| External resource | Strategy in unit tests | Strategy in integration tests |
|-------------------|------------------------|-------------------------------|
| Qdrant HTTP API | Replace `qdrant_client.QdrantClient` with a `FakeQdrantClient` that returns canned vectors. NO real network call. | Optional: real Qdrant when `QDRANT_URL` env var present; skip otherwise. |
| OpenAI embeddings API | Replace `openai.embeddings.create` with a stub returning deterministic 1536-dim vectors derived from input hash. | Skipped (cost). Manual verification only. |
| Azure OpenAI | Same stub pattern. | Skipped. |
| sentence-transformers model | Patch `SentenceTransformer` to return a hash-derived 384-dim vector; do NOT download a real model in CI. | Optional: download `BAAI/bge-small-en-v1.5` in a nightly job. |
| FAISS index file | Use `tmp_path` fixture; build a tiny index (3 vectors) per test. | Same. |
| `signals.jsonl` | Real file at `tmp_path`; assert append-only behavior. | Real file in a temporary spec directory. |
| `~/.cache/smart-ralph/` | Set `XDG_CACHE_HOME` to `tmp_path` so tests do not pollute the host cache. | Same. |

### Mock boundary

The mock boundary is the **adapter layer** — i.e. `QdrantProvider`, `OpenAIEmbedder`, `LocalEmbedder` are tested against fakes that look like the upstream library. **`RAGService` is never mocked**; it is always tested against fake providers. This keeps mocks shallow and lets the service-level invariants (graceful degradation, signal emission) be tested for real.

### Test Coverage Table

| Component | Test file | What it asserts |
|-----------|-----------|-----------------|
| `RAGConfig` | `rag/tests/test_config.py` | Default-disabled when no config, partial config merge, malformed YAML raises `ConfigurationError`, `enabled` property single source of truth. |
| `Chunker` | `rag/tests/test_chunker.py` | Per-artifact strategies produce non-empty chunks; line ranges accurate; JSONL chunker emits one chunk per line; long markdown sections split at 800-token boundary using embedder tokenizer. |
| `SecurityLayer` | `rag/tests/test_security.py` | Each allowlist pattern matches a known-bad fixture and rejects; secret content NEVER appears in return value or stdout; rejection log written to `XDG_CACHE_HOME/smart-ralph/rag/sanitization-rejections.log`. |
| `RAGService` | `rag/tests/test_service.py` | `retrieve()` returns `[]` on `ProviderError`, on `EmbedderError`, on `TimeoutError`; success path emits NO `signals.jsonl` entry; failure path emits exactly one `RETRIEVAL_FAILED` with correct `phase` field; per-call telemetry written to `retrieval-metrics.log`. |
| `QdrantProvider` | `rag/tests/test_providers.py` | Against `FakeQdrantClient`: `retrieve` round-trips vectors; `index` writes chunks with metadata; `health_check` returns False on connection error. Dimension-mismatch surfaces as `ProviderError` with a remediation hint. |
| `FAISSProvider` | `rag/tests/test_providers.py` | Read-only `index()` raises `NotImplementedError` unless `allow_write: true`; `retrieve` against a tmp index returns top-k by cosine. |
| `LocalEmbedder` | `rag/tests/test_embedder.py` | With stubbed `SentenceTransformer`, `embed_batch` chunks input into batches of 32; `dimensions` property returns 384 for `BAAI/bge-small-en-v1.5`. |
| `OpenAIEmbedder` | `rag/tests/test_embedder.py` | With stubbed `openai`, `embed` returns 1536-dim vector; rate-limit error triggers fallback. |
| Fallback chain | `rag/tests/test_embedder.py` | `[local, openai, azure]` — first failure tries next; all exhausted raises `EmbedderError`. |
| `lib-rag.sh` | `plugins/ralphharness/tests/test_lib_rag.bats` | `rag_enabled` returns "false" with no config (no subprocess); `rag_retrieve` emits 0 lines and returns 0 when disabled; 2 s timeout enforced; JSON envelope parsed correctly into TSV. |
| `post-task-rag.sh` integration | `plugins/ralphharness/tests/test_post_task_rag.bats` | When `rag_enabled=false`, helper is a no-op; when true, background invocation does not block `stop-watcher.sh` for more than 20 ms. |
| `OnboardingStep` framework | `rag/tests/test_onboarding.py` | Each concrete step: `detect()` returns each `DetectionState` value under controlled fixtures (e.g. mocked `subprocess.run` for `pip show`); `install_command()` is `None` for `PythonStep`; `install_command()` returns a `list[str]` (NOT a `str`) when not `None`; `subprocess.run` is always called with `shell=False` AND with the **exact list** returned by `install_command()` (asserted via `mock_run.call_args.args[0] == step.install_command()`); `verify()` matches `detect()` post-install. Confirmation prompts are exercised via mocked stdin: `y`/`n`/`r`/`a` paths each produce the documented summary outcome. AC-6.5: a `verify()`-returns-False path records `failed` and the loop continues to the next step (no abort). AC-6.3 idempotency: re-running after success returns all `OK`, prompts zero times, and the wall-clock from spawn to summary is < 5 s. |
| Qdrant integration | `rag/tests/test_qdrant_integration.py` | Skip when `QDRANT_URL` missing. Creates test collection, indexes 3 chunks, retrieves top-1, asserts content match, cleans up. |

### Fixtures

Shared `conftest.py` provides:
- `fake_qdrant_client` — in-memory dict-backed fake matching `qdrant_client.QdrantClient`'s interface (the methods used: `get_collections`, `recreate_collection`, `upsert`, `search`).
- `stub_embedder` — returns a hash-derived vector (deterministic, fast, no model load).
- `sample_chunks` — 5 chunks per collection with realistic content (one for each `Chunk` field exercised).
- `sample_signals_jsonl` — fixture with one of each existing signal type (HOLD, PENDING, DEADLOCK, URGENT) plus a placeholder `RETRIEVAL_FAILED` for assertion targets.
- `xdg_cache_tmp` — autouse fixture that points `XDG_CACHE_HOME` at `tmp_path` so cache writes are isolated.

### Coverage targets

- **Per-component branch coverage:** ≥ 80% on every file in `rag/` (enforced via `pytest --cov` in CI).
- **Service-level invariant coverage:** 100% — the hard invariant "`retrieve()` never raises" is the single most important property; every concrete exception class in the Error Handling table MUST have a test that proves the service swallows it.
- **bats coverage:** the `lib-rag.sh` public surface (`rag_enabled`, `rag_retrieve`, `rag_index_task`, `rag_health_check`) — one happy-path test plus disabled-path and timeout-path tests per function.

### File conventions

- Python tests live next to the module they test, under `rag/tests/test_<module>.py`. Invoked via `python -m pytest plugins/ralphharness/rag/tests/`.
- Bats tests live under `plugins/ralphharness/tests/test_<name>.bats`. Invoked via `bats plugins/ralphharness/tests/test_*.bats` — same convention as existing `harness-enforcement-gates` bats suite.
- CI invokes both in one step: `python -m pytest plugins/ralphharness/rag/tests/ -q && bats plugins/ralphharness/tests/test_*.bats`.

## Implementation Sequence (Build Order)

1. `rag/__init__.py`, `rag/config.py`, `rag/__main__.py` skeleton — `doctor` subcommand prints config.
2. `rag/providers/base.py` + `rag/embedder/base.py` (ABCs).
3. `rag/embedder/local.py` (sentence-transformers); `rag/embedder/openai.py`.
4. `rag/providers/qdrant.py` with `health_check` only.
5. `rag/chunker.py` and `rag/security.py` (+ allowlist).
6. `rag/service.py` (`RAGService` facade) and `rag/__main__.py retrieve` subcommand.
7. `hooks/scripts/lib-rag.sh` with `rag_enabled` and `rag_retrieve`.
8. `rag/__main__.py index` and `index-all`; `rag/signals.py` for the two RAG signals.
9. `commands/index-all.md`, `commands/rag-doctor.md`, `commands/rag-search.md`.
10. `rag/providers/faiss.py` (read-only fallback) and dimension-mismatch detection.
11. `rag/onboarding.py` (step framework + 7 concrete steps); `commands/rag-onboard.md` slash-command wrapper that walks the user through `python -m rag onboard` conversationally.
12. `hooks/scripts/post-task-rag.sh` helper; add 2-line `source + guarded invocation` to `stop-watcher.sh` post-`TASK_COMPLETE` block (surgical).
13. Test suite (`rag/tests/*.py` + `tests/test_lib_rag.bats` + `tests/test_post_task_rag.bats`) — see Test Strategy.

Each step is independently testable and produces a working subset. The plugin remains functional with RAG disabled at every step.
