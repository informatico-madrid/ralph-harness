# Requirements: Pre-Execution Security Critic

> Spec 9 of engine-roadmap-epic. Converts Spec 3's role-boundary rules from "prompt text the agent may ignore" into "constraints enforced by code." Adopts the OpenHands SDK SecurityAnalyzer + SecurityRisk + ConfirmRisky + Hooks (exit-code-2) pattern. Scope: **Core mechanical enforcement** — deterministic, no extra LLM calls.

## Goal

Add a mechanical pre-execution check that the coordinator runs before dispatching each task — hard-blocking role-contract violations and dangerous shell patterns, pausing HIGH/UNKNOWN-risk actions for explicit human confirmation, and recording every decision to `signals.jsonl`.

---

## User Stories

### US-1 — Hard-Block Role-Contract Violations (Layer 1)

**As a** RalphHarness operator
**I want** a delegated task that would write a file outside the target agent's `Writes` set (per `role-contracts.md`) blocked before it dispatches
**So that** role boundaries are enforced by code, not by prompt text the agent may ignore

**Acceptance Criteria:**
- **AC-1.1** `pre-execution-check.sh` receives the target agent role and the file path(s) the task intends to write, and resolves them against the `## Access Matrix` in `references/role-contracts.md`.
- **AC-1.2** A write to a path matching the role's `Denylist`, or a write outside the role's `Writes` set, is classified as a Layer 1 violation and **hard-blocks** — the script exits `2` with no confirmation path.
- **AC-1.3** Layer 1 blocks are unconditional: they are NOT subject to the ConfirmRisky threshold and CANNOT be approved by the coordinator. The only resolution is fixing the task or the role contract.
- **AC-1.4** When `role-contracts.md` is missing or the role is not found in the matrix, Layer 1 returns `UNKNOWN` (not `allow`) — see US-2 confirmation handling.

### US-2 — Pause HIGH/UNKNOWN Risk for Human Confirmation (Layer 3 + ConfirmRisky)

**As a** RalphHarness operator
**I want** a delegated action classified `HIGH` or `UNKNOWN` risk to pause delegation and wait for my explicit confirmation
**So that** dangerous-but-legitimate operations are not silently executed, and the engine does not lock up on actions it cannot classify

**Acceptance Criteria:**
- **AC-2.1** Every delegated task is assigned exactly one `SecurityRisk` level: `LOW`, `MEDIUM`, `HIGH`, or `UNKNOWN`. When multiple layers fire, the **highest (worst-case) risk wins** (max-severity, never averaging).
- **AC-2.2** The policy is fixed `ConfirmRisky(threshold=HIGH, confirm_unknown=true)`: `LOW`/`MEDIUM` → allow; `HIGH` → require confirmation; `UNKNOWN` → require confirmation.
- **AC-2.3** On a confirmation verdict the script exits `2`; the coordinator pauses delegation, surfaces the script's reason text to the human, and dispatches the task only after explicit human approval.
- **AC-2.4** Human approval of a confirmable action is recorded as a follow-up `security-decision` event (US-4) and does not require re-running the check.
- **AC-2.5** `UNKNOWN` always triggers confirmation, never a hard block and never a silent allow — preventing both lockout and unsafe pass-through.

### US-3 — Block Dangerous Shell Patterns (Layer 2)

**As a** RalphHarness operator
**I want** known-dangerous shell commands in a delegated task blocked regardless of which agent runs them
**So that** catastrophic operations are stopped by signature, independent of role

**Acceptance Criteria:**
- **AC-3.1** Layer 2 scans the task's intended shell command text against a deterministic pattern set covering at minimum: `rm -rf`, `sudo`, `chmod 777`, `curl | sh` / `wget | sh` (fetch piped to a shell), and `eval`.
- **AC-3.2** A Layer 2 pattern match classifies the action `HIGH` risk; combined with AC-2.2 this routes to confirmation. (Layer 2 does not hard-block — only Layer 1 hard-blocks.)
- **AC-3.3** Pattern matching is purely textual/regex and deterministic — no LLM call, no network call.
- **AC-3.4** When no task shell command is supplied to the script, Layer 2 is a no-op and contributes `LOW` risk.

### US-4 — Audit Every Pre-Execution Decision

