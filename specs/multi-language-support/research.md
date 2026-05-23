---
spec: multi-language-support
phase: research
created: 2026-05-22T15:52:11+0000
---

# Research: multi-language-support

## Executive Summary

RalphHarness's CI auto-detection (`detect-ci-commands.sh`) currently covers Python, Node.js,
Rust, Go, and Makefile. The goal is to extend it to the most-used languages — PHP, Ruby,
Java/Kotlin, Elixir, Deno (and arguably C#/.NET). **The existing `plans/multi-language-support-plan.md`
is directionally right but technically deficient**: its proposed detectors emit commands whose
first token is a project-relative path (`vendor/bin/phpunit`, `./gradlew test`), which the
script's own write-time `command -v` filter (lines 125–139) **silently drops** — so the plan as
written would add detectors that produce empty output on real projects. This research grounds the
work in the actual code, corrects the plan's false claims, and recommends a PATH-binary-first /
scripts-discovery detection strategy that matches the existing `detect_package_json` pattern.
Feasibility is high; the real work is the detection strategy and tests, not the line count.

## External Research

### Best Practices
- **PHP / Composer**: Composer temporarily prepends its `bin-dir` (`vendor/bin`) to `PATH` when
  running scripts, so the portable invocation is `composer test` / `composer run <script>` rather
  than a hardcoded `vendor/bin/phpunit`. The community convention is to define `scripts` in
  `composer.json` (`test`, `lint`, `analyze`, `fix-style`). Source: [Composer scripts docs](https://getcomposer.org/doc/articles/scripts.md), [Peter Fisher — composer scripts](https://www.peterfisher.me.uk/blog/php-composer-scripts/).
- **Deno**: single `deno` binary on PATH; canonical commands `deno test`, `deno lint`,
  `deno check`, `deno fmt --check`. `deno.json` can declare `tasks` → `deno task <name>`.
  `--permit-no-files` avoids CI errors when no files match (Deno 2.2+). Source: [deno lint](https://docs.deno.com/runtime/reference/cli/lint/), [deno check](https://docs.deno.com/runtime/reference/cli/check/), [Deno CI guide](https://docs.deno.com/runtime/reference/continuous_integration/).
- **Java/Kotlin**: the Gradle Wrapper (`./gradlew`) is the *recommended* entry point for
  reproducible CI builds; Kotlin DSL `build.gradle.kts` is the default since Gradle 8.0, so
  detection must check `build.gradle` **and** `build.gradle.kts`. Maven has an equivalent wrapper
  `./mvnw`. Source: [Gradle Wrapper docs](https://docs.gradle.org/current/userguide/gradle_wrapper.html), [Kotlin Gradle config](https://kotlinlang.org/docs/gradle-configure-project.html).
- **Elixir / Mix**: `mix` is on PATH; canonical `mix test`, `mix credo` (often `--strict`),
  `mix format --check-formatted`, `mix dialyzer`. Projects commonly define a `lint` alias in
  `mix.exs`. Source: [Mix introduction](https://hexdocs.pm/elixir/introduction-to-mix.html), [Credo](https://github.com/rrrene/credo), [Mastering Elixir CI](https://curiosum.com/blog/mastering-elixir-ci-pipeline).
- **Ruby / Bundler**: `bundle` is on PATH; canonical `bundle exec rspec`, `bundle exec rubocop`,
  `bundle exec rake`. Test command may be `rspec` or `rake test`/`rake spec` depending on project.

### Prior Art
- The repo's **own** `detect_package_json` (lines 45–73) is the gold-standard pattern: it does NOT
  hardcode tools — it reads `package.json` `scripts` keys, categorizes by name, and emits
  `<pkgmgr> run <script>` where `<pkgmgr>` is a PATH binary. PHP (`composer.json` `scripts`),
  Deno (`deno.json` `tasks`), and Elixir/Ruby (custom aliases/rake tasks) should follow this same
  scripts-discovery model rather than the plan's hardcoded-tool model.
- Comparable ecosystem auto-detectors (asdf `.tool-versions`, mise, OpenHands skill detection) are
  all **marker-based and stateless** — same philosophy as `detect-ci-commands.sh`. No AST parsing.

### Pitfalls to Avoid
- **The `command -v` write-time filter (CRITICAL).** Lines 125–139 extract the first token of each
  command and drop the entry if `command -v <token>` fails. For `./gradlew test` the token is
  `./gradlew`, which `command -v` resolves **against the script's CWD, not SPEC_PATH** — confirmed
  failing in this environment. The plan's `vendor/bin/phpunit` and `./gradlew test` entries are
  therefore dead on arrival. Any detector emitting wrapper/relative paths must either (a) emit a
  PATH binary (`composer`, `bundle`, `mix`, `deno`, `gradle`, `mvn`), or (b) the filter must be
  taught to resolve `./`-prefixed tokens against `SPEC_PATH`.
- **Aggregate-command miscategorization.** `./gradlew check` and `mvn verify` run tests + static
  analysis together; tagging them purely `typecheck` (as the plan does) is misleading and will
  double-run tests in Phase 4. Prefer `gradle test`→test, `gradle build`→build; avoid claiming a
  pure typecheck category for JVM aggregates.
- **Hardcoding tools that aren't installed.** Emitting `vendor/bin/phpstan` when the project uses
  Psalm, or `mix credo` when Credo isn't a dep, produces commands that fail at runtime. Scripts/
  alias discovery avoids guessing.
- **Groovy-only Gradle detection.** Checking only `build.gradle` misses every modern Kotlin-DSL
  project (`build.gradle.kts`).

## Codebase Analysis

### Existing Patterns
- [detect-ci-commands.sh](plugins/ralphharness/hooks/scripts/detect-ci-commands.sh): 5 detectors,
  an `ENTRIES` accumulator of JSON objects, a write-time `command -v` filter, and array output.
  Each detector is a `detect_<marker>()` function guarded by `[[ -f "$base/<marker>" ]] || return 0`.
  Adding a detector = define function + add one call line at lines 119–123.
- [detect_package_json](plugins/ralphharness/hooks/scripts/detect-ci-commands.sh#L45-L73): the
  scripts-discovery reference implementation (lockfile → pkgmgr, jq parse, name-pattern category).
- [references/quality-commands.md](plugins/ralphharness/references/quality-commands.md): guidance
  doc for the spec-executor/research-analyst (a *different* consumer than the script). Its config
  table (lines 64–72) **already lists Ruby, Java/Kotlin, Elixir, and Deno** — only **PHP is
  missing**. The plan's claim that 6 rows must be added is false; only 1 is.
- [tests/ci-autodetect.bats](tests/ci-autodetect.bats): 17 tests at **repo root** (not
  `plugins/.../tests/`, as the plan implies). Includes `command -v filter drops missing binaries
  at write time` — directly relevant. New detectors need fixtures here.

### Dependencies
- Runtime: `bash`, `jq` (already required for `detect_package_json`), standard coreutils. No new
  language toolchains needed in the plugin — detection only emits command strings.
- Test: `bats` (already used). New `.bats` fixtures create marker files in temp dirs.

### Constraints
- `set -euo pipefail` at the top — detectors must `return 0` (not non-zero) when their marker is
  absent, or the script aborts. The plan's `[[ -f ... ]] || return 0` is correct here.
- The script does not `cd` into `SPEC_PATH`; all paths are resolved relative to the caller's CWD.
  This is the root cause of the wrapper-path filter problem.
- Output contract is a JSON array of `{command, category}` consumed into `ciSnapshot` — categories
  must stay in the known set (`lint`, `typecheck`, `test`, `build`, `other`).

## Related Specs

| Spec | Relevance | Relationship | May Need Update |
|------|-----------|--------------|-----------------|
| signal-log-and-ci-autodetect | High | Original spec that built `detect-ci-commands.sh` + the 17 bats tests | No (extend, don't modify) |
| multi-language-support (this) | High | Extends the autodetect matrix | — |

### Coordination Notes
This spec extends, rather than alters, the `signal-log-and-ci-autodetect` design. The output
contract (`{command, category}` tuples → `ciSnapshot`), the `command -v` filter, and the dedupe
logic must all be preserved. The cleanest seam is: add detectors + (if we adopt option-b) a small,
backward-compatible tweak to the filter so it resolves `./`-relative tokens against `SPEC_PATH`.

## Feasibility Assessment

| Aspect | Assessment | Notes |
|--------|------------|-------|
| Technical Viability | High | Pure extension of an extensible, well-tested pattern |
| Effort Estimate | S–M | Larger than the plan's "~65 LOC" if we do scripts-discovery + fix the filter + tests; still small |
| Risk Level | Medium | The `command -v` filter interaction is a real correctness trap; aggregate-command categorization needs care |

## Recommendations for Requirements

1. **Adopt the scripts/tasks-discovery model where the ecosystem has one** (PHP `composer.json`
   `scripts` → `composer run <s>`; Deno `deno.json` `tasks` → `deno task <t>`), mirroring
   `detect_package_json`. Fall back to canonical hardcoded commands only when no scripts/tasks/
   aliases exist.
2. **Emit PATH-resolvable first tokens** for every new detector: `composer`, `bundle`, `mix`,
   `deno`. For JVM, prefer the wrapper but resolve the filter issue first (see #3).
3. **Decide the wrapper/relative-path question explicitly** in design: either (a) emit system
   `gradle`/`mvn` (simple, but loses wrapper reproducibility) or (b) extend the `command -v` filter
   to test `-x "$SPEC_PATH/$bin"` for `./`-prefixed tokens (preserves `./gradlew`/`./mvnw`). Option
   (b) is recommended and also future-proofs any wrapper-style command.
4. **Detect both Gradle DSLs**: `build.gradle` OR `build.gradle.kts`; same for `settings.gradle{.kts}`.
   Handle Maven `pom.xml` independently (a project can have both).
5. **Add only PHP to `references/quality-commands.md`** (the other four rows already exist); fix the
   plan's incorrect "6 rows" assumption. Optionally reconcile the doc's commands with what the
   script now emits to avoid drift.
6. **Categorize honestly**: `test`→test, `lint/format`→lint, dedicated static analysis
   (`phpstan`/`mypy`/`dialyzer`/`deno check`)→typecheck, `build/compile/package`→build. Avoid
   tagging JVM aggregates (`gradle check`, `mvn verify`) as pure typecheck.
7. **Extend `tests/ci-autodetect.bats`** with a matrix fixture per new marker (Gemfile, build.gradle,
   build.gradle.kts, pom.xml, mix.exs, deno.json, composer.json), plus a regression test asserting
   wrapper/relative-path commands survive the filter (or are correctly transformed).
8. **Plugin version bump is mandatory** (CLAUDE.md rule) in both `plugin.json` and `marketplace.json`
   — this is a feature ⇒ minor bump.

## Resolved Decisions (2026-05-22)

1. **Scope** = the 5 plan languages **+ C#/.NET**: PHP (`composer.json`), Ruby (`Gemfile`),
   Java/Kotlin (`build.gradle`/`build.gradle.kts`/`pom.xml`), Elixir (`mix.exs`), Deno (`deno.json`),
   and C#/.NET (`*.csproj`/`*.sln`/`global.json` → `dotnet test`/`dotnet build`/`dotnet format`).
   C/C++ (CMake) is **out of scope** for this spec.
2. **`command -v` filter fix is IN this spec**: extend the filter so a `./`-prefixed first token is
   tested with `-x "$SPEC_PATH/$bin"`, preserving wrapper commands (`./gradlew`, `./mvnw`). Keep the
   change backward-compatible with the 17 existing tests.
3. **Detection precedence** = prefer discovered **scripts/tasks/aliases** (composer `scripts`,
   deno `tasks`, mix aliases, npm-style) when present; fall back to canonical hardcoded commands
   only when none are defined.

## Open Questions (remaining)

- Do we want `--check`/non-mutating variants enforced (e.g. `deno fmt --check`, `mix format
  --check-formatted`, `cargo fmt --check` already used) so detection never emits a formatter that
  rewrites files in CI? (Lean: yes — emit non-mutating forms for the `lint` category.)

## Quality Commands

> For verifying changes to **this plugin** (not user projects).

| Type | Command | Source |
|------|---------|--------|
| Test | `bats tests/ci-autodetect.bats` | repo-root bats suite for the detector |
| Test | `bats plugins/ralphharness/tests/` | broader plugin bats suite |
| Lint | `shellcheck plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` | shell static analysis |
| Syntax | `bash -n plugins/ralphharness/hooks/scripts/detect-ci-commands.sh` | parse check |

## Sources

- [Composer scripts](https://getcomposer.org/doc/articles/scripts.md) — bin-dir on PATH; `composer run <script>`
- [Peter Fisher — composer scripts](https://www.peterfisher.me.uk/blog/php-composer-scripts/) — test/lint/analyze conventions
- [deno lint](https://docs.deno.com/runtime/reference/cli/lint/), [deno check](https://docs.deno.com/runtime/reference/cli/check/), [Deno CI](https://docs.deno.com/runtime/reference/continuous_integration/)
- [Gradle Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html), [Gradle best practices](https://docs.gradle.org/current/userguide/best_practices_general.html), [Kotlin Gradle config](https://kotlinlang.org/docs/gradle-configure-project.html)
- [Mix introduction](https://hexdocs.pm/elixir/introduction-to-mix.html), [Credo](https://github.com/rrrene/credo), [Mastering Elixir CI](https://curiosum.com/blog/mastering-elixir-ci-pipeline)
- [detect-ci-commands.sh](plugins/ralphharness/hooks/scripts/detect-ci-commands.sh) — current 5-detector implementation + `command -v` filter
- [references/quality-commands.md](plugins/ralphharness/references/quality-commands.md) — already has Ruby/JVM/Elixir/Deno; missing PHP
- [tests/ci-autodetect.bats](tests/ci-autodetect.bats) — 17 existing tests (repo root)
- [plans/multi-language-support-plan.md](plans/multi-language-support-plan.md) — source plan (deficient; corrected above)
