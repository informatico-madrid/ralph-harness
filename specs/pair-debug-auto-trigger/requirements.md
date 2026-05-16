---
spec: pair-debug-auto-trigger
phase: requirements
created: 2026-05-16T07:30:00Z
---

# Requirements: pair-debug-auto-trigger

## Goal

Make the spec-executor↔external-reviewer debugging collaboration fire automatically — via a mechanical 3-condition trigger and explicit Driver/Navigator roles — so agents pair on hard bugs without a human push. Spec 8 of engine-roadmap-epic; a thin orchestration layer over Spec 6's already-shipped collaboration machinery.

**Deployment model**: The Driver and Navigator are designed to run as **two separate agent instances** that coordinate purely through the shared filesystem (`chat.md`, `signals.jsonl`, `.ralph-state.json`) — no in-memory handoff, no Task-tool delegation between them. Each role is **exportable to a foreign agent runtime** (Roo Code, Qwen, Cursor, or any tool that can read/write files) so the Navigator can run on a different model/provider than the Driver. At the start of `/ralphharness:implement` the harness asks the developer where to run the pair-debug roles and, if a foreign runtime is chosen, either copies the role files there automatically or prints the exact file path and copy-paste text.

## User Stories

> Primary "user" = the autonomous RalphHarness loop itself, and the developer who runs `/ralphharness:implement` and currently has to manually push agents into hypothesis exchange.

### US-1: Pair-debug mode auto-triggers without a human push
**As a** developer running an autonomous spec execution
**I want to** have the harness enter pair-debug mode by itself when a fix is repeatedly failing
**So that** I no longer have to manually tell agents to "formulate hypotheses and listen to each other"

**Acceptance Criteria:**
- [ ] AC-1.1: When ALL three trigger conditions hold (pre-existing test failing + test file unchanged this spec + `taskIteration >= 2` + reviewer has not marked the task FAIL), the coordinator writes a `### PAIR-DEBUG MODE ACTIVATED` header to `chat.md` before generating the fix task — with NO human instruction. (Roadmap criterion 16.)
- [ ] AC-1.2: If ANY condition is false, no pair-debug announcement is written and the normal fix-task path runs unchanged.
- [ ] AC-1.3: Activation is observable ONLY via `chat.md` — no `.ralph-state.json` field and no `spec.schema.json` change. Tests verifying activation grep `chat.md` for the `### PAIR-DEBUG MODE ACTIVATED` header.
- [ ] AC-1.4: On a `taskIteration == 1` failure (no prior fix attempt), pair-debug mode does NOT activate.

### US-2: Driver/Navigator roles produce a collaborative root cause
**As a** developer debugging a hard bug autonomously
**I want to** have the executor and reviewer adopt distinct Driver and Navigator roles
**So that** they exchange hypotheses and converge on a root cause instead of issuing isolated sequential fix attempts

**Acceptance Criteria:**
- [ ] AC-2.1: `references/pair-debug.md` defines a Driver/Navigator role table — Driver = spec-executor (writes code, runs commands, applies fixes, adds debug logging); Navigator = external-reviewer (reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings).
- [ ] AC-2.2: The `### PAIR-DEBUG MODE ACTIVATED` announcement names `Driver: spec-executor` and `Navigator: external-reviewer` and instructs both to formulate and respond to hypotheses, and not to escalate to a human unless an explicit product/design decision is required.
- [ ] AC-2.3: In pair-debug mode, `chat.md` shows a hypothesis-exchange pattern (HYPOTHESIS/EXPERIMENT/FINDING signals from both agents), not a sequence of unilateral fix attempts. (Roadmap criterion 17.)
- [ ] AC-2.4: The Navigator (external-reviewer) never edits implementation files or `.ralph-state.json` — `external-reviewer.md`'s code-writing prohibition is unchanged by this spec.
- [ ] AC-2.5: `pair-debug.md` points to `collaboration-resolution.md` for the HYPOTHESIS→EXPERIMENT→FINDING→ROOT_CAUSE→FIX_PROPOSAL loop body and does NOT re-document that loop.