**As a** developer reviewing a spec run
**I want** each allow / block / confirm decision recorded as a structured event in `signals.jsonl`
**So that** I can replay and audit the engine's security decisions without re-running the loop

**Acceptance Criteria:**
- **AC-4.1** Every invocation of `pre-execution-check.sh` appends exactly one `security-decision` event to `specs/<name>/signals.jsonl` via the existing `append_signal` helper in `lib-signals.sh` (flock fd 202, JSON validated before write).
- **AC-4.2** The event records: `type:"security-decision"`, `decision` (`allow`/`block`/`confirm`), `layer` (`role-contract`/`shell-pattern`/`risk`/`none`), `risk` (`LOW`/`MEDIUM`/`HIGH`/`UNKNOWN`), `agent`, `task`, `path` (if applicable), `command` (if applicable), `reason`, `timestamp` (ISO-8601 UTC), `iteration`.
- **AC-4.3** `security-decision` events are append-only and existing lines are never edited — consistent with the Spec 4 immutability rule.
- **AC-4.4** `replay-signals.sh` continues to function over a log containing `security-decision` events; security decisions are visible in replay output.

### US-5 — Deterministic Exit-Code Contract

**As a** RalphHarness coordinator
**I want** a stable exit-code contract from `pre-execution-check.sh`
**So that** the gate is a mechanical check with no LLM interpretation

**Acceptance Criteria:**
- **AC-5.1** Exit `0` = allow: the action is permitted; the coordinator dispatches the task.
- **AC-5.2** Exit `2` = block/confirm: the coordinator does NOT dispatch. For a Layer 1 hard-block, no confirmation path exists. For a confirmable verdict (HIGH/UNKNOWN), the coordinator pauses for human approval.
- **AC-5.3** Any other non-zero exit = non-blocking script error: a WARN line is written to `.progress.md`; the coordinator treats the action as `UNKNOWN` and routes to confirmation (fail-safe, never fail-open).
- **AC-5.4** The script writes its human-readable reason to `stderr`; `stdout` is reserved for the (optional) structured verdict line.
- **AC-5.5** The exit-code contract matches the OpenHands SDK PreToolUse hook contract (`0` proceed, `2` block).

---

## Functional Requirements

| ID    | Requirement | Priority | Maps To |
|-------|-------------|----------|---------|
| FR-1  | Create `hooks/scripts/pre-execution-check.sh` accepting `--agent`, `--task`, `--paths`, `--command`, `--spec-path` and emitting an exit code per the US-5 contract | High | US-5 |
| FR-2  | Layer 1: parse the `## Access Matrix` table in `references/role-contracts.md`; classify writes outside `Writes` or matching `Denylist` as a hard-block | High | US-1 |
| FR-3  | Layer 2: deterministic regex set for dangerous shell patterns (`rm -rf`, `sudo`, `chmod 777`, fetch-piped-to-shell, `eval`); match → `HIGH` | High | US-3 |
| FR-4  | Layer 3: risk classifier assigning `LOW`/`MEDIUM`/`HIGH`/`UNKNOWN`; combine all layers by max-severity | High | US-2 |
| FR-5  | Apply fixed `ConfirmRisky(threshold=HIGH, confirm_unknown=true)` policy to the combined risk to produce the allow/block/confirm verdict | High | US-2 |
| FR-6  | Append one `security-decision` event per invocation via `append_signal` from `lib-signals.sh` | High | US-4 |
| FR-7  | Define the `security-decision` event shape in `schemas/spec.schema.json` (or the signals schema) with the AC-4.2 fields | High | US-4 |
| FR-8  | Update `commands/implement.md`: coordinator invokes `pre-execution-check.sh` before each task delegation; on exit `2` either hard-stop (Layer 1) or pause for human confirmation (HIGH/UNKNOWN) | High | US-1, US-2, US-5 |
| FR-9  | Header comment + commented example `security-decision` line added to `templates/signals.jsonl` | Medium | US-4 |
| FR-10 | Fail-safe handling: missing `role-contracts.md`, unknown role, or script error → `UNKNOWN` → confirmation; WARN to `.progress.md` | High | AC-1.4, AC-5.3 |
| FR-11 | Update `references/role-contracts.md`: add `pre-execution-check.sh` to the Access Matrix as a read-only consumer; note it as the mechanical enforcer of the matrix | Medium | US-1 |

