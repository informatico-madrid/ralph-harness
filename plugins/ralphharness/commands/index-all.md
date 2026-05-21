---
trigger: /ralphharness:index-all
description: Index all spec artifacts into the RAG vector store.
usage: "/ralphharness:index-all [--dry-run] [--collection NAME]"
---

# /ralphharness:index-all

Index all spec artifacts into the RAG vector store.

## Usage

```
/ralphharness:index-all [--dry-run] [--collection NAME]
```

## Flags

- `--dry-run`: Show what would be indexed without actually indexing.
- `--collection NAME`: Target collection name (default: auto-detect).

## Behavior

- Acquires an advisory flock on `~/.cache/smart-ralph/rag/index-all.lock`.
- Rejects if another instance is running (1/min rate limit, NFR-8).
- Streams per-spec progress as JSON lines to stdout.
- When RAG is disabled, returns immediately with zero overhead.