### US-3: Debug logging is a sanctioned, self-cleaning investigation technique
**As a** Driver instrumenting code to test a hypothesis
**I want to** add temporary debug logging that is explicitly allowed and mechanically guaranteed to be cleaned up
**So that** I can investigate freely without leaving orphan logs in shipped code

**Acceptance Criteria:**
- [ ] AC-3.1: `agents/spec-executor.md` lists debug logging as a sanctioned investigation technique, scoped to pair-debug mode: temporary `_LOGGER.warning()` / `console.log()` statements MAY be added.
- [ ] AC-3.2: The rule requires every temporary log to carry a consistent `PAIR-DEBUG:` marker in its message, and each log to record the suspect variable/code path and the hypothesis it tests (decision-path capture), not a bare "got here".
- [ ] AC-3.3: The rule requires removing or converting-to-test all `PAIR-DEBUG:`-tagged logs before emitting `TASK_COMPLETE`, verifiable by a single `grep` for the `PAIR-DEBUG:` marker returning empty. (Roadmap criterion 18.)

### US-4: Pair-debug mode cannot hang the loop
**As a** developer relying on autonomous execution to terminate
**I want to** have pair-debug mode bounded by the same hard limits as normal execution
**So that** a stuck pair session always exits — to success, or to a human

**Acceptance Criteria:**
- [ ] AC-4.1: The canonical SUCCESS exit is an explicit `ROOT_CAUSE` signal confirmed by the agents, followed by the fix task passing the previously-failing test.
- [ ] AC-4.2: Pair-debug mode reuses the existing `taskIteration` counter; the `taskIteration >= maxTaskIterations` (default 5) hard limit still applies and escalates to a human when exhausted. No new iteration counter or state field is introduced.
- [ ] AC-4.3: The hypothesis-cycle stalled-loop bound in `collaboration-resolution.md` is raised from `>3` to `>10` cycles before escalation. Pair-debug mode inherits this `>10 hypothesis cycles → escalate` bound as the stalled-loop safety exit; `pair-debug.md` references it and adds no competing bound.
- [ ] AC-4.4: There is no execution path in which pair-debug mode runs unbounded — ROOT_CAUSE is the success exit; the >10-cycle bound and the `taskIteration` hard limit are the safety exits.

### US-5: Pair-debug mode is operationally distinct, append-only, and version-tracked
**As a** maintainer of the RalphHarness plugin
**I want to** the change to be append-only to existing files, behaviorally distinct, and version-bumped
**So that** normal execution is unaffected and the plugin release is traceable

**Acceptance Criteria:**
- [ ] AC-5.1: `references/coordinator-pattern.md` documents the `### PAIR-DEBUG MODE ACTIVATED` chat.md announcement, reusing the existing atomic-append block, and states it replaces the normal delegation announcement for that one task only.
- [ ] AC-5.2: All edits to `failure-recovery.md`, `coordinator-pattern.md`, and `spec-executor.md` are append-only (new branches/sections) — no existing rule, condition, or role boundary is removed or weakened. The single exception is `collaboration-resolution.md` (FR-13), which receives one in-place value change (`>3` → `>10` cycles) to one sentence — no rule is removed or weakened, only a threshold raised.
- [ ] AC-5.3: Plugin version is bumped 5.2.0 → 5.3.0 in BOTH `plugins/ralphharness/.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json`.
- [ ] AC-5.4: Pair-debug mode is operationally distinct, not just a label: the announcement assigns concrete divergent behaviors (Driver instruments, Navigator hypothesizes) — not a generic restatement of normal execution.

### US-6: Driver and Navigator run as two separate, filesystem-coordinated instances
**As a** developer who wants the Navigator to run on a different model/provider than the Driver
**I want to** run the two pair-debug roles as independent agent instances over the same repository
**So that** I can pair, e.g., an Opus Driver with a Sonnet (or non-Anthropic) Navigator without either instance depending on the other's session

