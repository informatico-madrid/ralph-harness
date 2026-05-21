# RalphHarness

Spec-driven development plugin for Claude Code. Transforms feature requests into structured specs (research, requirements, design, tasks) then executes them task-by-task.

## Getting Started

```bash
claude --plugin-dir ./plugins/ralphharness
/ralphharness:new my-feature Describe your feature
/ralphharness:research my-feature
/ralphharness:requirements my-feature
/ralphharness:design my-feature
/ralphharness:tasks my-feature
/ralphharness:implement my-feature
```

## Commands

| Command | Purpose |
|---------|---------|
| `/ralphharness:new` | Create a new spec |
| `/ralphharness:research` | Generate research phase |
| `/ralphharness:requirements` | Generate user stories and acceptance criteria |
| `/ralphharness:design` | Generate technical design |
| `/ralphharness:tasks` | Generate task breakdown |
| `/ralphharness:implement` | Execute tasks with POC-first workflow |
| `/ralphharness:cancel` | Cancel current spec execution |
| `/ralphharness:triage` | Create/resume an epic |
| `/ralphharness:start` | Detect active epics, suggest next spec |

## RAG Integration (opt-in)

An opt-in retrieval-augmented generation layer enriches execution-phase context with past spec data.

**Enable**: `/ralphharness:rag-onboard` — recommended interactive installer (7-step detection and install)

**Or manually**: Add a `rag:` block to `.ralphharness.local.md` with `enabled: true`.

**Commands**:
- `/ralphharness:rag-doctor` — tiered health report (OK/WARN/FAIL per check)
- `/ralphharness:index-all` — index all spec artifacts (flock rate-limited, 1/min)
- `/ralphharness:rag-search` — human-operator triage tool across all collections
- `/ralphharness:rag-onboard` — interactive onboarding wizard

**Providers**: Qdrant (primary) with FAISS fallback. Embedder fallback: local (sentence-transformers) -> OpenAI -> Azure.

**Security**: SHA-256 hashed queries in telemetry, content sanitization against allowlist patterns, secrets never logged.

Disabling RAG is a no-op — the plugin functions identically with zero overhead.

## Version

See `.claude-plugin/plugin.json` for the current version.
