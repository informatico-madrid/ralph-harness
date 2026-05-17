---
spec: reviewer-warmup
basePath: specs/reviewer-warmup
phase: tasks
created: 2026-05-17
status: complete
granularity: coarse
---

# Tasks: reviewer-warmup

Single PR, phased internally. POC-first order: heartbeat (US-1/US-2) → bootstrap+skill (US-3/US-4) → docs (US-5) → tests → version bump + PR. Project type `cli` — markdown + shell plugin, NO VE/E2E tasks. Verification via `bats`, `grep`, `jq`, `bash -n`.

## Phase 1: Make It Work (POC)

Focus: land all functional edits end-to-end. Heartbeat emit + reviewer gate + bootstrap + skill + export + docs.

- [x] 1.1 Add executor heartbeat emission to spec-executor.md
  - **Do**:
    1. In `spec-executor.md` `<flow>`, after step 6 "Parse task", add a heartbeat-emit step: on entering Do-steps and before/around a long Explore or design-doc read, append an `ALIVE`/`STILL` `type:control` event to `signals.jsonl` via `append_signal`.
    2. Add a Signal Emission Contract row for `ALIVE`/`STILL` → `signals.jsonl` (NOT `chat.md`), tied to the "Do-steps" and "long read" triggers.
    3. Document the heartbeat JSON shape per design (fields `type/signal/from/to/task/status/timestamp/iteration/reason`), the `reason` format `"step N/M: <activity>"`, and the `ALIVE` (progressed) vs `STILL` (no progress) rule. Use `date -u +%Y-%m-%dT%H:%M:%SZ` for `timestamp`; pull `task`/`iteration` from `.ralph-state.json`.
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: `<flow>` has the heartbeat-emit step tied to concrete triggers; a Signal Emission Contract row routes `ALIVE`/`STILL` to `signals.jsonl`; `reason` format documented. `lib-signals.sh` NOT modified.
  - **Verify**: `grep -q 'ALIVE' plugins/ralphharness/agents/spec-executor.md && grep -q 'signals.jsonl' plugins/ralphharness/agents/spec-executor.md && grep -Eq 'step N/M|step [0-9]+/[0-9]+' plugins/ralphharness/agents/spec-executor.md && git diff --quiet -- plugins/ralphharness/hooks/scripts/lib-signals.sh && echo PASS`
  - **Commit**: `feat(executor): emit ALIVE/STILL liveness heartbeat to signals.jsonl`
  - _Requirements: FR-1, FR-2, AC-1.1, AC-1.2, AC-1.3, AC-1.6_
  - _Design: Component A, Implementation Step 1_

- [x] 1.2 Add reviewer freshness gate to external-reviewer.md Section 4 + Step 6
  - **Do**:
    1. Prepend the heartbeat freshness-gate algorithm block to `external-reviewer.md` Section 4, before the existing §4 "Convergence Detection" (lines ~380-405). Encode the 10-min time-based threshold, the newest-`ALIVE`/`STILL` `jq` selection, `date -u -d` epoch parse with fail-safe (parse failure / empty → `heartbeat_fresh=false`).
    2. Make the §4 `convergence_rounds` increment conditional on heartbeat freshness: fresh cycle → suppress verdict AND skip the increment + log the deferral string; stale/absent → existing §4 Convergence Detection runs unchanged (3-round → DEADLOCK).
    3. Reference the gate from Section 3b Step 6 (progress-real check) — add no new threshold.
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: Section 4 has the prepended gate block with the 10-min threshold; `convergence_rounds` increment is conditional on freshness; Step 6 references the gate; the §4 3-round escalation threshold is unchanged.
  - **Verify**: `grep -q '10' plugins/ralphharness/agents/external-reviewer.md && grep -Eq 'heartbeat|freshness' plugins/ralphharness/agents/external-reviewer.md && grep -Eq 'ALIVE|STILL' plugins/ralphharness/agents/external-reviewer.md && echo PASS`
  - **Commit**: `feat(reviewer): gate stagnation escalation on heartbeat freshness`
  - _Requirements: FR-3, FR-4, AC-2.1, AC-2.2, AC-2.3, AC-2.4_
  - _Design: Component B, Reviewer Freshness-Gate Algorithm, Implementation Step 2_

