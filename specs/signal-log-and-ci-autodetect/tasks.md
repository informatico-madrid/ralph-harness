# Tasks: Signal Event Log + CI Auto-Detection

**Spec**: `signal-log-and-ci-autodetect` (Phase 6 of engine-roadmap-epic)
**Granularity**: fine
**Total tasks**: 65 (implementation + [VERIFY] checkpoints, including 3 VE)
**Phase distribution**:
- Phase 1 (POC, end-to-end working path): 28 tasks (~43%)
- Phase 2 (Refactor): 6 tasks (~9%)
- Phase 3 (Testing — bats coverage): 24 tasks (~37%)
- Phase 4 (Quality Gates + PR): 4 tasks (~6%)
- Phase 5 (E2E Verification, VE1-VE3): 3 tasks (~5%)
**POC milestone**: Task `1.27` — end-to-end smoke invokes `/ralphharness:implement` against a real temp spec; verifies that the live coordinator's pre-delegation gate blocks while an active HOLD line exists in `signals.jsonl` and unblocks after a resolved line is appended; verifies `detect-ci-commands.sh` populates `ciCommands` with `{command,category}` entries.
**Last updated**: 2026-05-15

---

## Phase 1: Make It Work (POC)

Goal: a real test spec runs `/ralphharness:implement`, the engine reads HOLD signals from `signals.jsonl` via `jq` (both in `commands/implement.md` and in `hooks/scripts/stop-watcher.sh`), `detect-ci-commands.sh` populates per-category CI commands in `.ralph-state.json`, and agents emit signals to `signals.jsonl` per AC-3.5. No tests yet, no docs polish. Ordering is fixed: Step 0 (fd refactor) → schema → template → script → orchestrator → engine entry-point migration (atomic landing) → agent contracts → POC checkpoint.

### Step 0 — Prerequisite: free fd 202

- [x] 1.1 Refactor stop-watcher baseline lock fd 202 -> fd 204 (Step 0, BLOCKING)
  - **Phase**: 1 (POC) — Prerequisite
  - **Maps to**: D3, design.md Implementation Step 0, FR-7 (prerequisite)
  - **Depends on**: none
  - **Do**:
    1. Open `plugins/ralphharness/hooks/scripts/stop-watcher.sh`. Locate the baseline-lock block at lines 572-573 (`exec 202>"${BASELINE_FILE}.lock"` / `flock -x 202`).
    2. Replace both occurrences of `202` with `204` on those exact lines. Do NOT touch any other line.
    3. Search the rest of the file for any other reference to fd 202 (`grep -n "202" plugins/ralphharness/hooks/scripts/stop-watcher.sh`). If a stray comment mentions fd 202 for the baseline lock, update it to 204. If it refers to a future signals.jsonl.lock, leave it.
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when**:
    - `grep -nE "exec 202>|flock .* 202" plugins/ralphharness/hooks/scripts/stop-watcher.sh` returns no matches.
    - `grep -nE "exec 204>|flock .* 204" plugins/ralphharness/hooks/scripts/stop-watcher.sh` returns the baseline-lock lines.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh` exits 0.
  - **Commit**: `refactor(phase6): stop-watcher baseline lock fd 202 -> fd 204 (frees fd 202 for signals.jsonl.lock)`
  - _Requirements: AC-1.4_

- [x] 1.2 Update channel-map.md baseline-lock row to fd 204
  - **Phase**: 1 (POC) — Prerequisite
  - **Maps to**: D3, FR-5
  - **Depends on**: 1.1
  - **Do**:
    1. Open `plugins/ralphharness/references/channel-map.md`. Locate the row documenting `.ralph-field-baseline.json.lock`.
    2. Change the fd column from `202` to `204`. Leave all other rows untouched.
    3. If a footnote references fd 202 for the baseline lock, update to 204.
  - **Files**:
    - modify: `plugins/ralphharness/references/channel-map.md`
  - **Done when**: `grep -nE "field-baseline.*204|204.*field-baseline" plugins/ralphharness/references/channel-map.md` returns the baseline row; `grep -nE "field-baseline.*202|202.*field-baseline" plugins/ralphharness/references/channel-map.md` returns no matches.
  - **Verify**: `grep -nE "field-baseline" plugins/ralphharness/references/channel-map.md | grep -v 204 | grep -E "20[0-9]" && exit 1 || echo OK`
  - **Commit**: `docs(phase6): channel-map fd 204 for baseline lock (Step 0 follow-up)`
  - _Requirements: AC-1.4_

- [ ] 1.3 [VERIFY] Post Step 0 sanity — fd refactor lands cleanly
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh` exits 0.
    - `grep -nE "exec 202>|flock .* 202" plugins/ralphharness/hooks/scripts/stop-watcher.sh` returns no matches.
    - `grep -nE "field-baseline.*202" plugins/ralphharness/references/channel-map.md` returns no matches.
    - Existing bats suite passes: `bats tests/stop-hook.bats tests/state-management.bats` (subset that touches stop-watcher).
  - **Commit**: none. Log checkpoint timestamp to `.progress.md` under `## Learnings`.

### Step 1 — Schema

- [x] 1.4 Schema: add `signals.lastProcessedLine` field
  - **Phase**: 1 (POC)
  - **Maps to**: FR-4, AC-1.5
  - **Depends on**: 1.3
  - **Do**:
    1. Open `plugins/ralphharness/schemas/spec.schema.json`.
    2. Under `properties`, add or extend the `signals` object: `"signals": { "type": "object", "properties": { "lastProcessedLine": { "type": "integer", "minimum": 0, "default": 0 } }, "additionalProperties": false }`.
    3. Do not change `chat.executor.lastReadLine` or other existing fields.
  - **Files**:
    - modify: `plugins/ralphharness/schemas/spec.schema.json`
  - **Done when**: `jq -e '.properties.signals.properties.lastProcessedLine.type=="integer"' plugins/ralphharness/schemas/spec.schema.json` returns `true`.
  - **Verify**: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && echo OK`
  - **Commit**: `feat(phase6): schema adds signals.lastProcessedLine cursor`
  - _Requirements: AC-1.5_

- [x] 1.5 Schema: upgrade `ciCommands` from string[] to array<{command,category}>
  - **Phase**: 1 (POC)
  - **Maps to**: FR-4, AC-2.5
  - **Depends on**: 1.4
  - **Do**:
    1. In `plugins/ralphharness/schemas/spec.schema.json`, locate the `ciCommands` definition (currently `{"type": "array", "items": {"type": "string"}}`).
    2. Replace with: `{"type": "array", "items": {"type": "object", "required": ["command", "category"], "properties": {"command": {"type": "string", "minLength": 1}, "category": {"type": "string", "enum": ["lint", "typecheck", "test", "build", "other"]}}, "additionalProperties": false}}`.
  - **Files**:
    - modify: `plugins/ralphharness/schemas/spec.schema.json`
  - **Done when**: `jq -e '.properties.ciCommands.items.required==["command","category"]' plugins/ralphharness/schemas/spec.schema.json` returns `true`.
  - **Verify**: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && echo OK`
  - **Commit**: `feat(phase6): schema upgrades ciCommands to {command,category} tuples`
  - _Requirements: AC-2.5_

- [x] 1.6 Schema: add `ciSnapshot` per-category result map
  - **Phase**: 1 (POC)
  - **Maps to**: FR-4, FR-12, AC-2.5
  - **Depends on**: 1.5
  - **Do**:
    1. In `plugins/ralphharness/schemas/spec.schema.json`, add `ciSnapshot` under `properties`: `{"type": "object", "properties": {"lint": {"$ref": "#/definitions/ciResult"}, "typecheck": {"$ref": "#/definitions/ciResult"}, "test": {"$ref": "#/definitions/ciResult"}, "build": {"$ref": "#/definitions/ciResult"}, "other": {"$ref": "#/definitions/ciResult"}}, "additionalProperties": false}`.
    2. Add `definitions.ciResult`: `{"oneOf": [{"type": "null"}, {"type": "object", "required": ["result","exitCode","timestamp","iteration","command"], "properties": {"result": {"enum": ["pass","fail","skip"]}, "exitCode": {"type":"integer"}, "timestamp": {"type":"string"}, "iteration": {"type":"integer"}, "command": {"type":"string"}}}]}`.
  - **Files**:
    - modify: `plugins/ralphharness/schemas/spec.schema.json`
  - **Done when**: `jq -e '.properties.ciSnapshot.properties.lint."$ref"=="#/definitions/ciResult"' plugins/ralphharness/schemas/spec.schema.json` returns `true`.
  - **Verify**: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && echo OK`
  - **Commit**: `feat(phase6): schema adds ciSnapshot per-category result map`
  - _Requirements: AC-2.5, FR-12_

- [x] 1.7 [VERIFY] Schema sanity — JSON valid, all three additions present
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null && echo JSON_OK`
    - `jq -e '.properties.signals.properties.lastProcessedLine and .properties.ciCommands.items.properties.category and .properties.ciSnapshot' plugins/ralphharness/schemas/spec.schema.json` returns `true`.
    - If `tests/state-management.bats` exists and references schema, run it: `bats tests/state-management.bats`.
  - **Commit**: none. Log checkpoint timestamp to `.progress.md`.

### Step 2 — Template signals.jsonl

- [x] 1.8 Create `templates/signals.jsonl` seed file
  - **Phase**: 1 (POC)
  - **Maps to**: FR-1, AC-1.1
  - **Depends on**: 1.7
  - **Do**:
    1. Create `plugins/ralphharness/templates/signals.jsonl` with exactly the byte content specified in design.md §Data Model "templates/signals.jsonl exact bytes" (5 lines: header comment + schema comment + DO NOT EDIT comment + 2 commented example JSON lines).
    2. Ensure the file ends with a newline and no trailing whitespace on header lines.
  - **Files**:
    - create: `plugins/ralphharness/templates/signals.jsonl`
  - **Done when**: `head -1 plugins/ralphharness/templates/signals.jsonl` starts with `# signals.jsonl —`; uncommented JSONL content count is zero: `grep -cvE '^\s*#|^$' plugins/ralphharness/templates/signals.jsonl` returns `0`.
  - **Verify**: `grep -v '^[[:space:]]*#' plugins/ralphharness/templates/signals.jsonl | grep -v '^$' | wc -l | grep -q '^0$' && echo OK`
  - **Commit**: `feat(phase6): templates/signals.jsonl seed (header + example pair commented)`
  - _Requirements: AC-1.1_

### Step 3 — detect-ci-commands.sh

- [x] 1.9 Create `detect-ci-commands.sh` skeleton + argument parsing
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.1
  - **Depends on**: 1.8
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` with `#!/usr/bin/env bash` + `set -euo pipefail`.
    2. Accept `<spec-path>` positional arg and optional `--force` flag. Validate spec-path exists. Print usage to stderr on missing args.
    3. Output empty `[]` JSON if no markers match (placeholder; populated in next tasks).
    4. `chmod +x` the script.
  - **Files**:
    - create: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: `bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh /tmp` emits `[]` (or empty JSON array) and exits 0.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh /tmp | jq -e 'type=="array"' >/dev/null && echo OK`
  - **Commit**: `feat(phase6): detect-ci-commands.sh skeleton with --force arg`
  - _Requirements: AC-2.1_

- [x] 1.10 detect-ci-commands.sh: pyproject.toml marker matrix
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.2
  - **Depends on**: 1.9
  - **Do**:
    1. In `detect-ci-commands.sh`, add a function `detect_pyproject()` that emits 4 entries when `pyproject.toml` is present in spec-path or its repo root: `ruff check .` (lint), `ruff format --check .` (lint), `mypy .` (typecheck), `pytest` (test).
    2. Output is JSON array elements appended to an in-memory accumulator.
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: Running the script against the repo root (which has a `pyproject.toml` if present, else seed a tmp dir) emits all 4 entries with correct categories.
  - **Verify**: `tmpd=$(mktemp -d); touch "$tmpd/pyproject.toml"; bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd" | jq -e '[.[] | select(.command=="ruff check .")][0].category=="lint"' >/dev/null && echo OK; rm -rf "$tmpd"`
  - **Commit**: `feat(phase6): detect-ci-commands.sh handles pyproject.toml markers`
  - _Requirements: AC-2.2_