---

## Non-Functional Requirements

| ID    | Property | Metric / Target |
|-------|----------|-----------------|
| NFR-1 | Determinism | Zero LLM calls and zero network calls in `pre-execution-check.sh`; identical inputs always yield the identical verdict |
| NFR-2 | Speed | Single invocation completes < 100 ms — the check runs before every delegation and must not perceptibly slow the loop |
| NFR-3 | No false-positive lockout | `UNKNOWN` and script errors route to confirmation, never to a silent hard-block; only Layer 1 violations hard-block |
| NFR-4 | Fail-safe (never fail-open) | Any indeterminate state (missing contract, parse error, unexpected exit) is treated as `UNKNOWN`/confirm, never as `allow` |
| NFR-5 | Backward compatibility | Existing specs run unchanged: a spec with no `signals.jsonl` gets one created on first decision; a `LOW`/`MEDIUM` verdict is a transparent pass-through |
| NFR-6 | Auditability | Every decision is reconstructable from `signals.jsonl` alone via `replay-signals.sh`, with no need to re-run the loop |
| NFR-7 | Portability | Reuses `lib-signals.sh` `jq` + `grep` fallback path; the check degrades gracefully (to confirmation) where `jq` is absent |

---

## Glossary

- **Pre-execution check** — the `hooks/scripts/pre-execution-check.sh` script the coordinator runs before dispatching each task; classifies the action and emits an allow/block/confirm verdict via exit code.
- **SecurityRisk** — the risk level assigned to a delegated action. `LOW` = read-only / no state change; `MEDIUM` = modifies user data; `HIGH` = dangerous operation (deletion, privilege escalation, system commands); `UNKNOWN` = not analyzed or indeterminate.
- **Layer 1 (role-contract)** — deterministic check that a target agent's intended file writes stay within its `Writes` set and outside its `Denylist` per `role-contracts.md`. Violations hard-block.
- **Layer 2 (shell-pattern)** — regex check for known-dangerous shell commands, applied regardless of agent. Matches classify the action `HIGH`.
- **Layer 3 (risk classification)** — assigns a `SecurityRisk` level to every delegated action; combined with the other layers by max-severity.
- **role-contract** — the per-agent `Reads` / `Writes` / `Denylist` access record in the `## Access Matrix` of `references/role-contracts.md` (Spec 3).
- **ConfirmRisky** — the fixed confirmation policy: `threshold=HIGH`, `confirm_unknown=true`. `LOW`/`MEDIUM` allow; `HIGH`/`UNKNOWN` require human confirmation.
- **Hard-block** — an unconditional `exit 2` with no confirmation path; only Layer 1 violations produce this.
- **Confirmation (pause)** — an `exit 2` that the coordinator resolves by pausing delegation and waiting for explicit human approval.
- **security-decision event** — a `signals.jsonl` event recording one allow/block/confirm decision (the audit trail).
- **Exit-code contract** — `0` = allow, `2` = block/confirm, other non-zero = non-blocking error → treated as `UNKNOWN`.

---

## Out of Scope

Deferred to v2 — explicitly NOT in this spec:

- **Native Claude Code PreToolUse hook** — this iteration enforces via a coordinator-invoked shell script, not a native `PreToolUse` hook.
- **LLM-based risk analysis** — risk classification is deterministic (rules + regex) only; no LLM judgment.
- **Cyrillic / homoglyph / confusable detection** — no Unicode TR39 confusable handling.
- **Configurable / swappable confirmation policy** — only `ConfirmRisky(threshold=HIGH)` ships; no `AlwaysConfirm` / `NeverConfirm` / policy selection.
- **PolicyRail composed-threat rules** — beyond the fixed Layer 2 pattern set, no per-segment composed-threat engine.
- **Post-execution quality Critic** — the OpenHands experimental Critic (post-execution quality scoring / iterative refinement) is a different, orthogonal pattern.
- **Migrating or re-checking already-completed tasks** — the check runs forward, on tasks about to be dispatched.

---

## Dependencies

