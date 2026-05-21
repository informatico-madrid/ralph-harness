---
trigger: /ralphharness:rag-search
description: Search indexed spec artifacts for relevant context.
usage: '/ralphharness:rag-search "query" [--all-collections] [--top-k N]'
---

# /ralphharness:rag-search

Search indexed spec artifacts for relevant context (US-4 triage).

## Usage

```
/ralphharness:rag-search "query" [--all-collections] [--top-k N]
```

## Behavior

- Searches across `specs_tasks`, `execution_memory`, and `reviews` collections.
- Merges and reranks results by score.
- Outputs a colored TTY ranked list with source paths and score excerpts.
- **Read-only** — never modifies signals, progress, or any spec files.
- When disabled, prints `(no results)` and exits 0.
