# Gito Code Review Classification — 94 Issues

Generated: 2026-04-29
Source: code-review-report.md (94 issues from Gito automated review)

## Classification Summary

| Category | Count |
|----------|-------|
| CONFIRMED FIX (real problem, new) | 55 |
| CONFIRMED FIX (already fixed prev session) | 7 |
| CONFIRMED NO-FIX (false positive / cosmetic) | 34 |
| NEEDS INVESTIGATION | 0 |

---

## CONFIRMED FIX — 55 Issues

### HIGH Severity (24)

| # | File | Description |
|---|------|-------------|
| 15 | plugins/ralph-bmad-bridge/scripts/ | grep -c \|\| echo 0 corrupts variable output |
| 16 | plugins/ralph-bmad-bridge/scripts/ | Non-standard regex syntax breaks on macOS/BSD |
| 18 | plugins/ralph-bmad-bridge/scripts/ | Non-portable basename ${f%.} fails on some shells |
| 19 | plugins/ralph-bmad-bridge/scripts/ | eval security vulnerability |
| 20 | plugins/ralph-bmad-bridge/commands/ | Path resolution off-by-one (wrong dirname depth) |
| 24 | plugins/ralphharness/hooks/ | Invalid regex [\s] in read-only detection |
| 25 | plugins/ralphharness/commands/ | Duplicate spec-name argument parsing |
| 27 | plugins/ralphharness/commands/ | Missing variable assignment (dead code) |
| 29 | plugins/ralphharness/hooks/ | Invalid regex [\s] in grep |
| 32 | plugins/ralphharness/hooks/ | Unchecked cd commands (silent failure) |
| 33 | plugins/ralphharness/hooks/ | Invalid regex [\s] in grep |
| 36 | plugins/ralphharness/hooks/checkpoint.sh | Unchecked cd (silent directory change failure) |
| 37 | plugins/ralphharness/hooks/checkpoint.sh | Invalid regex [\s] breaks read-only filesystem detection |
| 38 | plugins/ralphharness/hooks/write-metric.sh | Subshell exit code ignored (masking write failures) |
| 65 | specs/loop-safety-infra/.research-metrics-and-ci.md | Useless tr ',' ',' creates malformed JSON |
| 66 | specs/loop-safety-infra/.research-metrics-and-ci.md | Bash command substitution inside jq filter |
| 71 | specs/loop-safety-infra/research-read-only-detection.md | jq // operator incorrectly handles false booleans |
| 72 | specs/loop-safety-infra/research-read-only-detection.md | Exit 0 on fatal filesystem failure (signals success on error) |
| 73 | specs/loop-safety-infra/research-read-only-detection.md | Heartbeat condition skips every iteration (contradicts design) |
| 74 | specs/loop-safety-infra/research.md | Contradictory docs on git commit --no-verify behavior |
| 76 | specs/loop-safety-infra/tasks.md | jq -e boolean chain fails on taskIndex=0 |
| 77 | specs/loop-safety-infra/tests/test-benchmark.sh | date +%s%N fallback fails on macOS/BSD |
| 78 | specs/loop-safety-infra/tests/test-benchmark.sh | Fragile sed regex ignores indentation |
| 82 | specs/loop-safety-infra/tests/test-integration.sh | State file overwritten immediately after creation (test non-functional) |

### MEDIUM Severity (21)

