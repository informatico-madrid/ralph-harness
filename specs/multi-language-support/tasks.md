# Tasks: multi-language-support

> Workflow: POC-first (GREENFIELD-style for a CLI/shell refactor). Granularity: fine.
> One code file under change: `plugins/ralphharness/hooks/scripts/detect-ci-commands.sh`.
> Hard invariant verified at every checkpoint: the 17 legacy `tests/ci-autodetect.bats` tests pass.
> Test runner: `bats tests/ci-autodetect.bats`. Syntax gate: `bash -n` (enforced). `shellcheck` if installed (advisory).
> POC milestone: **task 1.5** (sourceable `detect_ci_commands()` + main-guard proven via `source` + 17 legacy green).

## Phase 1: Make It Work (POC)

Focus: prove the FR-13 refactor (sourceable function + BASH_SOURCE guard) works end-to-end and the CLI path is unchanged, then prove the detector-add pattern with one new detector. No new tests beyond the legacy smoke.

- [x] 1.1 Snapshot baseline: capture green legacy suite + script syntax
  - **Do**:
    1. Run `bats tests/ci-autodetect.bats` and confirm 17/17 pass (baseline before any edit).
    2. Run `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` (must be clean).
  - **Files**: none (read-only baseline)
  - **Done when**: 17/17 legacy tests pass and `bash -n` exits 0 BEFORE edits.
  - **Verify**: `bats tests/ci-autodetect.bats && bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && echo BASELINE_OK`
  - **Commit**: None
  - _Requirements: NFR-4, NFR-5_
  - _Design: Test Strategy_

- [x] 1.2 Wrap detect→filter→emit in `detect_ci_commands()` with local scope
  - **Do**:
    1. In `detect-ci-commands.sh`, define `detect_ci_commands() { local SPEC_PATH="$1"; local ENTRIES=() FILTERED=(); ... }` wrapping the existing run block (lines ~119-123), the write-time filter (~125-139), and the JSON-array emit block.
    2. Keep the 5 existing detectors (`detect_pyproject`/`detect_package_json`/`detect_makefile`/`detect_cargo`/`detect_go_mod`) as top-level functions, called from inside `detect_ci_commands` in the same deterministic order.
    3. End the function with `return 0` (never `exit`).
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: All detect/filter/emit logic lives inside `detect_ci_commands`; `ENTRIES`/`FILTERED`/`SPEC_PATH` are `local`.
  - **Verify**: `grep -q 'detect_ci_commands()' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && grep -q 'local ENTRIES' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && echo FN_OK`
  - **Commit**: `refactor(detect-ci): wrap pipeline in detect_ci_commands() function`
  - _Requirements: FR-13, AC-9.1_
  - _Design: detect_ci_commands(dir)_

- [x] 1.3 Add BASH_SOURCE main-guard; scope `set -euo pipefail` to direct execution
  - **Do**:
    1. Move `set -euo pipefail` from top-level (line 2) into a `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` main-guard.
    2. Inside the guard: keep `FORCE=0`, the arg-parse `while/case` (`--force`, `-*` usage error, positional `SPEC_PATH`), the empty/`-d` validation with `exit 1`, then call `detect_ci_commands "$SPEC_PATH"`.
    3. Ensure NOTHING outside the guard parses args, exits, or prints.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: CLI body (arg-parse, validate, invoke) runs only when executed directly; sourcing runs nothing.
  - **Verify**: `grep -q 'BASH_SOURCE\[0\]' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && ! grep -qE '^set -euo pipefail' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && echo GUARD_OK`
  - **Commit**: `refactor(detect-ci): gate CLI body behind BASH_SOURCE main-guard`
  - _Requirements: FR-13, AC-9.2, AC-9.3_
  - _Design: BASH_SOURCE main-guard + CLI block_

- [x] 1.4 [VERIFY] Quality checkpoint: legacy tests + syntax after refactor
  - **Do**: Run `bash -n` and the full legacy bats suite to prove the refactor is behavior-preserving.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: `bash -n` clean and 17/17 legacy tests pass unchanged.
  - **Commit**: `fix(detect-ci): restore legacy parity after refactor` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5, AC-9.5_

