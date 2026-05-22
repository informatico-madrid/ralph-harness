# Chat Log — agent-chat-protocol

## Signal Legend

### Control signals (→ signals.jsonl)

Control signals are written to `signals.jsonl` via atomic flock — **not** as text in chat.md.

| Signal | Meaning |
|--------|---------|
| HOLD | Paused, waiting for input or resource |
| PENDING | Still evaluating; blocking — do not advance until resolved |
| URGENT | Needs immediate attention |
| DEADLOCK | Blocked, cannot proceed |
| INTENT-FAIL | Could not fulfill stated intent |
| SPEC-ADJUSTMENT | Spec criterion cannot be met cleanly; proposing minimal Verify/Done-when amendment |
| SPEC-DEFICIENCY | Spec criterion fundamentally broken; human decision required |

### Collaboration markers (→ chat.md, this file)

Collaboration markers are written as `**Signal**: <NAME>` in chat.md message bodies.

| Signal | Meaning |
|--------|---------|
| OVER | Task/turn complete, no more output |
| ACK | Acknowledged, understood |
| CONTINUE | Work in progress, more to come |
| STILL | Still alive/active, no progress but not dead — also the executor liveness **heartbeat** emitted to `signals.jsonl` |
| ALIVE | Initial check-in or liveness **heartbeat** — also the executor heartbeat emitted to `signals.jsonl` with `reason: "step N/M: <activity>"` |
| CLOSE | Conversation closing |
| HYPOTHESIS | Proposed root-cause theory for a regression (typically reviewer) |
| EXPERIMENT | A test/probe run to validate a hypothesis (typically executor) |
| FINDING | Observed result of an experiment, or recorded investigation note (typically both) |
| ROOT_CAUSE | Confirmed underlying defect, agreed by both agents |
| FIX_PROPOSAL | A concrete suggested fix derived from the root cause |
| BUG_DISCOVERY | A bug found via investigation; mirrored as a task_review.md row by reviewer |

> **Migration Note**: Legacy `[HOLD]`/`[PENDING]`/`[URGENT]`/`[DEADLOCK]` markers in chat.md continue to work for one release cycle (grep fallback). New control signals must use signals.jsonl — see `references/coordinator-pattern.md` §Signal Protocol.

## Message Format

### Header

Each message begins with a header line containing a timestamp and the writer/addressee. The signal itself is placed in the message body as `**Signal**: <SIGNAL>`.

Header format:

### [YYYY-MM-DD HH:MM:SS] <writer> → <addressee>

Example message body (signal in body):

```text
### [2026-04-12 09:00:00] spec-executor → coordinator
**Task**: task-1.1
**Signal**: ALIVE

### [2026-04-12 09:00:01] coordinator → spec-executor
**Task**: task-1.1
**Signal**: ACK

### [2026-04-12 09:01:30] spec-executor → coordinator
**Task**: task-1.1
**Signal**: OVER
```

### Blocking Signals (HOLD, PENDING, URGENT)

When sending a blocking signal, write it as a **standalone bracketed line** at the top of the message body so the coordinator's mechanical grep can detect it:

```text
### [2026-04-12 09:02:00] external-reviewer → spec-executor
[HOLD]
**Task**: task-1.1

The implementation does not match the spec. The verify command fails with exit code 1.
```

The coordinator runs: `grep -c '^\[HOLD\]$\|^\[PENDING\]$\|^\[URGENT\]$\|^\[DEADLOCK\]$' "$SPEC_PATH/chat.md"`
This only matches lines that are exactly `[HOLD]`, `[PENDING]`, `[URGENT]`, or `[DEADLOCK]` — not `**Signal**: HOLD`.

<!-- Messages accumulate here. Append only. Do not edit or delete. -->
### Optional: Pair-Debug Mode Note

When the coordinator announces "PAIR-DEBUG MODE ACTIVATED" in chat.md, the executor and reviewer should follow the pair-debug loop protocol defined in references/pair-debug.md.

### [2026-05-22 16:59:00] external-reviewer → coordinator
**Signal**: ALIVE
**Spec**: multi-language-support
**Phase**: execution
**taskIndex**: 0 (no tasks completed yet)
**Status**: Reviewer bootstrapped and active. Monitoring for completed tasks.

**Initial verification completed**:
- Baseline check: `bats tests/ci-autodetect.bats` → 17/17 PASS ✓
- Syntax check: `bash -n detect-ci-commands.sh` → PASS ✓
- Script state: ORIGINAL (no refactor yet — taskIndex=0 means execution just started)
- No active HOLD/PENDING/DEADLOCK signals found

**Monitoring begins**. Will verify each completed task independently.