- [x] 1.3 Verify AC-2.5 byte-stable detection sections are untouched
  - **Do**:
    1. Confirm the edits in task 1.2 land only as a NEW gate block prepended to Section 4 plus the conditional `convergence_rounds` increment — nothing inside the byte-stable ranges.
    2. Verify FABRICATION §5 (lines ~409-428, esp. the "actively run the exact verify command" PASS-evidence rule) is byte-identical to its pre-edit state.
    3. Verify e2e/Step-6 §3b detection logic (lines ~300-339) is byte-identical except for the additive Step 6 gate reference from task 1.2.
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: FABRICATION §5 verify-command-evidence sentence and the e2e anti-pattern detection text are unchanged verbatim; only the additive gate block + conditional increment + Step 6 reference differ.
  - **Verify**: `grep -q 'actively run the exact verify command' plugins/ralphharness/agents/external-reviewer.md && echo PASS`
  - **Commit**: None (verification only; commit fixes if edits strayed into byte-stable ranges)
  - _Requirements: NFR-4, AC-2.5_
  - _Design: AC-2.5 No-Regression Guard — BYTE-STABLE Sections_

- [x] 1.4 Rewrite external-reviewer.md Section 0 bootstrap (full spec-state read)
  - **Do**:
    1. Rewrite Section 0 (lines ~19-33): read `chat.md` IN FULL, read `.progress.md` fully, read `git log --oneline` + `git diff --stat` since the spec branch point.
    2. Stop setting `chat.reviewer.lastReadLine` to the full chat.md line count; set it to `0`.
    3. Add a step to state a short spec-state mental model before cycle 1; preserve the existing active HOLD/PENDING/DEADLOCK detection verbatim; keep `chat.md`-absent silent-skip.
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: Section 0 reads chat.md/.progress.md/git in full, sets `lastReadLine = 0`, states a mental model; the old "lastReadLine to the current line count" skip text is removed; HOLD/PENDING/DEADLOCK detection preserved.
  - **Verify**: `grep -Eq 'chat.md.*(IN FULL|in full)' plugins/ralphharness/agents/external-reviewer.md && grep -q '.progress.md' plugins/ralphharness/agents/external-reviewer.md && grep -Eq 'git (log|diff)' plugins/ralphharness/agents/external-reviewer.md && grep -Eq 'lastReadLine *= *0|lastReadLine.*0' plugins/ralphharness/agents/external-reviewer.md && echo PASS`
  - **Commit**: `feat(reviewer): bootstrap reads full spec state before cycle 1`
  - _Requirements: FR-5, AC-3.1, AC-3.2, AC-3.3, AC-3.4_
  - _Design: Component C, Bootstrap Redesign, Implementation Step 3_