- [x] 1.5 POC milestone: prove sourcing works end-to-end (function reachable, CLI unchanged)
  - **Do**:
    1. In a sub-shell, `source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` with NO args; confirm exit `$?` == 0, no stdout, shell not exited.
    2. After sourcing, call `detect_ci_commands "<tmp fixture dir with package.json>"`; confirm a valid JSON array is printed via `jq -e .`.
    3. Confirm CLI path still works: `bash detect-ci-commands.sh "<tmp dir>"` emits the same JSON.
    4. Mirror the real call site `commands/implement.md:221` shape: `cmds=$(source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && detect_ci_commands "$PWD")` and validate JSON.
  - **Files**: none (verification only; uses temp fixtures)
  - **Done when**: Sourcing has zero side effects AND the sourced `detect_ci_commands "$dir"` emits valid JSON AND the CLI path is unchanged — the implement.md:221 consumer is reachable.
  - **Verify**: `tmp=$(mktemp -d); echo '{"scripts":{}}' > "$tmp/package.json"; out=$(bash -c 'source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh; echo "SRC_RC=$?"; detect_ci_commands "'"$tmp"'"'); echo "$out" | grep -q SRC_RC=0 && echo "$out" | tail -n1 | jq -e . >/dev/null && echo POC_MILESTONE_OK; rm -rf "$tmp"`
  - **Commit**: `feat(detect-ci): expose sourceable detect_ci_commands (POC milestone)`
  - _Requirements: FR-13, AC-9.1, AC-9.3, AC-9.4_
  - _Design: Data Flow_

- [x] 1.6 Prove detector-add pattern: implement `detect_gemfile`
  - **Do**:
    1. Add top-level `detect_gemfile() { local base="$1"; [[ -f "$base/Gemfile" ]] || return 0; ENTRIES+=('{"command":"bundle exec rspec","category":"test"}'); ENTRIES+=('{"command":"bundle exec rubocop","category":"lint"}'); }`.
    2. Wire `detect_gemfile "$SPEC_PATH"` into `detect_ci_commands` in deterministic order (after the existing 5).
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: A dir with `Gemfile` emits `bundle exec rspec` (test) and `bundle exec rubocop` (lint); first token `bundle`.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/Gemfile"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/bundle"; chmod +x "$sb/bundle"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="bundle exec rspec" and .category=="test")]|length==1' >/dev/null && echo GEMFILE_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_gemfile (Ruby) detector`
  - _Requirements: FR-2, AC-2.1, AC-2.2, AC-2.3_
  - _Design: 6 new detectors_

- [x] 1.7 [VERIFY] Quality checkpoint: syntax + legacy + new detector
  - **Do**: Run `bash -n` and full legacy bats; confirm Gemfile detector works inline.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: `bash -n` clean, 17/17 legacy pass, Gemfile detector proven (1.6).
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5_

- [x] 1.8 POC Checkpoint: full pipeline demonstrable
  - **Do**: Run the sourced consumer path against a multi-marker temp dir (Gemfile + package.json) and confirm both ecosystems appear in one valid JSON array.
  - **Done when**: Sourced `detect_ci_commands` emits a single valid JSON array containing both Ruby and Node entries — feature demonstrably works end-to-end.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/Gemfile"; echo '{"scripts":{}}' > "$tmp/package.json"; sb=$(mktemp -d); for b in bundle npm; do printf '#!/bin/sh\n' > "$sb/$b"; chmod +x "$sb/$b"; done; PATH="$sb:$PATH" bash -c 'source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh; detect_ci_commands "'"$tmp"'"' | jq -e 'length>=1' >/dev/null && echo POC_DONE; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): complete POC (sourceable multi-ecosystem detection)`
  - _Requirements: FR-13, FR-2_

## Phase 2: Refactoring (remaining detectors + filter patch)

Focus: add the remaining 6 detectors and the `./`-token filter patch with honest categories. No new tests yet (Phase 3).

- [x] 2.1 Add `detect_composer` (PHP scripts-discovery + fallback)
  - **Do**:
    1. Add `detect_composer() { local base="$1"; [[ -f "$base/composer.json" ]] || return 0; ... }`.
    2. If `command -v jq` and `composer.json` has `.scripts`: emit `composer run <name>` per key, categorized by name (`test*`→test; `lint*|cs*|fix*`→lint; `analy[sz]e*|phpstan*|psalm*`→typecheck; `build*`→build; else→other) — mirror `detect_package_json`.
    3. Fallback (no scripts / no jq): emit `composer test` (test) only. Never hardcode `vendor/bin/*`. First token `composer`.
    4. Wire into `detect_ci_commands` after `detect_gemfile`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: scripts → `composer run <name>` categorized; no scripts → `composer test`; absent → nothing.
  - **Verify**: `tmp=$(mktemp -d); printf '{"scripts":{"test":"phpunit","lint":"phpcs","analyze":"phpstan","build":"box"}}' > "$tmp/composer.json"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/composer"; chmod +x "$sb/composer"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="composer run analyze" and .category=="typecheck")]|length==1' >/dev/null && echo COMPOSER_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_composer (PHP) detector`
  - _Requirements: FR-1, AC-1.1, AC-1.2, AC-1.3, AC-1.4_
  - _Design: 6 new detectors_

