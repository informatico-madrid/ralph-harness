---
name: role-contracts
description: Minimal role-contracts fixture for pre-execution critic tests
---

## Access Matrix

| Agent | Reads | Writes | Denylist |
|-------|-------|--------|----------|
| spec-executor | spec files, .ralph-state.json | .progress-task-*.md, chat.md, chat.executor.lastReadLine, src/*.ts | .ralph-state.json (except chat.executor.lastReadLine), .epic-state.json |