- [x] 1.11 detect-ci-commands.sh: package.json + lockfile-aware
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.2
  - **Depends on**: 1.10
  - **Do**:
    1. Add `detect_package_json()`. Detect lockfile: `pnpm-lock.yaml` → `pnpm`, `yarn.lock` → `yarn`, otherwise `npm`. Parse `package.json` `scripts` keys via `jq`.
    2. For each script name, categorize: keys matching `lint*` → lint, `typecheck*|check-types*|tsc*` → typecheck, `test*|spec*` → test, `build*` → build, else `other`. Emit `{command: "<pkgmgr> run <scriptname>", category: <cat>}`.
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: Tmp dir with `package.json` containing `{"scripts":{"lint":"eslint .","test":"jest"}}` + `pnpm-lock.yaml` emits `{command:"pnpm run lint",category:"lint"}` and `{command:"pnpm run test",category:"test"}`.
  - **Verify**: `tmpd=$(mktemp -d); printf '{"scripts":{"lint":"eslint .","test":"jest"}}' > "$tmpd/package.json"; touch "$tmpd/pnpm-lock.yaml"; bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd" | jq -e '[.[] | select(.command=="pnpm run lint")][0].category=="lint"' >/dev/null && echo OK; rm -rf "$tmpd"`
  - **Commit**: `feat(phase6): detect-ci-commands.sh parses package.json scripts with lockfile detection`
  - _Requirements: AC-2.2_

- [x] 1.12 [VERIFY] detect-ci-commands.sh emits valid JSON for known markers
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` exits 0.
    - Tmp dir smoke for both pyproject and package.json produces valid JSON arrays (`jq -e 'type=="array" and (all(.[]; has("command") and has("category")))' >/dev/null`).
  - **Commit**: none. Log to `.progress.md`.

- [x] 1.13 detect-ci-commands.sh: Makefile lint/test/check targets
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.2
  - **Depends on**: 1.12
  - **Do**:
    1. Add `detect_makefile()`. Use `grep -E '^(lint|test|check|build)[a-z-]*:' Makefile` to list targets. For each: command = `make <target>`, category = name-based mapping (`check` → typecheck).
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: Tmp dir with `Makefile` containing `lint:\n\techo ok\ntest:\n\techo ok` emits `{command:"make lint",category:"lint"}` and `{command:"make test",category:"test"}`.
  - **Verify**: `tmpd=$(mktemp -d); printf 'lint:\n\techo ok\ntest:\n\techo ok\n' > "$tmpd/Makefile"; bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd" | jq -e '[.[] | select(.command=="make lint")][0].category=="lint"' >/dev/null && echo OK; rm -rf "$tmpd"`
  - **Commit**: `feat(phase6): detect-ci-commands.sh detects Makefile targets`
  - _Requirements: AC-2.2_

- [x] 1.14 detect-ci-commands.sh: Cargo.toml + go.mod
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.2
  - **Depends on**: 1.13
  - **Do**:
    1. Add `detect_cargo()`: when `Cargo.toml` exists, emit `cargo clippy` (lint), `cargo fmt --check` (lint), `cargo test` (test).
    2. Add `detect_go_mod()`: when `go.mod` exists, emit `go vet ./...` (lint), `go test ./...` (test).
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: Tmp dirs containing each marker produce the expected entries.
  - **Verify**: `tmpd=$(mktemp -d); touch "$tmpd/Cargo.toml"; bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd" | jq -e '[.[] | select(.command=="cargo clippy")][0].category=="lint"' >/dev/null && echo OK; rm -rf "$tmpd"`
  - **Commit**: `feat(phase6): detect-ci-commands.sh detects Cargo.toml and go.mod`
  - _Requirements: AC-2.2_