- [x] 2.2 Add `detect_gradle` (both DSLs, wrapper-aware)
  - **Do**:
    1. Add `detect_gradle() { local base="$1"; [[ -f "$base/build.gradle" || -f "$base/build.gradle.kts" ]] || return 0; local W; if [[ -x "$base/gradlew" ]]; then W="./gradlew"; else W="gradle"; fi; ENTRIES+=("{\"command\":\"$W test\",\"category\":\"test\"}"); ENTRIES+=("{\"command\":\"$W build\",\"category\":\"build\"}"); }`.
    2. NO `check`-as-typecheck (AC-3.4). Wire into `detect_ci_commands`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: `build.gradle` OR `build.gradle.kts` → `<W> test`/`<W> build`; no typecheck entry.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/build.gradle.kts"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/gradle"; chmod +x "$sb/gradle"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '([.[]|select(.command=="gradle test")]|length==1) and ([.[]|select(.category=="typecheck")]|length==0)' >/dev/null && echo GRADLE_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_gradle (Groovy+Kotlin DSL) detector`
  - _Requirements: FR-3, AC-3.1, AC-3.4_
  - _Design: 6 new detectors_

- [x] 2.3 Add `detect_maven` (wrapper-aware, mvn package build)
  - **Do**:
    1. Add `detect_maven() { local base="$1"; [[ -f "$base/pom.xml" ]] || return 0; local M; if [[ -x "$base/mvnw" ]]; then M="./mvnw"; else M="mvn"; fi; ENTRIES+=("{\"command\":\"$M test\",\"category\":\"test\"}"); ENTRIES+=("{\"command\":\"$M package\",\"category\":\"build\"}"); }`.
    2. Independent of Gradle. Wire into `detect_ci_commands`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: `pom.xml` → `<M> test`/`<M> package`; Gradle+Maven coexist → both sets.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/pom.xml"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/mvn"; chmod +x "$sb/mvn"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="mvn package" and .category=="build")]|length==1' >/dev/null && echo MAVEN_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_maven detector`
  - _Requirements: FR-3, AC-3.2, AC-3.3_
  - _Design: 6 new detectors_

- [x] 2.4 [VERIFY] Quality checkpoint: syntax + legacy after PHP/JVM detectors
  - **Do**: Run `bash -n` and full legacy bats.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: `bash -n` clean, 17/17 legacy pass.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5_

- [x] 2.5 Add `detect_mix` (Elixir aliases grep-scan + canonical fallback)
  - **Do**:
    1. Add `detect_mix() { local base="$1"; [[ -f "$base/mix.exs" ]] || return 0; ... }`.
    2. Best-effort grep-scan `mix.exs` for alias names via `grep -oE` of known names (test/lint/credo/dialyzer/format) inside the aliases block; emit `mix <alias>` for matches.
    3. If grep finds nothing/ambiguous → canonical fallback: `mix test` (test), `mix credo` (lint), `mix dialyzer` (typecheck), `mix format --check-formatted` (lint). First token `mix`.
    4. Wire into `detect_ci_commands`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: `mix.exs` without aliases → 4 canonical commands with honest categories; first token `mix`.
  - **Verify**: `tmp=$(mktemp -d); printf 'defmodule M.MixProject do\nend\n' > "$tmp/mix.exs"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/mix"; chmod +x "$sb/mix"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="mix dialyzer" and .category=="typecheck")]|length==1' >/dev/null && echo MIX_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_mix (Elixir) detector`
  - _Requirements: FR-4, AC-4.1, AC-4.2, AC-4.3, AC-4.4_
  - _Design: 6 new detectors_

- [x] 2.6 Add `detect_deno` (tasks-discovery + fallback, .json/.jsonc)
  - **Do**:
    1. Add `detect_deno() { local base="$1"; [[ -f "$base/deno.json" || -f "$base/deno.jsonc" ]] || return 0; ... }`.
    2. If `command -v jq` and `.tasks` present (on `deno.json`): emit `deno task <name>` per key, name-pattern categorized (same map as composer).
    3. Fallback (no tasks / .jsonc / no jq): `deno test` (test), `deno lint` (lint), `deno check` (typecheck), `deno fmt --check` (lint). First token `deno`.
    4. Wire into `detect_ci_commands`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: tasks → `deno task <name>` categorized; no-tasks/.jsonc → 4 canonical; absent → nothing.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/deno.jsonc"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/deno"; chmod +x "$sb/deno"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="deno fmt --check" and .category=="lint")]|length==1' >/dev/null && echo DENO_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_deno detector`
  - _Requirements: FR-5, AC-5.1, AC-5.2, AC-5.3, AC-5.4_
  - _Design: 6 new detectors_