- [x] 1.5 Create reviewer-warmup SKILL.md (canonical rules)
  - **Do**:
    1. Create `plugins/ralphharness/skills/reviewer-warmup/SKILL.md` with frontmatter `name: reviewer-warmup`, `description`, `version: 0.1.0`, `user-invocable: false` (mirror `skills/reality-verification/SKILL.md`).
    2. Write the canonical Bootstrap section (full-read chat.md/.progress.md/git, `lastReadLine = 0`, mental model, preserve HOLD/PENDING/DEADLOCK).
    3. Write the canonical Heartbeat Freshness Gate section: 10-min time-based threshold, fresh → suppress + skip `convergence_rounds` increment, stale/absent → §4 runs unchanged, no new threshold; include the full freshness-gate pseudocode from the design.
  - **Files**: `plugins/ralphharness/skills/reviewer-warmup/SKILL.md`
  - **Done when**: SKILL.md exists with valid frontmatter, a Bootstrap section, and a Heartbeat Freshness Gate section containing the 10-min threshold and full pseudocode.
  - **Verify**: `grep -q 'name: reviewer-warmup' plugins/ralphharness/skills/reviewer-warmup/SKILL.md && grep -Eqi 'bootstrap' plugins/ralphharness/skills/reviewer-warmup/SKILL.md && grep -q '10 min' plugins/ralphharness/skills/reviewer-warmup/SKILL.md && echo PASS`
  - **Commit**: `feat(skill): add canonical reviewer-warmup skill`
  - _Requirements: FR-6, AC-4.1, AC-4.2_
  - _Design: Component D, Exportable Reviewer Skill, Implementation Step 4_

- [x] 1.6 Add skill references in external-reviewer.md Sections 0 and 4
  - **Do**:
    1. In `external-reviewer.md` Section 0, replace the verbose bootstrap text with a concise summary plus a `See skill: reviewer-warmup` pointer.
    2. In Section 4, add a `See skill: reviewer-warmup` pointer next to the freshness-gate block, keeping a concise inline summary.
  - **Files**: `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: Both Section 0 and Section 4 contain `See skill: reviewer-warmup`; the skill is the single source of truth and the agent text stays consistent with it.
  - **Verify**: `[ "$(grep -c 'See skill: reviewer-warmup' plugins/ralphharness/agents/external-reviewer.md)" -ge 2 ] && echo PASS`
  - **Commit**: `docs(reviewer): point Sections 0 and 4 to reviewer-warmup skill`
  - _Requirements: FR-6, AC-4.2_
  - _Design: Component D canonical relationship, Implementation Step 4_

- [x] 1.7 Add reviewer-skill export sub-step to implement.md onboarding
  - **Do**:
    1. Add an onboarding sub-step to `implement.md`, modeled on the "Pair-Debug Placement Step" (lines ~364-392), offering the reviewer-warmup skill export when the external reviewer runs in a foreign runtime.
    2. Reuse the pair-debug runtime→path map (Roo Code / Qwen / Cursor / Other) with filename `reviewer-warmup.md`; support manual-path mode (print absolute source path + activation step) and automatic-copy mode (resolve destination, copy `SKILL.md`).
    3. Add the conflict prompt (overwrite/skip per file, idempotent re-run), the unknown-runtime → manual fallback with reason `"no known destination path for <runtime>"`, and the export report.
  - **Files**: `plugins/ralphharness/commands/implement.md`
  - **Done when**: implement.md has a reviewer-skill export sub-step with manual + automatic modes, conflict prompt, unknown fallback, and export report — reusing the pair-debug map.
  - **Verify**: `grep -q 'reviewer-warmup' plugins/ralphharness/commands/implement.md && grep -Eqi 'automatic|manual' plugins/ralphharness/commands/implement.md && grep -q 'no known destination path' plugins/ralphharness/commands/implement.md && echo PASS`
  - **Commit**: `feat(implement): add reviewer-warmup skill export step`
  - _Requirements: FR-7, AC-4.3, AC-4.4_
  - _Design: Exportable Reviewer Skill — Export mechanism, Implementation Step 5_

- [x] 1.8 Update docs: chat.md legend, signals.jsonl schema, coordinator-pattern.md
  - **Do**:
    1. Update `templates/chat.md` legend rows for `ALIVE`/`STILL` to reflect their use as the executor liveness heartbeat in `signals.jsonl`.
    2. Add/extend the `templates/signals.jsonl` schema comment to document heartbeat events (`signal:ALIVE`/`STILL`, `reason` = `"step N/M: <activity>"`).
    3. Update the `references/coordinator-pattern.md` signal table heartbeat note (line ~246): clarify non-blocking (ignored by HOLD gate) + `signals.jsonl` transport.
  - **Files**: `plugins/ralphharness/templates/chat.md`, `plugins/ralphharness/templates/signals.jsonl`, `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: chat.md legend mentions the signals.jsonl heartbeat use; signals.jsonl has a heartbeat schema comment; coordinator-pattern.md signal table notes heartbeat non-blocking + signals.jsonl.
  - **Verify**: `grep -Eqi 'heartbeat|liveness' plugins/ralphharness/templates/chat.md && grep -Eqi 'ALIVE|STILL' plugins/ralphharness/templates/signals.jsonl && grep -Eqi 'heartbeat' plugins/ralphharness/references/coordinator-pattern.md && echo PASS`
  - **Commit**: `docs(signals): document ALIVE/STILL heartbeat in legend, schema, coordinator pattern`
  - _Requirements: FR-8, AC-5.1, AC-5.2, AC-5.3_
  - _Design: File Structure, Implementation Step 6_

