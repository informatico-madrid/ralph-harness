# Tasks: Pre-Execution Security Critic

**Spec**: `pre-execution-critic` (Spec 9 of engine-roadmap-epic)
**Granularity**: fine
**Total tasks**: 54 (implementation + [VERIFY] checkpoints + 1 VE end-to-end)
**Phase distribution**:
- Phase 1 (Make It Work — POC): 18 tasks (~33%)
- Phase 2 (Refactoring): 7 tasks (~13%)
- Phase 3 (Testing — full bats coverage + VE): 21 tasks (~39%)
- Phase 4 (Quality Gates): 5 tasks (~9%)
- Phase 5 (PR Lifecycle): 3 tasks (~6%)
**POC milestone**: Task `1.18` — the real `pre-execution-check.sh` correctly (a) allows an in-bounds spec-executor write (exit 0), (b) hard-blocks a Denylist write (exit 2, `layer:"role-contract"`), and (c) confirms a `rm -rf` verify command (exit 2, `decision:"confirm"`), appending exactly one `security-decision` event to a temp `signals.jsonl` per invocation.
**Delivery**: single PR — all 7 files (1 create, 6 modify) + tests in one branch.
**Last updated**: 2026-05-16

---

## Phase 1: Make It Work (POC)

Goal: build `pre-execution-check.sh` end-to-end (arg parsing, 3 layers, max-severity combiner, ConfirmRisky policy, the `security-decision` audit emitter) and wire the PRE-EXEC-GATE block into `commands/implement.md`. Skip tests here — prove the mechanism works against fixture inputs. Ordering: skeleton → Layer 1 → Layer 2 → Layer 3 → combiner → ConfirmRisky → audit emitter → coordinator gate → POC checkpoint.

- [x] 1.1 Create `pre-execution-check.sh` skeleton with arg parsing
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/pre-execution-check.sh` with `#!/usr/bin/env bash` and `set -euo pipefail` (relax `-e` where layer functions intentionally return non-zero).
    2. Parse flags `--agent`, `--task`, `--paths`, `--command`, `--spec-path` into variables; `--agent`, `--task`, `--spec-path` required, `--paths` and `--command` optional (default empty).
    3. On a missing required flag, print a usage message to stderr and exit `1` (non-blocking error → coordinator treats as UNKNOWN→confirm).
    4. Add a trailing `exit 0` placeholder so the skeleton runs.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: `bash -n` passes; invoking with all required flags exits 0; invoking with a missing required flag exits 1 with a usage message on stderr.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && bash plugins/ralphharness/hooks/scripts/pre-execution-check.sh --agent spec-executor --task 1.1 --spec-path /tmp && echo SKEL_OK`
  - **Commit**: `feat(pre-exec): add pre-execution-check.sh skeleton with arg parsing`
  - _Requirements: FR-1, AC-5.1_
  - _Design: pre-execution-check.sh CLI contract; Implementation Step 1_

- [x] 1.2 Add severity-rank helper and exit-code constants
  - **Do**:
    1. In `pre-execution-check.sh`, add a `rank()` function mapping `LOW=0 MEDIUM=1 HIGH=2 UNKNOWN=3` (UNKNOWN ranks above HIGH per design).
    2. Add a `max_risk()` helper that takes two risk strings and returns the higher-ranked one.
    3. Define exit-code constants in comments: `0` allow, `2` block/confirm, other non-zero = error.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: `max_risk LOW HIGH` prints `HIGH`; `max_risk HIGH UNKNOWN` prints `UNKNOWN`; `max_risk MEDIUM LOW` prints `MEDIUM`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo RANK_OK`
  - **Commit**: `feat(pre-exec): add severity-rank and max_risk helpers`
  - _Requirements: AC-2.1_
  - _Design: max-severity combiner; Implementation Step 5_

- [x] 1.3 [VERIFY] Quality checkpoint: skeleton syntax + arg contract
  - **Do**: Run `bash -n` on the script; confirm required/optional flag handling behaves per design.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo CHECKPOINT_OK`
  - **Done when**: No syntax errors; arg parsing matches the CLI contract table.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md` under `## Learnings`.