- [x] 2.7 Add `detect_dotnet` (glob markers via compgen -G + global.json) - 15dbab7
  - **Do**:
    1. Add `detect_dotnet()` per design: `if compgen -G "$base/*.csproj" >/dev/null 2>&1 || compgen -G "$base/*.sln" >/dev/null 2>&1 || [[ -f "$base/global.json" ]]; then` emit `dotnet test` (test), `dotnet build` (build), `dotnet format --verify-no-changes` (lint); `fi; return 0`.
    2. CRITICAL: use `compgen -G` for globs (NOT `[[ -f "$base/*.csproj" ]]`). Wire into `detect_ci_commands`.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: any `*.csproj`/`*.sln`/`global.json` fires; emits 3 commands; absent → nothing.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/App.csproj"; sb=$(mktemp -d); printf '#!/bin/sh\n' > "$sb/dotnet"; chmod +x "$sb/dotnet"; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e '[.[]|select(.command=="dotnet format --verify-no-changes" and .category=="lint")]|length==1' >/dev/null && echo DOTNET_OK; rm -rf "$tmp" "$sb"`
  - **Commit**: `feat(detect-ci): add detect_dotnet (compgen glob markers) detector`
  - _Requirements: FR-6, AC-6.1, AC-6.2, AC-6.3, AC-6.4_
  - _Design: detect_dotnet marker guard_

