---
trigger: /ralphharness:rag-onboard
description: Interactive step-by-step installer for RAG dependencies.
usage: "/ralphharness:rag-onboard"
---

# /ralphharness:rag-onboard

Walk the user through a step-by-step interactive installer for RAG dependencies.
Detects, explains, and (with explicit per-step confirmation) installs each dependency.
Idempotent — safe to re-run.

## Usage

```
/ralphharness:rag-onboard
```

## Agent Instructions

1. Run `python -m plugins.ralphharness.rag onboard` (interactive mode by default).
2. For each of the 7 steps, read the output aloud:
   - `[N/7] <step-name>` — which step we are on
   - `Detect: <state> – <detail>` — current state
   - `Why: <explanation>` — why this step matters
   - `Would run: <install-cmd>` — what command would be executed (or manual step)
3. Wait for the user's answer before passing it to stdin:
   - `y` — proceed with install
   - `n` — skip this step
   - `r` — retry detect (check again without installing)
   - `a` — auto-approve remaining steps
4. After all 7 steps complete, the command prints an **Onboarding summary** with four counters:
   - `installed: N` — steps successfully installed and verified
   - `already_present: N` — steps already satisfied
   - `skipped: N` — steps the user declined or were skipped (non-interactive)
   - `failed: N` — steps whose install/verify failed
5. Present the summary to the user. If any step failed, suggest running again or the `rag-doctor` command.

## Steps

1. **Python 3.10+** — check Python version
2. **Python dependencies** — install qdrant-client, faiss-cpu, pyyaml
3. **Vector database** — start Qdrant Docker container (or FAISS)
4. **Embedder library** — install sentence-transformers (or configure OpenAI/Azure)
5. **RAG configuration** — add `rag:` block to `.ralphharness.local.md`
6. **Index bootstrap** — run `/ralphharness:index-all`
7. **Doctor check** — run `/ralphharness:rag-doctor` to verify health

When RAG is disabled, all steps report `ok` and exit immediately.