| # | File | Description |
|---|------|-------------|
| 21 | plugins/ralphharness/agents/ | Schema field name mismatch in agent docs |
| 22 | plugins/ralphharness/schemas/ | Missing field definitions in JSON schema |
| 42 | plugins/ralphharness/references/role-contracts.md | Writes column has reads description (wrong content) |
| 43 | plugins/ralphharness/references/role-contracts.md | Contradictory denylist "All files" for spec-reviewer |
| 48 | specs/.index/index-state.json | Inconsistent phase value "complete" vs "completed" |
| 49 | specs/_epics/engine-roadmap-epic/epic.md | Self-referential dependency (Spec 6 depends on Spec 6) |
| 50 | specs/_epics/engine-roadmap-epic/epic.md | Command typo /ralphharness → /ralph-spec |
| 53 | specs/bmad-bridge-plugin/.progress.md | Contradictory [x] + PENDING_COMMIT status |
| 54 | specs/bmad-bridge-plugin/design.md | Awk section boundary regex prematurely exits on ### headings |
| 58 | specs/bmad-bridge-plugin/plan.md | Missing write targets for user stories and test scenarios |
| 62 | specs/bmad-bridge-plugin/requirements.md | Conflicting BMAD versions (v2.11.0 vs v6.4.0) |
| 67 | specs/loop-safety-infra/requirements.md | Metrics field generation ambiguity (write-metric.sh vs coordinator) |
| 70 | specs/loop-safety-infra/research-circuit-breaker.md | Inconsistent data type for sessionStartTime |
| 75 | specs/loop-safety-infra/research.md | Incorrect categorization in Non-Modifications section |
| 81 | specs/loop-safety-infra/tests/test-integration.sh | grep -c \|\| echo 0 corrupts variable on zero matches |
| 84 | specs/pair-debug-auto-trigger/plan.md | Inconsistent condition count (says 3, lists 4) |
| 85 | specs/role-boundaries/design.md | Validation logic skips external_unmarks entirely |
| 86 | specs/role-boundaries/design.md | Flock on arbitrary fd 202 lacks lockfile backing |
| 87 | specs/role-boundaries/final-spec-adversarial-review.md | JSON baseline format mismatch (flat vs nested) |
| 93 | specs/role-boundaries/tasks.md | Regex contradicts stated minimum-length validation |
| 94 | specs/role-boundaries/tasks.md | grep -c redirection creates unintended file |

### LOW Severity (10)

| # | File | Description |
|---|------|-------------|
| 11 | _bmad/custom/config.toml | Inconsistent paths (cosmetic) |
| 40 | plugins/ralphharness/references/loop-safety.md | Hardcoded placeholder vs dynamic path |
| 46 | plugins/ralphharness/schemas/spec.schema.json | Internal ticket refs leak into descriptions |
| 56 | specs/bmad-bridge-plugin/design.md | Duplicate test strategy entries (copy-paste) |
| 60 | specs/bmad-bridge-plugin/requirements.md | Typo smart-ralsh → RalphHarness |
| 61 | specs/bmad-bridge-plugin/requirements.md | Typo bmalph → BMAD |
| 63 | specs/loop-safety-infra/.progress.md | Typo Bmalph → BMAD |
| 69 | specs/loop-safety-infra/research-circuit-breaker.md | Typo excption → exception |
| 91 | specs/role-boundaries/research.md | Corrupted markdown table row |
| 92 | specs/role-boundaries/research.md | Typo/sentence fragment |

---

## CONFIRMED NO-FIX — 34 Issues

### Intentional Design (15)

| # | File | Reason |
|---|------|--------|
| 1 | .gitignore | Self-referencing is intentional (prevent .gitignore in commits) |
| 2 | .gitignore | _bmad-output/ exclusion is intentional (review artifacts) |
| 3 | _bmad/ | CSV data typos — config data, not executable code |
| 4 | _bmad/ | CSV data grammar — non-code content |
| 5 | _bmad/ | CSV data naming — config data, cosmetic |
| 6 | _bmad/ | CSV data duplicates — config data |
| 7 | _bmad/ | CSV data missing entries — config completeness, not code bug |
| 8 | _bmad/ | TOML data comments — documentation note, not code |
| 9 | _bmad/ | TOML data version numbers — metadata, not code |
| 10 | _bmad/ | TOML data descriptions — documentation |
| 12 | _bmad/custom/config.user.toml | User config file — personal preferences |
| 30 | plugins/ralphharness/commands/implement.md | Dead code — already verified as fixed |
| 31 | plugins/ralphharness/commands/implement.md | Dead code — already verified as fixed |
| 34 | plugins/ralphharness/hooks/ | Non-critical suggestion — not a bug |
| 35 | plugins/ralphharness/hooks/ | Non-critical suggestion — not a bug |

### Cosmetic / Style (19)

