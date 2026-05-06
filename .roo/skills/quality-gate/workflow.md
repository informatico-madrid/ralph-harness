# Quality Gate Workflow

**Goal:** Execute deterministic code quality validations across 4 layers (L3A→L1→L2→L3B), generating a checkpoint JSON consumed by RalphHarness VERIFY steps.

**Role:** You are a quality gate executor. You run smoke test (Tier A AST), test execution, test quality analysis, and deep code quality checks (Tier B BMAD) and produce a PASS/FAIL checkpoint. No subjectivity, no opinions — only measurable criteria.

---

## PATH RESOLUTION

- `{skill-root}` resolves to this workflow skill's installed directory.
- `{project-root}` resolves to the repository working directory.
- Resolve sibling workflow files such as `instructions.md`, `checklist.md`, `steps-c/...`, `steps-v/...`, and templates from `{skill-root}`, not from the workspace root.

---

## WORKFLOW ARCHITECTURE

This workflow uses **step-file architecture** for disciplined execution:

- **Micro-file Design**: Each step is self-contained and followed exactly
- **Just-In-Time Loading**: Only load the current step file
- **Sequential Enforcement**: Complete steps in order, no skipping
- **State Tracking**: Persist progress via in-memory variables
- **Append-Only Building**: Build artifacts incrementally

### Step Processing Rules

1. **READ COMPLETELY**: Read the entire step file before acting
2. **FOLLOW SEQUENCE**: Execute sections in order
3. **WAIT FOR INPUT**: Halt at checkpoints and wait for human
4. **LOAD NEXT**: When directed, read fully and follow the next step file

### Critical Rules (NO EXCEPTIONS)

- **NEVER** load multiple step files simultaneously
- **ALWAYS** read entire step file before execution
- **NEVER** skip steps or optimize the sequence
- **ALWAYS** follow the exact instructions in the step file
- **ALWAYS** halt at checkpoints and wait for human input

### Anti-Evasion Policy (ZERO TOLERANCE)

The following agent excuses are **INVALID** and must be rejected:

| Excuse | Why it's invalid | Required action |
|--------|-----------------|-----------------|
| "I didn't write this code" / "pre-existing problem" | The quality gate evaluates the ENTIRE codebase, not just recent changes. If code exists in the repo, it must meet standards. | Fix the issue or flag it as a blocking technical debt item. |
| Adding `# pragma: no cover` to skip coverage | This hides dead code instead of removing it or writing tests. Only acceptable for truly unreachable defensive code (e.g., abstract method stubs). | Remove dead code, OR write tests, OR refactor to make testable. |
| Using mocks where fixtures are needed | If a mock cannot replicate the real behavior needed to test the logic, the test is worthless. | Replace mock with pytest fixture, factory, or real dependency. |
| "The code is too complex to test" | Untestable code is a design smell, not a testing problem. | Refactor the source code (extract methods, inject dependencies, reduce coupling) until it becomes testable. |
| Creating shallow tests just to pass coverage | 100% coverage with trivial assertions (e.g., `assert True`) is worse than no coverage — it gives false confidence. | Write meaningful tests that verify behavior, not just execution. |
| "This is a known limitation" | Known limitations that affect quality must be tracked as blocking issues, not dismissed. | Create a blocking issue and fix it before COMMIT. |

**Enforcement:** If the quality gate finds violations, the agent MUST fix them. There are no exceptions for "pre-existing" code. The checkpoint will remain FAIL until all violations are resolved.

---

## LAYER EXECUTION ORDER: L3A → L1 → L2 → L3B

### Why This Order?

1. **Fail-Fast**: L3A (Tier A AST, <1 min) is the smoke test. If code quality fails, don't waste time on mutation testing (~15 min) or BMAD Party Mode (~15 min).

2. **Resource Protection**: Mutation testing and BMAD Party Mode are the most expensive operations. They only run if L3A (fast checks) passes first.

3. **Iterative Refactoring Safety**: When L3B fails and refactorización breaks tests, we go back to L3A (not L1), saving ~15 min of mutation testing per cycle.

### Layer Duration Estimates

| Layer | Content | Duration |
|-------|---------|----------|
| **L3A** | Tier A AST smoke test (ruff, pyright, SOLID Tier A, principles, antipatterns Tier A) | <1 min |
| **L1** | Test execution (pytest, coverage, mutation testing, E2E) | ~15 min |
| **L2** | Test quality analysis (weak tests, kill-map, diversity) | ~2 min |
| **L3B** | Tier B BMAD Party Mode (SOLID Tier B, antipatterns Tier B) | ~15 min |

---

## LAYERS OVERVIEW

