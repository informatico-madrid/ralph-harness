# Gito Review Context: pre-execution-critic (Spec 9)

## Spec Overview
- **Spec**: pre-execution-critic (Spec 9 of engine-roadmap-epic)
- **Branch**: spec/pre-execution-critic
- **Base**: main
- **Goal**: Add a mechanical pre-execution security critic (`pre-execution-check.sh`) that blocks/suggests risky operations before task dispatch

## Architecture: 3-Layer Security Critic
Built on the OpenHands SDK SecurityAnalyzer pattern with exit-code contract:
- **Exit 0** = allow — coordinator dispatches task
- **Exit 2** = block/confirm — coordinator hard-stops or asks for confirmation
- **Other non-zero** = UNKNOWN → confirm (fail-safe)

### Layer 1: Role-Contract Matrix Parser
- Parses `references/role-contracts.md` Access Matrix via awk
- Glob-matches each task's `--paths` against per-agent Writes/Denylist
- Violation → short-circuit to `block` (layer=role-contract, risk=HIGH)
- Intentional: Layer 1 short-circuits ALL subsequent layers (path-based veto)

### Layer 2: Shell Pattern Detector
- ERE regex set: `rm -rf`, `sudo`, `chmod 777`, `curl|wget` piped to `sh|bash`, `eval`
- Returns risk=HIGH, layer=shell-pattern
- No match → risk=LOW

### Layer 3: Risk Classifier
- `--paths` absent → UNKNOWN
- `--paths` present, Layer 1/2 clean → MEDIUM
- No match → LOW

### Combiner + Policy
- Max-severity: UNKNOWN > HIGH > MEDIUM > LOW
- ConfirmRisky policy: threshold=HIGH, confirm_unknown=true
- Security-decision events appended to `signals.jsonl` (append-only, flock fd 202)

## Implementation Summary

### Files Changed (7)
1. **NEW:** `plugins/ralphharness/hooks/scripts/pre-execution-check.sh` (~607 lines)
2. **NEW:** `plugins/ralphharness/tests/pre-exec-check.bats` (22 tests)
3. **NEW:** `plugins/ralphharness/tests/fixtures/pre-exec/` (2 fixture files)
4. **MODIFIED:** `plugins/ralphharness/commands/implement.md` (PRE-EXEC-GATE block between MALFORMED-CHECK and HOLD-GATE)
5. **MODIFIED:** `plugins/ralphharness/schemas/spec.schema.json` (added securityDecisionEvent definition)
6. **MODIFIED:** `plugins/ralphharness/templates/signals.jsonl` (security-decision header + commented example)
7. **MODIFIED:** `plugins/ralphharness/hooks/scripts/replay-signals.sh` (added comment-line stripping)
8. **MODIFIED:** `plugins/ralphharness/references/role-contracts.md` (added pre-execution-check.sh row to Access Matrix)
9. **MODIFIED:** `plugins/ralphharness/.claude-plugin/plugin.json` (version 5.3.0→5.4.0)
10. **MODIFIED:** `.claude-plugin/marketplace.json` (version 5.3.0→5.4.0)
11. **MODIFIED:** `CLAUDE.md` (version note)

### Test Coverage (22 bats tests)
- Layer 1: in-bounds, Denylist, outside Writes, missing contracts, unknown agent (5 tests)
- Layer 2: rm-rf, sudo, chmod777, curl|sh, eval, benign, absent (7 tests)
- Layer 3: no Files field (1 test)
- Combiner: Denylist+rm-rf short-circuit (1 test)
- ConfirmRisky: LOW/MEDIUM allow, HIGH/UNKNOWN confirm (4 tests)
- Audit: append-only, schema-conformant (1 test)
- Replay: handles security-decision events (1 test)
- Determinism + speed: <100ms (2 tests)
- VE E2E: full exit-code contract (1 test)

## Intentional Patterns (NOT bugs)
- **Append-only edits**: All changes to existing files are append-only (new sections, new rows in tables)
- **Layer 1 short-circuit**: Layer 1 violation ALWAYS blocks before Layer 2/3 evaluation — this is by design (path-based security gate)
- **No new subagent_type**: pre-execution-check.sh is a bash script, not a Claude Code agent
- **Comment handling in replay-signals.sh**: The signals.jsonl template contains comment lines (starting with #); replay must strip them before jq parsing — this is why grep -v '^#' was added
- **Fixture path `docs/guide.md`**: Used in "outside Writes" test because it's truly outside spec-executor's Writes set (`.progress-task-*.md, chat.md, chat.executor.lastReadLine, src/*.ts`)
- **exit code contract**: Strict 0/2 — no other non-zero values from the script itself
- **Append-only signals.jsonl**: Events are never modified, only appended. Resolution is via new event with status=resolved
- **Version bump**: 5.3.0 → 5.4.0 (minor, new feature — required by CLAUDE.md)

## Files Under Review
### Production/Plugin Files (review these)
- `plugins/ralphharness/hooks/scripts/pre-execution-check.sh` — MAIN CODE, ~607 lines
- `plugins/ralphharness/hooks/scripts/replay-signals.sh` — BUG FIX (comment handling)
- `plugins/ralphharness/commands/implement.md` — PRE-EXEC-GATE block insertion
- `plugins/ralphharness/schemas/spec.schema.json` — securityDecisionEvent definition
- `plugins/ralphharness/templates/signals.jsonl` — added comment + example
- `plugins/ralphharness/references/role-contracts.md` — added row to Access Matrix
- `plugins/ralphharness/.claude-plugin/plugin.json` — version bump
- `.claude-plugin/marketplace.json` — version bump
- `CLAUDE.md` — version note

### Test Files (review these)
- `plugins/ralphharness/tests/pre-exec-check.bats` — 22 tests
- `plugins/ralphharness/tests/fixtures/pre-exec/` — 2 fixture files

### Intentionally excluded (planning artifacts)
- `specs/pre-execution-critic/` — spec planning documents, not production code
- `specs/.index/` — index files
- `.claude/` — Claude Code config