- [x] 1.15 detect-ci-commands.sh: `command -v` write-time filter
  - **Phase**: 1 (POC)
  - **Maps to**: FR-3, AC-2.4, D5
  - **Depends on**: 1.14
  - **Do**:
    1. After accumulating all entries, filter each by `command -v` on the binary name (first token of `command`). Drop entries whose binary is absent.
    2. Log dropped entries to stderr as `[detect-ci-commands] WARN: skipping <cmd> (binary <bin> not on PATH)`.
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`
  - **Done when**: With `PATH=/nonexistent` the script emits `[]`; with normal PATH and a tmp `pyproject.toml`, only entries whose binaries exist are emitted.
  - **Verify**: `tmpd=$(mktemp -d); touch "$tmpd/pyproject.toml"; out=$(PATH=/nonexistent bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd" 2>/dev/null); [ "$out" = "[]" ] && echo OK; rm -rf "$tmpd"`
  - **Commit**: `feat(phase6): detect-ci-commands.sh filters by command -v at write time`
  - _Requirements: AC-2.4_

- [x] 1.16 [VERIFY] detect-ci-commands.sh full marker matrix smoke
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - Syntax: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` exits 0.
    - Build an isolated fixture with all 5 marker types and run the script against it (NOT against the repo root — repo state is volatile):
      ```bash
      tmpd=$(mktemp -d)
      touch "$tmpd/pyproject.toml"
      printf '{"scripts":{"lint":"eslint .","test":"jest","build":"tsc"}}' > "$tmpd/package.json"
      touch "$tmpd/pnpm-lock.yaml"
      printf 'lint:\n\techo ok\ntest:\n\techo ok\ncheck:\n\techo ok\n' > "$tmpd/Makefile"
      touch "$tmpd/Cargo.toml"
      printf 'module example.com/x\ngo 1.22\n' > "$tmpd/go.mod"
      out=$(bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmpd")
      echo "$out" | jq -e 'type=="array"' >/dev/null || exit 1
      # Per-marker assertions (each command -v may filter; assert at least one entry per category survives if its binary exists, but always assert valid shape):
      echo "$out" | jq -e 'all(.[]; has("command") and has("category"))' >/dev/null || exit 1
      # Assert the script emitted at least one entry attributable to each marker family that has a usable binary in this environment.
      # If a binary is missing, the WARN line is in stderr — captured separately for cross-check.
      rm -rf "$tmpd"
      echo MATRIX_SMOKE_OK
      ```
    - Final assertion: the snippet above prints `MATRIX_SMOKE_OK` on its last line.
  - **Commit**: none. Log checkpoint to `.progress.md`.

### Step 4 — Compose detect-ci with discover-ci

- [x] 1.17 Wire orchestrator in `commands/implement.md` Step 3
  - **Phase**: 1 (POC)
  - **Maps to**: FR-11, AC-2.3
  - **Depends on**: 1.16
  - **Do**:
    1. Open `plugins/ralphharness/commands/implement.md`. Locate Step 3 (pre-loop) where `discover-ci.sh` is currently invoked (or where state-integrity validation completes).
    2. Add invocation of `detect-ci-commands.sh` immediately after `discover-ci.sh`. Pipe both outputs through `jq -s 'add'` to concatenate arrays.
    3. Pipe concatenated array through dedupe by `(command, category)` tuple: `jq 'unique_by([.command, .category])'`.
    4. Write final array into `.ralph-state.json.ciCommands` atomically (jq-based update, write to tmp then mv).
    5. **Wrap the entire orchestrator block with `# BEGIN ORCHESTRATOR` / `# END ORCHESTRATOR` marker comments** so downstream tasks (1.27, VE2) can extract it by awk.
  - **Files**:
    - modify: `plugins/ralphharness/commands/implement.md`
  - **Done when**: `grep -nE "detect-ci-commands.sh" plugins/ralphharness/commands/implement.md` returns the orchestrator block.
  - **Verify**: `grep -nE "detect-ci-commands.sh|unique_by\(\[\.command" plugins/ralphharness/commands/implement.md | wc -l | awk '$1 >= 2 {print "OK"; exit 0} {exit 1}'`
  - **Commit**: `feat(phase6): implement.md Step 3 composes discover-ci + detect-ci with tuple dedupe`
  - _Requirements: AC-2.3, FR-11_

- [x] 1.18 One-shot legacy `ciCommands: string[]` migrator (rewrites state once on first read)
  - **Phase**: 1 (POC)
  - **Maps to**: AC-2.5, D9, schema invariant (single shape post-migration)
  - **Depends on**: 1.17
  - **Do**:
    1. **Design choice locked in: one-shot migrator that rewrites state on first read.** The schema (1.5) is the single source of truth — legacy `string[]` is invalid against it. We do NOT relax the schema to `oneOf:[string,object]`; we migrate the state file once and every consumer thereafter sees only the new shape.
    2. Create a small helper script `plugins/ralphharness/hooks/scripts/migrate-state.sh` containing the migration logic. Functions:
       - `migrate_cicommands <state-file>`: reads the file, if `.ciCommands[0] | type == "string"`, applies `.ciCommands |= map(if type=="string" then {command:., category:"other"} else . end)`, writes atomically to a tmp file, then `mv` over the original. If already migrated, no-op. Appends `WARN: migrated legacy ciCommands string[] to {command,category}` to the sibling `.progress.md` exactly once per migration.
    3. In `commands/implement.md` Step 3, **before** the orchestrator block and **before** the active-signal gate, invoke `bash plugins/ralphharness/hooks/scripts/migrate-state.sh "$SPEC_PATH/.ralph-state.json"`. This guarantees every downstream reader (orchestrator, gate, schema validator) sees the post-migration shape.
    4. The migrator is the SINGLE call-site for this transformation. No other code path is allowed to inline-wrap.
  - **Files**:
    - create: `plugins/ralphharness/hooks/scripts/migrate-state.sh`
    - modify: `plugins/ralphharness/commands/implement.md`
  - **Done when**:
    - `bash -n plugins/ralphharness/hooks/scripts/migrate-state.sh` exits 0.
    - `grep -q "migrate-state.sh" plugins/ralphharness/commands/implement.md` succeeds.
    - Behavioural smoke: `tmpd=$(mktemp -d); printf '{"ciCommands":["pytest","ruff check ."]}' > "$tmpd/.ralph-state.json"; touch "$tmpd/.progress.md"; bash plugins/ralphharness/hooks/scripts/migrate-state.sh "$tmpd/.ralph-state.json"; jq -e '.ciCommands[0] | type=="object" and .command=="pytest" and .category=="other"' "$tmpd/.ralph-state.json" >/dev/null && grep -q "migrated legacy ciCommands" "$tmpd/.progress.md" && echo MIGRATE_OK; rm -rf "$tmpd"`.
  - **Verify**: the behavioural smoke above prints `MIGRATE_OK`.
  - **Commit**: `feat(phase6): one-shot legacy ciCommands migrator (migrate-state.sh, invoked from implement.md Step 3)`
  - _Requirements: AC-2.5_

- [x] 1.18a Wire migrate-state.sh into every other state-file loader (stop-watcher, replay-signals, future readers)
  - **Phase**: 1 (POC)
  - **Maps to**: AC-2.5, H2 resolution — the migrator must run before any consumer reads .ralph-state.json
  - **Depends on**: 1.18
  - **Do**:
    1. Audit every code path that reads `.ralph-state.json` and could observe legacy `ciCommands`:
       - `plugins/ralphharness/commands/implement.md` (already wired by 1.18 — verify present).
       - `plugins/ralphharness/hooks/scripts/stop-watcher.sh` (currently reads state directly via `jq` at lines ~445-450). stop-watcher does NOT read `ciCommands` today, BUT it reads the state with `jq empty` for corruption check; a legacy state still validates as JSON, so stop-watcher does not need to migrate. **Document this finding** in a comment block immediately above the `jq empty` check.
       - `plugins/ralphharness/hooks/scripts/replay-signals.sh` (created later in 3.21) — add an explicit call to `migrate-state.sh` at the top of the script as soon as it is created. Track this as a follow-up in task 3.21's Do steps (will be added by this task as a one-line note in `.progress.md` under `## Learnings`).
       - Any future loader added in Phase 2 / Phase 3 must call `migrate-state.sh` first; document this rule as a comment block at the top of `migrate-state.sh` itself.
    2. Add a top-of-file comment in `migrate-state.sh` listing every known loader site (with file path + line ranges as of this commit) and the rule "Every reader of .ralph-state.json that touches .ciCommands MUST source this migrator first."
    3. In `commands/implement.md`, add a one-line comment immediately above the `migrate-state.sh` invocation: `# Loader-site #1 of N. See hooks/scripts/migrate-state.sh header for the canonical list.`
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/migrate-state.sh`
    - modify: `plugins/ralphharness/commands/implement.md`
    - modify: `plugins/ralphharness/hooks/scripts/stop-watcher.sh` (documentation-only comment block)
  - **Done when**:
    - `grep -q "Loader-site" plugins/ralphharness/commands/implement.md` succeeds.
    - `grep -q "Every reader of .ralph-state.json" plugins/ralphharness/hooks/scripts/migrate-state.sh` succeeds.
    - `grep -q "legacy ciCommands.*does not affect this read" plugins/ralphharness/hooks/scripts/stop-watcher.sh` succeeds (the documentation comment).
    - `.progress.md` contains a Learnings line tracking that 3.21 must add a `migrate-state.sh` call to `replay-signals.sh`.
  - **Verify**: `for f in plugins/ralphharness/hooks/scripts/migrate-state.sh plugins/ralphharness/hooks/scripts/stop-watcher.sh; do bash -n "$f" || exit 1; done && grep -q "Loader-site" plugins/ralphharness/commands/implement.md && echo LOADERS_OK`
  - **Commit**: `docs(phase6): document every .ralph-state.json loader site and the migrate-state.sh contract`
  - _Requirements: AC-2.5_

### Step 5+6 — Replace HOLD check in BOTH engine entry points (atomic landing)

- [x] 1.19 Land canonical signals.jsonl HOLD gate in implement.md AND stop-watcher.sh (single atomic commit)
  - **Phase**: 1 (POC)
  - **Maps to**: FR-2, FR-7, FR-14, AC-3.3, AC-3.4, AC-1.2, AC-1.6
  - **Depends on**: 1.18a
  - **Do**:
    1. **In `plugins/ralphharness/commands/implement.md`** — locate the existing pre-delegation HOLD gate. Anchor: the literal line that currently reads (around line 304):
       ```
       count=$(grep -c '^\[HOLD\]$\|^\[PENDING\]$\|^\[URGENT\]$' "$SPEC_PATH/chat.md" 2>/dev/null || true)
       ```
       and the surrounding `MANDATORY: Mechanical HOLD check BEFORE delegation` bullet block (lines ~302-310). REPLACE that entire bullet block with the canonical active-signal gate. **Wrap the replacement block with `# BEGIN HOLD-GATE` / `# END HOLD-GATE` marker comments** so downstream tasks (1.27, VE2, 3.23) can extract it by awk:
       ```bash
       # BEGIN HOLD-GATE
       # Mechanical active-signal gate (Layer 2). Source of truth: signals.jsonl.
       # Legacy chat.md [HOLD] markers are honoured for one release cycle (NFR-6, AC-3.6)
       # via the grep fallback below — emits WARN; removed in next release.
       [ ! -f "$SPEC_PATH/signals.jsonl" ] && cp plugins/ralphharness/templates/signals.jsonl "$SPEC_PATH/signals.jsonl"
       if command -v jq >/dev/null 2>&1; then
         active_count=$(grep -v '^[[:space:]]*#' "$SPEC_PATH/signals.jsonl" 2>/dev/null \
           | jq -c 'select(.status=="active") | select(.signal=="HOLD" or .signal=="PENDING" or .signal=="URGENT" or .signal=="DEADLOCK")' \
           | wc -l | tr -d ' ')
       else
         active_count=$(grep -c '"status":"active"' "$SPEC_PATH/signals.jsonl" 2>/dev/null || echo 0)
         echo "[ralphharness] WARN: jq unavailable, using grep fallback" >> "$SPEC_PATH/.progress.md"
       fi
       # Legacy [HOLD] grace fallback (AC-3.6, NFR-6) — one release cycle only.
       if [ "$active_count" = "0" ] && grep -qE '^\[HOLD\]$|^\[PENDING\]$|^\[URGENT\]$' "$SPEC_PATH/chat.md" 2>/dev/null; then
         echo "[ralphharness] WARN: legacy [HOLD] marker in chat.md — migrate to signals.jsonl" >> "$SPEC_PATH/.progress.md"
         active_count=1
       fi
       if [ "$active_count" -gt 0 ]; then
         echo "COORDINATOR BLOCKED: active control signal in signals.jsonl for task $taskIndex" >> "$SPEC_PATH/.progress.md"
         exit 0
       fi
       # END HOLD-GATE
       ```
    2. **In `plugins/ralphharness/hooks/scripts/stop-watcher.sh`** — there is **no existing HOLD gate** to replace; we are **ADDING** the same canonical gate.
       - **Insertion anchor (exact line to grep for)**: the line
         ```
             MAX_TASK_ITER=$(jq -r '.maxTaskIterations // 5' "$STATE_FILE" 2>/dev/null || echo "5")
         ```
         which is currently the last line inside the `if [ "$PHASE" = "execution" ] && [ "$TASK_INDEX" -lt "$TOTAL_TASKS" ]; then` block before the `# Safety guard: prevent infinite re-invocation loop` comment.
       - Insert the canonical gate **immediately AFTER that `MAX_TASK_ITER=` line and BEFORE the `# Safety guard:` comment block** (so it runs every iteration of the continuation prompt). Use the SAME jq query string as implement.md (byte-identical between the two `jq -c 'select(.status==...)'` invocations). On block, `echo "[ralphharness] HOLD gate active — not emitting continuation prompt"` to stderr and `exit 0` (allowing the natural stop).
    3. Both edits land in **one single commit**. Staging guard (run BEFORE `git commit`, see Verify): assert exactly two files are staged — `commands/implement.md` and `hooks/scripts/stop-watcher.sh`.
    4. Do NOT introduce any abstraction in this task — the gate is inlined identically in both files. Phase 2 task 2.1 will extract the shared block into `lib-signals.sh`; this task deliberately keeps the inline form for atomic landing.
  - **Files**:
    - modify: `plugins/ralphharness/commands/implement.md`
    - modify: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
  - **Done when** (these assertions are robust across Phase 1 inline and Phase 2 extracted forms — they describe "same source of truth", not "byte-identical inline strings"):
    - Both files reference `signals.jsonl` as the active-signal source: `grep -q signals.jsonl plugins/ralphharness/commands/implement.md && grep -q signals.jsonl plugins/ralphharness/hooks/scripts/stop-watcher.sh`.
    - In the Phase 1 (pre-2.1-extraction) era, both files contain the literal canonical jq query string. In the Phase 2 (post-2.1) era, both files call the shared `active_signal_count` function from `lib-signals.sh`. The check below covers both cases:
      ```bash
      both_inline=$(grep -lE 'jq -c .select\(\.status=="active"\)' plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh | wc -l)
      both_lib=$(grep -lE 'active_signal_count|\. .*lib-signals\.sh' plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh | wc -l)
      [ "$both_inline" -eq 2 ] || [ "$both_lib" -eq 2 ] || exit 1
      ```
    - The stop-watcher anchor line is preserved (no accidental removal): `grep -q 'MAX_TASK_ITER=$(jq -r' plugins/ralphharness/hooks/scripts/stop-watcher.sh`.
    - The new gate is positioned AFTER that anchor and BEFORE the `# Safety guard:` comment:
      ```bash
      awk '/MAX_TASK_ITER=\$\(jq -r/{anchor=NR} /signals\.jsonl/{if(anchor && NR>anchor){found=NR}} /# Safety guard:/{if(found && NR>found){print "ORDER_OK"; exit 0}}' plugins/ralphharness/hooks/scripts/stop-watcher.sh | grep -q ORDER_OK
      ```
  - **Verify** (run in this order — staging guard FIRST so an unbalanced stage is caught BEFORE the commit):
    - Atomic-landing staging guard (executed before `git commit`):
      ```bash
      git add plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh
      git diff --cached --name-only | grep -E '(implement\.md|stop-watcher\.sh)$' | wc -l | tr -d ' ' | grep -q '^2$' || { echo "ATOMIC_LANDING_FAIL: staging is unbalanced"; exit 1; }
      ```
    - `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo SYNTAX_OK`
    - Both files reference signals.jsonl: `grep -l signals.jsonl plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh | wc -l | tr -d ' ' | grep -q '^2$' && echo BOTH_REFERENCE_OK`
    - Same-source-of-truth check (the OR of inline-string-match and lib-function-call) per the Done-when snippet above.
    - Ordering check: gate lives between the anchor and the safety guard per the awk snippet above.
  - **Commit**: `feat(phase6): canonical signals.jsonl HOLD gate inlined in implement.md and added to stop-watcher.sh (atomic landing)`
  - _Requirements: AC-1.2, AC-1.6, AC-3.3, AC-3.4, FR-2, FR-7, FR-14_

- [x] 1.20 Add malformed-JSON detection + auto-DEADLOCK at coordinator start
  - **Phase**: 1 (POC)
  - **Maps to**: design.md §Concurrency torn-line handling, Verification Contract escalation
  - **Depends on**: 1.19
  - **Do**:
    1. In `commands/implement.md` Step 3 (before the active-signal query), add the validation pass from design.md §Concurrency: iterate over non-comment lines of `signals.jsonl`; for each line, validate with `jq -e . <<< "$line"`. If any line is invalid:
       - Append a DEADLOCK signal to `signals.jsonl` via the atomic-append snippet (canonical block from design.md §Concurrency).
       - Append a line beginning `MALFORMED SIGNAL LINE` to `.progress.md`, naming the offending line number.
       - Exit non-zero so the coordinator halts.
    2. Create the fixture `tests/fixtures/phase6/malformed-signals.jsonl` (used by both this task's behavioural smoke and by Phase 3 task 3.x). Contents: one valid active-HOLD line followed by one literal malformed line `{"signal":"HOLD","status":"active" THIS IS NOT JSON`.
  - **Files**:
    - modify: `plugins/ralphharness/commands/implement.md`
    - create: `tests/fixtures/phase6/malformed-signals.jsonl`
  - **Done when**:
    - `grep -nE "MALFORMED SIGNAL LINE|malformed JSON line in signals.jsonl" plugins/ralphharness/commands/implement.md` finds the block.
    - Behavioural smoke (must succeed):
      ```bash
      tmpd=$(mktemp -d)
      cp tests/fixtures/phase6/malformed-signals.jsonl "$tmpd/signals.jsonl"
      touch "$tmpd/.progress.md"
      # Extract and run the validation snippet from implement.md against this fixture (sourced into a sub-shell). Pseudo: SPEC_PATH=$tmpd; source snippet; expect non-zero exit AND .progress.md contains MALFORMED AND signals.jsonl contains a new DEADLOCK line.
      SPEC_PATH="$tmpd" bash -c 'set -e; src=$(awk "/# BEGIN MALFORMED-CHECK/,/# END MALFORMED-CHECK/" plugins/ralphharness/commands/implement.md); eval "$src"' && rc=$? || rc=$?
      grep -q "MALFORMED SIGNAL LINE" "$tmpd/.progress.md" || exit 1
      grep -q '"signal":"DEADLOCK"' "$tmpd/signals.jsonl" || exit 1
      [ "$rc" -ne 0 ] || exit 1
      rm -rf "$tmpd"
      echo MALFORMED_SMOKE_OK
      ```
      (The validation block in `implement.md` MUST be delimited by `# BEGIN MALFORMED-CHECK` and `# END MALFORMED-CHECK` markers so the snippet can be extracted by awk for sub-shell evaluation.)
  - **Verify**: the behavioural smoke above prints `MALFORMED_SMOKE_OK`.
  - **Commit**: `feat(phase6): coordinator detects malformed signals.jsonl line and auto-DEADLOCKs (with fixture-driven smoke)`
  - _Requirements: NFR-5 (concurrency — torn line handling), Verification Contract escalation rule_

- [x] 1.21 [VERIFY] Engine entry points agree on HOLD verdict
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md, AC-3.4
  - **Verify**:
    - `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh` exits 0.
    - Both engine files reference signals.jsonl: `grep -l signals.jsonl plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh | wc -l | grep -q ^2$`.
    - Neither engine file matches the old grep pattern on chat.md HOLD: `! grep -nE "grep -c .*\\\[HOLD\\\].*chat\\.md" plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh`.
  - **Commit**: none. Log to `.progress.md`.

### Step 7-9 — Reference docs

- [x] 1.22 channel-map.md: add signals.jsonl row (fd 202)
  - **Phase**: 1 (POC)
  - **Maps to**: FR-5, AC-1.4
  - **Depends on**: 1.21
  - **Do**:
    1. In `plugins/ralphharness/references/channel-map.md`, add a new row to the channels table: file `signals.jsonl`, fd `202`, writers `coordinator, external-reviewer, spec-executor, human`, readers `coordinator, stop-watcher`, lock file `signals.jsonl.lock`.
    2. Place the row near the chat.md/tasks.md rows so the fd numbering reads sequentially (200, 201, 202, 204).
  - **Files**:
    - modify: `plugins/ralphharness/references/channel-map.md`
  - **Done when**: `grep -nE "signals\\.jsonl.*202|202.*signals\\.jsonl" plugins/ralphharness/references/channel-map.md` returns the new row.
  - **Verify**: `grep -E "signals.jsonl" plugins/ralphharness/references/channel-map.md | grep -q 202 && echo OK`
  - **Commit**: `docs(phase6): channel-map.md documents signals.jsonl (fd 202)`
  - _Requirements: AC-1.4_

- [x] 1.23 verification-layers.md: Layer 2 reads signals.jsonl (keep legacy-grace sentence)
  - **Phase**: 1 (POC)
  - **Maps to**: FR-6, AC-3.3, AC-3.6, NFR-6
  - **Depends on**: 1.22
  - **Do**:
    1. In `plugins/ralphharness/references/verification-layers.md`, locate Layer 2 (Signal). Update the primary data-source description to: "jq active-signal query on `signals.jsonl` (fallback: `grep -c '\"status\":\"active\"' signals.jsonl` when `jq` is missing)".
    2. **Keep exactly one sentence about the legacy grace period.** Add (or preserve, if already present) this sentence at the end of Layer 2's description:
       > Legacy `[HOLD]` markers in `chat.md` are honoured for one release cycle via a grep fallback — emits a WARN to `.progress.md`; will be removed in the next release (NFR-6, AC-3.6).
       This sentence MUST remain so the test in task 3.20 (which exercises the grace path) is doc-consistent. The 'replacement' is the *primary* path; the grace fallback is the documented secondary path.
    3. Other layers untouched.
  - **Files**:
    - modify: `plugins/ralphharness/references/verification-layers.md`
  - **Done when**:
    - `grep -nE "Layer 2.*signals\\.jsonl|signals\\.jsonl.*Layer 2" plugins/ralphharness/references/verification-layers.md` returns a match.
    - `grep -nE "legacy .*\\[HOLD\\].*chat\\.md|one release cycle" plugins/ralphharness/references/verification-layers.md` returns a match (the preserved grace sentence).
    - No new grep-on-chat.md is documented as the *primary* path: `! grep -E 'Layer 2.*primary.*chat\\.md' plugins/ralphharness/references/verification-layers.md`.
  - **Verify**: `grep -nE "signals.jsonl" plugins/ralphharness/references/verification-layers.md && grep -q "one release cycle\|legacy.*HOLD" plugins/ralphharness/references/verification-layers.md && echo OK`
  - **Commit**: `docs(phase6): verification-layers Layer 2 reads signals.jsonl (keeps one-release legacy grace sentence)`
  - _Requirements: AC-3.3, AC-3.6, NFR-6_

- [ ] 1.24 [VERIFY] Reference-doc trio sanity (channel-map + verification-layers + atomic-append precursor)
  - **Phase**: 1 (POC)
  - **Maps to**: quality-checkpoints.md cadence rule
  - **Depends on**: 1.23
  - **Verify**:
    - `grep -nE "signals\\.jsonl.*fd 202|fd 202.*signals\\.jsonl" plugins/ralphharness/references/channel-map.md` returns the new row.
    - `grep -nE "Layer 2.*signals\\.jsonl" plugins/ralphharness/references/verification-layers.md` returns a match.
    - `grep -nE "exec 202|flock.*202" plugins/ralphharness/hooks/scripts/stop-watcher.sh` returns **no matches** (Step 0 prerequisite still holds — no regression).
    - Files staged so far in this phase parse cleanly: `for f in plugins/ralphharness/hooks/scripts/*.sh; do bash -n "$f" || exit 1; done`.
  - **Commit**: none — verification-only checkpoint. Log timestamp to `.progress.md`.

- [x] 1.25 coordinator-pattern.md: Signal Protocol section + atomic-append snippet (fd 202)
  - **Phase**: 1 (POC)
  - **Maps to**: FR-10, FR-8, AC-1.4
  - **Depends on**: 1.24
  - **Do**:
    1. In `plugins/ralphharness/references/coordinator-pattern.md`, add a new `## Signal Protocol` section BEFORE the existing `## Chat Protocol` section.
    2. Insert the canonical atomic-append snippet from design.md §Concurrency (`append_signal()` function, fd 202 with flock -w 5, `jq -e .` pre-validation). **Wrap it with `# BEGIN ATOMIC-APPEND` / `# END ATOMIC-APPEND` marker comments** so downstream tasks (1.27, VE2) can extract it by awk.
    3. State explicitly: "signals.jsonl read precedes chat.md read in pre-delegation gate".
    4. Note that fd 202 is the result of Step 0 refactor (baseline lock moved to fd 204).
  - **Files**:
    - modify: `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: `grep -nE "## Signal Protocol|append_signal|flock.* 202" plugins/ralphharness/references/coordinator-pattern.md | wc -l` returns >= 3.
  - **Verify**: `grep -E "Signal Protocol|append_signal" plugins/ralphharness/references/coordinator-pattern.md | head && echo OK`
  - **Commit**: `docs(phase6): coordinator-pattern Signal Protocol section + atomic-append snippet`
  - _Requirements: FR-10, AC-1.4_

### Step 10-11 — Agent contracts + chat.md split

- [x] 1.26 Agent contracts: external-reviewer + spec-executor emit signals to signals.jsonl
  - **Phase**: 1 (POC)
  - **Maps to**: FR-8, AC-3.5
  - **Depends on**: 1.25
  - **Do**:
    1. In `plugins/ralphharness/agents/external-reviewer.md`, add a Signal Emission Contract section: writes `HOLD`, `PENDING`, `SPEC-ADJUSTMENT`, `SPEC-DEFICIENCY` to `signals.jsonl` via the atomic-append helper. Reference `references/coordinator-pattern.md §Signal Protocol`.
    2. In `plugins/ralphharness/agents/spec-executor.md`, add the same section: writes `INTENT-FAIL` to `signals.jsonl`. Do NOT remove existing chat.md behaviours for collaboration markers (ACK/CONTINUE/OVER/CLOSE).
    3. Cross-reference: both files must say "Control signals go to signals.jsonl; collaboration markers stay in chat.md."
  - **Files**:
    - modify: `plugins/ralphharness/agents/external-reviewer.md`
    - modify: `plugins/ralphharness/agents/spec-executor.md`
  - **Done when**: Both files contain a `Signal Emission Contract` block referencing signals.jsonl; the executor file references INTENT-FAIL; the reviewer file references HOLD/PENDING/SPEC-ADJUSTMENT/SPEC-DEFICIENCY.
  - **Verify**: `grep -l "Signal Emission Contract" plugins/ralphharness/agents/external-reviewer.md plugins/ralphharness/agents/spec-executor.md | wc -l | grep -q ^2$ && echo OK`
  - **Commit**: `feat(phase6): agent contracts emit control signals to signals.jsonl (AC-3.5)`
  - _Requirements: AC-3.5, FR-8_

### POC milestone

- [x] 1.27 POC milestone — end-to-end signals.jsonl + CI auto-detect via the live coordinator
  - **Phase**: 1 (POC) — MILESTONE
  - **Maps to**: design.md Implementation Steps 0-5 + 10, requirements Verification Contract
  - **Depends on**: 1.26
  - **Do**:
    1. Create the smoke script at `tests/fixtures/phase6/poc-smoke.sh` (executable, `set -euo pipefail`). It exercises the **live coordinator gate** in `commands/implement.md`, not just helpers.
    2. Bootstrap a real temp spec at `/tmp/ralphharness-phase6-poc/specs/poc-smoke/` with: a minimal `tasks.md` containing one trivial task, a `pyproject.toml` (so detect-ci-commands.sh produces entries), `templates/signals.jsonl` copied in, and a valid `.ralph-state.json` per the schema (`globalIteration:1`, empty `ciCommands`).
    3. **Run the coordinator pre-delegation gate against the temp spec.** Because `/ralphharness:implement` is a slash command that cannot be invoked non-interactively from bash, we must source the gate snippet directly from `commands/implement.md`. The gate block landed in task 1.19 MUST be delimited by `# BEGIN HOLD-GATE` and `# END HOLD-GATE` markers (add the markers as part of task 1.19's edit if not already present — this dependency is enforced by 1.27's Done-when below). The smoke script extracts the gate block:
       ```bash
       gate_src=$(awk '/# BEGIN HOLD-GATE/,/# END HOLD-GATE/' plugins/ralphharness/commands/implement.md)
       SPEC_PATH="/tmp/ralphharness-phase6-poc/specs/poc-smoke"
       taskIndex=0
       # Run #1: signals.jsonl has no active entries → gate should pass (not block)
       set +e; (eval "$gate_src") ; rc_unblocked=$?; set -e
       # Append a HOLD via the canonical atomic-append snippet (sourced from coordinator-pattern.md or lib-signals.sh if Phase 2 has landed).
       append_src=$(awk '/# BEGIN ATOMIC-APPEND/,/# END ATOMIC-APPEND/' plugins/ralphharness/references/coordinator-pattern.md)
       eval "$append_src"
       append_signal "$SPEC_PATH" '{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"active","timestamp":"2026-05-15T00:00:00Z","iteration":1,"reason":"POC smoke"}'
       # Run #2: gate should now BLOCK (exit non-zero or write COORDINATOR BLOCKED to .progress.md and return early).
       set +e; (eval "$gate_src") ; rc_blocked=$?; set -e
       # Append the resolved counterpart.
       append_signal "$SPEC_PATH" '{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"resolved","timestamp":"2026-05-15T00:01:00Z","iteration":2,"reason":"POC smoke resolved"}'
       # Run #3: gate should pass again.
       set +e; (eval "$gate_src") ; rc_unblocked2=$?; set -e
       ```
       (The block markers `# BEGIN ATOMIC-APPEND` / `# END ATOMIC-APPEND` must exist in `references/coordinator-pattern.md` — add them as part of task 1.25 if not already there. This dependency is enforced by 1.27's Done-when.)
       **Rationale for sourcing rather than invoking `/ralphharness:implement`**: the slash command requires Claude Code's interactive harness; it cannot be exercised from a non-interactive bash subshell. Sourcing the gate block by its delimited markers exercises the **same lines of code** the live coordinator runs, against a **real spec directory** with **real signals.jsonl writes** — which is the E2E property under test (AC-3.4, AC-1.2).
    4. **CI auto-detect leg**: invoke the orchestrator block (also delimited by `# BEGIN ORCHESTRATOR` / `# END ORCHESTRATOR` in `commands/implement.md` — markers added by task 1.17) against the temp spec. Capture `ci_count = jq '.ciCommands | length' < .ralph-state.json`.
    5. Final assertion block in the script:
       ```bash
       [ "$rc_unblocked" -eq 0 ] || { echo "FAIL: gate blocked on empty signals.jsonl"; exit 1; }
       grep -q "COORDINATOR BLOCKED" "$SPEC_PATH/.progress.md" || { echo "FAIL: gate did not log block after HOLD append"; exit 1; }
       [ "$rc_unblocked2" -eq 0 ] || { echo "FAIL: gate still blocked after resolve"; exit 1; }
       [ "$ci_count" -ge 1 ] || { echo "FAIL: ciCommands empty"; exit 1; }
       jq -e '.ciCommands[0] | has("command") and has("category")' "$SPEC_PATH/.ralph-state.json" >/dev/null || { echo "FAIL: ciCommands shape wrong"; exit 1; }
       echo POC_PASS
       ```
    6. Teardown: `rm -rf /tmp/ralphharness-phase6-poc/`.
  - **Files**:
    - create: `tests/fixtures/phase6/poc-smoke.sh` (executable smoke script — reused by Phase 3).
    - no plugin tree modifications. Temp runtime files under `/tmp/ralphharness-phase6-poc/` only.
  - **Done when**:
    - `bash tests/fixtures/phase6/poc-smoke.sh` exits 0 and the final line is `POC_PASS`.
    - The gate block in `commands/implement.md` carries `# BEGIN HOLD-GATE` / `# END HOLD-GATE` markers (precondition for the smoke's `awk` extraction). `grep -q '# BEGIN HOLD-GATE' plugins/ralphharness/commands/implement.md`.
    - The atomic-append block in `references/coordinator-pattern.md` carries `# BEGIN ATOMIC-APPEND` / `# END ATOMIC-APPEND` markers. `grep -q '# BEGIN ATOMIC-APPEND' plugins/ralphharness/references/coordinator-pattern.md`.
    - The orchestrator block in `commands/implement.md` carries `# BEGIN ORCHESTRATOR` / `# END ORCHESTRATOR` markers. `grep -q '# BEGIN ORCHESTRATOR' plugins/ralphharness/commands/implement.md`.
    - `/tmp/ralphharness-phase6-poc/` is absent after the script completes.
  - **Verify**:
    - `bash -n tests/fixtures/phase6/poc-smoke.sh` exits 0 (syntax).
    - `bash tests/fixtures/phase6/poc-smoke.sh | tail -n1 | grep -q '^POC_PASS$'` exits 0 (behavioural).
    - `[ ! -d /tmp/ralphharness-phase6-poc ]` (clean teardown).
    - All three block-marker greps pass.
  - **Commit**: `feat(phase6): POC milestone — live coordinator gate proven E2E against real spec`
  - _Requirements: Verification Contract Observable PASS, AC-1.2, AC-3.4_

---

## Phase 2: Refactor

Goal: dedupe and clean up. No new features. Code that landed inline in Phase 1 moves to canonical helpers; cosmetic inconsistencies across references resolved.

- [x] 2.1 Extract atomic-append and active-signal-count helpers into `lib-signals.sh` (canonical name)
  - **Phase**: 2 (Refactor)
  - **Maps to**: FR-10, code dedupe
  - **Depends on**: 1.27
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/lib-signals.sh` containing exactly two functions named `append_signal` and `active_signal_count`, implementations taken verbatim from design.md §Concurrency. **Function naming is canonical and is referenced by tests in Phase 3** — do not rename.
    2. In `commands/implement.md`: replace the inline canonical jq active-signal query (landed in 1.19) with a call to `active_signal_count`. Source the lib at the top of Step 3: `. plugins/ralphharness/hooks/scripts/lib-signals.sh`. Preserve the surrounding `# BEGIN HOLD-GATE` / `# END HOLD-GATE` markers from 1.19 so 1.27's smoke continues to extract the gate.
    3. In `hooks/scripts/stop-watcher.sh`: same — source the lib and call `active_signal_count`. Preserve the insertion anchor and the `signals.jsonl` reference.
    4. Update `references/coordinator-pattern.md` to point to `hooks/scripts/lib-signals.sh` as the canonical implementation. Preserve `# BEGIN ATOMIC-APPEND` / `# END ATOMIC-APPEND` markers around the inline reference snippet (the snippet now reads `. .../lib-signals.sh; append_signal "$@"` so the smoke script's eval still works).
    5. **Update Phase 3 test 3.23 to reference the lib function**: this task adds a note to `.progress.md` under `## Learnings` reminding the executor that 3.23's assertion changes from "byte-identical inline jq string" to "both files call `active_signal_count`". Also update task 3.23's wording in this same commit (a small markdown edit to tasks.md is permitted as part of this refactor since the test would otherwise be inconsistent with the new code).
  - **Files**:
    - create: `plugins/ralphharness/hooks/scripts/lib-signals.sh`
    - modify: `plugins/ralphharness/commands/implement.md`
    - modify: `plugins/ralphharness/hooks/scripts/stop-watcher.sh`
    - modify: `plugins/ralphharness/references/coordinator-pattern.md`
    - modify: `specs/signal-log-and-ci-autodetect/tasks.md` (the note in 3.23 only)
  - **Done when**:
    - `bash -c '. plugins/ralphharness/hooks/scripts/lib-signals.sh && type append_signal && type active_signal_count' | grep -c function` returns `2`.
    - `grep -q "lib-signals.sh" plugins/ralphharness/commands/implement.md && grep -q "lib-signals.sh" plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo BOTH_SOURCE_LIB`.
    - The inline jq query no longer appears in either engine file: `! grep -E "jq -c .select\\(\\.status==\"active\"\\)" plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/lib-signals.sh && grep -q "active_signal_count" plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/stop-watcher.sh && echo OK`
  - **Commit**: `refactor(phase6): extract append_signal + active_signal_count into lib-signals.sh; engine files source the lib`

- [x] 2.2 Dedupe helper `dedupe_ci_commands` lives in `lib-signals.sh` (single shared lib — canonical)
  - **Phase**: 2 (Refactor)
  - **Maps to**: D4, FR-11
  - **Depends on**: 2.1
  - **Do**:
    1. **Library name is locked: `plugins/ralphharness/hooks/scripts/lib-signals.sh`.** Do NOT create a sibling `lib-ci.sh` — Karpathy rule 3 (no abstractions outside design.md's component list; design.md sanctions exactly one helper file). All shared shell helpers for this spec live in `lib-signals.sh`, regardless of whether they concern signals or CI.
    2. Add `dedupe_ci_commands()` function to `plugins/ralphharness/hooks/scripts/lib-signals.sh`. It reads stdin (concatenated JSON arrays) and emits the unique `(command, category)` tuples via `jq -s 'add | unique_by([.command, .category])'`.
    3. Replace the inline `jq 'unique_by([.command, .category])'` invocation inside `commands/implement.md`'s `# BEGIN ORCHESTRATOR` / `# END ORCHESTRATOR` block with a call to `dedupe_ci_commands`.
  - **Files**:
    - modify: `plugins/ralphharness/hooks/scripts/lib-signals.sh`
    - modify: `plugins/ralphharness/commands/implement.md`
  - **Done when**: `grep -nE "dedupe_ci_commands" plugins/ralphharness/commands/implement.md` finds a call; the inline `unique_by` snippet is removed from `commands/implement.md` (`! grep -E "unique_by\\(\\[\\.command" plugins/ralphharness/commands/implement.md`).
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/lib-signals.sh && grep -q dedupe_ci_commands plugins/ralphharness/commands/implement.md && grep -q "dedupe_ci_commands" plugins/ralphharness/hooks/scripts/lib-signals.sh && echo OK`
  - **Commit**: `refactor(phase6): dedupe_ci_commands helper in lib-signals.sh replaces inline jq`

- [x] 2.3 [VERIFY] Refactor preserves behaviour
  - **Phase**: 2 (Refactor)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - `bash -n plugins/ralphharness/hooks/scripts/lib-signals.sh` exits 0.
    - `bash -n plugins/ralphharness/hooks/scripts/stop-watcher.sh` exits 0.
    - `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` exits 0.
    - All schema JSON still valid: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null`.
  - **Commit**: none. Log to `.progress.md`.

- [x] 2.4 Cosmetic alignment: references trio (channel-map / verification-layers / coordinator-pattern)
  - **Phase**: 2 (Refactor)
  - **Maps to**: doc consistency
  - **Depends on**: 2.3
  - **Do**:
    1. Read all three reference files. Ensure cross-links are bidirectional (channel-map links to coordinator-pattern Signal Protocol; coordinator-pattern links to channel-map for fd allocations; verification-layers links to coordinator-pattern Signal Protocol).
    2. Normalize the description of fd 202 across all three files to one sentence (copy-paste).
  - **Files**:
    - modify: `plugins/ralphharness/references/channel-map.md`
    - modify: `plugins/ralphharness/references/verification-layers.md`
    - modify: `plugins/ralphharness/references/coordinator-pattern.md`
  - **Done when**: Each file references the other two by relative path.
  - **Verify**: per-file explicit checks (one assertion per target file — no awk one-liner that can silently pass):
    ```bash
    grep -q "verification-layers" plugins/ralphharness/references/channel-map.md || { echo "channel-map missing link to verification-layers"; exit 1; }
    grep -q "coordinator-pattern"  plugins/ralphharness/references/channel-map.md || { echo "channel-map missing link to coordinator-pattern"; exit 1; }
    grep -q "channel-map"          plugins/ralphharness/references/verification-layers.md || { echo "verification-layers missing link to channel-map"; exit 1; }
    grep -q "coordinator-pattern"  plugins/ralphharness/references/verification-layers.md || { echo "verification-layers missing link to coordinator-pattern"; exit 1; }
    grep -q "channel-map"          plugins/ralphharness/references/coordinator-pattern.md || { echo "coordinator-pattern missing link to channel-map"; exit 1; }
    grep -q "verification-layers"  plugins/ralphharness/references/coordinator-pattern.md || { echo "coordinator-pattern missing link to verification-layers"; exit 1; }
    echo TRIO_LINKED_OK
    ```
  - **Commit**: `docs(phase6): cross-link references trio for fd 202 / Signal Protocol`

- [x] 2.5 chat.md template: split signal legend into control vs collaboration tables
  - **Phase**: 2 (Refactor)
  - **Maps to**: FR-9, AC-3.6
  - **Depends on**: 2.4
  - **Do**:
    1. In `plugins/ralphharness/templates/chat.md`, split the existing 12-signal legend into two tables: **Control signals** (HOLD/PENDING/URGENT/DEADLOCK/INTENT-FAIL/SPEC-ADJUSTMENT/SPEC-DEFICIENCY) marked "→ signals.jsonl"; **Collaboration markers** (OVER/ACK/CONTINUE/STILL/ALIVE/CLOSE) marked "→ chat.md (this file)".
    2. Add a Migration Note: "Legacy `[HOLD]` markers in chat.md continue to work for one release cycle (grep fallback). New control signals must use signals.jsonl — see references/coordinator-pattern.md §Signal Protocol."
  - **Files**:
    - modify: `plugins/ralphharness/templates/chat.md`
  - **Done when**: `grep -cE "Control signals|Collaboration markers|signals.jsonl" plugins/ralphharness/templates/chat.md` returns >= 3.
  - **Verify**: `grep -E "Control signals.*signals.jsonl|signals.jsonl.*Control" plugins/ralphharness/templates/chat.md && echo OK`
  - **Commit**: `docs(phase6): chat.md signal legend split (control -> signals.jsonl, collaboration stays)`

- [x] 2.6 Wire Layer 3 (ciSnapshot) writer in coordinator
  - **Phase**: 2 (Refactor)
  - **Maps to**: FR-12, Gap C4
  - **Depends on**: 2.5
  - **Do**:
    1. In `commands/implement.md`, after each quality-checkpoint block (where CI commands run), add a writer that records the per-category result to `.ralph-state.json.ciSnapshot` (atomically via tmp+mv). **Wrap the writer block with `# BEGIN CI-SNAPSHOT-WRITER` / `# END CI-SNAPSHOT-WRITER` marker comments** so task 3.22 and VE2 can extract it by awk.
    2. Schema: `{result, exitCode, timestamp, iteration, command}`. Categories not run this iteration stay `null`.
  - **Files**:
    - modify: `plugins/ralphharness/commands/implement.md`
  - **Done when**: `grep -nE "ciSnapshot.*(lint|typecheck|test|build)" plugins/ralphharness/commands/implement.md` finds the writer block.
  - **Verify**: `grep -E "ciSnapshot" plugins/ralphharness/commands/implement.md | head && echo OK`
  - **Commit**: `feat(phase6): coordinator writes per-category ciSnapshot after quality checkpoints`
  - _Requirements: FR-12_

---

## Phase 3: Testing

Goal: derive one bats test per row of the Test Coverage Table in design.md §Test Strategy. Each test lives in `tests/signal-log.bats`, `tests/ci-autodetect.bats`, or `tests/fd-202-refactor.bats`. Fixtures live under `tests/fixtures/phase6/`. Tests use real flock, real filesystem, real jq — no mocks.

### Fixtures

- [x] 3.1 Create fixture directory and shared helpers
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md §Fixtures & Test Data
  - **Depends on**: 2.6
  - **Do**:
    1. Create `tests/fixtures/phase6/`.
    2. Create `tests/fixtures/phase6/signals-mixed.jsonl` — 3 active + 2 resolved + 1 superseded entries across HOLD/PENDING/URGENT/DEADLOCK (design.md §Fixtures row 1).
    3. Create `tests/fixtures/phase6/state-legacy-cicmds.json` — `.ralph-state.json` with legacy `"ciCommands": ["pytest", "ruff check ."]`.
    4. Create `tests/fixtures/phase6/legacy-hold-chat.md` — `chat.md` with bare `[HOLD]` marker.
    5. Create `tests/fixtures/phase6/signals-history.jsonl` — append-ordered entries with `iteration` field for replay test.
    6. Create `tests/fixtures/phase6/signals-history-iter12.golden.txt` — expected replay output at iteration 12.
  - **Files**:
    - create: `tests/fixtures/phase6/signals-mixed.jsonl`
    - create: `tests/fixtures/phase6/state-legacy-cicmds.json`
    - create: `tests/fixtures/phase6/legacy-hold-chat.md`
    - create: `tests/fixtures/phase6/signals-history.jsonl`
    - create: `tests/fixtures/phase6/signals-history-iter12.golden.txt`
  - **Done when**: All 5 fixture files exist and are non-empty.
  - **Verify**: `for f in signals-mixed.jsonl state-legacy-cicmds.json legacy-hold-chat.md signals-history.jsonl signals-history-iter12.golden.txt; do [ -s tests/fixtures/phase6/$f ] || exit 1; done && echo OK`
  - **Commit**: `test(phase6): Phase 6 bats fixtures`

### tests/fd-202-refactor.bats

- [x] 3.2 bats: fd 204 baseline lock works identically to prior fd 202
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "stop-watcher baseline lock refactor"
  - **Depends on**: 3.1
  - **Do**:
    1. Create `tests/fd-202-refactor.bats`.
    2. Test: seed a tmp baseline file, source the baseline-lock section of stop-watcher.sh (or call the script with a minimal harness), assert flock on fd 204 succeeds and serialises 5 concurrent writers without torn writes.
    3. Test: assert no other consumer in stop-watcher.sh references fd 202.
  - **Files**:
    - create: `tests/fd-202-refactor.bats`
  - **Done when**: `bats tests/fd-202-refactor.bats` passes.
  - **Verify**: `bats tests/fd-202-refactor.bats`
  - **Commit**: `test(phase6): bats coverage for fd 202 -> fd 204 baseline lock refactor`

### tests/signal-log.bats

- [x] 3.3 bats: signals.jsonl append immutability (hash stability)
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row 1, AC-4.1
  - **Depends on**: 3.2
  - **Do**:
    1. Create `tests/signal-log.bats`.
    2. Test: seed signals.jsonl with 9 lines, snapshot `sha256sum` of each line, append a 10th, re-snapshot, assert lines 1..9 hashes unchanged.
  - **Files**:
    - create: `tests/signal-log.bats`
  - **Done when**: Test passes; intentional edit-in-place mutation fails the test.
  - **Verify**: `bats tests/signal-log.bats -f "append immutability"`
  - **Commit**: `test(phase6): hash-stability test for signals.jsonl append immutability`

- [x] 3.4 bats: active-signal jq query — only-active
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row 2, AC-1.2
  - **Depends on**: 3.3
  - **Do**:
    1. In `tests/signal-log.bats`, add test: load `tests/fixtures/phase6/signals-mixed.jsonl`, run the canonical jq active-signal query, assert count matches the fixture's documented active-HOLD count.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: Active count equals expected (3) for the fixture.
  - **Verify**: `bats tests/signal-log.bats -f "active signal only-active"`
  - **Commit**: `test(phase6): active-signal jq query only counts status=active`

- [x] 3.5 bats: active-signal jq query — resolved ignored
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row 3, AC-1.3
  - **Depends on**: 3.4
  - **Do**:
    1. Add test: seed signals.jsonl with 1 active + 1 resolved on the same task+signal; run query; assert count == 1 (the resolved entry itself does not block; the rule is "any active entry blocks"). NOTE: per design, supersedes is checked via replay, not via the count query; this test asserts the literal documented filter behaviour.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: Test passes per design's literal jq filter.
  - **Verify**: `bats tests/signal-log.bats -f "resolved ignored"`
  - **Commit**: `test(phase6): resolved entries do not appear in active count`

- [x] 3.6 [VERIFY] Phase 3 cadence checkpoint #1 — signal-log bats pass so far
  - **Phase**: 3 (Testing)
  - **Maps to**: quality-checkpoints.md
  - **Verify**:
    - `bats tests/signal-log.bats tests/fd-202-refactor.bats`
    - `bash -n` on all phase 6 scripts: `for f in plugins/ralphharness/hooks/scripts/*.sh; do bash -n "$f"; done`
  - **Commit**: none. Log to `.progress.md`.

- [x] 3.7 bats: non-control entries ignored
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row 4
  - **Depends on**: 3.6
  - **Do**:
    1. Add test: seed signals.jsonl with an entry where `"type":"collab"`. Run query; assert count == 0.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/signal-log.bats -f "non-control ignored"`
  - **Commit**: `test(phase6): non-control entries are filtered out`

- [x] 3.8 bats: flock fd 202 isolation under 5 parallel writers
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row 5, NFR-5
  - **Depends on**: 3.7
  - **Do**:
    1. Add test: launch 5 background subshells, each calling the atomic-append helper with a distinct payload; wait for all; assert every line in the resulting signals.jsonl is valid JSON (`jq -e .`) and the count == 5.
    2. Assert that the baseline-lock (fd 204) does not contend with fd 202 — run baseline-lock in parallel and verify both complete.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: All 5 writers' lines well-formed; no torn writes.
  - **Verify**: `bats tests/signal-log.bats -f "flock fd 202 isolation"`
  - **Commit**: `test(phase6): concurrency — flock fd 202 isolates 5 parallel writers`

- [x] 3.9 bats: jq missing → grep fallback + WARN once
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "jq missing fallback", AC-1.6, NFR-3
  - **Depends on**: 3.8
  - **Do**:
    1. Add test: stub PATH to hide jq (`PATH=/tmp/no-jq-stub`); run the active-signal pipeline against a seeded signals.jsonl; assert grep fallback runs and exits 0; assert exactly one `WARN: jq unavailable` line is logged.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: Fallback path executes; WARN logged exactly once.
  - **Verify**: `bats tests/signal-log.bats -f "jq missing"`
  - **Commit**: `test(phase6): grep fallback engaged when jq is absent`

- [x] 3.10 [VERIFY] Phase 3 cadence checkpoint #2
  - **Phase**: 3 (Testing)
  - **Maps to**: quality-checkpoints.md
  - **Verify**: `bats tests/signal-log.bats tests/fd-202-refactor.bats` (all green).
  - **Commit**: none. Log to `.progress.md`.

### tests/ci-autodetect.bats

- [x] 3.11 bats: detect-ci-commands.sh — pyproject.toml marker matrix
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "detect-ci-commands.sh — pyproject markers", AC-2.2
  - **Depends on**: 3.10
  - **Do**:
    1. Create `tests/ci-autodetect.bats`.
    2. Add test: tmp dir with `pyproject.toml`; run script; assert output includes 4 entries (ruff check, ruff format --check, mypy, pytest) with correct categories.
  - **Files**:
    - create: `tests/ci-autodetect.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/ci-autodetect.bats -f "pyproject"`
  - **Commit**: `test(phase6): detect-ci-commands.sh pyproject.toml matrix`

- [x] 3.12 bats: detect-ci-commands.sh — package.json + pnpm-lock prefers pnpm
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "package.json + pnpm-lock", AC-2.2
  - **Depends on**: 3.11
  - **Do**:
    1. Add test: tmp dir with `package.json` (scripts {lint, test}) + `pnpm-lock.yaml`; run script; assert output uses `pnpm run` not `npm run`.
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/ci-autodetect.bats -f "package.json.*pnpm"`
  - **Commit**: `test(phase6): detect-ci-commands.sh respects pnpm-lock.yaml`

- [x] 3.13 bats: detect-ci-commands.sh — Makefile lint/test/check
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "Makefile lint/test/check"
  - **Depends on**: 3.12
  - **Do**:
    1. Add test: tmp dir with Makefile `lint:`, `test:`, `check:` targets; assert output emits all three with correct categories.
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/ci-autodetect.bats -f "Makefile"`
  - **Commit**: `test(phase6): detect-ci-commands.sh Makefile targets`

- [x] 3.14 [VERIFY] Phase 3 cadence checkpoint #3
  - **Phase**: 3 (Testing)
  - **Maps to**: quality-checkpoints.md
  - **Verify**: `bats tests/ci-autodetect.bats` (all green so far).
  - **Commit**: none. Log to `.progress.md`.

- [x] 3.15 bats: detect-ci-commands.sh — Cargo + go.mod
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "Cargo + go.mod"
  - **Depends on**: 3.14
  - **Do**:
    1. Add test for Cargo.toml emitting clippy/fmt --check/test with right categories.
    2. Add test for go.mod emitting `go vet ./...` (lint) and `go test ./...` (test).
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Both tests pass.
  - **Verify**: `bats tests/ci-autodetect.bats -f "Cargo|go.mod"`
  - **Commit**: `test(phase6): detect-ci-commands.sh Cargo and go.mod markers`

- [x] 3.16 bats: `command -v` filter drops missing binaries
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "command -v filter", AC-2.4
  - **Depends on**: 3.15
  - **Do**:
    1. Add test: seed pyproject.toml in tmp; set `PATH` to a stub dir containing only `pytest` (no mypy); run script; assert `mypy .` is absent and `pytest` is present; assert a WARN line for the dropped binary.
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/ci-autodetect.bats -f "command -v"`
  - **Commit**: `test(phase6): command -v filter drops missing binaries at write time`

- [x] 3.17 bats: dedupe by (command, category) tuple
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "Dedupe by (command, category)", D4
  - **Depends on**: 3.16
  - **Do**:
    1. Add test: simulate `discover-ci.sh` emitting `{command:"pytest",category:"test"}` and `detect-ci-commands.sh` emitting `{command:"pytest",category:"test"}`. Run dedupe step; assert single entry.
    2. Add test: same command different categories produce two entries.
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Both tests pass.
  - **Verify**: `bats tests/ci-autodetect.bats -f "dedupe"`
  - **Commit**: `test(phase6): tuple dedupe by (command, category)`

- [x] 3.18 bats: migration — legacy ciCommands string[] auto-wrap
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "Migration: legacy ciCommands", AC-2.5
  - **Depends on**: 3.17
  - **Do**:
    1. Add test: load `tests/fixtures/phase6/state-legacy-cicmds.json`; run the auto-wrap migration snippet from `commands/implement.md`; assert resulting `.ciCommands` is `[{command:"pytest",category:"other"},{command:"ruff check .",category:"other"}]`.
  - **Files**:
    - modify: `tests/ci-autodetect.bats`
  - **Done when**: Test passes.
  - **Verify**: `bats tests/ci-autodetect.bats -f "legacy.*string"`
  - **Commit**: `test(phase6): legacy ciCommands string[] auto-wraps to {command,category:other}`

- [x] 3.19 [VERIFY] Phase 3 cadence checkpoint #4
  - **Phase**: 3 (Testing)
  - **Maps to**: quality-checkpoints.md
  - **Verify**: `bats tests/ci-autodetect.bats tests/signal-log.bats tests/fd-202-refactor.bats` (all green).
  - **Commit**: none. Log to `.progress.md`.

- [x] 3.20 bats: migration — legacy [HOLD] in chat.md grep fallback
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md §Failure Modes row "signals.jsonl missing on legacy spec / legacy `[HOLD]` markers still in chat.md", AC-3.6, NFR-6 (backward compat)
  - **Depends on**: 3.19
  - **Do**:
    1. Add test in `tests/signal-log.bats`: seed `tests/fixtures/phase6/legacy-hold-chat.md` and an empty signals.jsonl (no active entries). Run the engine's pre-delegation check (as it appears in implement.md after the migration block). Assert the grep fallback returns "block" and exactly one `WARN: legacy [HOLD] marker in chat.md` is logged.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: Test passes; WARN logged once per spec.
  - **Verify**: `bats tests/signal-log.bats -f "legacy.*HOLD"`
  - **Commit**: `test(phase6): legacy [HOLD] in chat.md honoured for one release cycle`

- [x] 3.21 Create replay-signals.sh + bats: replay determinism at iteration N
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Implementation Step 13, FR-13, AC-4.3, NFR-4
  - **Depends on**: 3.20
  - **Do**:
    1. Create `plugins/ralphharness/hooks/scripts/replay-signals.sh` accepting `<spec-path>` and `--at-iteration N`. **As the FIRST action of the script, invoke `bash plugins/ralphharness/hooks/scripts/migrate-state.sh "$spec_path/.ralph-state.json"` (per the loader-site rule from 1.18a) so any legacy state is migrated before reading.** Then perform a stateful fold over signals.jsonl line-by-line: for each `(task, signal)` pair, the latest event by `(iteration, line-number)` wins; output only entries whose final `status=="active"` at iteration N. Tie-break by file order when iterations match.
    2. Add test in new file `tests/replay-signals.bats`: feed `tests/fixtures/phase6/signals-history.jsonl` at iteration 12; assert output matches `tests/fixtures/phase6/signals-history-iter12.golden.txt`. Run 3 times; assert byte-identical output.
  - **Files**:
    - create: `plugins/ralphharness/hooks/scripts/replay-signals.sh`
    - create: `tests/replay-signals.bats`
  - **Done when**: Replay output matches golden; 3 runs byte-identical.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/replay-signals.sh && bats tests/replay-signals.bats`
  - **Commit**: `feat(phase6): replay-signals.sh + bats deterministic replay coverage`
  - _Requirements: FR-13, AC-4.3_

- [x] 3.22 bats: ciSnapshot per-category recording (fixture-driven stub exits)
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "ciSnapshot per-category recording", FR-12
  - **Depends on**: 3.21
  - **Do**:
    1. Create the fixture `tests/fixtures/phase6/ci-stub-exits.env` with deterministic exit codes the test sources at run time:
       ```
       # Stub exit codes for ciSnapshot bats test (loaded via `set -a; . ci-stub-exits.env; set +a`).
       STUB_LINT_EXIT=0
       STUB_TYPECHECK_EXIT=1
       STUB_TEST_EXIT=0
       ```
    2. Create three stub binaries on the bats `PATH` (under a tmp dir) named `stub-lint`, `stub-typecheck`, `stub-test`, each exiting with the value of the corresponding env var.
    3. Add the bats test in `tests/ci-autodetect.bats`: seed a `.ralph-state.json` with three `ciCommands` referencing the stubs (lint+typecheck+test). Source `tests/fixtures/phase6/ci-stub-exits.env`. Run the Layer 3 writer block from `commands/implement.md` (extracted via `# BEGIN CI-SNAPSHOT-WRITER` / `# END CI-SNAPSHOT-WRITER` markers — add to 2.6's edit). Assert `ciSnapshot.lint.result=="pass"`, `ciSnapshot.typecheck.result=="fail"`, `ciSnapshot.test.result=="pass"`, `ciSnapshot.build==null`, `ciSnapshot.other==null`.
  - **Files**:
    - create: `tests/fixtures/phase6/ci-stub-exits.env`
    - modify: `tests/ci-autodetect.bats`
    - (verify) `plugins/ralphharness/commands/implement.md` carries `# BEGIN CI-SNAPSHOT-WRITER` / `# END CI-SNAPSHOT-WRITER` markers (added by task 2.6).
  - **Done when**: All five `ciSnapshot.*` assertions pass; the stub exits are sourced from the fixture file (no inline magic numbers in the test body).
  - **Verify**: `[ -s tests/fixtures/phase6/ci-stub-exits.env ] && bats tests/ci-autodetect.bats -f "ciSnapshot"`
  - **Commit**: `test(phase6): ciSnapshot records per-category results (fixture-driven stub exits)`

- [x] 3.23 bats: coordinator and stop-watcher agree on HOLD verdict (via shared lib call-site assertion)
  - **Phase**: 3 (Testing)
  - **Maps to**: design.md Test Coverage row "Coordinator/stop-watcher agreement", AC-3.4
  - **Depends on**: 3.22
  - **Do**:
    1. Add a test in `tests/signal-log.bats` named "coordinator and stop-watcher agree on HOLD verdict". After task 2.1 lands, both engine files no longer carry inline jq queries — they call `active_signal_count` from `lib-signals.sh`. The test therefore exercises the **shared lib function** against `tests/fixtures/phase6/signals-mixed.jsonl` and asserts both call sites resolve to it:
       - Source `plugins/ralphharness/hooks/scripts/lib-signals.sh`.
       - Run `active_signal_count "$fixture_dir"` (the fixture dir is the tmp dir holding `signals-mixed.jsonl`). Capture the returned count.
       - Assert that `commands/implement.md` invokes `active_signal_count` exactly within its HOLD-GATE block: `awk '/# BEGIN HOLD-GATE/,/# END HOLD-GATE/' plugins/ralphharness/commands/implement.md | grep -q active_signal_count`.
       - Assert that `hooks/scripts/stop-watcher.sh` invokes the same function: `grep -q active_signal_count plugins/ralphharness/hooks/scripts/stop-watcher.sh`.
       - Both assertions plus a non-zero `active_signal_count` value prove the two entry points cannot diverge: they share the same code path by construction.
    2. **Backward-compat note**: if the test is ever run in a tree where 2.1 has not yet landed (e.g. mid-Phase-1 CI run), fall back to the byte-identical-inline-string assertion that task 1.19's Done-when uses (the "same source of truth" check). Detect which era we are in via `grep -l active_signal_count`; pick the appropriate assertion path.
  - **Files**:
    - modify: `tests/signal-log.bats`
  - **Done when**: The test passes; whichever era of the codebase it runs in (Phase 1 inline or Phase 2 lib-extracted), the assertion structure proves both engine files share a single source of truth for the active-signal verdict.
  - **Verify**: `bats tests/signal-log.bats -f "coordinator.*stop-watcher agree"`
  - **Commit**: `test(phase6): coordinator and stop-watcher share active_signal_count by construction (era-aware)`

- [x] 3.24 [VERIFY] Phase 3 full suite green
  - **Phase**: 3 (Testing)
  - **Maps to**: quality-checkpoints.md, NFR-2, NFR-4, NFR-5, NFR-7
  - **Verify**:
    - `bats tests/signal-log.bats tests/ci-autodetect.bats tests/fd-202-refactor.bats tests/replay-signals.bats` (all green).
    - `bats tests/` — full suite — assert zero regressions in existing tests.
  - **Commit**: none. Log to `.progress.md` with full suite result.

---

## Phase 4: Quality Gates

Goal: plugin version bumps, full local CI, PR creation, AC verification. No new features.

- [x] 4.1 Bump plugin version 5.0.0 -> 5.1.0 (BOTH manifest files, minor for new feature)
  - **Phase**: 4 (Quality Gates)
  - **Maps to**: CLAUDE.md "Version bumps required" rule
  - **Depends on**: 3.24
  - **Do**:
    1. Edit `plugins/ralphharness/.claude-plugin/plugin.json`: change `"version": "5.0.0"` to `"version": "5.1.0"`.
    2. Edit `.claude-plugin/marketplace.json`: find the `ralphharness` entry, change its version to `5.1.0`.
    3. Both edits in the same commit.
  - **Files**:
    - modify: `plugins/ralphharness/.claude-plugin/plugin.json`
    - modify: `.claude-plugin/marketplace.json`
  - **Done when**:
    - `jq -r '.version' plugins/ralphharness/.claude-plugin/plugin.json` returns `5.1.0`.
    - `jq -r '.plugins[] | select(.name=="ralphharness") | .version' .claude-plugin/marketplace.json` returns `5.1.0`.
  - **Verify**: `[ "$(jq -r .version plugins/ralphharness/.claude-plugin/plugin.json)" = "5.1.0" ] && [ "$(jq -r '.plugins[]|select(.name=="ralphharness")|.version' .claude-plugin/marketplace.json)" = "5.1.0" ] && echo OK`
  - **Commit**: `chore(phase6): bump ralphharness plugin 5.0.0 -> 5.1.0`

- [x] V4 [VERIFY] Full local CI suite — 257 bats PASS, 14 script syntax OK, schema JSON valid, version 5.1.0
  - **Phase**: 4 (Quality Gates)
  - **Maps to**: quality-checkpoints.md final sequence
  - **Verify**:
    - Syntax: `for f in plugins/ralphharness/hooks/scripts/*.sh; do bash -n "$f" || exit 1; done`
    - Schema: `jq -e . plugins/ralphharness/schemas/spec.schema.json >/dev/null`
    - Template JSON examples valid: `grep -v '^[[:space:]]*#' plugins/ralphharness/templates/signals.jsonl | grep -v '^$' | wc -l | grep -q ^0$` (template is comment-only).
    - Bats full suite: `bats tests/` (all green).
    - Plugin version: `[ "$(jq -r .version plugins/ralphharness/.claude-plugin/plugin.json)" = "5.1.0" ]`.
  - **Commit**: none — V4 is verification-only. If any check fails, fix it in a follow-up commit attributed to the originating task; do not bundle fixes under a V4 commit.

- [ ] 4.2 Branch + commits ready; open PR with `gh pr create`
  - **Phase**: 4 (Quality Gates)
  - **Maps to**: quality-checkpoints.md V5
  - **Depends on**: V4
  - **Do**:
    1. Verify current branch is a feature branch (not `main`): `b=$(git branch --show-current); [ "$b" != "main" ] || exit 1`.
    2. Push: `git push -u origin $(git branch --show-current)`.
    3. Open PR: `gh pr create --title "Phase 6: Signal Event Log + CI Auto-Detection" --body-file <(cat <<'EOF'
## Summary
- Replaces grep-based HOLD detection (gap C2) with `signals.jsonl` event log + `jq` query
- Auto-detects per-category CI commands (gap C4) via new `detect-ci-commands.sh`
- Refactors stop-watcher baseline lock fd 202 -> fd 204 (prerequisite Step 0)

## Test plan
* bats tests/ all green
* /ralphharness:start smoke runs end-to-end
* AC checklist (V6) verified
EOF
)`.
  - **Files**: none (state change only)
  - **Done when**: `gh pr view --json url,state | jq -r .state` returns `OPEN`.
  - **Verify**: `gh pr view --json state | jq -r .state | grep -q OPEN && echo PR_OPEN`
  - **Commit**: none (PR creation only; no code change)
  - **Output**: `PR_OPENED <#N> -> <url>`

- [ ] V6 [VERIFY] AC checklist — every AC in requirements.md verified programmatically
  - **Phase**: 4 (Quality Gates)
  - **Maps to**: quality-checkpoints.md final sequence, all AC-* in requirements.md
  - **Verify**:
    - AC-1.1: `signals.jsonl` schema documented in template — `grep -q "schema" plugins/ralphharness/templates/signals.jsonl`.
    - AC-1.2: canonical jq query present in both engine files — see 1.19 verify.
    - AC-1.3: append-only test green — `bats tests/signal-log.bats -f "append immutability"`.
    - AC-1.4: fd 202 documented in channel-map for signals.jsonl, fd 204 for baseline — `grep -q "signals.jsonl.*202" plugins/ralphharness/references/channel-map.md && grep -q "field-baseline.*204" plugins/ralphharness/references/channel-map.md`.
    - AC-1.5: schema has signals.lastProcessedLine — `jq -e '.properties.signals.properties.lastProcessedLine' plugins/ralphharness/schemas/spec.schema.json`.
    - AC-1.6: grep fallback test green — `bats tests/signal-log.bats -f "jq missing"`.
    - AC-2.1: detect-ci-commands.sh invoked in implement.md — `grep -q "detect-ci-commands.sh" plugins/ralphharness/commands/implement.md`.
    - AC-2.2: marker matrix bats tests green — `bats tests/ci-autodetect.bats`.
    - AC-2.3: dedupe by tuple — `grep -q "dedupe_ci_commands\|unique_by\(\[\.command" plugins/ralphharness/commands/implement.md plugins/ralphharness/hooks/scripts/*.sh`.
    - AC-2.4: command -v filter test green — `bats tests/ci-autodetect.bats -f "command -v"`.
    - AC-2.5: schema upgrade + legacy auto-wrap test green — `bats tests/ci-autodetect.bats -f "legacy"`.
    - AC-3.3/AC-3.4: coordinator+stop-watcher agreement test green — `bats tests/signal-log.bats -f "coordinator.*stop-watcher"`.
    - AC-3.5: agent contracts have Signal Emission Contract — see 1.26 verify.
    - AC-3.6: legacy [HOLD] grace test green — `bats tests/signal-log.bats -f "legacy.*HOLD"`.
    - AC-4.1: hash-stability test green.
    - AC-4.3: replay-signals.bats green.
  - **Commit**: none. Log AC status table to `.progress.md`.

---

## Phase 5: E2E Verification (VE1-VE3)

Goal: end-to-end verification by bootstrapping a temp test spec, running `/ralphharness:implement` against it, verifying signals.jsonl + ciCommands behaviour with real flock + real jq + real filesystem, then tearing down.

> **Note**: This plugin is a CLI tool / coordination engine. `UI Present: No`. VE tasks use CLI verification + filesystem assertions (no browser automation). No `ui-map-init` (VE0) needed.

- [x] VE1 [VERIFY] E2E startup: bootstrap temp spec + populate state
  - **Phase**: 5 (E2E)
  - **Skills**: e2e
  - **Do**:
    1. Create temp dir `/tmp/ralphharness-phase6-ve/specs/poc-smoke/`.
    2. Copy `plugins/ralphharness/templates/signals.jsonl` into the temp spec dir.
    3. Initialise `.ralph-state.json` with `{"name":"poc-smoke","basePath":"/tmp/ralphharness-phase6-ve/specs/poc-smoke","phase":"implement","taskIndex":0,"totalTasks":1,"taskIteration":0,"maxTaskIterations":5,"globalIteration":1,"maxGlobalIterations":10,"signals":{"lastProcessedLine":0},"ciCommands":[]}`.
    4. Create a minimal `tasks.md` with one trivial task.
    5. Touch a `pyproject.toml` in the smoke dir to force detect-ci-commands.sh to produce entries.
    6. Run the orchestrator block (discover-ci + detect-ci + dedupe + write to state). Wait for state file to be updated.
  - **Verify**: `[ -s /tmp/ralphharness-phase6-ve/specs/poc-smoke/signals.jsonl ] && jq -e '.ciCommands | length > 0' /tmp/ralphharness-phase6-ve/specs/poc-smoke/.ralph-state.json && echo VE1_PASS`
  - **Done when**: Temp spec exists with signals.jsonl, state has non-empty ciCommands with `{command,category}` shape.
  - **Commit**: None

- [x] VE2 [VERIFY] E2E check: exercise the live coordinator gate (sourced from `commands/implement.md`) against a real temp spec
  - **Phase**: 5 (E2E)
  - **Skills**: e2e
  - **Do**:
    1. Source `plugins/ralphharness/hooks/scripts/lib-signals.sh` (created in Phase 2).
    2. **Run the actual coordinator gate from `commands/implement.md` against the temp spec**, not a hand-crafted helper. Slash commands cannot be invoked from bash, so extract and `eval` the canonical block by its delimited markers (the markers were enforced as preconditions in 1.27's Done-when):
       ```bash
       SPEC_PATH=/tmp/ralphharness-phase6-ve/specs/poc-smoke
       gate_src=$(awk '/# BEGIN HOLD-GATE/,/# END HOLD-GATE/' plugins/ralphharness/commands/implement.md)
       orch_src=$(awk '/# BEGIN ORCHESTRATOR/,/# END ORCHESTRATOR/' plugins/ralphharness/commands/implement.md)
       snap_src=$(awk '/# BEGIN CI-SNAPSHOT-WRITER/,/# END CI-SNAPSHOT-WRITER/' plugins/ralphharness/commands/implement.md)
       # ITER 1: gate against empty signals.jsonl → should NOT block.
       set +e; (eval "$gate_src"); rc1=$?; set -e
       # Emit HOLD via the live append helper.
       append_signal "$SPEC_PATH" "$(jq -nc --arg ts "$(date -u +%FT%TZ)" '{type:"control",signal:"HOLD",from:"external-reviewer",to:"coordinator",task:"task-1.1",status:"active",timestamp:$ts,iteration:1,reason:"VE2 smoke"}')"
       # ITER 2: gate must block now.
       set +e; (eval "$gate_src"); rc2=$?; set -e
       # Resolve the HOLD.
       append_signal "$SPEC_PATH" "$(jq -nc --arg ts "$(date -u +%FT%TZ)" '{type:"control",signal:"HOLD",from:"external-reviewer",to:"coordinator",task:"task-1.1",status:"resolved",timestamp:$ts,iteration:2,reason:"VE2 resolve"}')"
       # ITER 3: gate must unblock again.
       set +e; (eval "$gate_src"); rc3=$?; set -e
       # CI snapshot writer with stub exits from the fixture.
       set -a; . tests/fixtures/phase6/ci-stub-exits.env; set +a
       eval "$snap_src"
       # Replay determinism.
       plugins/ralphharness/hooks/scripts/replay-signals.sh "$SPEC_PATH" --at-iteration 2 > /tmp/ve2-replay.txt
       grep -q HOLD /tmp/ve2-replay.txt && { echo "FAIL: replay still shows HOLD after resolve"; exit 1; }
       ```
    3. **Why sourcing the gate counts as an E2E exercise of the live coordinator**: every line evaluated by `eval "$gate_src"` is taken verbatim from the file that `/ralphharness:implement` reads. There is no parallel implementation. The only thing the slash-command harness adds is the surrounding Task-tool delegation — which is not the property under test for AC-1.2/AC-3.4. The gate property under test is "given this signals.jsonl state, does the gate emit BLOCK", and that is exactly what the eval'd block does, against a real spec directory, with real `signals.jsonl.lock` flock contention.
    4. Final assertion block:
       ```bash
       [ "$rc1" -eq 0 ] || { echo "FAIL: iter1 gate blocked unexpectedly"; exit 1; }
       grep -q "COORDINATOR BLOCKED" "$SPEC_PATH/.progress.md" || { echo "FAIL: iter2 gate did not log block"; exit 1; }
       [ "$rc3" -eq 0 ] || { echo "FAIL: iter3 gate still blocked after resolve"; exit 1; }
       jq -e '.ciSnapshot.lint.result=="pass" and .ciSnapshot.typecheck.result=="fail" and .ciSnapshot.test.result=="pass"' "$SPEC_PATH/.ralph-state.json" >/dev/null || { echo "FAIL: ciSnapshot wrong"; exit 1; }
       # Construction-level agreement between engine entry points.
       grep -q active_signal_count plugins/ralphharness/commands/implement.md || exit 1
       grep -q active_signal_count plugins/ralphharness/hooks/scripts/stop-watcher.sh || exit 1
       echo VE2_PASS
       ```
  - **Verify**: end-to-end smoke captures all assertions above; final line `echo VE2_PASS`.
  - **Done when**: Gate cycle BLOCK -> UNBLOCK proven against the **live coordinator block** sourced from `commands/implement.md`; ciSnapshot populated via the live writer block; both engine files call `active_signal_count`.
  - **Commit**: None

- [x] VE3 [VERIFY] E2E cleanup: tear down temp spec dir, verify no stray flock files
  - **Phase**: 5 (E2E)
  - **Skills**: e2e
  - **Do**:
    1. Remove temp dir: `rm -rf /tmp/ralphharness-phase6-ve/`.
    2. Verify no orphaned `.lock` files remain: `! find /tmp -maxdepth 3 -name 'signals.jsonl.lock' 2>/dev/null | grep -q .`.
  - **Verify**: `[ ! -e /tmp/ralphharness-phase6-ve ] && echo VE3_PASS`
  - **Done when**: Temp dir removed; no lock files orphaned.
  - **Commit**: None

---

## Notes

- **POC shortcuts taken in Phase 1**: HOLD-check landed inline in both engine entry points using raw shell snippets (extracted in Phase 2 `lib-signals.sh`); legacy `ciCommands` migration is a one-shot rewrite in `migrate-state.sh` (single call-site for the transformation, documented in the migrator's header).
- **No deferred items**: every Implementation Step 0-15 in design.md maps to at least one task. Open Questions Q2 (severity), Q3 (pytest canonicalisation), Q4 (signals-diff log) are non-blocking per `.progress.md` and remain out of scope for this spec.
- **Hard ordering invariants enforced by task numbering**:
  - Step 0 (1.1-1.2) before everything (1.3 [VERIFY] gate).
  - Schema (1.4-1.6) before any consumer (1.17+ implement.md).
  - templates/signals.jsonl (1.8) before chat.md split (2.5) — chat.md migration note points to it.
  - detect-ci-commands.sh (1.9-1.15) before orchestrator (1.17).
  - `migrate-state.sh` one-shot migrator (1.18) before any state-loading code path that touches `.ciCommands`. Loader-site audit (1.18a) immediately follows.
  - HOLD-gate landing (1.19) — `implement.md` REPLACES its existing chat.md grep gate; `stop-watcher.sh` ADDS a new gate immediately after the `MAX_TASK_ITER=` anchor and before the `# Safety guard:` comment. Both edits in one atomic commit with a staging guard (`git diff --cached --name-only | grep -c '(implement\\.md|stop-watcher\\.sh)$' == 2`).
  - coordinator-pattern.md atomic-append snippet (1.25) AFTER Step 0 (1.1) — fd 202 must be free.
  - Block-marker contract: tasks 1.17 (ORCHESTRATOR), 1.19 (HOLD-GATE), 1.20 (MALFORMED-CHECK), 1.25 (ATOMIC-APPEND), 2.6 (CI-SNAPSHOT-WRITER) each wrap their inserted code with named `# BEGIN <NAME>` / `# END <NAME>` comments. Tasks 1.27, VE2, 3.22 extract blocks by these markers for E2E execution.
  - Phase 2 (2.1) extracts `active_signal_count` + `append_signal` into `lib-signals.sh` (single canonical lib — no sibling `lib-ci.sh`). Test 3.23 is era-aware: it asserts byte-identical inline strings BEFORE 2.1 lands and `active_signal_count` call-sites AFTER 2.1 lands.
  - Doc consistency (1.23 ↔ 3.20): `verification-layers.md` Layer 2 keeps ONE sentence about the one-release legacy `[HOLD]` grace fallback; test 3.20 exercises that fallback. The two are co-consistent by construction.
  - Bats tests (Phase 3) last in their phase; implementation Verify steps use `bash -n` / `jq -e .` plus behavioural fixture smokes until bats exists.
- **Plugin version bump (4.1)** is single, in Phase 4 only, not scattered.
- **VE0 omitted**: this is a CLI tool, `UI Present: No` per project-type detection rules. VE0 (ui-map-init) is only required when browser automation is involved.
- **Live coordinator E2E rationale**: `/ralphharness:implement` cannot be invoked from non-interactive bash (slash commands require Claude Code harness). Tasks 1.27 and VE2 therefore eval the canonical gate / orchestrator / writer blocks extracted by their `# BEGIN ...` / `# END ...` markers — every evaluated line is taken verbatim from `commands/implement.md`. This exercises the same code path the live coordinator runs, against real spec directories with real `flock` contention; the only thing skipped is the Task-tool delegation wrapper (not under test for AC-1.2/AC-3.4).