- **Spec 3 (role-boundaries / `role-contracts.md`)** ✅ — supplies the `## Access Matrix` that Layer 1 enforces.
- **Spec 4 (signal-log-and-ci-autodetect)** ✅ — supplies `signals.jsonl`, `lib-signals.sh` (`append_signal`, flock fd 202), `templates/signals.jsonl`, and `replay-signals.sh`, which the audit trail extends.
- **`commands/implement.md`** — the coordinator prompt where the pre-execution check is invoked before each delegation.

---

## Verification Contract

**Project type**: cli

**Entry points**:
- `hooks/scripts/pre-execution-check.sh` — the new check script (CLI, exit-code contract).
- `commands/implement.md` — coordinator delegation gate, invokes the script before each task.
- `specs/<name>/signals.jsonl` — audit trail destination.
- `hooks/scripts/replay-signals.sh` — incident-review replay over `security-decision` events.

**Observable signals**:
- PASS looks like:
  - A task writing within the target role's `Writes` set → script exits `0`, coordinator dispatches; one `security-decision` event with `decision:"allow"` appended.
  - A task writing to a role's `Denylist` path → script exits `2` with a Layer 1 reason on stderr; coordinator does NOT dispatch; event with `decision:"block"`, `layer:"role-contract"`.
  - A task containing `rm -rf` → script exits `2`; coordinator pauses for confirmation; event with `decision:"confirm"`, `layer:"shell-pattern"`, `risk:"HIGH"`.
  - An unclassifiable task → exits `2`, `risk:"UNKNOWN"`, `decision:"confirm"`.
- FAIL looks like:
  - A Denylist write reaches spec-executor (script exited `0` or coordinator ignored exit `2`).
  - A `rm -rf` task dispatched without a pause.
  - A `security-decision` line edited in place, or a decision with no corresponding event.
  - The script makes an LLM or network call, or takes > 100 ms.

**Hard invariants**:
- Layer 1 role-contract violations ALWAYS hard-block — never reachable by confirmation.
- The check NEVER fails open: indeterminate state → `UNKNOWN` → confirmation.
- `signals.jsonl` is append-only — existing lines (including `security-decision` events) are never mutated.
- The script performs no LLM calls and no network access (determinism).
- `LOW`/`MEDIUM` verdicts are transparent — existing specs run unchanged.

**Seed data**:
- A spec with a populated `references/role-contracts.md` (the real Spec 3 file).
- `templates/signals.jsonl` present (Spec 4 seed); `lib-signals.sh` sourced.
- Sample delegated tasks: (a) an in-bounds write, (b) a Denylist write, (c) a `rm -rf` shell command, (d) an unclassifiable action.

**Dependency map**:
- `role-contracts.md` (Spec 3) — Layer 1 reads it; if Spec 3 changes the matrix shape, the Layer 1 parser must follow.
- `signals.jsonl` + `lib-signals.sh` + `replay-signals.sh` (Spec 4) — shared append-only log; new `security-decision` event type co-exists with control signals.
- `commands/implement.md` — shares the delegation flow; the gate is inserted before the existing signal HOLD check.

**Escalate if**:
- `role-contracts.md` is missing or its Access Matrix is unparseable on a real run (cannot enforce Layer 1) — confirm with a human rather than silently allowing.
- A confirmable verdict involves an irreversible action (data deletion, external API call with billing).
- The dangerous-pattern set needs to grow beyond the agreed Layer 2 list — a scope decision, not an implementation detail.

---

## Unresolved Questions

- How does the coordinator obtain the "intended write paths" and "intended shell command" for a task before delegation? Tasks in `tasks.md` are prose; the check needs structured inputs. Likely resolved at design time — candidate sources: task metadata, the task's file-touch hints, or a conservative parse of the task text. Flagging so design picks one explicitly rather than the script guessing.
- Whether human confirmation is captured inline in the coordinator chat or via a `signals.jsonl` ACK-style event — AC-2.4 records it as a follow-up `security-decision` event; design should confirm the exact mechanism.

## Next Steps

1. Obtain user approval of these requirements.
2. Run `/ralphharness:design` — design `pre-execution-check.sh` internals (Layer 1 matrix parser, Layer 2 regex set, Layer 3 classifier, max-severity combiner), the `security-decision` schema, and the `implement.md` gate insertion point.
3. Resolve the Unresolved Questions during design (task → structured-input mapping; confirmation-capture mechanism).
4. Run `/ralphharness:tasks` to break the design into tasks.