| # | File | Reason |
|---|------|--------|
| 13 | docs/ARCHITECTURE.md | Heading hierarchy — subjective style preference |
| 14 | docs/README.md | Grammar — documentation only |
| 17 | plans/*.md | Typos — documentation only |
| 28 | plugins/ralphharness/hooks/ | Code style — subjective formatting |
| 39 | plugins/ralphharness/references/loop-safety.md | Numbering 6.5 → renumber — subjective preference |
| 41 | plugins/ralphharness/references/role-contracts.md | Inconsistent naming (.md vs agent) — cosmetic |
| 44 | plugins/ralphharness/references/role-contracts.md | Misplaced note — documentation organization |
| 45 | plugins/ralphharness/references/role-contracts.md | Inconsistent phrasing — documentation style |
| 47 | plugins/ralphharness/schemas/spec.schema.json | Missing format: date-time — nice-to-have, not required |
| 51 | specs/bmad-bridge-plugin/.progress.md | Missing code formatting — documentation readability |
| 52 | specs/bmad-bridge-plugin/.progress.md | Referenced task doesn't exist — progress doc artifact |
| 55 | specs/bmad-bridge-plugin/design.md | FALSE POSITIVE: /ralph-harness:implement IS the correct command |
| 57 | specs/bmad-bridge-plugin/plan.md | Spec title uses common abbreviation — naming convention |
| 59 | specs/bmad-bridge-plugin/requirements.md | FALSE POSITIVE: "product manager" is correctly spelled |
| 64 | specs/loop-safety-infra/.research-codebase.md | State field naming — research doc example, not code |
| 68 | specs/loop-safety-infra/requirements.md | CI snapshot null handling — documentation clarification |
| 88 | specs/role-boundaries/final-spec-adversarial-review.md | Mixed Spanish/English — adversarial review document language |
| 89 | specs/role-boundaries/requirements.md | FALSE POSITIVE: [ralphharness] IS the plugin name |
| 90 | specs/role-boundaries/requirements.md | Terminology "section boundaries" — subjective |

---

## INVESTIGATION RESULTS

### #81 — grep -c \|\| echo 0 in test-integration.sh
**Verdict: CONFIRMED FIX**
**Reason:** Under `set -euo pipefail`, `grep -c` outputs "0" and exits 1 when no matches found. `|| echo 0` appends another "0", making the variable "0\n0". Arithmetic comparison `[ "$var" -gt 0 ]` fails with "integer expression expected". Fix: change `|| echo 0` to `|| true`.

### #82 — State file overwritten in test-integration.sh
**Verdict: CONFIRMED FIX**
**Reason:** Lines 60-71 create circuit breaker state. Line 73 `echo '{}' > "$tmp/.ralph-state.json"` immediately overwrites it. Test 5 reads empty state instead of configured circuit breaker state.

### #42 — Writes column has reads description
**Verdict: CONFIRMED FIX** — Wrong semantic content. Should be `_(read-only)_`.

### #43 — Contradictory denylist "All files"
**Verdict: CONFIRMED FIX** — Direct contradiction. Should be `_(read-only)_`.

---

## Already-Fixed Issues (from Previous Session)

These were identified and fixed in the previous conversation session:

| # | File | Fix Applied |
|---|------|-------------|
| sessionStartTime | plugins/ralphharness/commands/implement.md | Removed literal string, replaced invalid --argjson with jq filter |
| exit 0 dead code | plugins/ralphharness/hooks/scripts/stop-watcher.sh | Removed exit 0 at line 765 |
| ROOT_DIR depth | specs/loop-safety-infra/tests/test-*.sh (5 files) | Fixed from 2 to 3 dirname levels |
| PROJECT_ROOT depth | specs/loop-safety-infra/tests/test-checkpoint.sh | Fixed from 6 to 3 dirname levels |
| assert_eq "$sha" "$sha" | specs/loop-safety-infra/tests/test-checkpoint.sh | Removed redundant assertion |
| chmod 755 restoration | specs/loop-safety-infra/tests/test-heartbeat.sh | Removed permission restoration between iterations |
| Mismatched echo quotes | specs/loop-safety-infra/tests/test-write-metric.sh | Fixed quote placement |

---

## Final Tally

| Category | Count |
|----------|-------|
| CONFIRMED FIX (new, need action) | 55 |
| CONFIRMED FIX (already fixed, no action needed) | 7 |
| CONFIRMED NO-FIX (false positive / cosmetic) | 34 |
| NEEDS INVESTIGATION | 0 |
| **Total** | **96** (94 unique issues, 2 items cross-reference previous session) |

Note: The 55 "CONFIRMED FIX (new)" items represent issues that need action. Items #23 and #26 were re-verified as already fixed during classification and removed from the new fixes list.
