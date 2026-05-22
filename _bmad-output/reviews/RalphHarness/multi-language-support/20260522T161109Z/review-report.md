# Smart-Ralph Review: multi-language-support (Phase: requirements)

**Reviewed**: 2026-05-22 · **Mode**: full · **Consensus**: majority · **apply_fixes**: false
**Artifacts**: `specs/multi-language-support/{research.md, requirements.md}` contrasted against real plugin code.

## Executive Summary

The requirements/research are **well-grounded for the detector internals** (categories,
filter fix, scripts-discovery, version bump all verified against real code). But the review found
**one HIGH architectural gap**: the requirements model `detect-ci-commands.sh` as a **CLI-only**
entry point, while its *actual runtime consumer* (`implement.md`) **sources** the script and calls a
**`detect_ci_commands()` function that does not exist**. Adding 6 inline detectors — as the spec
currently assumes — does **not** make them reachable by the real loop. Five secondary gaps confirmed.

## Findings

| # | Sev | Status | File | Finding |
|---|-----|--------|------|---------|
| SR-001 | **HIGH** | CONFIRMED (verified fact) | requirements.md (model) | Detector consumed via `source` + `detect_ci_commands()` **function call** in [implement.md:215,221](plugins/ralphharness/commands/implement.md#L215); that function/guard **does not exist**. Spec treats script as CLI-only ("the only runtime entry", "output contract unchanged") and misses this contract. |
| SR-002 | MEDIUM | CONFIRMED (verified fact) | detect-ci-commands.sh | No `BASH_SOURCE` main-guard. Sourcing runs the CLI body with `set -euo pipefail`, and a no-arg `exit 1` in a sourced file **aborts the parent orchestrator**. Adding detectors doesn't fix this; refactor is needed. |
| SR-004 | MEDIUM | CONFIRMED (4/4) | requirements.md | `discover-ci.sh` already emits canonical commands scraped from workflows/bats; merged + deduped by **exact `(command,category)` tuple** ([lib-signals.sh:38](plugins/ralphharness/hooks/scripts/lib-signals.sh#L38)). `composer test` vs `phpunit`/`composer run test` won't dedupe → **duplicate/overlapping gates**. Unaddressed. |
| SR-006 | MEDIUM | CONFIRMED (3/4) | requirements.md AC-6.1 | C#/.NET marker is a **glob** (`*.csproj`/`*.sln`). All existing detectors use `[[ -f "$base/<fixed>" ]]`; `[[ -f "$base/*.csproj" ]]` **does not glob** and silently fails. Pitfall unflagged for design/tasks (needs `compgen -G`/nullglob). `global.json` is fixed and fine. |
| SR-005 | LOW | CONFIRMED (4/4) | requirements.md | Dependency map omits `discover-ci.sh` — the **co-producer** of `ciCommands` merged with detector output. Accuracy gap. |
| SR-003 | LOW | DISPUTED→CONFIRMED (doc-only) | requirements.md Goal | Detection is **top-level only** (runs at `REPO_ROOT`, `[[ -f "$base/marker" ]]`); nested/monorepo subprojects undetected. Pre-existing constraint, but Goal overclaims "more user projects". Add a one-line non-goal — NOT a new functional requirement. |

## What the review CONFIRMED as correct (no change needed)

- Category vocabulary `{lint,typecheck,test,build,other}` matches [spec.schema.json:656-659](plugins/ralphharness/schemas/spec.schema.json#L656) and the `ciSnapshot` keys ([implement.md:236](plugins/ralphharness/commands/implement.md#L236)). ✓
- `command -v` filter problem (US-7) is real and the `-x "$SPEC_PATH/$bin"` fix is sound. ✓
- quality-commands.md: PHP **and** C#/.NET rows genuinely missing; other 4 present. ✓
- Version 5.9.5 → 5.10.0 confirmed in both manifests. ✓
- `dedupe_ci_commands` and `discover_ci_commands` exist as claimed. ✓
- Scripts-discovery model correctly mirrors `detect_package_json`. ✓

## Recommended requirements changes (apply via /ralphharness:requirements)

1. **[SR-001/SR-002] Add FR + AC for the source/function contract.** The spec MUST require that
   `detect-ci-commands.sh` is refactored to (a) expose a `detect_ci_commands()` function wrapping the
   detect+filter+emit logic, and (b) add a `BASH_SOURCE` guard so the CLI path still works for the 17
   bats tests. AC: `source detect-ci-commands.sh && detect_ci_commands <dir>` returns the JSON array
   without executing the CLI body or aborting; `implement.md`'s call site works end-to-end.
   *(This is the headline gap — without it the 6 new detectors never reach the real loop.)*
2. **[SR-004]** Add a requirement/note: detector output overlaps `discover-ci.sh`; exact-tuple dedupe
   will not collapse semantically-equal commands. Decide: accept (documented) or normalize.
3. **[SR-006]** Add design/tasks guidance: `*.csproj`/`*.sln` need `compgen -G`/nullglob, not `[[ -f ]]`.
4. **[SR-005]** Add `discover-ci.sh (discover_ci_commands)` to the Dependency map as co-producer.
5. **[SR-003]** Add "Out of Scope: nested/monorepo subproject detection (top-level marker only)".

## Consensus summary
- Raw findings: 6 · Confirmed: 5 · Disputed→confirmed (downgraded): 1 · Rejected: 0 · Escalated: 0
- SR-001/SR-002 are code-verified facts (no vote needed). SR-003–006 validated by 4-persona roundtable.