- [x] 2.8 [VERIFY] Quality checkpoint: syntax + legacy after all 6 detectors
  - **Do**: Run `bash -n` and full legacy bats; confirm all detectors wired into `detect_ci_commands`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && grep -q 'detect_dotnet "\$SPEC_PATH"' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && echo CHECKPOINT_OK`
  - **Done when**: `bash -n` clean, 17/17 legacy pass, all 11 detectors wired.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: FR-8, NFR-4, NFR-5_

- [x] 2.9 Patch write-time filter for `./`-prefixed wrapper tokens
  - **Do**:
    1. In the filter loop inside `detect_ci_commands`, declare `local cmd bin keep` (all three — AC-9.3 hygiene).
    2. For first token `bin`: `if [[ "$bin" == ./* ]]; then [[ -x "$SPEC_PATH/$bin" ]] || keep=0; else command -v "$bin" >/dev/null 2>&1 || keep=0; fi`.
    3. Keep the non-`./` `command -v` path and the WARN message `[detect-ci-commands] WARN: skipping $cmd binary $bin not on PATH` verbatim.
  - **Files**: plugins/ralphharness/hooks/scripts/detect-ci-commands.sh
  - **Done when**: `./gradlew test` survives iff `-x "$SPEC_PATH/gradlew"`; non-`./` behavior unchanged; `cmd`/`bin`/`keep` all local.
  - **Verify**: `tmp=$(mktemp -d); touch "$tmp/build.gradle"; printf '#!/bin/sh\n' > "$tmp/gradlew"; chmod +x "$tmp/gradlew"; bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" 2>/dev/null | jq -e '[.[]|select(.command=="./gradlew test")]|length==1' >/dev/null && grep -q 'local cmd bin keep' plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && echo FILTER_OK; rm -rf "$tmp"`
  - **Commit**: `fix(detect-ci): resolve ./-prefixed wrapper tokens against SPEC_PATH`
  - _Requirements: FR-7, AC-7.1, AC-7.2, AC-9.3_
  - _Design: Write-time filter patch_

- [x] 2.10 [VERIFY] Quality checkpoint: syntax + legacy + categories enum
  - **Do**: Run `bash -n`, full legacy bats, and assert all emitted categories ∈ {lint,typecheck,test,build,other} across a multi-marker fixture.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && tmp=$(mktemp -d); touch "$tmp/Gemfile" "$tmp/pom.xml"; sb=$(mktemp -d); for b in bundle mvn; do printf '#!/bin/sh\n' > "$sb/$b"; chmod +x "$sb/$b"; done; PATH="$sb:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$tmp" | jq -e 'all(.category; .=="lint" or .=="typecheck" or .=="test" or .=="build" or .=="other")' >/dev/null && echo CHECKPOINT_OK; rm -rf "$tmp" "$sb"`
  - **Done when**: `bash -n` clean, 17/17 legacy pass, categories strictly within the enum.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-1, NFR-4, NFR-5_

## Phase 3: Testing

Focus: one bats `@test` per Test Coverage Table row + filter regression + source-no-side-effects. Tests live at repo-root `tests/ci-autodetect.bats`; extend `STUBBIN` loop with `composer bundle mix deno dotnet gradle mvn`; build markers inline in temp dirs. The 17 legacy tests stay unchanged.

> Phase 3 test tasks append serially to the single file `tests/ci-autodetect.bats` — they are logically independent but must NOT be run as concurrent file writers.

- [x] 3.1 Extend STUBBIN with 7 new stub bins
  - **Do**: In `setup()`, extend the existing `for bin in ...` loop to also create stubs for `composer bundle mix deno dotnet gradle mvn` in `STUBBIN`.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: All 7 new stub bins are created and executable in `STUBBIN`.
  - **Verify**: `grep -qE 'composer.*bundle.*mix.*deno.*dotnet.*gradle.*mvn' tests/ci-autodetect.bats && echo STUBS_OK`
  - **Commit**: `test(detect-ci): add 7 new stub binaries to STUBBIN`
  - _Requirements: FR-10_
  - _Design: Fixtures & Test Data_

- [x] 3.2 composer tests (scripts + no-scripts)
  - **Do**: Add 2 `@test`s — each `@test` description string MUST contain the keyword `composer` so the `-f composer` Verify filter matches them: (a) `composer.json` with `scripts:{test,lint,analyze,build}` → asserts `composer run test`(test), `composer run lint`(lint), `composer run analyze`(typecheck), `composer run build`(build); (b) `composer.json` with no scripts → `composer test`(test), and no `vendor/bin/*`.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: Both composer tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f composer --count) && [ "$cnt" -ge 2 ] && bats tests/ci-autodetect.bats -f composer && echo COMPOSER_TESTS_OK`
  - **Commit**: `test(detect-ci): add composer scripts + fallback tests`
  - _Requirements: FR-1, FR-10, AC-1.1, AC-1.2_

- [x] 3.3 gemfile + deno tests
  - **Do**: Add `@test`s — each `@test` description string MUST contain a keyword matched by the `-f 'gemfile|deno'` Verify filter (the gemfile test description must contain `gemfile`; the two deno test descriptions must contain `deno`): gemfile → `bundle exec rspec`(test)/`bundle exec rubocop`(lint); deno tasks-discovery (`deno.json` with `tasks`) → `deno task <name>` categorized; deno fallback (`deno.jsonc`) → `deno test`/`deno lint`/`deno check`(typecheck)/`deno fmt --check`(lint).
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: gemfile + both deno tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f 'gemfile|deno' --count) && [ "$cnt" -ge 3 ] && bats tests/ci-autodetect.bats -f 'gemfile|deno' && echo GEMFILE_DENO_OK`
  - **Commit**: `test(detect-ci): add gemfile + deno detector tests`
  - _Requirements: FR-2, FR-5, FR-10, AC-2.*, AC-5.*_

- [ ] 3.4 [VERIFY] Quality checkpoint: bats + syntax
  - **Do**: Run full bats suite and `bash -n`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: All tests (legacy + new) pass, `bash -n` clean.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5_

- [x] 3.5 gradle tests (build.gradle, .kts, wrapper)
  - **Do**: Add `@test`s — each `@test` description string MUST contain the keyword `gradle` so the `-f gradle` Verify filter matches them: `build.gradle` → `gradle test`/`gradle build`, no typecheck; `.kts` fires same; executable `./gradlew` fixture → `./gradlew test`/`./gradlew build` SURVIVE filter.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: All three gradle tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f gradle --count) && [ "$cnt" -ge 3 ] && bats tests/ci-autodetect.bats -f gradle && echo GRADLE_TESTS_OK`
  - **Commit**: `test(detect-ci): add gradle (DSL + wrapper) tests`
  - _Requirements: FR-3, FR-10, AC-3.1, AC-3.4, AC-3.5_

- [ ] 3.6 maven + coexist tests
  - **Do**: Add `@test`s — each `@test` description string MUST contain a keyword matched by the `-f 'maven|coexist'` Verify filter (the pom.xml and `./mvnw` test descriptions must contain `maven`; the Gradle+Maven test description must contain `coexist`): `pom.xml` → `mvn test`/`mvn package`; `./mvnw` fixture → wrapper analog survives; Gradle+Maven coexist → both command sets present.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: maven + coexist tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f 'maven|coexist' --count) && [ "$cnt" -ge 3 ] && bats tests/ci-autodetect.bats -f 'maven|coexist' && echo MAVEN_TESTS_OK`
  - **Commit**: `test(detect-ci): add maven + gradle/maven coexist tests`
  - _Requirements: FR-3, FR-10, AC-3.2, AC-3.3_

- [ ] 3.7 mix + dotnet tests
  - **Do**: Add `@test`s — each `@test` description string MUST contain a keyword matched by the `-f 'mix|dotnet'` Verify filter (the `mix.exs` fallback and alias test descriptions must contain `mix`; the `.csproj`/`.sln`/`global.json` test descriptions must contain `dotnet`): `mix.exs` fallback → `mix test`/`mix credo`/`mix dialyzer`(typecheck)/`mix format --check-formatted`(lint); mix with aliases → `mix <alias>` preferred; dotnet `.csproj` glob fires (NOT skipped) → 3 commands; `.sln` and `global.json` each fire independently.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: mix + dotnet tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f 'mix|dotnet' --count) && [ "$cnt" -ge 2 ] && bats tests/ci-autodetect.bats -f 'mix|dotnet' && echo MIX_DOTNET_OK`
  - **Commit**: `test(detect-ci): add mix + dotnet detector tests`
  - _Requirements: FR-4, FR-6, FR-10, AC-4.*, AC-6.*_

- [ ] 3.8 [VERIFY] Quality checkpoint: bats + syntax
  - **Do**: Run full bats suite and `bash -n`.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: All tests pass, `bash -n` clean.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5_

- [ ] 3.9 `./`-filter regression test (present vs absent gradlew)
  - **Do**: Add a `@test` whose description string MUST contain a keyword matched by the `-f 'filter|gradlew|wrapper'` Verify filter (use `filter`, `gradlew`, or `wrapper` in the description) asserting `./gradlew test` SURVIVES when an executable `$base/gradlew` exists, and is DROPPED (with WARN on stderr) when absent — using a `chmod +x` toggle fixture.
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: Regression test exists and passes both branches.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f 'filter|gradlew|wrapper' --count) && [ "$cnt" -ge 1 ] && bats tests/ci-autodetect.bats -f 'filter|gradlew|wrapper' && echo FILTER_REGRESSION_OK`
  - **Commit**: `test(detect-ci): add ./-filter wrapper regression test`
  - _Requirements: FR-7, AC-7.1, AC-7.4_

- [ ] 3.10 source-no-side-effects + sourced-call integration tests
  - **Do**: Add 2 integration `@test`s — each `@test` description string MUST contain a keyword matched by the `-f 'source|sourced'` Verify filter (use `source` or `sourced` in both descriptions): (a) `source detect-ci-commands.sh` in a sub-shell with no args → `$?`==0, no stdout, shell not exited, `set -e` not active afterward; (b) after source, `detect_ci_commands "$dir"` emits valid JSON array for a fixture (mirrors implement.md:221).
  - **Files**: tests/ci-autodetect.bats
  - **Done when**: Both integration tests exist and pass.
  - **Verify**: `cnt=$(bats tests/ci-autodetect.bats -f 'source|sourced' --count) && [ "$cnt" -ge 2 ] && bats tests/ci-autodetect.bats -f 'source|sourced' && echo SOURCE_TESTS_OK`
  - **Commit**: `test(detect-ci): add source-no-side-effects + sourced-call tests`
  - _Requirements: FR-13, AC-9.1, AC-9.3, AC-9.4_

- [ ] 3.11 [VERIFY] Quality checkpoint: full bats + syntax + legacy invariant
  - **Do**: Run full bats; confirm the original 17 legacy tests still pass alongside the new ones; `bash -n` clean.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo CHECKPOINT_OK`
  - **Done when**: All tests pass (legacy 17 unchanged + new), `bash -n` clean.
  - **Commit**: `chore(detect-ci): pass quality checkpoint` (only if fixes needed)
  - _Requirements: NFR-4, NFR-5, AC-7.3, AC-9.5_

## Phase 4: Quality Gates

- [ ] 4.1 Add PHP + C#/.NET doc rows
  - **Do**: In `references/quality-commands.md` config table (~lines 64-72), add a PHP (`composer.json`) row and a C#/.NET (`*.csproj`/`*.sln`) row. Do NOT duplicate the existing Ruby/JVM/Elixir/Deno rows.
  - **Files**: plugins/ralphharness/references/quality-commands.md
  - **Done when**: PHP and C#/.NET rows present; no duplicate ecosystem rows.
  - **Verify**: `grep -qi 'composer.json' plugins/ralphharness/references/quality-commands.md && grep -qiE 'csproj|\.sln' plugins/ralphharness/references/quality-commands.md && echo DOC_OK`
  - **Commit**: `docs(quality-commands): add PHP + C#/.NET ecosystem rows`
  - _Requirements: FR-11, AC-8.1, AC-8.2_

- [ ] 4.2 Version bump 5.9.5 → 5.10.0 in both manifests
  - **Do**: Bump `version` to `5.10.0` in `plugins/ralphharness/.claude-plugin/plugin.json` AND the ralphharness entry in `.claude-plugin/marketplace.json`.
  - **Files**: plugins/ralphharness/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - **Done when**: Both manifests show 5.10.0 for ralphharness.
  - **Verify**: `grep -q '"version": "5.10.0"' plugins/ralphharness/.claude-plugin/plugin.json && jq -e '.plugins[]|select(.name=="ralphharness").version=="5.10.0"' .claude-plugin/marketplace.json >/dev/null && echo VERSION_OK`
  - **Commit**: `chore(release): bump ralphharness 5.9.5 -> 5.10.0`
  - _Requirements: FR-12, AC-8.3_

- [ ] 4.3 Local quality gate: bash -n + shellcheck(if present) + full bats
  - **Do**:
    1. Run `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` (enforced gate).
    2. Run `shellcheck` if available; if not installed, note manual/CI-side check (do NOT block on absence).
    3. Run full `bats tests/ci-autodetect.bats`.
  - **Files**: none (verification)
  - **Done when**: `bash -n` clean, all bats pass; shellcheck clean if installed.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && { command -v shellcheck >/dev/null 2>&1 && shellcheck plugins/ralphharness/hooks/scripts/detect-ci-commands.sh || echo "shellcheck not installed - CI-side check"; } && bats tests/ci-autodetect.bats && echo LOCAL_CI_OK`
  - **Commit**: `fix(detect-ci): address lint/syntax issues` (only if fixes needed)
  - _Requirements: NFR-5_

- [ ] VE1 [VERIFY] E2E startup: build temp fixtures + PATH stub bins
  - **Do**:
    1. Create a temp fixture root: `VE_TMP=$(mktemp -d); echo "$VE_TMP" > /tmp/ve-mls.txt`.
    2. Create a STUBBIN dir with stub binaries: `VE_STUB=$(mktemp -d); echo "$VE_STUB" >> /tmp/ve-mls.txt; for b in composer bundle mix deno dotnet gradle mvn npm; do printf '#!/bin/sh\n' > "$VE_STUB/$b"; chmod +x "$VE_STUB/$b"; done`.
    3. Populate a multi-marker fixture dir: `touch "$VE_TMP/Gemfile" "$VE_TMP/pom.xml"; echo '{"scripts":{}}' > "$VE_TMP/composer.json"`.
  - **Files**: none (temp fixtures; no long-running process — CLI is the e2e surface)
  - **Done when**: Fixture dir + stub bins exist; PID/path file `/tmp/ve-mls.txt` written.
  - **Verify**: `test -s /tmp/ve-mls.txt && head -1 /tmp/ve-mls.txt | xargs test -d && echo VE1_PASS`
  - **Commit**: None

- [ ] VE2 [VERIFY] E2E check: run bats suite + detect against real fixtures (CLI + sourced)
  - **Do**:
    1. Run the full bats e2e suite: `bats tests/ci-autodetect.bats`.
    2. CLI path: `VE_TMP=$(head -1 /tmp/ve-mls.txt); VE_STUB=$(sed -n 2p /tmp/ve-mls.txt); PATH="$VE_STUB:$PATH" bash plugins/ralphharness/hooks/scripts/detect-ci-commands.sh "$VE_TMP"` → assert expected tuples via jq (`bundle exec rspec`/test, `mvn package`/build, `composer test`/test).
    3. Sourced path (implement.md:221 shape): `PATH="$VE_STUB:$PATH" bash -c 'source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh; detect_ci_commands "'"$VE_TMP"'"'` → valid JSON array.
  - **Files**: none
  - **Done when**: bats green AND both CLI and sourced invocations emit the expected `{command,category}` tuples against real fixtures.
  - **Verify**: `bats tests/ci-autodetect.bats && VE_TMP=$(head -1 /tmp/ve-mls.txt); VE_STUB=$(sed -n 2p /tmp/ve-mls.txt); PATH="$VE_STUB:$PATH" bash -c 'source plugins/ralphharness/hooks/scripts/detect-ci-commands.sh; detect_ci_commands "'"$VE_TMP"'"' | jq -e '([.[]|select(.command=="mvn package" and .category=="build")]|length==1) and ([.[]|select(.command=="bundle exec rspec")]|length==1)' >/dev/null && echo VE2_PASS`
  - **Commit**: None

- [ ] VE3 [VERIFY] E2E cleanup: remove temp fixtures + stub bins
  - **Do**:
    1. Remove fixture dirs: `while read -r d; do rm -rf "$d"; done < /tmp/ve-mls.txt`.
    2. Remove the tracking file: `rm -f /tmp/ve-mls.txt`.
  - **Files**: none
  - **Done when**: Temp fixture dirs and tracking file removed.
  - **Verify**: `! test -f /tmp/ve-mls.txt && echo VE3_PASS`
  - **Commit**: None

- [ ] V4 [VERIFY] Full local CI: bash -n + bats + version/doc consistency
  - **Do**: Run the complete local gate: `bash -n`, full bats, version assertions, doc-row assertions.
  - **Files**: none
  - **Done when**: All checks pass — script syntax clean, all tests green, version 5.10.0 in both manifests, PHP+C# doc rows present.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && grep -q '"version": "5.10.0"' plugins/ralphharness/.claude-plugin/plugin.json && grep -qi 'composer.json' plugins/ralphharness/references/quality-commands.md && echo FULL_CI_OK`
  - **Commit**: `chore(detect-ci): pass local CI` (only if fixes needed)
  - _Requirements: NFR-1, NFR-4, NFR-5, FR-11, FR-12_

- [ ] V5 [VERIFY] Phase 4 exit gate
  - **Do**: Confirm Phase 4 quality gate met: doc rows, version bump, full bats, `bash -n` all green before advancing to PR.
  - **Verify**: `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh && bats tests/ci-autodetect.bats && echo PHASE4_GATE_OK`
  - **Done when**: All Phase 4 gates satisfied.
  - **Commit**: None

## Phase 5: PR Lifecycle

- [ ] 5.1 Create PR and verify CI
  - **Do**:
    1. Verify current branch is a feature branch: `git branch --show-current` (if on `main`, STOP and alert — branch should be set at startup).
    2. Push branch: `git push -u origin <branch-name>`.
    3. Create PR: `gh pr create --title "feat(detect-ci): multi-language CI detection (PHP/Ruby/JVM/Elixir/Deno/.NET) + sourceable refactor" --body "<summary>"`.
  - **Files**: none
  - **Done when**: PR created; CI checks queued.
  - **Verify**: `gh pr view --json url -q .url && echo PR_OK`
  - **Commit**: None

- [ ] 5.2 Monitor CI and resolve failures
  - **Do**:
    1. Watch CI: `gh pr checks --watch`.
    2. If failing: read `gh pr checks`, fix locally, `git push`, re-verify.
  - **Files**: as needed for fixes
  - **Done when**: All CI checks green.
  - **Verify**: `gh pr checks | grep -qiv fail && echo CI_GREEN`
  - **Commit**: `fix(detect-ci): resolve CI failures` (only if fixes needed)

- [ ] V6 [VERIFY] AC checklist
  - **Do**: Read requirements.md and programmatically verify each AC. For each ecosystem run the detector against a temp fixture and assert the expected tuples; assert `./`-filter behavior, source-no-side-effects, version bump, doc rows, and 17-legacy-pass invariant.
  - **Files**: none
  - **Done when**: All AC-1.* through AC-9.* confirmed met via automated checks.
  - **Verify**: `bats tests/ci-autodetect.bats && grep -q '"version": "5.10.0"' plugins/ralphharness/.claude-plugin/plugin.json && echo AC_CHECKLIST_OK`
  - **Commit**: None

- [ ] V7 [VERIFY] Phase 5 exit gate
  - **Do**: Confirm PR created, CI green, all ACs satisfied.
  - **Verify**: `gh pr checks | grep -qiv fail && echo PHASE5_GATE_OK`
  - **Done when**: PR ready for review with all completion criteria met.
  - **Commit**: None

## Notes

- **POC milestone**: task 1.5 — sourceable `detect_ci_commands()` + BASH_SOURCE main-guard proven via `source` (zero side effects) + 17 legacy bats green. Until this works, no detector reaches the loop (implement.md:215,221). Sequenced FIRST.
- **Hard invariant**: the 17 legacy `tests/ci-autodetect.bats` tests pass — verified at checkpoints 1.4, 1.7, 2.4, 2.8, 2.10, 3.4, 3.8, 3.11, V4, V5.
- **POC shortcuts**: Phase 1 adds only `detect_gemfile` to prove the pattern; remaining 6 detectors + filter patch deferred to Phase 2; all new bats tests deferred to Phase 3.
- **shellcheck**: NOT installed locally — `bash -n` is the enforced syntax gate; shellcheck runs only if available (advisory / CI-side), never blocks (design Unresolved Question).
- **No new source files**: only `detect-ci-commands.sh` (modify), `tests/ci-autodetect.bats` (modify), `quality-commands.md` (doc), and the two manifests (version). Fixtures built inline in temp dirs.
- **Categories**: strictly ∈ {lint, typecheck, test, build, other} (NFR-1) — verified at checkpoint 2.10.
- **NFR-6 (accepted)**: exact-tuple dedupe will not collapse semantic duplicates (e.g. `composer test` vs scraped `phpunit`); dedupe contract is a non-goal and untouched.
