---
name: quality-gate
description: 'Execute deterministic code quality validations as a quality gate for RalphHarness task execution. Runs Layer 3A smoke test (Tier A AST, <1 min), Layer 1 (test execution), Layer 2 (test quality analysis), Layer 3B (Tier B BMAD Party Mode, ~15 min). Uses Two-Tier approach: Tier A (AST deterministic) + Tier B (BMAD Party Mode consensus). Generates a checkpoint JSON consumed by RalphHarness VERIFY steps. Use when you need to validate that code meets quality standards before COMMIT.'
---

## When to Use This Skill

Activate this skill when:
- Running RalphHarness `[VERIFY]` steps
- Validating code quality before `COMMIT`
- Performing pre-merge quality checks
- Executing sprint quality gates

## When NOT to Use This Skill

Do NOT activate this skill when:
- Writing new code (use dev story skill instead)
- Just exploring the codebase
- Running single unit tests (pytest alone is sufficient)

## Inputs Required

- `{project-root}`: The repository working directory (must contain `src/` and `tests/`)
- `{project-root}/src/`: Python source directory to analyze
- `{project-root}/tests/`: Python test directory to analyze
- `{project-root}/tests/e2e/`: End-to-end test directory (Playwright E2E tests)
- `{project-root}/Makefile`: Must contain `make e2e` target

## Conventions

- `{skill-root}` resolves to this workflow skill's installed directory.
- `{project-root}` resolves to the repository working directory.
- Resolve sibling workflow files such as `instructions.md`, `checklist.md`, `steps-c/...`, `steps-v/...`, and templates from `{skill-root}`, not from the workspace root.

---

## Workflow Architecture

