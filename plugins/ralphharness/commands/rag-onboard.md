---
trigger: /ralphharness:rag-onboard
description: Interactive RAG setup wizard.
---

# /ralphharness:rag-onboard

Interactive setup wizard for the RAG integration. Guides the user through provider selection, API key configuration, and index initialization.

## Usage

```
/ralphharness:rag-onboard [--non-interactive]
```

## Behavior

- Shells to `python -m plugins.ralphharness.rag onboard "$@"`.
- Creates a guided YAML frontmatter block in `.ralphharness.local.md`.
- `--non-interactive`: skip prompts, use defaults.
