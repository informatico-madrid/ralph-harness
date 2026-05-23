# Requirements: multi-language-support

## Goal
Extend `detect-ci-commands.sh` top-level-marker CI auto-detection from 5 ecosystems to 11 (add PHP, Ruby, Java/Kotlin, Elixir, Deno, C#/.NET), fix the `command -v` write-time filter so wrapper/relative commands (`./gradlew`, `./mvnw`) survive, AND refactor the script so its detection logic is reachable as a sourced `detect_ci_commands()` function — because the real execution loop (`implement.md`) consumes it that way, not as a CLI. Goal: Smart-Ralph runs correct quality gates on more top-level user projects.

## User Stories

### US-1: PHP project detection
**As a** PHP developer running a spec
**I want to** have `composer.json` projects auto-detect CI commands
**So that** quality gates run without manual config

**Acceptance Criteria:**
- [ ] AC-1.1: `composer.json` with a `scripts` block emits `composer run <script>` per script, categorized by name (test→test, lint/cs/fix→lint, analyse/analyze/phpstan/psalm→typecheck, build→build, else→other) — mirroring `detect_package_json`.
- [ ] AC-1.2: `composer.json` with NO `scripts` block falls back to canonical `composer test` (test) only — never hardcodes `vendor/bin/*`.
- [ ] AC-1.3: Every emitted command's first token is `composer` (PATH-resolvable), surviving the filter.
- [ ] AC-1.4: Absent `composer.json` → detector returns 0, emits nothing.

### US-2: Ruby project detection
**As a** Ruby developer
**I want** `Gemfile` projects auto-detected
**So that** rspec/rubocop run as gates

**Acceptance Criteria:**
- [ ] AC-2.1: `Gemfile` present emits canonical `bundle exec rspec` (test) and `bundle exec rubocop` (lint).
- [ ] AC-2.2: First token is `bundle` (PATH-resolvable).
- [ ] AC-2.3: Absent `Gemfile` → emits nothing.

### US-3: Java/Kotlin (Gradle + Maven) detection
**As a** JVM developer
**I want** Gradle (Groovy or Kotlin DSL) and Maven projects auto-detected, including via wrapper
**So that** `./gradlew`/`./mvnw` commands run as gates

**Acceptance Criteria:**
- [ ] AC-3.1: Presence of `build.gradle` OR `build.gradle.kts` triggers Gradle detection (both DSLs).
- [ ] AC-3.2: `pom.xml` triggers Maven detection independently — a project with both emits both sets.
- [ ] AC-3.3: When `./gradlew` exists, emit `./gradlew test` (test) and `./gradlew build` (build); else emit `gradle test`/`gradle build`. Maven analog: `./mvnw`/`mvn` → `test` (test) and `package` (build).
- [ ] AC-3.4: JVM aggregate commands (`gradle check`, `mvn verify`) are NOT emitted as a pure `typecheck` category. Test and build are split into honest categories.
- [ ] AC-3.5: Wrapper commands (`./gradlew test`) survive the filter (depends on US-7).

### US-4: Elixir (Mix) detection
**As an** Elixir developer
**I want** `mix.exs` projects auto-detected
**So that** mix test/credo/format run as gates

**Acceptance Criteria:**
- [ ] AC-4.1: `mix.exs` with discoverable `aliases` prefers `mix <alias>` for matching names (test/lint/credo/dialyzer); else canonical fallback.
- [ ] AC-4.2: Canonical fallback emits `mix test` (test), `mix credo` (lint), `mix dialyzer` (typecheck), `mix format --check-formatted` (lint, non-mutating).
- [ ] AC-4.3: First token is `mix` (PATH-resolvable).
- [ ] AC-4.4: Absent `mix.exs` → emits nothing.

### US-5: Deno detection
**As a** Deno developer
**I want** `deno.json` projects auto-detected
**So that** deno test/lint/check run as gates

**Acceptance Criteria:**
- [ ] AC-5.1: `deno.json` (or `deno.jsonc`) with a `tasks` block prefers `deno task <name>` per task, categorized by name.
- [ ] AC-5.2: With NO `tasks`, canonical fallback emits `deno test` (test), `deno lint` (lint), `deno check` (typecheck), `deno fmt --check` (lint, non-mutating).
- [ ] AC-5.3: First token is `deno` (PATH-resolvable).
- [ ] AC-5.4: Absent `deno.json`/`deno.jsonc` → emits nothing.

### US-6: C#/.NET detection
**As a** .NET developer
**I want** `*.csproj`/`*.sln`/`global.json` projects auto-detected
**So that** dotnet test/build/format run as gates

**Acceptance Criteria:**
- [ ] AC-6.1: Presence of any `*.csproj`, `*.sln`, OR `global.json` triggers detection. CRITICAL: `*.csproj`/`*.sln` are GLOBS — must use `compgen -G "$base/*.csproj"` (or `shopt -s nullglob` + array test), NOT `[[ -f "$base/*.csproj" ]]` (a fixed-file test silently never matches a glob). `global.json` stays a fixed-file `[[ -f ]]` check.
- [ ] AC-6.2: Emits `dotnet test` (test), `dotnet build` (build), `dotnet format --verify-no-changes` (lint, non-mutating).
- [ ] AC-6.3: First token is `dotnet` (PATH-resolvable).
- [ ] AC-6.4: Absence of all three markers → emits nothing.

### US-7: Fix `command -v` filter for relative/wrapper tokens
**As a** maintainer
**I want** the write-time filter to resolve `./`-prefixed tokens against `SPEC_PATH`
**So that** wrapper commands (`./gradlew`, `./mvnw`) survive instead of being silently dropped

**Acceptance Criteria:**
- [ ] AC-7.1: First token starting with `./` is kept iff `-x "$SPEC_PATH/$bin"` (executable at that path); else dropped with the existing WARN.
- [ ] AC-7.2: First token NOT starting with `./` uses existing `command -v` PATH check (unchanged behavior).
- [ ] AC-7.3: All 17 existing `tests/ci-autodetect.bats` tests still pass unchanged.
- [ ] AC-7.4: A regression test asserts `./gradlew test` survives when an executable `./gradlew` exists in the fixture and is dropped when absent.

### US-8: Reference doc + version bump
**As a** maintainer
**I want** the guidance doc and plugin version kept consistent
**So that** docs match emitted commands and the marketplace reflects the change

**Acceptance Criteria:**
- [ ] AC-8.1: A PHP (`composer.json`) row is added to the config table in `references/quality-commands.md`. The other four rows already exist — do NOT duplicate.
- [ ] AC-8.2: A C#/.NET (`*.csproj`/`*.sln`) row is added (currently absent).
- [ ] AC-8.3: `version` bumped (minor) in BOTH `plugins/ralphharness/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (5.9.5 → 5.10.0).

### US-9: Expose detection as a sourceable `detect_ci_commands()` function
**As** the execution-loop orchestrator (`implement.md`)
**I want** to `source detect-ci-commands.sh` and call `detect_ci_commands "$REPO_ROOT"`
**So that** marker-based detection is actually reachable by the loop — today the script defines NO such function and the call site is dead (`implement.md:215,221`)

**Acceptance Criteria:**
- [ ] AC-9.1: `detect-ci-commands.sh` exposes a `detect_ci_commands(<dir>)` function wrapping the full detect→filter→emit logic and printing the JSON array to stdout. ALL detectors (existing 5 + 6 new) run inside it.
- [ ] AC-9.2: A `BASH_SOURCE`-based main-guard (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) gates the CLI body (arg parsing, path validation, the top-level `detect_ci_commands "$SPEC_PATH"` invocation). The CLI path `detect-ci-commands.sh <spec-path> [--force]` behaves identically to today.
- [ ] AC-9.3: Sourcing the file with NO arguments has ZERO side effects: no arg parsing, no `exit`, no output, and no `set -euo pipefail` option leaking into / aborting the caller's shell. Asserted by a test that sources the file and confirms the caller continues (`$?` == 0, shell not exited).
- [ ] AC-9.4: After sourcing, `detect_ci_commands "$dir"` emits the JSON array without re-running the CLI body. The existing call site `detect_cmds=$(detect_ci_commands "$REPO_ROOT")` (`implement.md:221`) works end-to-end and the merge+dedupe at `implement.md:224` receives valid JSON.
- [ ] AC-9.5: All 17 existing `tests/ci-autodetect.bats` tests (which invoke the CLI path) still pass unchanged.

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | `detect_composer` detector (scripts-discovery + fallback) | High | AC-1.* |
| FR-2 | `detect_gemfile` detector (canonical) | High | AC-2.* |
| FR-3 | `detect_gradle` (both DSLs) + `detect_maven` detectors | High | AC-3.* |
| FR-4 | `detect_mix` detector (aliases + fallback) | High | AC-4.* |
| FR-5 | `detect_deno` detector (tasks-discovery + fallback) | High | AC-5.* |
| FR-6 | `detect_dotnet` detector (glob markers via `compgen -G`/nullglob, NOT fixed-file test) | High | AC-6.* |
| FR-7 | Fix `command -v` filter for `./`-prefixed tokens | High | AC-7.* |
| FR-8 | Wire all new detectors into the run block — now INSIDE `detect_ci_commands()` (replacing the top-level run block at lines ~119-123) | High | AC-1..6, AC-9.1 |
| FR-9 | Non-mutating formatter variants for `lint` category | Medium | AC-4.2, AC-5.2, AC-6.2 |
| FR-10 | bats fixtures: one matrix test per new marker + filter regression | High | AC-7.4, all detector ACs |
| FR-11 | PHP + C#/.NET rows in quality-commands.md | Medium | AC-8.1, AC-8.2 |
| FR-12 | Minor version bump in both manifests | High | AC-8.3 |
| FR-13 | Refactor `detect-ci-commands.sh`: expose `detect_ci_commands(<dir>)` function + `BASH_SOURCE` main-guard so the sourced consumer at `implement.md:215,221` is reachable; sourcing must have no side effects | High | AC-9.* |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Output contract unchanged | JSON array of `{command, category}` | categories ∈ {lint, typecheck, test, build, other} |
| NFR-2 | No new runtime deps | toolchain additions | 0 (only bash + jq, already required) |
| NFR-3 | `set -euo pipefail` safe | detector exit on absent marker | `return 0` (never non-zero) |
| NFR-4 | Backward compatibility | existing bats suite | 17/17 pass unchanged |
| NFR-5 | Shell quality | shellcheck + `bash -n` | clean |
| NFR-6 | Semantic-duplicate gates accepted | detector output merged with `discover_ci_commands` then deduped by EXACT (command,category) tuple (`lib-signals.sh:37`, `implement.md:224`) | Detectors emit CANONICAL commands; exact-tuple dedupe will NOT collapse semantic duplicates (e.g. canonical `composer test` vs scraped `phpunit`/`composer run test`) → possible overlapping gates. Accepted & documented. Dedupe contract is a non-goal — do NOT alter it. |

## Glossary
- **Marker**: a file whose presence signals an ecosystem (e.g. `composer.json`, `Gemfile`).
- **Scripts/tasks-discovery**: reading user-defined script/task/alias names from a manifest and emitting `<pkgmgr> run <name>` rather than hardcoding tools (the `detect_package_json` pattern).
- **Write-time filter**: the `command -v` loop (lines 125-139) that drops entries whose first token is not resolvable.
- **Aggregate command**: a single command running multiple gate types (e.g. `gradle check`, `mvn verify`).
- **Non-mutating variant**: a formatter invoked in check mode (`--check`, `--check-formatted`, `--verify-no-changes`) that does not rewrite files.

## Out of Scope
- C/C++ (CMake) detection — explicitly excluded.
- AST parsing or deep config introspection — detection stays marker- and name-pattern-based.
- Modifying the `signal-log-and-ci-autodetect` design contract (`ciSnapshot`, dedupe) — extend, do not alter.
- CI-config fallback parsing (`.github/workflows`, `Jenkinsfile`) — doc-level guidance only.
- Installing/validating language toolchains — detection only emits command strings.
- Nested/monorepo subproject detection — only top-level markers at the repo root are scanned (pre-existing constraint, shared by the 5 existing detectors).
- Semantic (cross-string) dedupe of CI commands — exact (command,category) tuple dedupe is retained as-is (see NFR-6).

## Dependencies
- `jq` (already required by `detect_package_json`).
- `bats` (already used) for new fixtures.
- Existing `lib-signals.sh` dedupe + `ciSnapshot` writer remain unchanged consumers.
- `implement.md` ORCHESTRATOR block — sources the script (line 215) and calls `detect_ci_commands "$REPO_ROOT"` (line 221); this is the real runtime consumer the function refactor (FR-13) targets.
- `discover-ci.sh` (`discover_ci_commands`) — co-producer of `ciCommands`, scrapes `.github/workflows` + `tests/*.bats`; its output is merged with detector output before dedupe (`implement.md:202,221-224`).

## Success Criteria
- 6 new ecosystems detected with honest category mapping; PATH-resolvable or wrapper-surviving first tokens.
- `./gradlew`/`./mvnw` commands survive the fixed filter; 17 legacy tests + new matrix/regression tests all pass.
- shellcheck + `bash -n` clean; version bumped to 5.10.0 in both manifests.

## Verification Contract

**Project type**: cli — RalphHarness is a Claude Code plugin; the detector is a CLI shell script with no UI or HTTP API. e2e verification is bats + direct script invocation.

**Entry points**:
- CLI: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh <spec-path> [--force]` (CLI path, gated behind the new main-guard).
- Sourced function: `source detect-ci-commands.sh && detect_ci_commands "$dir"` — the REAL runtime consumer at `commands/implement.md:215` (source) and `:221` (call). This call site is currently dead.
- New detector functions: `detect_composer`, `detect_gemfile`, `detect_gradle`, `detect_maven`, `detect_mix`, `detect_deno`, `detect_dotnet`.
- New wrapper: `detect_ci_commands(<dir>)` (FR-13) + `BASH_SOURCE` main-guard.
- Modified write-time filter block (lines ~125-139).
- `tests/ci-autodetect.bats` (repo root — NOT `plugins/.../tests/`).
- `plugins/ralphharness/references/quality-commands.md` (config table, lines ~64-72).
- `plugins/ralphharness/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (version).

**Observable signals**:
- PASS: running the script against a fixture dir prints a JSON array containing the expected `{command, category}` tuples; `jq -e .` validates; expected first tokens present; `bats tests/ci-autodetect.bats` reports all tests passing; `shellcheck` + `bash -n` exit 0.
- FAIL: empty `[]` when a marker exists; missing/wrong category; wrapper command silently dropped (WARN on stderr + absent from output); any of the 17 legacy tests fails; invalid JSON; non-zero shellcheck/`bash -n`.

**Hard invariants**:
- Output is always a valid JSON array; categories stay within {lint, typecheck, test, build, other}.
- Existing 5 detectors and all 17 legacy tests behave identically.
- Detector returns 0 when its marker is absent (no `set -e` abort).
- Filter behavior for non-`./` tokens unchanged.
- Sourcing the script has ZERO side effects: no arg parse, no `exit`, no output, no `set -euo pipefail` leakage into the caller (the orchestrator must never be aborted by sourcing).
- The exact-tuple dedupe contract (`dedupe_ci_commands`) is NOT altered.

**Seed data**: temp fixture dirs containing one marker file each (composer.json with/without scripts, Gemfile, build.gradle, build.gradle.kts, pom.xml, mix.exs, deno.json, *.csproj, plus an executable `./gradlew` for the filter regression). Stub binaries on PATH (composer, bundle, mix, deno, dotnet, gradle, mvn) so write-time filter retains PATH-token entries.

**Dependency map**:
- `commands/implement.md` ORCHESTRATOR — sources the script (`:215`) and calls `detect_ci_commands` (`:221`); merges with discover output and dedupes (`:224`). Primary consumer of FR-13.
- `discover-ci.sh` (`discover_ci_commands`) — co-producer of `ciCommands`; its output is merged with detector output before dedupe (`implement.md:202,221-224`). Semantic duplicates across the two producers are NOT collapsed (NFR-6).
- `lib-signals.sh` (`dedupe_ci_commands`, line 37) — consumes the merged output; exact-tuple dedupe; must not break.
- `commands/implement.md` CI-SNAPSHOT-WRITER — records per-category snapshot; shares the category vocabulary.
- `signal-log-and-ci-autodetect` spec — original owner of the contract; extended not modified.

**Escalate if**:
- Fixing the filter would require changing behavior of any non-`./` token path.
- A detector cannot emit a PATH-resolvable or wrapper-surviving first token without guessing an uninstalled tool.
- Honest categorization of an ecosystem's commands is genuinely ambiguous (e.g. an aggregate with no test/build split).
- The `BASH_SOURCE` main-guard refactor would change CLI output or break any legacy bats test (sourcing and CLI paths must stay isolated).
- A glob marker (`*.csproj`/`*.sln`) appears to need a fixed-file test — it does not; use `compgen -G`/nullglob (do not silently fall back to `[[ -f ]]`).

## Unresolved Questions
- (Resolved via binding decision, capturing as requirement) Non-mutating formatter variants are emitted for the lint category — confirm no project expects the mutating form in CI.
- Maven build category: emit `mvn package` vs `mvn compile` as the canonical build command — design to pick one (lean `package`).
- Deno config: should `deno.jsonc` be treated identically to `deno.json`? (Assumed yes.)

## Post-Implementation Defects (Adversarial Review — 2026-05-22)

Six confirmed behavioral defects were found in the green suite (36/36 bats pass).
Each hypothesis was reproduced by running the script against temp fixtures.
Two hypotheses (F-7: "17 legacy tests wrong" and F-11: "detectors return non-zero") were **refuted** by live testing (git diff confirms all 17 legacy tests unchanged; bash `if` without `else` returns 0, detectors are NFR-3-compliant).

| ID | Defect | Severity | Status |
|----|--------|----------|--------|
| F-1 | `analysz*` typo in category map → British `analyse` mis-categorized as `other` (should be `typecheck`) | High | **FIX REQUIRED** |
| F-2 | Wrapper detection uses `-f` (exists) instead of design's `-x` (executable) → non-executable `gradlew`/`mvnw` yields empty `[]`, gates lost | High | **FIX REQUIRED** |
| F-3 | Deno discovery map copy-pasted from PHP (`phpstan*|psalm*` never valid for Deno); no `check`→typecheck mapping | High | **FIX REQUIRED** |
| F-4 | `deno.jsonc` detection triggers, but task discovery is `.json`-only — contradicts design "treat identically" | Medium | **FIX REQUIRED** |
| F-5 | Mix alias parser uses `sed /aliases/,/end(/p` + value-match (`"test"`) — never fires for real atom-keyed `mix.exs` | Medium | **FIX REQUIRED** |
| F-6 | `quality-commands.md` 4 stale rows contradict emitted commands (JVM: `./gradlew check`/`mvn verify`; Ruby: `rake build`; Elixir: `mix compile`) | Low | **FIX REQUIRED** |
| F-8 | `CLAUDE.md:74` still says "5.9.0" while manifests are 5.10.0 | Low | **FIX REQUIRED** |
| F-9 | NFR-5: `shellcheck` never enforced — only `bash -n` ran | Advisory | Documented |

AC-1.1 is superseded by F-1 (British `analyse` must map to `typecheck`).

## Next Steps
1. User approves requirements.
2. Run `/ralphharness:design` to specify detector function signatures, the exact filter patch, and category mappings.
3. `/ralphharness:tasks` to break into POC-first tasks (function refactor + main-guard → detectors → filter fix → bats fixtures → doc/version bump).
4. `/ralphharness:implement`.

<!-- Changed: added US-9/FR-13 (sourceable detect_ci_commands() + BASH_SOURCE main-guard, the real implement.md:215,221 consumer); added NFR-6 (accepted exact-tuple semantic-dup limitation); fixed AC-6.1 glob-marker pitfall (compgen/nullglob not [[ -f ]]); added monorepo + semantic-dedupe out-of-scope lines; expanded Verification Contract entry points/invariants/dependency map/escalate-if. Supersedes nothing — corrective pass from smart-ralph-review consensus (SR-001..006). -->

<!-- Post-implementation adversarial review 2026-05-22: 6 confirmed defects in green suite, 2 refuted. See Post-Implementation Defects table above. -->