- [x] 1.4 Implement Layer 1 — locate and extract the Access Matrix table
  - **Do**:
    1. In `pre-execution-check.sh`, add `layer1_role_contract()`.
    2. Resolve `references/role-contracts.md` relative to `CLAUDE_PLUGIN_ROOT` (fall back to a path relative to the script's own dir if the env var is unset).
    3. If the file is missing, return risk `UNKNOWN` with a reason naming the missing file (never `allow`, never `block`).
    4. Use `awk` to extract the table region between `## Access Matrix` and the next `## ` heading.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: With `CLAUDE_PLUGIN_ROOT` pointing at the real plugin dir, the function extracts a non-empty Access Matrix region; with it pointing at an empty dir, the function yields `UNKNOWN`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo L1_EXTRACT_OK`
  - **Commit**: `feat(pre-exec): Layer 1 locates and extracts the Access Matrix table`
  - _Requirements: FR-2, AC-1.1, AC-1.4_
  - _Design: Layer 1 — role-contract matrix parser; Implementation Step 2_

- [x] 1.5 Implement Layer 1 — agent-row lookup
  - **Do**:
    1. In `layer1_role_contract()`, split extracted table rows on `|`, trim cells.
    2. Find the row whose `Agent` cell equals `--agent`; capture its `Writes` and `Denylist` cells.
    3. If no matching row (unknown agent) or the table is unparseable, return `UNKNOWN` with a reason naming the failure.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: A known agent (`spec-executor`) resolves to its Writes/Denylist cells; an unknown agent yields `UNKNOWN`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo L1_LOOKUP_OK`
  - **Commit**: `feat(pre-exec): Layer 1 resolves the target agent row in the matrix`
  - _Requirements: FR-2, AC-1.1, AC-1.4_
  - _Design: Layer 1 — role-contract matrix parser; Error Handling table_

- [x] 1.6 Implement Layer 1 — glob path matching and hard-block verdict
  - **Do**:
    1. In `layer1_role_contract()`, enable `shopt -s extglob`; for each path in `--paths` (comma-split), test against each `Denylist` then each `Writes` pattern using `[[ "$path" == $pattern ]]`.
    2. A path matching `Denylist`, or NOT matching any `Writes` pattern, is a Layer 1 violation → set verdict `block`, `layer=role-contract`, risk `HIGH`, build a reason naming the offending path.
    3. `--paths` absent → return `UNKNOWN` (cannot prove writes are in-bounds).
    4. All paths in-bounds → return `clear` (risk `LOW`, layer `none`).
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: An in-bounds path returns `clear`; a Denylist path returns a `block` violation; absent `--paths` returns `UNKNOWN`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo L1_MATCH_OK`
  - **Commit**: `feat(pre-exec): Layer 1 glob-matches paths and emits hard-block on violation`
  - _Requirements: FR-2, AC-1.2, AC-1.3_
  - _Design: Layer 1 — role-contract matrix parser; Technical Decisions (glob matching)_

- [x] 1.7 [VERIFY] Quality checkpoint: Layer 1 logic
  - **Do**: Run `bash -n`; invoke the script directly against the real `role-contracts.md` for in-bounds, Denylist, and unknown-agent paths to confirm Layer 1 behaviour via exit codes.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo CHECKPOINT_OK`
  - **Done when**: No syntax errors; Layer 1 yields `clear` / `block` / `UNKNOWN` for the three cases.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 1.8 Implement Layer 2 — dangerous shell pattern regex set
  - **Do**:
    1. In `pre-execution-check.sh`, add `layer2_shell_pattern()` operating on `--command`.
    2. Define the ERE pattern set from the design (case-sensitive): `rm -rf` / `rm -fr` / `rm -r -f`; `sudo`; `chmod 777`; fetch-piped-to-shell (`curl|wget` piped to `sh|bash`); `eval`.
    3. On a match, return risk `HIGH`, `layer=shell-pattern`, reason naming which pattern matched.
    4. No match or `--command` absent → return `LOW`, `layer=none` (no-op).
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: `rm -rf build/`, `sudo apt install x`, `chmod 777 f`, `curl x | sh`, `eval $x` each return `HIGH`; `pnpm test` and absent `--command` return `LOW`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo L2_OK`
  - **Commit**: `feat(pre-exec): Layer 2 dangerous shell pattern regex set`
  - _Requirements: FR-3, AC-3.1, AC-3.2, AC-3.3, AC-3.4_
  - _Design: Layer 2 — dangerous shell pattern regex set; Implementation Step 3_

- [x] 1.9 Implement Layer 3 — risk classifier
  - **Do**:
    1. In `pre-execution-check.sh`, add `layer3_risk()`.
    2. `--paths` absent → `UNKNOWN`.
    3. `--paths` present, Layer 1 clean, `--command` absent or read-only → `LOW`.
    4. `--paths` present (task modifies files), Layer 2 clean → `MEDIUM`.
    5. Do NOT re-derive Layer 1/Layer 2 outcomes — the combiner merges them.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: No `--paths` → `UNKNOWN`; in-bounds `--paths` with no command → `LOW`; in-bounds `--paths` with a benign command → `MEDIUM`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo L3_OK`
  - **Commit**: `feat(pre-exec): Layer 3 risk classifier (UNKNOWN/LOW/MEDIUM baseline)`
  - _Requirements: FR-4, AC-2.1_
  - _Design: Layer 3 — risk classifier; Implementation Step 4_

- [x] 1.10 [VERIFY] Quality checkpoint: Layers 2 and 3
  - **Do**: Run `bash -n`; spot-check Layer 2 against each dangerous pattern and Layer 3 against the three input shapes.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo CHECKPOINT_OK`
  - **Done when**: No syntax errors; Layers 2/3 behave per the design tables.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 1.11 Implement the max-severity combiner
  - **Do**:
    1. In `pre-execution-check.sh`, add `combine_risk()`: if Layer 1 returned a `block` violation, short-circuit to `block` (hard-block, layer `role-contract`) before combining.
    2. Otherwise combine Layer 1 risk-contribution, Layer 2 risk, Layer 3 risk via `max_risk` (UNKNOWN > HIGH > MEDIUM > LOW).
    3. Set the driving `layer` to the layer that produced the max risk (`none` for a clean LOW/MEDIUM).
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: A Layer 1 violation short-circuits to `block`; otherwise the combined risk equals the highest layer risk with the correct driving `layer`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo COMBINE_OK`
  - **Commit**: `feat(pre-exec): max-severity combiner with Layer 1 short-circuit`
  - _Requirements: FR-4, AC-2.1, AC-1.3_
  - _Design: max-severity combiner; Implementation Step 5_

- [x] 1.12 Implement the ConfirmRisky policy and verdict output
  - **Do**:
    1. In `pre-execution-check.sh`, add `confirm_risky()` mapping combined risk to a verdict: `LOW`/`MEDIUM` → `allow`/exit `0`; `HIGH`/`UNKNOWN` → `confirm`/exit `2`. A Layer 1 `block` bypasses this → `block`/exit `2`.
    2. Write the human-readable reason to stderr; write a structured one-line verdict (e.g. `decision=... layer=... risk=...`) to stdout.
    3. Set the script's final exit code per the verdict.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: LOW/MEDIUM exits `0`; HIGH/UNKNOWN exits `2` with `decision=confirm`; Layer 1 block exits `2` with `decision=block`; reason goes to stderr, verdict line to stdout.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo POLICY_OK`
  - **Commit**: `feat(pre-exec): fixed ConfirmRisky policy and exit-code verdict`
  - _Requirements: FR-5, AC-2.2, AC-5.1, AC-5.2, AC-5.4_
  - _Design: ConfirmRisky policy function; Implementation Step 5_

- [x] 1.13 [VERIFY] Quality checkpoint: combiner + ConfirmRisky
  - **Do**: Run `bash -n`; invoke the script end-to-end against the real `role-contracts.md` for an in-bounds write and confirm exit `0` + a stdout verdict line.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo CHECKPOINT_OK`
  - **Done when**: No syntax errors; an in-bounds write exits `0`.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 1.14 Wire the `security-decision` event emitter
  - **Do**:
    1. In `pre-execution-check.sh`, build the `security-decision` JSON payload with all design fields (`type`, `decision`, `layer`, `risk`, `agent`, `task`, `path`, `command`, `reason`, `timestamp` via `date -u +%FT%TZ`, `iteration` from `globalIteration` in `<spec-path>/.ralph-state.json`, default `1`).
    2. `source` `lib-signals.sh` (resolved relative to the script dir) and call `append_signal "$spec_path" "$payload"`.
    3. If `append_signal` returns non-zero (flock timeout / malformed payload), WARN to `<spec-path>/.progress.md` and exit non-zero (not 0/2) so the coordinator routes to confirm.
    4. Emit the event for every verdict (allow/block/confirm) — exactly once per invocation.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: Every invocation appends exactly one valid JSON line to `<spec-path>/signals.jsonl`; an `append_signal` failure WARNs and exits non-zero.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo EMITTER_OK`
  - **Commit**: `feat(pre-exec): emit one security-decision event per invocation via append_signal`
  - _Requirements: FR-6, AC-4.1, AC-4.2, NFR-7_
  - _Design: security-decision event emitter; Data Design; Implementation Step 6_

- [x] 1.15 [VERIFY] Quality checkpoint: end-to-end script invocation
  - **Do**: Run `bash -n`; invoke the script against the real `role-contracts.md` with a temp `--spec-path` and confirm one `security-decision` line is appended.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && d=$(mktemp -d) && CLAUDE_PLUGIN_ROOT=plugins/ralphharness bash plugins/ralphharness/hooks/scripts/pre-execution-check.sh --agent spec-executor --task 1.1 --paths 'chat.md' --spec-path "$d"; test "$(wc -l < "$d/signals.jsonl")" -eq 1 && echo CHECKPOINT_OK; rm -rf "$d"`
  - **Done when**: No syntax errors; exactly one event line appended.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 1.16 Insert the PRE-EXEC-GATE block into `commands/implement.md`
  - **Do**:
    1. Open `plugins/ralphharness/commands/implement.md`; insert a new `# BEGIN PRE-EXEC-GATE` / `# END PRE-EXEC-GATE` block AFTER `# END MALFORMED-CHECK` and BEFORE `# BEGIN HOLD-GATE`.
    2. The block instructs the coordinator to: parse the current task block's `**Files:**` → `--paths` and `**Verify:**` → `--command` (verbatim); a missing `**Files:**` means no `--paths`.
    3. Choose `--agent` = `spec-executor`, or `qa-engineer` for `[VERIFY]` tasks; pass `--task` and `--spec-path`.
    4. Invoke `pre-execution-check.sh` and read its exit code.
  - **Files**: plugins/ralphharness/commands/implement.md
  - **Done when**: The PRE-EXEC-GATE block exists between MALFORMED-CHECK and HOLD-GATE and describes parsing inputs + invoking the script.
  - **Verify**: `grep -n 'BEGIN PRE-EXEC-GATE' plugins/ralphharness/commands/implement.md && awk '/END MALFORMED-CHECK/{m=NR} /BEGIN PRE-EXEC-GATE/{p=NR} /BEGIN HOLD-GATE/{h=NR} END{exit !(m<p && p<h)}' plugins/ralphharness/commands/implement.md && echo GATE_PLACED_OK`
  - **Commit**: `feat(pre-exec): add PRE-EXEC-GATE block to implement.md coordinator`
  - _Requirements: FR-8, AC-5.1, AC-5.2_
  - _Design: implement.md PRE-EXEC-GATE block; Implementation Step 10_

- [x] 1.17 Implement PRE-EXEC-GATE exit-code branching
  - **Do**:
    1. In the PRE-EXEC-GATE block, branch on exit code: `0` → fall through to HOLD-GATE then dispatch.
    2. `2` with `layer=role-contract` on the stdout verdict → hard-stop: log the Layer 1 reason to `.progress.md`, do NOT dispatch, do NOT advance `taskIndex`.
    3. `2` confirmable (any other layer) → pause, surface the stderr reason to the human inline; on approval append a follow-up `security-decision` event (`decision:"allow"`, reason prefixed `human approved: ...`) via `append_signal` then dispatch; on refusal hard-stop.
    4. Other non-zero → WARN to `.progress.md`, treat as UNKNOWN, follow the confirmable path.
  - **Files**: plugins/ralphharness/commands/implement.md
  - **Done when**: The block documents all four exit-code branches including the follow-up event on approval.
  - **Verify**: `grep -cE 'hard-stop|confirm|follow-up' plugins/ralphharness/commands/implement.md >/dev/null && grep -q 'END PRE-EXEC-GATE' plugins/ralphharness/commands/implement.md && echo BRANCH_OK`
  - **Commit**: `feat(pre-exec): PRE-EXEC-GATE exit-code branching (allow/hard-stop/confirm)`
  - _Requirements: FR-8, FR-10, AC-1.3, AC-2.3, AC-2.4, AC-5.3_
  - _Design: implement.md PRE-EXEC-GATE block; Implementation Step 10_

- [x] 1.18 POC checkpoint — prove the three core verdicts end-to-end
  - **Do**:
    1. Create a temp spec dir with a temp `signals.jsonl`.
    2. Run the real script three times with `CLAUDE_PLUGIN_ROOT=plugins/ralphharness`: (a) in-bounds write (`--agent spec-executor --paths chat.md`) — expect exit `0`; (b) Denylist write (`--agent spec-executor --paths .ralph-state.json`) — expect exit `2` with `layer=role-contract` on stdout; (c) `rm -rf` verify (`--agent spec-executor --paths chat.md --command 'rm -rf build/'`) — expect exit `2` with `decision=confirm`.
    3. Confirm each run appended exactly one `security-decision` line (3 lines total).
  - **Files**: _(verification only — no file changes)_
  - **Done when**: Case (a) exits 0; (b) exits 2 with `layer=role-contract`; (c) exits 2 with `decision=confirm`; `signals.jsonl` has exactly 3 lines.
  - **Verify**: `d=$(mktemp -d); R=plugins/ralphharness; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task 1.1 --paths chat.md --spec-path "$d"; a=$?; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task 1.2 --paths .ralph-state.json --spec-path "$d" 1>/tmp/o2; b=$?; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task 1.3 --paths chat.md --command 'rm -rf build/' --spec-path "$d" 1>/tmp/o3; c=$?; test $a -eq 0 && test $b -eq 2 && grep -q role-contract /tmp/o2 && test $c -eq 2 && grep -q confirm /tmp/o3 && test "$(wc -l < "$d/signals.jsonl")" -eq 3 && echo POC_PASS; rm -rf "$d"`
  - **Commit**: `feat(pre-exec): POC complete — allow/hard-block/confirm verdicts proven end-to-end`
  - _Requirements: US-1, US-3, US-5, AC-1.2, AC-3.2, AC-4.1_
  - _Design: Decision Flow; POC milestone_

---

## Phase 2: Refactoring

Goal: clean up the script, extend the schema, update the signals template and the role-contracts Access Matrix. No behaviour changes — verified by re-running the POC checkpoint command.

- [x] 2.1 Refactor `pre-execution-check.sh` — extract layer functions cleanly
  - **Do**:
    1. Review the script; ensure each of `layer1_role_contract`, `layer2_shell_pattern`, `layer3_risk`, `combine_risk`, `confirm_risky` is a self-contained function with a documented contract comment (inputs, return convention).
    2. Hoist the pattern set, severity map, and path resolution into clearly-labelled sections at the top.
    3. Remove any dead/placeholder code from Phase 1.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: Each layer is a documented function; no dead code; the POC checkpoint command still passes.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo REFACTOR_OK`
  - **Commit**: `refactor(pre-exec): extract layer functions with documented contracts`
  - _Requirements: NFR-1_
  - _Design: Components; Existing Patterns to Follow_

- [x] 2.2 Refactor `pre-execution-check.sh` — consistent error handling
  - **Do**:
    1. Standardise the fail-safe path: every indeterminate state (missing contract, parse error, append failure) routes through one helper that sets `UNKNOWN` + a reason + WARNs to `.progress.md` where applicable.
    2. Ensure no code path can produce `allow` from an indeterminate state.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: All indeterminate states route to UNKNOWN→confirm via one consistent helper; no fail-open path exists.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && echo ERRHANDLE_OK`
  - **Commit**: `refactor(pre-exec): consistent fail-safe error handling`
  - _Requirements: NFR-3, NFR-4, FR-10_
  - _Design: Error Handling & Failure Modes_

- [x] 2.3 [VERIFY] Quality checkpoint: refactor preserves POC behaviour
  - **Do**: Re-run the POC checkpoint command (task 1.18 Verify) and confirm `POC_PASS`.
  - **Verify**: re-run task 1.18 Verify command; expect `POC_PASS`.
  - **Done when**: The three core verdicts still behave identically after the refactor.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 2.4 Extend `spec.schema.json` with the `securityDecisionEvent` definition
  - **Do**:
    1. Open `plugins/ralphharness/schemas/spec.schema.json`; under `definitions` add the `securityDecisionEvent` object exactly per the design (required fields, `decision`/`layer`/`risk` enums, `path`/`command` nullable, `iteration` integer ≥ 1).
    2. Do not modify any other definition.
  - **Files**: plugins/ralphharness/schemas/spec.schema.json
  - **Done when**: `securityDecisionEvent` is present under `definitions` with the design's required fields and enums; the schema is still valid JSON.
  - **Verify**: `jq -e '.definitions.securityDecisionEvent.required | index("type")' plugins/ralphharness/schemas/spec.schema.json >/dev/null && jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && echo SCHEMA_OK`
  - **Commit**: `feat(pre-exec): add securityDecisionEvent definition to spec.schema.json`
  - _Requirements: FR-7, AC-4.2_
  - _Design: spec.schema.json extension; Data Design_

- [x] 2.5 Add header note + commented example to `templates/signals.jsonl`
  - **Do**:
    1. Open `plugins/ralphharness/templates/signals.jsonl`; add a header comment line noting the `security-decision` event type co-exists with `control` events.
    2. Add one commented example `security-decision` JSONL line matching the design's Data Design shape.
    3. Keep existing lines unchanged.
  - **Files**: plugins/ralphharness/templates/signals.jsonl
  - **Done when**: The template has a `security-decision` header note and one commented example line; existing lines untouched.
  - **Verify**: `grep -q 'security-decision' plugins/ralphharness/templates/signals.jsonl && echo TEMPLATE_OK`
  - **Commit**: `docs(pre-exec): document security-decision event in signals.jsonl template`
  - _Requirements: FR-9_
  - _Design: templates/signals.jsonl; Implementation Step 8_

- [x] 2.6 Add the `pre-execution-check.sh` row to the role-contracts Access Matrix
  - **Do**:
    1. Open `plugins/ralphharness/references/role-contracts.md`; add an Access Matrix row for `pre-execution-check.sh` as a read-only consumer (Reads: `role-contracts.md`, `.ralph-state.json`; Writes: `signals.jsonl` via `append_signal`; Denylist: N/A).
    2. Add a short note that the script mechanically enforces the matrix.
    3. Do not alter other rows.
  - **Files**: plugins/ralphharness/references/role-contracts.md
  - **Done when**: The Access Matrix has a `pre-execution-check.sh` row and an enforcer note; other rows unchanged.
  - **Verify**: `grep -q 'pre-execution-check.sh' plugins/ralphharness/references/role-contracts.md && echo MATRIX_ROW_OK`
  - **Commit**: `docs(pre-exec): add pre-execution-check.sh to role-contracts Access Matrix`
  - _Requirements: FR-11_
  - _Design: role-contracts.md update; Implementation Step 9_

- [x] 2.7 [VERIFY] Quality checkpoint: schema + template + matrix
  - **Do**: Validate the schema is well-formed JSON; confirm the template and matrix changes are present.
  - **Verify**: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && grep -q security-decision plugins/ralphharness/templates/signals.jsonl && grep -q pre-execution-check.sh plugins/ralphharness/references/role-contracts.md && echo CHECKPOINT_OK`
  - **Done when**: Schema valid; template and matrix updated.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

---

## Phase 3: Testing

Goal: implement the FULL Test Coverage Table from design.md as `tests/pre-exec-check.bats` with fixtures under `tests/fixtures/pre-exec/`. One task per Coverage Table row. No mocks — fixtures + temp dirs only (Test Double Policy). Test file location and `setup()`/`teardown()` per the design's Test File Conventions.

- [x] 3.1 Create the `pre-exec` test fixtures
  - **Do**:
    1. Create `plugins/ralphharness/tests/fixtures/pre-exec/role-contracts.full.md` — a minimal `## Access Matrix` with a `spec-executor` row whose `Writes` includes a path used as an in-bounds case and whose `Denylist` includes `.ralph-state.json`.
    2. Create `plugins/ralphharness/tests/fixtures/pre-exec/task-no-files.md` — a sample task block with no `**Files:**` field.
    3. (Empty-fixture-dir case uses a `mktemp -d` with no contract file — no fixture file needed.)
  - **Files**: plugins/ralphharness/tests/fixtures/pre-exec/role-contracts.full.md, plugins/ralphharness/tests/fixtures/pre-exec/task-no-files.md
  - **Done when**: Both fixture files exist; `role-contracts.full.md` has a parseable `## Access Matrix` with a `spec-executor` row.
  - **Verify**: `grep -q '## Access Matrix' plugins/ralphharness/tests/fixtures/pre-exec/role-contracts.full.md && test -f plugins/ralphharness/tests/fixtures/pre-exec/task-no-files.md && echo FIXTURES_OK`
  - **Commit**: `test(pre-exec): add role-contract and task-block fixtures`
  - _Requirements: NFR-1_
  - _Design: Fixtures & Test Data; Test File Conventions_

- [x] 3.2 Create `tests/pre-exec-check.bats` with setup/teardown harness
  - **Do**:
    1. Create `plugins/ralphharness/tests/pre-exec-check.bats`.
    2. `setup()` creates a `mktemp -d` workspace and copies `templates/signals.jsonl` into it; `teardown()` `rm -rf`s it; set `REPO_ROOT="$(dirname "$BATS_TEST_DIRNAME")"`.
    3. Add a helper to invoke `pre-execution-check.sh` with `CLAUDE_PLUGIN_ROOT` pointed at the fixture dir or the real plugin dir as needed.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: `bats tests/pre-exec-check.bats` runs (even with zero/placeholder tests) without harness errors.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo HARNESS_OK`
  - **Commit**: `test(pre-exec): add bats harness with setup/teardown`
  - _Requirements: NFR-1_
  - _Design: Test File Conventions_

- [x] 3.3 Test: in-bounds write exits 0 with allow event
  - **Do**: Add a bats test — invoke the script with an in-bounds `spec-executor` path; assert exit `0` and one appended event `decision:"allow"`, `risk:"LOW"`, `layer:"none"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes and asserts exit code + event fields.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'in-bounds' && echo T_OK`
  - **Commit**: `test(pre-exec): in-bounds write exits 0 with allow event`
  - _Requirements: AC-5.1, AC-4.2_
  - _Design: Test Coverage Table (in-bounds write)_

- [x] 3.4 Test: Layer 1 Denylist write hard-blocks
  - **Do**: Add a bats test — `--paths` matching the fixture `Denylist`; assert exit `2`, stderr names Layer 1, event `decision:"block"`, `layer:"role-contract"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'Denylist' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 1 Denylist write hard-blocks (exit 2)`
  - _Requirements: AC-1.2, AC-1.3_
  - _Design: Test Coverage Table (Denylist write)_

- [x] 3.5 [VERIFY] Quality checkpoint: harness + first tests
  - **Do**: Run the full bats file so far.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo CHECKPOINT_OK`
  - **Done when**: All tests so far pass.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 3.6 Test: Layer 1 write outside the Writes set
  - **Do**: Add a bats test — `--paths` for a path not covered by any `Writes` pattern; assert exit `2`, event `decision:"block"`, `layer:"role-contract"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'outside Writes' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 1 write outside Writes set hard-blocks`
  - _Requirements: AC-1.2_
  - _Design: Test Coverage Table (write outside Writes set)_

- [x] 3.7 Test: Layer 1 missing `role-contracts.md` → UNKNOWN/confirm
  - **Do**: Add a bats test — `CLAUDE_PLUGIN_ROOT` at an empty dir; assert exit `2`, event `risk:"UNKNOWN"`, `decision:"confirm"` (never block, never allow).
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'missing role-contracts' && echo T_OK`
  - **Commit**: `test(pre-exec): missing role-contracts.md routes to UNKNOWN/confirm`
  - _Requirements: AC-1.4, NFR-4_
  - _Design: Test Coverage Table (missing role-contracts.md)_

- [x] 3.8 Test: Layer 1 unknown agent → UNKNOWN/confirm
  - **Do**: Add a bats test — `--agent nonexistent-agent` against the fixture contract; assert exit `2`, `risk:"UNKNOWN"`, `decision:"confirm"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'unknown agent' && echo T_OK`
  - **Commit**: `test(pre-exec): unknown agent routes to UNKNOWN/confirm`
  - _Requirements: AC-1.4_
  - _Design: Test Coverage Table (unknown agent)_

- [x] 3.9 [VERIFY] Quality checkpoint: Layer 1 test coverage
  - **Do**: Run the full bats file.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo CHECKPOINT_OK`
  - **Done when**: All Layer 1 tests pass.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 3.10 Test: Layer 2 `rm -rf` command escalates to HIGH/confirm
  - **Do**: Add a bats test — `--command 'rm -rf build/'`; assert exit `2`, event `layer:"shell-pattern"`, `risk:"HIGH"`, `decision:"confirm"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'rm -rf' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 2 rm -rf escalates to HIGH/confirm`
  - _Requirements: AC-3.1, AC-3.2_
  - _Design: Test Coverage Table (rm -rf command)_

- [x] 3.11 Test: Layer 2 sudo / chmod 777 / curl|sh / eval each → HIGH
  - **Do**: Add bats tests (one per pattern) — `sudo apt install x`, `chmod 777 f`, `curl x | sh`, `eval $x`; each asserts exit `2` with `risk:"HIGH"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: All four pattern tests pass.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'Layer 2' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 2 sudo/chmod777/curl|sh/eval escalate to HIGH`
  - _Requirements: AC-3.1, AC-3.2, AC-3.3_
  - _Design: Test Coverage Table (sudo / chmod 777 / curl|sh / eval)_

- [x] 3.12 Test: Layer 2 benign / absent command does not escalate
  - **Do**: Add bats tests — `--command 'pnpm test'` and an invocation with no `--command`; assert neither escalates (contributes `LOW`).
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: Both tests pass.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'benign' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 2 benign and absent command contribute LOW`
  - _Requirements: AC-3.4_
  - _Design: Test Coverage Table (benign command, no --command)_

- [x] 3.13 [VERIFY] Quality checkpoint: Layer 2 test coverage
  - **Do**: Run the full bats file.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo CHECKPOINT_OK`
  - **Done when**: All Layer 2 tests pass.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 3.14 Test: Layer 3 task with no `**Files:**` → UNKNOWN/confirm
  - **Do**: Add a bats test — invoke with no `--paths` (the `task-no-files.md` case); assert `risk:"UNKNOWN"`, `decision:"confirm"`, exit `2`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'no Files' && echo T_OK`
  - **Commit**: `test(pre-exec): Layer 3 missing Files field routes to UNKNOWN/confirm`
  - _Requirements: AC-2.1, AC-2.5_
  - _Design: Test Coverage Table (task with no Files)_

- [x] 3.15 Test: combiner — Denylist + `rm -rf` together, Layer 1 wins
  - **Do**: Add a bats test — `--paths` matching `Denylist` AND `--command 'rm -rf x'`; assert Layer 1 hard-block wins → `decision:"block"`, exit `2`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes and confirms the Layer 1 short-circuit.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'combiner' && echo T_OK`
  - **Commit**: `test(pre-exec): max-severity combiner — Layer 1 short-circuit wins`
  - _Requirements: AC-2.1, AC-1.3_
  - _Design: Test Coverage Table (combiner — Denylist + rm -rf)_

- [x] 3.16 Test: ConfirmRisky LOW/MEDIUM allow, HIGH/UNKNOWN confirm
  - **Do**: Add bats tests — a LOW and a MEDIUM input each exit `0` with `decision:"allow"`; a HIGH and an UNKNOWN input each exit `2` with `decision:"confirm"`.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: All four ConfirmRisky tests pass.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'ConfirmRisky' && echo T_OK`
  - **Commit**: `test(pre-exec): ConfirmRisky maps LOW/MEDIUM to allow, HIGH/UNKNOWN to confirm`
  - _Requirements: AC-2.2_
  - _Design: Test Coverage Table (ConfirmRisky)_

- [x] 3.17 [VERIFY] Quality checkpoint: Layer 3 + combiner + ConfirmRisky
  - **Do**: Run the full bats file.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo CHECKPOINT_OK`
  - **Done when**: All tests through ConfirmRisky pass.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

- [x] 3.18 Test: audit append — one valid line, schema-conformant, immutable
  - **Do**: Add a bats test — seed a temp `signals.jsonl` with one prior line; invoke the script; assert exactly one new line added, the new line is valid JSON matching the `securityDecisionEvent` schema (via `jq`), and the pre-existing line is byte-identical (immutability, AC-4.3).
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes and verifies append-only behaviour.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'audit append' && echo T_OK`
  - **Commit**: `test(pre-exec): audit append — one valid schema-conformant immutable line`
  - _Requirements: AC-4.1, AC-4.2, AC-4.3_
  - _Design: Test Coverage Table (audit append)_

- [x] 3.19 Test: `replay-signals.sh` over `security-decision` events
  - **Do**: Add a bats integration test — build a temp log mixing `control` and `security-decision` events; run `replay-signals.sh`; assert it completes without error and the security decision is visible in output.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: The test passes.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'replay' && echo T_OK`
  - **Commit**: `test(pre-exec): replay-signals.sh handles security-decision events`
  - _Requirements: AC-4.4, NFR-6_
  - _Design: Test Coverage Table (replay-signals.sh)_

- [x] 3.20 Test: determinism + speed (<100ms NFR-2)
  - **Do**: Add bats tests — (a) run identical inputs twice; assert identical exit code and identical event payload modulo `timestamp`; (b) `time` a single invocation and assert it completes < 100 ms.
  - **Files**: plugins/ralphharness/tests/pre-exec-check.bats
  - **Done when**: Both tests pass.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats --filter 'determinism|speed' && echo T_OK`
  - **Commit**: `test(pre-exec): determinism and <100ms speed (NFR-1, NFR-2)`
  - _Requirements: NFR-1, NFR-2_
  - _Design: Test Coverage Table (Determinism, Speed)_

- [x] 3.21 VE [VERIFY] E2E: real `pre-execution-check.sh` against fixture contracts and task blocks
  - **Do**:
    1. Run the REAL `pre-execution-check.sh` end-to-end (no bats wrapper) against the `tests/fixtures/pre-exec/` contracts in a `mktemp -d` spec dir.
    2. Exercise the full exit-code contract: an in-bounds write (`0`), a Denylist write (`2`, `layer=role-contract`), a `rm -rf` verify (`2`, `decision=confirm`), and a no-`--paths` task (`2`, `risk=UNKNOWN`).
    3. Assert the `signals.jsonl` audit append: one event per invocation, all valid JSON, append-only (prior lines unchanged).
    4. This is a shell-level CLI integration check — no dev server, no browser; no `e2e`/`playwright` skills needed.
  - **Files**: _(verification only — runs the built script and fixtures)_
  - **Done when**: All four exit-code cases match the contract; `signals.jsonl` has exactly one event per invocation and is append-only.
  - **Verify**: `d=$(mktemp -d); R=plugins/ralphharness; F=$R/tests/fixtures/pre-exec; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task ve.1 --paths chat.md --spec-path "$d"; e1=$?; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task ve.2 --paths .ralph-state.json --spec-path "$d" 1>/tmp/ve2; e2=$?; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task ve.3 --paths src/x.ts --command 'rm -rf b' --spec-path "$d" 1>/tmp/ve3; e3=$?; CLAUDE_PLUGIN_ROOT=$R bash $R/hooks/scripts/pre-execution-check.sh --agent spec-executor --task ve.4 --spec-path "$d" 1>/tmp/ve4; e4=$?; test $e1 -eq 0 && test $e2 -eq 2 && grep -q role-contract /tmp/ve2 && test $e3 -eq 2 && grep -q confirm /tmp/ve3 && test $e4 -eq 2 && grep -q UNKNOWN /tmp/ve4 && test "$(wc -l < "$d/signals.jsonl")" -eq 4 && while read -r l; do echo "$l" | jq -e . >/dev/null || exit 1; done < "$d/signals.jsonl" && echo VE_PASS; rm -rf "$d"`
  - **Commit**: none. Log the VE result to `.progress.md` under `## Learnings`.
  - _Requirements: US-5, AC-4.1, AC-4.3, Verification Contract_
  - _Design: Decision Flow; exit-code contract_

---

## Phase 4: Quality Gates

<mandatory>
NEVER push directly to the default branch. Branch management is handled at startup — you should already be on `spec/pre-execution-critic`.
</mandatory>

- [x] 4.1 Shellcheck and lint `pre-execution-check.sh`
  - **Do**: Run `shellcheck` on the script; fix any reported issues without changing behaviour. If `shellcheck` is unavailable, fall back to `bash -n`.
  - **Files**: plugins/ralphharness/hooks/scripts/pre-execution-check.sh
  - **Done when**: `shellcheck` reports no errors (or `bash -n` passes if shellcheck absent).
  - **Verify**: `shellcheck plugins/ralphharness/hooks/scripts/pre-execution-check.sh 2>/dev/null || bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh; echo LINT_OK`
  - **Commit**: `fix(pre-exec): resolve shellcheck findings in pre-execution-check.sh` (only if fixes needed)
  - _Requirements: NFR-1_

- [x] 4.2 Run the full bats suite
  - **Do**: Run the new test file plus the existing suite to confirm no regressions.
  - **Files**: _(verification only)_
  - **Done when**: `bats tests/pre-exec-check.bats` passes and existing bats tests still pass.
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats tests/signal-log.bats && echo SUITE_OK`
  - **Commit**: `fix(pre-exec): address test failures` (only if fixes needed)
  - _Requirements: NFR-1, NFR-5_

- [x] 4.3 Version bump `5.3.0` → `5.4.0`
  - **Do**: Bump the `ralphharness` version to `5.4.0` in BOTH `plugins/ralphharness/.claude-plugin/plugin.json` AND the corresponding `ralphharness` entry in `.claude-plugin/marketplace.json` (minor — new feature).
  - **Files**: plugins/ralphharness/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - **Done when**: Both files show `5.4.0` for `ralphharness`.
  - **Verify**: `jq -r .version plugins/ralphharness/.claude-plugin/plugin.json | grep -qx 5.4.0 && grep -q '5.4.0' .claude-plugin/marketplace.json && echo VERSION_OK`
  - **Commit**: `chore(pre-exec): bump ralphharness to 5.4.0`
  - _Requirements: (CLAUDE.md version-bump mandate)_

- [x] 4.4 Update CLAUDE.md current-version note
  - **Do**: Update the "Current version:" note in `CLAUDE.md` from the prior value to `5.4.0 (pre-execution-critic spec)`. If no such note exists, skip.
  - **Files**: CLAUDE.md
  - **Done when**: The CLAUDE.md current-version note reads `5.4.0 (pre-execution-critic spec)`, or the note does not exist.
  - **Verify**: `grep -q '5.4.0' CLAUDE.md || ! grep -q 'Current version:' CLAUDE.md; echo CLAUDEMD_OK`
  - **Commit**: `docs(pre-exec): update CLAUDE.md current-version note to 5.4.0`
  - _Requirements: (CLAUDE.md version-bump mandate)_

- [x] 4.5 [VERIFY] Full local CI gate
  - **Do**: Run shellcheck/`bash -n` on the script, the full bats suite, and the schema JSON validation; confirm all pass.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/pre-execution-check.sh && jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && cd plugins/ralphharness && bats tests/pre-exec-check.bats tests/signal-log.bats && echo LOCAL_CI_OK`
  - **Done when**: Script lints clean, schema valid, all bats tests pass.
  - **Commit**: `chore(pre-exec): pass local CI` (only if fixes needed)

---

## Phase 5: PR Lifecycle

- [x] 5.1 [VERIFY] Acceptance-criteria check against the Verification Contract
  - **Do**: Read `requirements.md`; programmatically confirm each PASS observable in the Verification Contract: in-bounds write → exit `0` + `decision:"allow"`; Denylist write → exit `2` + `layer:"role-contract"`; `rm -rf` task → exit `2` + `decision:"confirm"` + `risk:"HIGH"`; unclassifiable task → exit `2` + `risk:"UNKNOWN"`. Confirm the hard invariants (Layer 1 always hard-blocks, never fails open, append-only, no LLM/network call).
  - **Files**: _(verification only)_
  - **Done when**: Every Verification Contract PASS observable and hard invariant is confirmed by an automated check (re-run task 3.21 VE plus the relevant bats filters).
  - **Verify**: `cd plugins/ralphharness && bats tests/pre-exec-check.bats && echo AC_CHECK_OK`
  - **Commit**: none. Log the AC check result to `.progress.md` under `## Learnings`.
  - _Requirements: All US/FR/NFR; Verification Contract_

- [x] 5.2 Create the PR
  - **Do**:
    1. Confirm the current branch is `spec/pre-execution-critic` (`git branch --show-current`). If on the default branch, STOP and alert the user.
    2. Push the branch: `git push -u origin spec/pre-execution-critic`.
    3. Create the PR via `gh pr create` with a title and a body summarising the 3-layer pre-execution critic, the 7 files changed, and the test coverage.
  - **Files**: _(git/PR operations only)_
  - **Done when**: The PR is created and links all 7 changed files + the new test file.
  - **Verify**: `gh pr view --json url -q .url`
  - **Commit**: none (PR creation).

- [x] 5.3 [VERIFY] CI pipeline passes
  - **Do**: Verify the PR's CI checks pass; if any fail, read the failure, fix locally, push, and re-verify.
  - **Verify**: `gh pr checks`
  - **Done when**: All CI checks show passing.
  - **Commit**: `fix(pre-exec): address CI failures` (only if fixes needed)

---

## Notes

- **POC shortcuts taken (Phase 1)**: layer functions written inline before extraction; no tests until Phase 3; the PRE-EXEC-GATE block is coordinator prompt text, contract-tested through the script's exit codes (not unit-tested directly, per the design Mock Boundary).
- **Production TODOs (resolved in Phase 2)**: extract layer functions into documented units (2.1); unify the fail-safe error path (2.2); schema/template/matrix updates (2.4-2.6).
- **Out of scope (do NOT add)**: native Claude Code PreToolUse hook, LLM-based risk analysis, homoglyph/confusable detection, configurable/swappable confirmation policy, PolicyRail composed-threat rules, post-execution Critic, re-checking completed tasks.
- **Test Double Policy**: no mocks/stubs/fakes — filesystem fixtures (`role-contracts.md` variants, task blocks) and temp `signals.jsonl` via `mktemp -d` only.
- **Dependency risk**: Layer 1 is coupled to Spec 3's `## Access Matrix` table shape — if that table's columns/headers change, the `awk` parser in task 1.4-1.6 must follow.