**Acceptance Criteria:**
- [ ] AC-6.1: `references/pair-debug.md` states that Driver and Navigator are designed to run as two separate instances coordinating ONLY through the shared filesystem (`chat.md`, `signals.jsonl`, `.ralph-state.json`) — no in-memory handoff, no Task-tool call from one role to the other.
- [ ] AC-6.2: Each role file carries a **Section 0 — Bootstrap (Self-Start)** block (modeled on `external-reviewer.md` Section 0): when invoked with no parameters, the agent self-discovers context by reading `specs/.current-spec`, `<basePath>/.ralph-state.json`, and the spec files — so it can run standalone in a foreign runtime.
- [ ] AC-6.3: The two instances are safe to run concurrently: every write to `chat.md` / `signals.jsonl` uses the existing atomic-append (`flock`) blocks; each role tracks its own `lastReadLine` and never assumes the other role shares its process.
- [ ] AC-6.4: Single-instance and separate-instance topologies are BOTH first-class and equally supported — the choice is the developer's, made via the US-7 placement question, not a fixed architectural decision. The same role files work unchanged in both topologies.
- [ ] AC-6.5: Foreign-runtime instances need NO RalphHarness plugin installed — a role file is self-contained: it carries (or points to) every rule it needs and depends only on filesystem access to the spec directory.

### US-7: The harness asks where to run pair-debug and helps export the role files
**As a** developer starting `/ralphharness:implement`
**I want to** be asked, once, where the pair-debug roles should run, and — if I pick a foreign agent — be helped to get the role files there
**So that** setting up a cross-provider pair is a guided step, not a manual file hunt