### [2026-05-22 17:02:00] external-reviewer → coordinator
**Signal**: STILL
**Status**: Cycle 2 — no completed tasks detected. taskIndex=0. 
**Note**: Executor has not marked any tasks complete. Will continue monitoring.
### [2026-05-22 17:05:00] spec-executor → external-reviewer
**Task**: T1.1
**Signal**: ACK

Baseline verification complete — both checks pass:
- bats tests/ci-autodetect.bats → 17/17 PASS
- bash -n detect-ci-commands.sh → EXIT=0

No files modified (read-only baseline). Ready for task 1.2.

**Expected Response**: ACK

### [2026-05-22 17:06:00] external-reviewer → spec-executor
**Task**: T1.1
**Signal**: ACK

Verified independently:
- bats tests/ci-autodetect.bats → 17/17 PASS ✓
- bash -n detect-ci-commands.sh → EXIT=0 ✓
- No files modified (read-only baseline) ✓

Task 1.1 PASS — reviewed and confirmed. Monitoring for task 1.2.
### [2026-05-22 17:08:00] spec-executor → external-reviewer
**Task**: T1.2
**Signal**: OVER

Task 1.2 complete. All detect→filter→emit logic wrapped in `detect_ci_commands()` function with:
- `local SPEC_PATH="$1"`, `local ENTRIES=()`, `local FILTERED=()`
- 5 detectors remain top-level, called inside function
- Function ends with `return 0`
- 17/17 bats tests pass, `bash -n` clean
- Commit: 3d00fbb

**Expected Response**: ACK
### [2026-05-22 17:10:00] spec-executor → external-reviewer
**Task**: T1.2
**Signal**: OVER

Task 1.2 complete: detect→filter→emit pipeline wrapped in detect_ci_commands() with local scope.

**Changes**:
- detect-ci-commands.sh: wrapped lines 119-156 (detector calls + filter + emit) in detect_ci_commands() function
- local SPEC_PATH="$1", local ENTRIES=(), local FILTERED=() inside function
- 5 detector functions remain top-level, called inside the function in original order
- Function ends with return 0 (never exit)
- Top-level ENTRIES=() removed from outer scope

**Verification**:
- grep detect_ci_commands() OK
- grep local ENTRIES OK
- bash -n OK
- bats tests/ci-autodetect.bats -> 17/17 PASS

**Commit**: b0c1731 (refactor(detect-ci): wrap pipeline in detect_ci_commands() function)

**Expected Response**: ACK

### [2026-05-22 17:09:40] external-reviewer → spec-executor
**Task**: T1.2
**Signal**: ACK

Verified independently:
- grep detect_ci_commands() → line 117 ✓
- grep local ENTRIES → line 119 ✓
- grep local SPEC_PATH → line 118 ✓
- grep local FILTERED → line 120 ✓
- bash -n → clean ✓
- bats tests/ci-autodetect.bats → 17/17 PASS ✓
- 5 detector functions remain top-level, called inside function ✓
- Function ends with return 0 (never exit) ✓

Task 1.2 PASS — reviewed and confirmed. Monitoring for task 1.3.

### [2026-05-22 17:16:00] external-reviewer → coordinator
**Signal**: STILL
**Status**: Cycle 6 — no new tasks claimed. taskIndex=0.
**Anomaly detected**: detect-ci-commands.sh shows BASH_SOURCE guard (task 1.3 changes) but task 1.3 not marked [x] in tasks.md. Git log shows no new commit since 1.2 completion. Executor may be working on task 1.3 without claiming it.
**Note**: Will review task 1.3 when marked. Continuing monitoring.
### [2026-05-22 17:20:00] spec-executor → external-reviewer
**Task**: T1.3
**Signal**: OVER

Task 1.3 complete: BASH_SOURCE main-guard added to detect-ci-commands.sh.

**Changes**:
- Wrapped `set -euo pipefail`, FORCE/SPEC_PATH vars, arg parsing, validation in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard
- All function definitions (5 detectors + detect_ci_commands) remain top-level
- CLI path: guard → set -euo pipefail → parse args → validate → call detect_ci_commands → script ends naturally
- Sourcing path: functions defined, guard condition false → script ends with zero side effects

**Verification**:
- grep BASH_SOURCE[0] → OK
- grep -qE '^set -euo pipefail' → NOT found (no leak)
- bash -n → clean
- bats tests/ci-autodetect.bats → 17/17 PASS
- Sourcing produces no output

**Commit**: 8cf90bd (refactor(detect-ci): gate CLI body behind BASH_SOURCE main-guard)

**Expected Response**: ACK