- [x] 1.9 POC Checkpoint: heartbeat shape valid + non-blocking
  - **Do**:
    1. Construct the sample heartbeat JSON line from the design and confirm it passes `jq -e .`.
    2. Source `lib-signals.sh` and run `active_signal_count` on a `signals.jsonl` containing one `ALIVE` line; confirm it returns `0` (heartbeat non-blocking).
    3. Confirm `lib-signals.sh`, `condense-context.sh`, `lib-context.sh` are unmodified by this spec.
  - **Files**: none (verification only)
  - **Done when**: Sample heartbeat passes `jq -e`; `active_signal_count` returns `0` for an ALIVE-only log; the three protected scripts are byte-unchanged.
  - **Verify**: `echo '{"type":"control","signal":"ALIVE","from":"spec-executor","to":"external-reviewer","task":"task-1.3","status":"active","timestamp":"2026-05-17T14:22:08Z","iteration":3,"reason":"step 3/5: reading design.md"}' | jq -e . >/dev/null && git diff --quiet -- plugins/ralphharness/hooks/scripts/lib-signals.sh plugins/ralphharness/hooks/scripts/condense-context.sh plugins/ralphharness/hooks/scripts/lib-context.sh && echo PASS`
  - **Commit**: `chore(reviewer-warmup): complete POC`
  - _Requirements: FR-2, AC-1.4, AC-1.5, NFR-2_
  - _Design: Component A non-blocking proof, Data Flow_

## Phase 2: Refactoring

After POC validated, tighten the agent-prompt edits to match surrounding style.

- [x] 2.1 Tighten heartbeat + gate prose to match surrounding style
  - **Do**:
    1. Review the task 1.1/1.2/1.4 edits in `spec-executor.md` and `external-reviewer.md`; trim verbose prose to terse bullets / one-line steps matching the surrounding agent-prompt style.
    2. Ensure no duplicated rule text between the agent prompts and `SKILL.md` — agent prompts keep concise summaries; the skill stays canonical.
    3. Make no behavioral change; only concision and consistency.
  - **Files**: `plugins/ralphharness/agents/spec-executor.md`, `plugins/ralphharness/agents/external-reviewer.md`
  - **Done when**: Edited sections read as terse bullets consistent with the surrounding prompts; no rule duplication beyond a concise summary + skill pointer; behavior unchanged.
  - **Verify**: `grep -q 'See skill: reviewer-warmup' plugins/ralphharness/agents/external-reviewer.md && grep -q 'ALIVE' plugins/ralphharness/agents/spec-executor.md && echo PASS`
  - **Commit**: `refactor(reviewer-warmup): tighten heartbeat and gate prose`
  - _Requirements: NFR-3_
  - _Design: Existing Patterns to Follow — Concision_

## Phase 3: Testing

Build `test-reviewer-warmup.bats` per the design Test Coverage Table (11 rows). One test file, `bats` runner.