The quality gate uses a **4-layer validation approach** (L3A→L1→L2→L3B):

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 3A: SMOKE TEST (Tier A AST, <1 min)                         │
│  ├── ruff check + format check                                      │
│  ├── pyright type check                                             │
│  ├── check_headers                                                  │
│  ├── SOLID Tier A (fast AST)                                        │
│  ├── Principles (DRY/KISS/YAGNI/LoD/CoI)                           │
│  └── Antipatterns Tier A (25 patterns, AST-based)                  │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│        L3A FAIL                           L3A PASS                  │
│        (STOP - fail-fast)                  │                       │
│                                             ▼                       │
└─────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1: TEST EXECUTION (~15 min)                                 │
│  ├── pytest                                                         │
│  ├── coverage check                                                │
│  ├── mutation testing (per-module gate)                             │
│  └── E2E tests (make e2e) [MANDATORY]                              │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│        L1 FAIL                           L1 PASS                   │
│        (refactor tests)                    │                       │
│                                             ▼                       │
└─────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 2: TEST QUALITY (~2 min)                                     │
│  ├── Weak test detection (A1-A8 rules)                              │
│  ├── Mutation kill-map analysis                                     │
│  └── Test diversity metric                                         │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│        L2 FAIL                           L2 PASS                   │
│        (improve tests)                     │                       │
│                                             ▼                       │
└─────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 3B: DEEP QUALITY (Tier B BMAD Party Mode, ~15 min)           │
│  ├── SOLID Tier B (BMAD multi-agent consensus)                      │
│  └── Antipatterns Tier B (BMAD multi-agent consensus)              │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│        L3B FAIL                           L3B PASS                  │
│        (refactor → L3A)                   (COMPLETE)               │
│        NO go to L1                                                 │
└─────────────────────────────────────────────────────────────────────┘
```

### Fail-Fast: L3A as Smoke Test

**L3A acts as a smoke test — if code quality fails, don't waste time on mutation testing (~15 min) or BMAD Party Mode (~15 min).**

| If L3A FAILS | Action |
|--------------|--------|
| Refactorizar código | Go back to L3A |
| Maximum retries | 3 |
| If still failing | Block iteration |

### Recovery Playbook

| When L3B Fails | Action |
|----------------|--------|
| After L1+L2 passed | Refactorizar código → go to L3A (NOT to L1) |
| Rationale | Refactorización may have broken code quality without breaking tests |
| Benefit | Saves ~15 min of mutation testing per recovery cycle |

### E2E Tests (MANDATORY)

E2E tests are **OBLIGATORY** in Layer 1 and must be executed via `make e2e`.
This command automatically starts Home Assistant if needed and runs Playwright E2E tests.

**If `make e2e` fails, Layer 1 FAILS** — no exceptions.

---

## On Activation

1. Read `{skill-root}/workflow.md` and follow it exactly.
2. The workflow will guide you through all 4 layers sequentially: L3A → L1 → L2 → L3B.
3. L3A is the smoke test — if it fails, stop immediately without running L1/L2/L3B.
4. Each layer produces a PASS/FAIL result stored in the checkpoint JSON.
5. The final checkpoint is consumed by RalphHarness `[COMMIT]` decision.

---

## Key Files

| File | Purpose |
|------|---------|
| `workflow.md` | Main orchestrator with layer overview |
| `steps/step-01-init.md` | Initialization and state setup |
| `steps/step-03a-layer3a.md` | Layer 3A: Tier A smoke test (first after init) |
| `steps/step-02-layer1.md` | Layer 1: Test execution |
| `steps/step-03-layer2.md` | Layer 2: Test quality analysis |
| `steps/step-04-layer3b.md` | Layer 3B: Tier B deep quality |
| `steps/step-05-checkpoint.md` | Final checkpoint generation |
| `config/quality-gate.yaml` | All configurable thresholds |
| `scripts/solid_metrics.py` | Fast AST-based SOLID check (Tier A) |
| `scripts/llm_solid_judge.py` | SOLID context generator for BMAD agents (Tier B) |
| `scripts/weak_test_detector.py` | Weak test detection (A1-A8 rules) |
| `scripts/antipattern_checker.py` | 50 antipatterns: 25 Tier A (AST) + 25 Tier B (BMAD) |
| `scripts/antipattern_judge.py` | Tier B antipattern context generator for BMAD agents |
| `scripts/principles_checker.py` | DRY, KISS, YAGNI, LoD, CoI |
| `scripts/mutation_analyzer.py` | Mutation kill-map analysis + per-module gate (OK/NOK) |
| `scripts/diversity_metric.py` | Test diversity scoring (Levenshtein edit distance) |

---

## Two-Tier Systems

Both SOLID and Antipatterns use a Two-Tier approach for maximum accuracy:

### Tier A: Fast AST Rules (Always Runs in L3A)
Deterministic checks using AST parsing — no external dependencies.

### Tier B: BMAD Multi-Agent Consensus (Runs in L3B)
For patterns needing semantic understanding:
- Uses context generators (`llm_solid_judge.py`, `antipattern_judge.py`)
- Spawns BMAD Party Mode with Winston (Architect) + Murat (Test Architect)
- Runs BMAD Adversarial Review to eliminate false positives
- Reaches consensus: violation confirmed if 2/3 agents agree

**Fallback:** If BMAD Party Mode is not available, Tier B patterns are marked as `SKIPPED`
and do not affect the global PASS/FAIL. Only Tier A results determine the outcome.

---

## Mutation Testing Gate

Mutation testing uses **per-module thresholds** defined in `{project-root}/pyproject.toml` under `[tool.quality-gate.mutation]`.

### How it works

1. **Layer 1 (step-02)** runs `mutation_analyzer.py --gate` which:
   - Parses `.mutmut/index.html` for kill statistics per file
   - Reads `pyproject.toml` `[tool.quality-gate.mutation]` for per-module thresholds
   - Compares each module's kill rate against its threshold
   - Outputs OK/NOK gate result with per-module table

2. **Layer 2 (step-03)** runs `mutation_analyzer.py` (original mode) for detailed kill-map analysis

### Managing Thresholds

Edit `pyproject.toml` `[tool.quality-gate.mutation]` section to:
- Set `global_kill_threshold` (fallback for modules without specific target)
- Set per-module `kill_threshold` under `[tool.quality-gate.mutation.modules.<name>]`
- Track module `status` (`"in_progress"`, `"passing"`, `"planned"`, `"future"`)
- Configure incremental strategy (`increment_step`, `target_final`)

### When Gate Fails (NOK)

If mutation testing FAILS, the agent should:
1. Report which modules failed and their scores vs thresholds
2. **RECOMMEND** activating the `mutation-testing` skill for guidance on improving weak tests

---

## Output Format

The checkpoint JSON follows this structure:

```json
{
  "checkpoint": "quality-gate",
  "timestamp": "2026-04-30T12:00:00Z",
  "PASS": true,
  "layers": {
    "layer3a_smoke_test": {
      "PASS": true,
      "ruff": {"status": "PASS", "violations": 0},
      "pyright": {"status": "PASS", "errors": 0},
      "check_headers": {"status": "PASS"},
      "SOLID_tier_a": {"S": "PASS", "O": "PASS", "L": "PASS", "I": "PASS", "D": "PASS"},
      "principles": {"DRY": "PASS", "KISS": "PASS", "YAGNI": "PASS", "LoD": "PASS", "CoI": "PASS"},
      "antipatterns_tier_a": {"passed": 23, "failed": 2}
    },
    "layer1_test_execution": { "PASS": true, ... },
    "layer2_test_quality": { "PASS": true, ... },
    "layer3b_deep_quality": {
      "PASS": true,
      "SOLID_tier_b": { "status": "PASS", "violations": [] },
      "antipatterns_tier_b": { "status": "SKIPPED" }
    }
  },
  "summary": {
    "total_tests": 150,
    "weak_test_count": 2,
    "SOLID_violations_tier_a": 0,
    "SOLID_violations_tier_b": 0,
    "principle_violations": 1,
    "antipattern_violations_tier_a": 3,
    "antipattern_violations_tier_b": 0
  }
}
