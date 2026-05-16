# PR Context: Collaboration Resolution (spec/collaboration-resolution)

## Spec Name
`collaboration-resolution` (Spec 7 in engine-roadmap-epic)

## Branch
`spec/collaboration-resolution` → `main`

## Feature Description
Encodes ad-hoc agent collaboration patterns as explicit, machine-actionable rules in the RalphHarness plugin:

1. **Cross-branch regression workflow** — spec-executor detects `git diff main...HEAD` regressions against main via `collaboration-resolution` reference
2. **Experiment-propose-validate pattern** — structured hypothesis/experiment/finding/root_cause workflow for agent collaboration
3. **BUG_DISCOVERY-triggered fix tasks** — when reviewer finds a bug via investigation, automatic fix task generation with deduplication and depth limits
4. **6 new chat collaboration signals** — HYPOTHESIS, EXPERIMENT, FINDING, ROOT_CAUSE, FIX_PROPOSAL, BUG_DISCOVERY (appended to chat.md, NOT control signals)

## Changed Files
- `plugins/ralphharness/agents/external-reviewer.md` — Baseline Check section, BUG_DISCOVERY emit rule
- `plugins/ralphharness/agents/spec-executor.md` — cross-branch detection in exit_code_gate
- `plugins/ralphharness/references/channel-map.md` — spec-executor added as chat.md writer
- `plugins/ralphharness/references/collaboration-resolution.md` — full spec document
- `plugins/ralphharness/references/failure-recovery.md` — BUG_DISCOVERY trigger mapping
- `plugins/ralphharness/templates/chat.md` — 6 new collaboration signal markers
- `plugins/ralphharness/.claude-plugin/plugin.json` — version bump 5.1.0 → 5.2.0
- `.claude-plugin/marketplace.json` — version bump 5.1.0 → 5.2.0
- `specs/collaboration-resolution/` — all spec artifacts (research, requirements, design, tasks, chat, task_review)
- `tests/collaboration-resolution.bats` — 19 structural + integration tests

## Intentional Patterns (NOT BUGS)
- **6 new signal markers** in chat.md are collaboration content markers, NOT control signals — they must NOT appear in `signals.jsonl`
- **BUG_DISCOVERY** in task_review.md is documentation of a bug, NOT a test status — it triggers fix task generation
- **Additivity invariant** (NFR-1) — no deletions from existing files, only additions
- **Append-only chat.md** — all messages appended via flock locking, never edited in place
- **fixTaskMap deduplication** — same evidence for same task_id yields zero additional fix tasks
- **Depth/limit guards** — maxFixTasksPerOriginal and maxFixTaskDepth prevent infinite fix loops

## Implementation Details
- All plugin files are markdown-based (commands, agents, hooks, skills)
- Changes are purely additive to plugin markdown files
- Test coverage via bats (Bash Automated Testing System) — 19 tests
- Version bumped from 5.1.0 to 5.2.0 (minor — new features)
- All 52 tasks completed across 5 phases (POC, refactor, testing, quality, PR)
- AC checklist: 27/27 verified
- External reviewer active with SOLID + DRY principles