- [x] 3.1 Create test-reviewer-warmup.bats — heartbeat shape + non-regression + emission - pending-commit
  - **Do**:
    1. Create `plugins/ralphharness/tests/test-reviewer-warmup.bats` resolving `REPO_ROOT` via `git rev-parse --show-toplevel` (mirror `test-export.bats`).
    2. Add `@test`: a sample heartbeat line passes `jq -e .`, has `type=control`, `signal` ∈ {ALIVE,STILL}, `reason` matching `^step [0-9]+/[0-9]+: `.
    3. Add `@test`: sourcing `lib-signals.sh` and running `active_signal_count` on a `signals.jsonl` (in `BATS_TEST_TMPDIR`) with one `ALIVE` line returns `0`.
    4. Add `@test`: grep `spec-executor.md` finds the `<flow>` heartbeat-emit step AND a Signal Emission Contract row for `ALIVE`/`STILL` → `signals.jsonl` tied to "Do-steps"/"long" read triggers.
  - **Files**: `plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Done when**: The three coverage rows (heartbeat shape, `active_signal_count` non-regression, executor emission grep) are implemented and pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Commit**: `test(reviewer-warmup): heartbeat shape, non-regression, executor emission`
  - _Requirements: AC-1.1, AC-1.3, AC-1.4, AC-1.5, AC-1.6_
  - _Design: Test Coverage Table rows 1-3_

- [x] 3.2 Add freshness-gate simulation tests (fresh / stale / skip-increment / empty) - pending-commit
  - **Do**:
    1. In `test-reviewer-warmup.bats`, build inline `signals.jsonl` fixtures via `date -u -d` heredocs in `BATS_TEST_TMPDIR`: a fresh `ALIVE` (now − 90 s) and a stale `ALIVE` (now − 25 min).
    2. Add `@test` fresh case: 90 s-old heartbeat → gate yields `escalate=false` plus a deferral log string.
    3. Add `@test` stale + 3 convergence rounds: 25 min-old heartbeat → gate falls through to §4 Convergence Detection; at the 3rd unresolved round escalates to DEADLOCK.
    4. Add `@test` fresh skips round increment: 90 s-old heartbeat → verdict suppressed AND `convergence_rounds` NOT incremented.
    5. Add `@test` empty/missing `signals.jsonl` → `heartbeat_fresh=false`, normal logic.
  - **Files**: `plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Done when**: The four freshness-gate coverage rows (fresh, stale+3 rounds, fresh-skips-increment, empty) are implemented and pass.
  - **Verify**: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Commit**: `test(reviewer-warmup): freshness-gate simulation cases`
  - _Requirements: AC-2.2, AC-2.3, AC-2.4_
  - _Design: Test Coverage Table rows 4-7, Fixtures & Test Data_

- [x] 3.3 Add bootstrap, byte-stable guard, skill, reference, export, docs grep tests - pending-commit
  - **Do**:
    1. Add `@test` Section 0 bootstrap: grep `external-reviewer.md` finds "Read chat.md IN FULL", ".progress.md", "git log"/"git diff --stat", `lastReadLine = 0`; the old "lastReadLine to the current line count" skip text is ABSENT.
    2. Add `@test` AC-2.5 byte-stable guard: grep finds the verbatim FABRICATION/verify-command-evidence sentence and the e2e anti-pattern reference string.
    3. Add `@test` SKILL.md: grep finds frontmatter `name: reviewer-warmup`, bootstrap section, "10 min" threshold, freshness pseudocode.
    4. Add `@test` skill reference: grep finds `See skill: reviewer-warmup` in `external-reviewer.md` Sections 0 and 4.
    5. Add `@test` implement.md export: grep finds the reviewer-skill export with manual-path + automatic-copy modes, conflict prompt, "no known destination path" fallback.
    6. Add `@test` docs: grep finds the `ALIVE`/`STILL` heartbeat note in `chat.md` legend, the schema comment in `signals.jsonl`, the heartbeat row in `coordinator-pattern.md`.
  - **Files**: `plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Done when**: The remaining coverage rows (bootstrap, byte-stable guard, SKILL.md, skill reference, export, docs) are implemented; the full file passes.
  - **Verify**: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats`
  - **Commit**: `test(reviewer-warmup): bootstrap, byte-stable, skill, export, docs grep tests`
  - _Requirements: AC-2.5, AC-3.1, AC-3.3, AC-4.1, AC-4.2, AC-4.3, AC-4.4, AC-5.1, AC-5.2, AC-5.3_
  - _Design: Test Coverage Table rows 8-13_

