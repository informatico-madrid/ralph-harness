---
spec: rag-integration
basePath: specs/rag-integration
phase: research
created: 2026-05-20
source: _bmad-output/planning-artifacts/research/
---

# Research: rag-integration

This research was produced as BMAD planning artifacts and imported via
`/ralphharness-bmad-bridge:ralph-bmad-import`. The full source documents
remain authoritative; this file is a navigation index and a synthesis of
the load-bearing findings.

## Source documents

| Document | Path | Purpose |
|----------|------|---------|
| Product brief | [_bmad-output/planning-artifacts/product-brief-rag-smart-ralph.md](../../_bmad-output/planning-artifacts/product-brief-rag-smart-ralph.md) | Vision, target users, problem statement |
| PR/FAQ | [_bmad-output/planning-artifacts/prfaq-rag-smart-ralph.md](../../_bmad-output/planning-artifacts/prfaq-rag-smart-ralph.md) | Launch announcement framing + Q&A |
| Domain research — RAG + Claude Code plugins | [_bmad-output/planning-artifacts/research/domain-rag-claude-code-plugins-research-2026-05-20.md](../../_bmad-output/planning-artifacts/research/domain-rag-claude-code-plugins-research-2026-05-20.md) | State of the art for RAG in IDE plugins |
| Technical research — RAG + Ralph Loop architecture | [_bmad-output/planning-artifacts/research/technical-rag-ralph-loop-architecture-research-2026-05-20.md](../../_bmad-output/planning-artifacts/research/technical-rag-ralph-loop-architecture-research-2026-05-20.md) | Integration points with the existing loop, signal protocol |
| Technical research — git worktree agent isolation | [_bmad-output/planning-artifacts/research/technical-git-worktree-agent-isolation-research-2026-05-20.md](../../_bmad-output/planning-artifacts/research/technical-git-worktree-agent-isolation-research-2026-05-20.md) | Relevant for indexing across worktree-scoped specs |
| Brainstorming session | [_bmad-output/brainstorming/brainstorming-session-2026-05-20-09-04.md](../../_bmad-output/brainstorming/brainstorming-session-2026-05-20-09-04.md) | Idea generation, trade-off exploration |
| Winston's architecture analysis | [_bmad-output/brainstorming/winston-architecture-analysis.md](../../_bmad-output/brainstorming/winston-architecture-analysis.md) | 6 architectural concerns + 4 trade-offs |
| PRD | [_bmad-output/planning-artifacts/prd.md](../../_bmad-output/planning-artifacts/prd.md) | Full requirements doc |
| PRD validation report | [_bmad-output/planning-artifacts/prd-validation-report.md](../../_bmad-output/planning-artifacts/prd-validation-report.md) | Issues identified in PRD draft |
| Architecture | [_bmad-output/planning-artifacts/architecture.md](../../_bmad-output/planning-artifacts/architecture.md) | Winston's full architecture write-up |

## Key findings (synthesis)

### F-1. Execution memory is the differentiator, not generic RAG
Smart Ralph already produces `chat.md`, `task_review.md`, and `signals.jsonl`
during every spec run. These are the **unique input** that competitors can't
reproduce, because they're a side-effect of the Ralph Loop. The retrieval
value is highest when indexing them, not when indexing source code.

### F-2. Plugin distribution constrains technology choices
The plugin runs on every developer's machine; assumptions about GPU,
network, or API credentials are wrong somewhere. This forces:
- A **fallback chain** for embeddings (local → OpenAI → Azure).
- A **fallback provider** for the vector DB (Qdrant → FAISS local file).
- **Default disabled** — RAG must be opt-in, not opt-out, or the plugin
  breaks for users without the dependencies installed.

### F-3. Bash + Python is the right boundary
Existing plugin: bash scripts + markdown agent prompts. Adding Python
in-process is impossible (the runtime is Claude Code, not a Python
interpreter). The natural boundary is a subprocess CLI — `python -m rag …`
returning JSON to stdout — mirroring how the plugin already calls
`detect-ci-commands.sh`, `verify-fix-present.sh`, etc.

### F-4. The 2-second retrieval budget is binding
Pre-task retrieval (UC-1) is **synchronous** — the coordinator waits before
delegating to spec-executor. A retrieval that exceeds 2s makes the loop
feel broken. This drives:
- Hard `timeout 2s` in `lib-rag.sh`.
- Local embedder default (no network round-trip).
- Pre-warmed model load (lazy but cached at first call).

### F-5. signals.jsonl economy
Every iteration the coordinator re-reads `signals.jsonl`. Adding 2-4
signals per task would balloon the file (Winston: 100 specs × 20 tasks × 4
signals = 8 000 entries). Only the two operationally useful signals
survive: `RETRIEVAL_FAILED` (incident review) and `INDEXING_QUEUED`
(observability of background work).

### F-6. Security is allowlist, not denylist
Regex denylists for secrets have well-known false negatives (encoded
tokens, novel formats). The PRD validation report flagged this; the
architecture switched to an **allowlist of known-bad shapes** — AWS keys,
SSH keys, Bearer tokens, Slack/GitHub PATs — with a rejection log written
to a local cache (NEVER to `signals.jsonl`, since the rejection itself
might contain the secret).

### F-7. Cross-project retrieval is dangerous by default
A team with three projects could trivially leak secrets between them via
shared collections. The architecture defaults to **project-scoped
collection prefixes** (`smart-ralph-{project}-{collection}`) with a
top-level opt-in flag `rag.allow_cross_project: true` for the cases where
shared learning is valuable.

## Open questions (resolved by architecture)

| Q | Resolution |
|---|------------|
| MVP scope — execution-only or include planning phases? | Execution only (UC-1 … UC-5). Planning phases (UC-6 … UC-9) deferred. |
| Qdrant + FAISS — both writeable, or FAISS as read-only fallback? | FAISS read-only cache of Qdrant. Single writer avoids sync. |
| Signal volume — all four, or minimal two? | Minimal two: `RETRIEVAL_FAILED`, `INDEXING_QUEUED`. |
| Sanitization — regex denylist or structured allowlist? | Structured allowlist + offline rejection log. |
| Cross-project default — opt-in or opt-out? | Opt-in via explicit flag. Default project-scoped. |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Python missing on user machine | Medium | RAG disabled silently | `lib-rag.sh` detects, logs WARN once, returns 0 chunks. |
| Qdrant outage during peak use | Medium | RAG returns nothing | FAISS fallback (read-only); coordinator continues unchanged. |
| Embedding cost via OpenAI grows unbounded | Low | $ | Local embedder default; OpenAI is opt-in via fallback chain. |
| Secret leaks into vector DB | Low | High | Allowlist sanitization at index time; rejection log isolated. |
| signals.jsonl bloat | Medium | Loop slowdown | Only 2 RAG signals; INDEXING_QUEUED can be batched per N tasks (post-MVP). |
| Dimension mismatch after embedder swap | Medium | All retrievals fail | `rag-doctor` reports mismatch; remediation = `index-all --force`. |
| Concurrent bulk index | Low | Vector DB corruption | flock at `~/.cache/smart-ralph/rag/index-all.lock`. |

## Out of scope for this spec (deferred)

- Planning-phase retrieval (UC-6 … UC-9)
- Reranking / query expansion
- Knowledge-graph metadata
- HMAC-signed FAISS index files
- Web UI / observability dashboard
- Cross-project beyond opt-in flag