```
+-------------------------------------------------------------------------------------------+
|                               quality-gate                                                |
+----------------------------+----------------------------+-----------------------------+
|  Layer 3A (SMOKE TEST)     |  Layer 1                   |  Layer 2                     |
|  TIER A AST (<1 min)       |  TEST EXECUTION (~15 min)  |  TEST QUALITY (~2 min)       |
+----------------------------+----------------------------+-----------------------------+
|  3A.1 ruff check           | 1.1 pytest                 | 2.1 Weak-test detection     |
|  3A.2 ruff format check    | 1.2 coverage               | 2.2 Mutation kill-map       |
|  3A.3 pyright              | 1.3 mutation testing       | 2.3 Diversity metric        |
|  3A.4 check_headers        | 1.4 orphan cleanup         |                              |
|  3A.5 SOLID Tier A         | 1.5 E2E (make e2e) [MAND.] |                              |
|  3A.6 Principles            |                             |                              |
|      (DRY/KISS/YAGNI/LoD/CoI)                             |                              |
|  3A.7 Antipatterns Tier A   |                             |                              |
+----------------------------+----------------------------+-----------------------------+
|                                                                                           |
|                                                                                           v
|                                                                              +-----------------------------+
|                                                                              |      Layer 3B (DEEP)         |
|                                                                              |      TIER B BMAD (~15 min)   |
|                                                                              +-----------------------------+
|                                                                              | 3B.1 SOLID Tier B            |
|                                                                              |     (BMAD Party Mode)        |
|                                                                              | 3B.2 Antipatterns Tier B     |
|                                                                              |     (BMAD Party Mode)        |
+------------------------------------------------------------------------------+-----------------------------+
                                      |
                                      v
                          +---------------------------+
                          |    quality-gate.json      |
                          |    (checkpoint output)    |
                          +---------------------------+
```

### Fail-Fast Rule

**If L3A FAIL → STOP immediately. Do not execute L1, L2, or L3B.**

The rationale: If code quality smoke test fails, running mutation testing (~15 min) is wasted effort. Fix the code quality issues first.

### Recovery Playbook

| When | Action |
|------|--------|
| L3A FAIL | Refactorizar código → volver a L3A (máximo 3 reintentos) |
| L1 FAIL | Arreglar tests → volver a L1 |
| L2 FAIL | Mejorar tests → volver a L2 |
| L3B FAIL | Refactorizar código → volver a L3A (NO a L1) |

**Important**: When L3B fails after L1+L2 passed, we go back to L3A (not L1) because the refactorización may have broken code quality (detectable by L3A's fast AST checks) without breaking tests. This saves ~15 min of mutation testing per recovery cycle.

---

## LAYER 3A: Tier A Smoke Test (<1 min)

- **3A.1** ruff check + format check
- **3A.2** pyright type check
- **3A.3** check_headers
- **3A.4** SOLID Tier A (fast AST via `solid_metrics.py`)
- **3A.5** DRY, KISS, YAGNI, LoD, CoI (via `principles_checker.py`)
- **3A.6** Antipatterns Tier A (25 patterns via `antipattern_checker.py`)

---

## LAYER 1: Test Execution

- **1.1** kill_pytest_orphans (cleanup)
- **1.2** pytest tests/
- **1.3** coverage check
- **1.4** mutation testing with per-module gate (`mutation_analyzer.py --gate`)
  - Reads thresholds from `{project-root}/plans/mutation-targets.yaml`
  - Outputs OK/NOK per module with human-readable table
  - If NOK: recommend activating `mutation-testing` skill
- **1.5** E2E tests via `make e2e` (**MANDATORY** — FAILS if not run or fails)

---

## LAYER 2: Test Quality Analysis

- **2.1** Weak test detection (A1-A8 rules)
- **2.2** Mutation kill-map analysis
- **2.3** Test diversity metric

---

## LAYER 3B: Tier B Deep Quality (~15 min)

- **3B.1** SOLID Tier B (BMAD Party Mode + Adversarial via `llm_solid_judge.py`)
- **3B.2** Antipatterns Tier B (BMAD Party Mode + Adversarial via `antipattern_judge.py`)

### Two-Tier System Reminder

Both SOLID (Layer 3A.4 + 3B.1) and Antipatterns (Layer 3A.6 + 3B.2) use a Two-Tier approach:

| Tier | Method | When |
|------|--------|------|
| **Tier A** | Fast AST rules (deterministic Python scripts) | Always runs (L3A) |
| **Tier B** | BMAD Party Mode + Adversarial (multi-agent consensus) | For patterns needing semantic understanding (L3B) |

**Tier B Fallback:** If BMAD Party Mode is not available or the user skips it, Tier B patterns are marked as `SKIPPED` and do not affect the global PASS/FAIL. Only Tier A results determine the outcome.

---

## INITIALIZATION SEQUENCE

### 1. Configuration Loading

Load config from `{skill-root}/config/quality-gate.yaml`.

If no config found, use defaults:
- `output_folder = _bmad-output/quality-gate`
- `timestamp = current datetime ISO format`
- `checkpoint_file = {output_folder}/quality-gate-{timestamp}.json`

### 2. First Step Execution

Read fully and follow: `./steps/step-01-init.md` to begin the workflow.

**Important**: After initialization, the workflow proceeds to `./steps/step-03a-layer3a.md` (L3A smoke test), NOT to step-02-layer1.md (L1). This is the new order: L3A → L1 → L2 → L3B.

---

## KEY FILES REFERENCE

| File | Purpose |
|------|---------|
| `steps/step-01-init.md` | Initialization and state setup |
| `steps/step-03a-layer3a.md` | Layer 3A: Tier A smoke test (NEW - first after init) |
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
| `scripts/mutation_analyzer.py` | Mutation kill-map analysis |
| `scripts/diversity_metric.py` | Test diversity scoring |
