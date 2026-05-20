---
trigger: /ralphharness:rag-doctor
description: Health-check the RAG integration layer.
usage: "/ralphharness:rag-doctor"
---

# /ralphharness:rag-doctor

Perform a health check on the RAG integration layer.

## Usage

```
/ralphharness:rag-doctor
```

## Output

Tiered YAML report with OK/WARN/FAIL per check:
- Config validity
- Embedder reachability
- Vector DB reachability
- Last index time per collection
- Embedder dimension match per collection

When RAG is disabled, reports `enabled: false` and exits 0.