**Acceptance Criteria:**
- [ ] AC-7.1: At the start of `/ralphharness:implement` (in the same onboarding step as the parallel-reviewer question), the harness asks the developer where to run the pair-debug roles. This is an explicit **user decision**, never assumed by the harness. The options offered are at minimum: (a) both roles in this same instance, (b) a second Claude Code instance, (c) a foreign agent runtime (Roo Code, Qwen, Cursor, other). Single-instance vs. separate-instance is itself part of this choice — the harness must not pre-decide it.
- [ ] AC-7.2: If a foreign runtime is chosen, the harness asks which specific runtime, then offers TWO export modes and lets the developer pick: (a) **automatic copy** — the harness writes the role files into that runtime's conventional location; (b) **manual** — the harness prints the absolute source path of each role file AND the copy-paste-ready text/instructions.
- [ ] AC-7.3: For automatic copy, the destination path is resolved per known runtime (e.g. Roo Code → `.roo/commands/` or `.roo/skills/<name>/`, Qwen → `.qwen/commands/`); for an unknown runtime the harness falls back to manual mode and explains why.
- [ ] AC-7.4: In BOTH export modes the harness reports, explicitly: the absolute path(s) of the file(s), and what the developer must do next to activate the role in the chosen runtime. The current `external-reviewer` onboarding gap — telling the user to `@external-reviewer` with no path and no copy step — must NOT be reproduced.
- [ ] AC-7.5: If the developer picks "this same instance" (default), no files are copied and the pair runs in-session exactly as US-2 describes — the export step is skipped silently.
- [ ] AC-7.6: The export step is **idempotent and non-destructive**: re-running `/ralphharness:implement` re-detects an existing exported file and offers to overwrite/skip rather than failing or silently clobbering local edits.

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | Create `references/pair-debug.md` with: the 3-condition auto-trigger, the Driver/Navigator role table, the anti-anchoring rule, and a pointer to `collaboration-resolution.md` for the loop body. | High | File exists; contains all four sections; does not duplicate the HYPOTHESIS→FIX_PROPOSAL loop. |
| FR-2 | `pair-debug.md` states the trigger canonically as exactly **3 conditions** (a/b/c below), explicitly noting once that the reviewer-FAIL gate is condition (c) — reconciling the roadmap's "3" with plan.md's "4". ALL THREE must hold to trigger. | High | `pair-debug.md` states "3 conditions" and the reconciliation sentence verbatim once. |
| FR-3 | Trigger condition (a): a pre-existing test is failing AND its test file is unchanged this spec — `git diff $TASK_START_SHA..HEAD -- tests/` returns empty. Use the pre-existing-test proxy; do NOT require a per-test green/red snapshot. | High | `pair-debug.md` documents condition (a) using the existing `TASK_START_SHA` variable and the proxy phrasing; no per-test snapshot mechanism introduced. |
| FR-4 | Trigger condition (b): `taskIteration >= 2` — at least one fix attempt has failed — read via `jq` on `.ralph-state.json`. | High | Condition (b) documented as a `jq` read; no new counter. |
| FR-5 | Trigger condition (c): the external-reviewer has NOT marked the task FAIL — absence of a FAIL row for `taskIndex` in `task_review.md`, which the coordinator already parses. | High | Condition (c) documented; reuses existing `task_review.md` FAIL-row parsing. |
| FR-6 | Define Driver = spec-executor and Navigator = external-reviewer as ROLES of existing agents — no new agent type in the coordinator's delegation logic. Both share the instruction: formulate hypotheses, respond to the other's, do not escalate to a human unless an explicit product/design decision is required. The two exportable role files (FR-14) package these existing behaviors for standalone invocation; they do not register a new `subagent_type`. | High | Role table present; coordinator delegation references no new `subagent_type`; the role files of FR-14 are standalone-invocation packages, not coordinator-delegated agents. |
| FR-7 | Anti-anchoring rule in `pair-debug.md`: (i) the Navigator MUST propose ≥2 independent hypotheses — explicitly not anchored on the executor's already-failed first fix — before the pair commits to investigating one; (ii) a hypothesis becomes `ROOT_CAUSE` only after an EXPERIMENT produced direct evidence, not reasoning alone; (iii) reuse `collaboration-resolution.md`'s >10-cycle escalation bound as the stalled-loop exit. | High | All three sub-rules present in `pair-debug.md`. |
| FR-8 | Append to `references/failure-recovery.md` a new branch: when `taskIteration >= 2` AND the failing test is pre-existing AND no reviewer FAIL row → announce pair-debug mode before generating the fix task. The fix task becomes the Driver's first action. | High | New branch present, append-only; existing Max Retries / Recovery Mode / BUG_DISCOVERY sections unchanged. |
| FR-9 | Append to `agents/spec-executor.md` a debug-logging section: temporary logs allowed in pair-debug mode, tagged with the `PAIR-DEBUG:` marker, capturing the decision path, removed/converted before `TASK_COMPLETE` with a mechanical `grep` check. | High | Section present, append-only; `<role>` and Role Boundaries section unchanged. |
| FR-10 | Append to `references/coordinator-pattern.md` documentation of the `### PAIR-DEBUG MODE ACTIVATED` chat.md announcement (Driver/Navigator/Trigger summary/instruction), reusing the existing atomic-append block; states it replaces the normal delegation announcement for that one task only. | High | Section present, append-only; existing Signal/Chat Protocol sections unchanged. |
| FR-11 | Bump plugin version 5.2.0 → 5.3.0 (minor) in `plugins/ralphharness/.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json`. | High | Both files show 5.3.0. |
| FR-12 | Optionally add a one-line note to `templates/chat.md` that a `### PAIR-DEBUG MODE ACTIVATED` coordinator message may appear. No new signal type is added. | Low | If added, one line only; no change to the 6-signal legend. |
| FR-13 | Raise the hypothesis-cycle stalled-loop bound in `references/collaboration-resolution.md` from `>3` to `>10` cycles before escalation (single-sentence value change at line 53). This is a deliberate edit to a Spec 6 file — 3 cycles is too aggressive for a real debugging session. | High | `collaboration-resolution.md` reads `more than 10 times`; no other edit to that file. |
| FR-14 | Create two **exportable role files** — `agents/pair-debug-driver.md` and `agents/pair-debug-navigator.md` — each a self-contained agent definition with a Section 0 Bootstrap (self-discovery from `specs/.current-spec` + `.ralph-state.json`), an identity/role section, the filesystem-coordination protocol, and explicit exit conditions. These are role files for *existing* agent identities (Driver = spec-executor behavior, Navigator = external-reviewer behavior) packaged for standalone/foreign-runtime invocation — they introduce no new agent type in the coordinator's delegation logic. | High | Both files exist; each has a Section 0 Bootstrap; neither is referenced as a new `subagent_type` by the coordinator. |
| FR-15 | Each role file is **runtime-agnostic and self-contained**: it depends only on filesystem access to the spec directory and either inlines or clearly references every rule it needs (`pair-debug.md`, `collaboration-resolution.md`), so it works in an agent runtime with no RalphHarness plugin installed. | High | Role files contain no dependency on plugin-only paths that a foreign runtime cannot resolve; any reference is either inlined or accompanied by the snippet needed. |
| FR-16 | Add a **pair-debug placement step** to `/ralphharness:implement` onboarding (`commands/implement.md`), co-located with the existing Parallel Reviewer Onboarding. It asks the developer where to run the pair-debug roles: (a) this instance, (b) second Claude Code instance, (c) foreign runtime. Default = this instance. | High | `implement.md` has a new onboarding sub-section; default path leaves behavior unchanged when (a) is chosen. |
| FR-17 | When the developer picks a foreign runtime, the placement step asks **which runtime** and then offers two export modes: **automatic copy** (write role files into the runtime's conventional location) or **manual** (print absolute source paths + copy-paste text). The developer chooses the mode. | High | Both modes are offered and selectable; choosing manual never writes files; choosing automatic writes to the resolved destination. |
| FR-18 | Define a **runtime → destination-path map** for automatic copy (e.g. Roo Code → `.roo/commands/<name>.md`, Qwen → `.qwen/commands/<name>.md`). For an unrecognized runtime, fall back to manual mode and state the reason. The map lives in `references/pair-debug.md` (or a small companion section) so it is maintainable in one place. | Medium | Map documented; known runtimes resolve to a path; unknown runtime → manual fallback with explanation. |
| FR-19 | Both export modes MUST report, explicitly: the **absolute path** of every role file involved, and the **next action** to activate the role in the chosen runtime. This requirement exists to fix the known `external-reviewer` onboarding gap (`@external-reviewer` with no path, no copy step). | High | Onboarding output for both modes prints absolute paths and a concrete activation instruction; no `@name`-only instruction without a path. |
| FR-20 | The export step is **idempotent and non-destructive**: if a destination role file already exists, the harness detects it and asks overwrite/skip rather than failing or clobbering silently. Re-running `/ralphharness:implement` is safe. | Medium | Re-run with an existing exported file prompts overwrite/skip; no silent overwrite of a user-edited file. |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Trigger is mechanical/deterministic — no LLM interpretation in any of the 3 conditions. | conditions evaluable by `git diff` / `jq` / FAIL-row parse | 3/3 conditions mechanical |
| NFR-2 | No regression to the normal execution path — when the trigger does not fire, behavior is byte-identical to pre-spec. | existing failure-recovery / coordinator / executor behavior | unchanged |
| NFR-3 | Changes to existing files are append-only — no removal or weakening of existing rules, conditions, or role boundaries. The sole exception is the FR-13 threshold change in `collaboration-resolution.md` (a value raised, not a rule removed). | diff of the modified existing files | additions only, except FR-13's one-value change |
| NFR-4 | Pair-debug mode is operationally distinct — agents behave differently (Driver instruments, Navigator hypothesizes), not merely re-labeled. | announcement assigns divergent concrete actions | distinct behaviors specified |
| NFR-5 | No new *coordinator* infrastructure — no new `subagent_type` in delegation logic, no new hooks, no schema fields, no `.ralph-state.json` keys. New files are bounded: `references/pair-debug.md` plus the two exportable role files (`pair-debug-driver.md`, `pair-debug-navigator.md`). | new files: 3; new subagent_type / hook / schema changes: 0 | met |
| NFR-6 | Pair-debug mode is bounded — every entry path has a designed exit (success / >10-cycle / hard limit). | unbounded execution paths | 0 |
| NFR-7 | The two role files are runtime-portable — usable by an agent runtime with no RalphHarness plugin installed, depending only on filesystem access to the spec directory. | plugin-only path dependencies in role files | 0 |
| NFR-8 | The export step is non-destructive and idempotent — re-running `/ralphharness:implement` never silently overwrites a user-edited exported file. | silent clobbers on re-run | 0 |

## Glossary

- **Pair-debug mode**: An escalation posture (not a code state) in which spec-executor and external-reviewer adopt Driver/Navigator roles and collaborate on hypothesis-driven debugging. Announced solely via a `### PAIR-DEBUG MODE ACTIVATED` header in `chat.md`.
- **Driver**: Role of the spec-executor in pair-debug mode — writes code, runs commands, applies fixes, adds debug logging, runs experiments.
- **Navigator**: Role of the external-reviewer in pair-debug mode — reads diff, analyzes architecture, proposes hypotheses, suggests experiments, validates findings; never writes implementation code.
- **Pre-existing-test proxy**: A test is treated as "was green, now red" if its test file is unchanged since `TASK_START_SHA` AND it is not the output of a `[RED]` task in this spec. Used because no per-test green/red snapshot infrastructure exists.
- **TASK_START_SHA**: The `git rev-parse HEAD` recorded by the coordinator before delegating any task (coordinator-pattern.md:345, already exists). Enables `git diff $TASK_START_SHA..HEAD -- tests/`.
- **3-condition trigger**: The canonical, mechanical entry rule for pair-debug mode — conditions (a) pre-existing test failing + test file unchanged, (b) `taskIteration >= 2`, (c) no reviewer FAIL row. ALL three must hold.
- **Role file**: A self-contained agent definition (`pair-debug-driver.md` / `pair-debug-navigator.md`) carrying a Section 0 Bootstrap, identity, coordination protocol, and exit conditions — packaged so it can be invoked standalone in any agent runtime with filesystem access to the spec directory.
- **Section 0 Bootstrap (Self-Start)**: The self-discovery block at the top of a role file. When invoked with no parameters it reads `specs/.current-spec`, `<basePath>/.ralph-state.json`, and the spec files to recover its context — modeled on `external-reviewer.md` Section 0.
- **Foreign runtime**: An agent runtime other than the Driver's Claude Code instance (Roo Code, Qwen, Cursor, etc.) — possibly a different model/provider. It needs no RalphHarness plugin; it needs only filesystem access to the spec directory.
- **Placement question**: The onboarding question at the start of `/ralphharness:implement` asking the developer where to run the pair-debug roles — same instance, second Claude Code instance, or a foreign runtime — and, for a foreign runtime, which one and which export mode.
- **Export mode**: How role files reach a foreign runtime — **automatic copy** (harness writes the files into the runtime's conventional location) or **manual** (harness prints absolute source paths + copy-paste text).

## Out of Scope

- New agent *types in the coordinator's delegation logic* — Driver/Navigator are roles of the existing spec-executor and external-reviewer. The two exportable role files (FR-14) package these existing behaviors for standalone/foreign-runtime invocation; the coordinator delegates no new `subagent_type`.
- Loosening the external-reviewer's prohibition on writing code — Navigator reads, hypothesizes, proposes; never edits implementation files.
- Making pair-debug mode the default — it is an escalation path, not the normal execution mode.
- Micro-rules on *how* to debug — the loop body lives in `collaboration-resolution.md` and is not duplicated.
- A `pairDebugMode` flag in `.ralph-state.json` or `spec.schema.json` — activation is chat.md-only.
- A new iteration counter — pair-debug reuses `taskIteration`.
- Per-test green/red CI snapshot infrastructure — the pre-existing-test proxy is used instead.
- A new signal type — the announcement is a coordinator chat.md message; the 6 collaboration signals are reused as-is.
- Coordinator core-loop changes, new hooks, schema changes.
- Building runtime adapters or plugins for foreign agents (Roo Code, Qwen, etc.) — the export step copies/points-to self-contained role files; it does not author runtime-specific integrations beyond the destination-path map (FR-18).
- Automatic detection of which foreign runtime the developer uses — the developer states the runtime in the placement question (US-7).
- Live cross-instance process supervision — the harness does not monitor or restart a foreign Navigator instance; coordination is filesystem-only and each instance is launched by the developer.
- Anything belonging to Spec 9 (pre-execution-critic) or Spec 10 (context-middleware).

## Dependencies

- **Spec 6 (collaboration-resolution)** — load-bearing. Its HYPOTHESIS/EXPERIMENT/FINDING/ROOT_CAUSE/FIX_PROPOSAL signals, experiment-propose-validate loop, BUG_DISCOVERY fix-task trigger, baseline check, and >10-cycle escalation bound are all reused. `pair-debug.md` references `collaboration-resolution.md`; it must not duplicate or fork its loop body.
- **Spec 3 (role-boundaries)** — the Driver/Navigator roles must not loosen `role-contracts.md` / agent-file role boundaries. Reviewer-cannot-write-code is load-bearing and unchanged.
- Existing harness machinery: `TASK_START_SHA` (coordinator-pattern.md:345), `taskIteration` / `maxTaskIterations` (`.ralph-state.json`), `task_review.md` FAIL-row parsing, the atomic chat.md append block.
- **`external-reviewer.md` Section 0 Bootstrap** — the self-discovery pattern the two new role files copy. The existing `external-reviewer` onboarding in `implement.md` is a *negative* reference: its gap (`@external-reviewer` with no path, no copy step) is the specific failure FR-19 exists to avoid.
- **`commands/implement.md` onboarding** — the placement step (FR-16/17) is added co-located with the existing Parallel Reviewer Onboarding sub-section.

## Success Criteria

- Roadmap criterion 16: pair-debug auto-triggers without a human push (verified via `chat.md` on `taskIteration >= 2`).
- Roadmap criterion 17: Driver/Navigator collaboration produces a root cause — `chat.md` shows hypothesis exchange, not sequential fix attempts.
- Roadmap criterion 18: debug logging is used and fully cleaned up — `grep` for `PAIR-DEBUG:` returns empty after the session.
- Normal execution path is unaffected when the trigger does not fire.
- The Driver and Navigator can run as two separate instances on different models/providers, coordinating purely through the shared filesystem.
- `/ralphharness:implement` asks where to run the pair-debug roles and, for a foreign runtime, helps export the role files via automatic copy or manual path+text — always reporting absolute paths and the next activation step.
- Three new files (`pair-debug.md` + two role files), four append-only edits, one one-value threshold change (`collaboration-resolution.md`), one version bump — no new coordinator `subagent_type`, hook, or schema change.

## Verification Contract

**Project type**: cli

> RalphHarness is a Claude Code plugin: prompts, reference markdown, and shell hooks. No browser UI, no HTTP API, no runtime server. The deliverable is invoked via `/ralphharness:*` slash commands. e2e routing type = `cli`.

**Entry points**:
- `references/pair-debug.md` (NEW reference file, loaded by coordinator/agents on pair-mode escalation; also holds the runtime→destination-path map)
- `agents/pair-debug-driver.md` and `agents/pair-debug-navigator.md` (NEW exportable role files with Section 0 Bootstrap)
- `references/failure-recovery.md` — new pair-debug branch in the fix-task generation path
- `references/coordinator-pattern.md` — new `### PAIR-DEBUG MODE ACTIVATED` announcement documentation
- `agents/spec-executor.md` — new debug-logging investigation section
- `commands/implement.md` — new pair-debug placement step in onboarding (where-to-run + export mode)
- `plugins/ralphharness/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — version 5.3.0
- Runtime surface: the placement question at the start of `/ralphharness:implement`; the coordinator's failure-recovery path; observable output is the `chat.md` announcement and the export onboarding text

**Observable signals**:
- PASS looks like:
  - `references/pair-debug.md` exists with the 3-condition trigger, Driver/Navigator role table, anti-anchoring rule, a pointer to `collaboration-resolution.md`, and the runtime→destination-path map.
  - `agents/pair-debug-driver.md` and `agents/pair-debug-navigator.md` exist, each with a Section 0 Bootstrap and no plugin-only path dependency.
  - In an execution where a pre-existing test fails twice (`taskIteration` reaches 2) with the test file unchanged and no reviewer FAIL row, `chat.md` contains a `### PAIR-DEBUG MODE ACTIVATED` header naming Driver and Navigator.
  - `chat.md` shows HYPOTHESIS/EXPERIMENT/FINDING signals from both agents.
  - After the pair session, `grep -r 'PAIR-DEBUG:' <impl files>` returns empty.
  - `/ralphharness:implement` asks the placement question; choosing a foreign runtime offers both export modes; both modes print absolute paths and a concrete activation step.
  - Both `plugin.json` and `marketplace.json` show `5.3.0`.
- FAIL looks like:
  - `taskIteration == 1` failure produces a pair-debug announcement (premature trigger).
  - Trigger fires when the failing test was authored this spec or its test file changed (false trigger).
  - `chat.md` shows only sequential unilateral fix attempts with no hypothesis exchange.
  - Orphan `PAIR-DEBUG:`-tagged logs remain after `TASK_COMPLETE`.
  - A `pairDebugMode` field appears in `.ralph-state.json` or `spec.schema.json`.
  - An existing rule/condition/role boundary in a modified file was removed or weakened.
  - The placement step exports a role file but tells the user only `@name` with no absolute path (the known `external-reviewer` onboarding gap reproduced).
  - The export step silently overwrites a user-edited exported role file on re-run.
  - A role file references a plugin-only path a foreign runtime cannot resolve.

**Hard invariants**:
- External-reviewer (Navigator) never edits implementation files or `.ralph-state.json` — Spec 3 role boundaries unchanged.
- `.ralph-state.json` schema is unchanged — no new fields.
- The `maxTaskIterations` hard limit and `collaboration-resolution.md`'s >10-cycle bound still terminate execution; pair-debug mode never runs unbounded.
- Normal (non-triggered) failure-recovery, coordinator, and executor behavior is byte-identical to pre-spec.
- The 6 collaboration signals and the chat.md signal legend are unchanged.
- The coordinator delegates no new `subagent_type` — the two role files are standalone-invocation packages, not coordinator-delegated agents.
- The export step is non-destructive — it never overwrites a user-edited destination file without an explicit overwrite confirmation.
- Choosing "this same instance" at the placement question leaves onboarding behavior byte-identical to pre-spec (export step skipped silently).
- Role files depend only on filesystem access to the spec directory — no plugin-only path a foreign runtime cannot resolve.

**Seed data**:
- A spec with at least one pre-existing test (green at `TASK_START_SHA`) and a code path that can be intentionally broken so a first fix attempt fails — driving `taskIteration` to 2.
- `.ralph-state.json` with `taskIteration` and `maxTaskIterations` (default 5) present.
- A `task_review.md` with no FAIL row for the failing task's index.
- A clean git tree at task start so `TASK_START_SHA` and `git diff` are meaningful.

**Dependency map**:
- `collaboration-resolution.md` — shares the HYPOTHESIS→FIX_PROPOSAL loop and the >10-cycle bound; regression-check that pair-debug.md only references it.
- `failure-recovery.md` — shares the fix-task generation path (Max Retries, Recovery Mode, BUG_DISCOVERY); regression-check those branches still fire when pair mode does not.
- `coordinator-pattern.md` — shares the atomic chat.md append block and `TASK_START_SHA`.
- `spec-executor.md` / `external-reviewer.md` — share role-boundary contracts (Spec 3); regression-check boundaries unchanged.
- `templates/chat.md` — shares the signal legend.

**Escalate if**:
- The pre-existing-test proxy proves insufficient to distinguish a genuine regression from a flaky/env failure in a real run (would need product input on tightening condition (a)).
- A modified file cannot accept the change append-only without restructuring an existing section.
- Implementing the trigger appears to require a coordinator core-loop change, a new hook, or a schema field.
- Pair-debug mode is found to be reachable in a state with no designed exit.

## Unresolved Questions

- None blocking. Interview decisions are locked: shared `taskIteration`, no `pairDebugMode` flag, ROOT_CAUSE-plus-safety-nets exit; the pre-existing-test proxy for "was green, now red" is accepted per research recommendation 2 and plan.md AC#2; separate-vs-same instance is a developer choice (US-7); export offers both automatic-copy and manual modes.
- Open for design to settle (not blocking requirements): the exact set of foreign runtimes seeded into the destination-path map (FR-18) — Roo Code and Qwen are confirmed; Cursor and others may be added if their conventional location is known.

## Next Steps

1. Run `/ralphharness:design` to define: the exact content/structure of `pair-debug.md` and the two role files (`pair-debug-driver.md`, `pair-debug-navigator.md`) including their Section 0 Bootstrap; the placement-step dialog in `implement.md`; the runtime→destination-path map; the precise insertion points/anchor text for the four append-only edits; and the exact line for the FR-13 `collaboration-resolution.md` threshold change.
2. Confirm the `git diff $TASK_START_SHA..HEAD -- tests/` invocation and the failing-test-path extraction belong in the `failure-recovery.md` branch.
3. Proceed to `/ralphharness:tasks` once design is approved.