## Phase 4: Quality Gates

NEVER push to the default branch. Use a feature branch + PR. Branch should already be set by `/ralphharness:start`.

- [x] 4.1 Version bump 5.5.1 → 5.6.0 - c2d2eac
  - **Do**:
    1. Bump `version` in `plugins/ralphharness/.claude-plugin/plugin.json` from `5.5.1` to `5.6.0`.
    2. Mirror the bump in the ralphharness entry of `.claude-plugin/marketplace.json`.
  - **Files**: `plugins/ralphharness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - **Done when**: Both files report `5.6.0` for the ralphharness plugin.
  - **Verify**: `grep -q '5.6.0' plugins/ralphharness/.claude-plugin/plugin.json && grep -q '5.6.0' .claude-plugin/marketplace.json && jq -e . plugins/ralphharness/.claude-plugin/plugin.json >/dev/null && jq -e . .claude-plugin/marketplace.json >/dev/null && echo PASS`
  - **Commit**: `chore(ralphharness): bump version 5.5.1 -> 5.6.0`
  - _Requirements: NFR-5_
  - _Design: File Structure, Implementation Step 8_

- [x] 4.2 [VERIFY] Full local CI: bats suite + JSON + bash -n - 2fb5010
  - **Do**:
    1. Run the spec test file: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats`.
    2. Run the broader plugin test suite to confirm no regression: `bats plugins/ralphharness/tests/`.
    3. Validate all touched JSON files with `jq -e .`; run `bash -n` on any `.sh` this spec edited (expected: none).
  - **Files**: none (verification; commit fixes if needed)
  - **Done when**: `test-reviewer-warmup.bats` passes; the full bats suite is green; all touched JSON parses; no `.sh` edited (or `bash -n` clean if any).
  - **Verify**: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats && bats plugins/ralphharness/tests/ && jq -e . plugins/ralphharness/.claude-plugin/plugin.json >/dev/null && jq -e . .claude-plugin/marketplace.json >/dev/null && echo CI_PASS`
  - **Commit**: `chore(reviewer-warmup): pass local CI` (only if fixes were needed)
  - _Requirements: NFR-4, NFR-5_
  - _Design: Test Strategy_

- [x] 4.3 [VERIFY] Create PR and verify CI - 2fb5010
  - **Do**:
    1. Verify current branch is a feature branch: `git branch --show-current`. If on `main`, STOP and alert the user (branch should be set at startup).
    2. Push the branch: `git push -u origin <branch-name>`.
    3. Create the PR: `gh pr create --title "feat(reviewer-warmup): executor heartbeat + reviewer bootstrap skill" --body "<summary of US-1..US-5>"`.
    4. Watch CI: `gh pr checks --watch`. If CI fails, read `gh pr checks`, fix locally, `git push`, re-watch.
  - **Files**: none
  - **Verify**: `gh pr checks` shows all checks green.
  - **Done when**: PR created on a feature branch; all CI checks pass.
  - **Commit**: `fix(reviewer-warmup): address CI failures` (only if fixes were needed)
  - _Requirements: NFR-5_
  - _Design: File Structure_

- [x] 4.4 [VERIFY] AC checklist - 2fb5010
  - **Do**:
    1. Read `requirements.md`; for each AC (AC-1.1–AC-5.3) programmatically confirm satisfaction via grep on the touched artifacts and a `bats` run.
    2. Confirm hard invariants: `active_signal_count()` unchanged; no new `READING` kind; bootstrap no longer skips history; FABRICATION/e2e detection text byte-stable; `condense-context.sh`/`lib-context.sh` untouched.
  - **Files**: none
  - **Verify**: `git diff --quiet origin/main -- plugins/ralphharness/hooks/scripts/lib-signals.sh plugins/ralphharness/hooks/scripts/condense-context.sh plugins/ralphharness/hooks/scripts/lib-context.sh && ! grep -rq 'READING' plugins/ralphharness/agents/spec-executor.md && bats plugins/ralphharness/tests/test-reviewer-warmup.bats && echo AC_PASS`
  - **Done when**: Every AC confirmed met via automated checks; all hard invariants hold.
  - **Commit**: None
  - _Requirements: AC-1.1–AC-5.3, NFR-1–NFR-5_
  - _Design: Verification Contract observable signals_

## Phase 5: PR Lifecycle

- [ ] 5.1 [VERIFY] Resolve CI failures and review comments
  - **Do**:
    1. Monitor the PR: `gh pr checks` and `gh pr view --comments`.
    2. For each CI failure or review comment, fix locally, commit, `git push`, re-verify.
    3. Repeat until CI is green and all actionable review comments are resolved.
  - **Files**: as needed per failure/comment
  - **Verify**: `gh pr checks` all green; no unresolved actionable review comments.
  - **Done when**: CI green, review comments addressed, zero test regressions.
  - **Commit**: `fix(reviewer-warmup): address review feedback` (per fix)
  - _Requirements: NFR-4_
  - _Design: Test Strategy_

- [ ] VF [VERIFY] Final verification: heartbeat suppresses false escalation, stale still DEADLOCKs
  - **Do**:
    1. Re-run `bats plugins/ralphharness/tests/test-reviewer-warmup.bats` and confirm the fresh-heartbeat case suppresses escalation and skips the `convergence_rounds` increment, while the stale + 3-round case escalates to DEADLOCK.
    2. Confirm `active_signal_count` returns `0` for an `ALIVE`-only `signals.jsonl` (heartbeat non-blocking).
    3. Document the AFTER state in `.progress.md` learnings: cold-start false-escalation path closed, genuine-stall DEADLOCK path preserved.
  - **Files**: `specs/reviewer-warmup/.progress.md`
  - **Verify**: `bats plugins/ralphharness/tests/test-reviewer-warmup.bats && echo VF_PASS`
  - **Done when**: All `test-reviewer-warmup.bats` cases pass; the fresh-vs-stale behavior is proven; AFTER state recorded in `.progress.md`.
  - **Commit**: `chore(reviewer-warmup): verify heartbeat gate resolves cold-start escalation`
  - _Requirements: NFR-1, NFR-4, AC-2.2, AC-2.4_
  - _Design: AC-2.2 / AC-2.4 worked paths_

## Notes

- **POC shortcuts**: Phase 1 lands all functional edits; concision pass deferred to Phase 2.
- **Protected files (must NOT be modified)**: `lib-signals.sh` (`active_signal_count`, `append_signal`), `condense-context.sh`, `lib-context.sh`. Heartbeat rides the existing open `signals.jsonl` enum — no schema migration.
- **Byte-stable ranges**: external-reviewer.md FABRICATION §5 (~409-428) and e2e/Step-6 §3b detection (~300-339) stay byte-identical; §4 Convergence Detection IS modified (conditional round increment).
- **No new signal kind**: reuse `ALIVE`/`STILL`; no `READING`.
- **Project type `cli`**: no VE/E2E tasks, no Playwright; verification via `bats`/`grep`/`jq`/`bash -n`.
- **Single PR**: one feature branch, one version bump 5.5.1 → 5.6.0.
