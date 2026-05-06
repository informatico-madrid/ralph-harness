---
spec: ralphharness-rename
phase: design
created: 2026-05-02
---

# Design: RalphHarness Rename

## Overview

This is a **rename-only refactoring**. No architectural changes, no logic changes, no new features. All changes are string/path replacements across ~278+ files spanning 4 plugins, config files, CI/CD pipelines, tests, and documentation.

The project transitions from `tzachbon/smart-ralph` (a fork) to `informatico-madrid/RalphHarness` (an independent project). The rename preserves the existing plugin structure, execution flow, and state machine -- everything functions identically, just under a new identity.

## Scope

### In Scope (~278+ files)

| Category | Files | Examples |
|----------|-------|---------|
| Plugin manifests (4 plugins) | 5 | `plugin.json` files in each plugin dir, 2 `marketplace.json` files |
| Plugin core (`ralph-specum` -> `ralphharness`) | ~100 | 16 commands, 10 hook scripts, 10 agents, 17 skills, 20+ references, 14+ templates, 2 schemas |
| Plugin codex (`ralph-specum-codex` -> `ralphharness-codex`) | ~65 | 10 agent-config TOMLs, 15 skills, 3 schemas, scripts, templates |
| Plugin speckit (`ralph-speckit` -> `ralphharness-speckit`) | 1 | Manifest + LICENSE |
| Plugin bmad-bridge | 2 | Manifest + 1 script comment |
| Root docs + configs | ~17 | README.md, CLAUDE.md, CONTRIBUTING.md, TROUBLESHOOTING.md, LICENSE, gito, serena |
| GitHub CI/CD + templates | ~7 | 3 workflows, 2 issue templates, 1 config, 1 agents marketplace |
| Test infrastructure | ~13 | 6 .bats files, 1 helper script, version-sync |
| BMAD configs + output | ~8 | 4 config files in `_bmad/`, 3 output files |
| Skills outside plugins | ~8 | `.claude/skills/` and `.agents/skills/` review skills |
| Other hidden configs | ~5 | `.gito/`, `.serena/`, `.bmad-harness/`, `.roo/` |

### 17. Roo IDE Config (8+ files)

| File | Changes |
|------|---------|
| `.roo/skills/quality-gate/SKILL.md` | `smart-ralph` -> `RalphHarness` (3+ refs) |
| `.roo/skills/quality-gate/steps/step-05-checkpoint.md` | `smart-ralph` -> `RalphHarness` (2 refs) |
| `.roo/skills/quality-gate/workflow.md` | `smart-ralph` -> `RalphHarness` (1 ref) |
| `.roo/mcp.json` | Check for plugin path references |
| `.roo/commands/external-reviewer.md` | Check for command references |
| Directory renames | 4 directories | `git mv` operations |
| File deletion | 1 file | `README.fork.md` |

### Out of Scope

| Category | Files | Reason |
|----------|-------|--------|
| `specs/` (historical) | ~186 | Generated artifacts, historical records, not actionable for rename PR |
| `platforms/codex/skills/ralph-specum*/` | 16 dirs | Explicitly out per epic AC-13.8. **Note: These directories will need manual rename/update after migration. Do not forget to update them before the next development cycle.** |
| `platforms/codex/manifest.json` | 1 | Out per epic -- contains `ralph-specum-codex` but not part of the plugin rename scope. Will be updated separately. |
| `_bmad-output/**/*.md` | 4 | Auto-generated artifacts |
| `docs/brainstormmejora/` | 4 | Historical brainstorm documents |
| `docs/plans/`, `plans/` | 6 | Historical planning documents |
| User spec directories | ~228 | Existing user-created specs excluded from rename PR. They remain valid and will be recognized by the renamed plugin. No migration needed. |

## Architecture

No architecture changes. The existing plugin structure, execution flow, and state machine remain identical.

The plugin system (Claude Code `--plugin-dir` loading mechanism, skill invocation format, hook watcher loop) functions the same way -- only identifiers change.

```
plugins/ralphharness/              plugins/ralphharness-codex/
├── commands/                     ├── agent-configs/
├── hooks/scripts/                ├── hooks/
├── agents/                       ├── schemas/
├── skills/                       └── scripts/
├── templates/
├── references/
├── schemas/
└── .claude-plugin/plugin.json

plugins/ralphharness-speckit/      plugins/ralphharness-bmad-bridge/
├── .claude-plugin/plugin.json    ├── .claude-plugin/plugin.json
├── commands/                     ├── commands/
├── skills/                       └── scripts/
└── LICENSE
```

## Rename Mapping Table

Every mapping below is derived from the research inventory and 9 rounds of adversarial review.

### Plugin Name Mappings

| Original | New | Files Affected |
|----------|-----|----------------|
| `ralph-specum` (plugin name) | `ralphharness` | ~100 files (commands, hooks, agents, skills, templates, references, schemas) |
| `ralph-speckit` (plugin name) | `ralphharness-speckit` | 1 (plugin.json name field) |
| `ralph-bmad-bridge` (plugin name) | `ralphharness-bmad-bridge` | 1 (plugin.json author/description only) |
| `ralph-specum-codex` (plugin name) | `ralphharness-codex` | ~65 files (manifest, agent-configs, skills, schemas, scripts, templates) |

### Command Prefix Mappings

| Original | New | Files Affected |
|----------|-----|----------------|
| `/ralph-specum:` | `/ralph-harness:` | ~200 locations across commands, hooks, agents, templates, references, skills, docs, tests, CI, BMAD configs |
| `ralph-specum:` (skill invocations) | `ralphharness:` | Same ~200 locations |
| `ralph-speckit:` | `ralphharness-speckit:` | Skill invocation patterns in agents and templates |

### Identity Mappings

| Original | New | Files Affected |
|----------|-----|----------------|
| `tzachbon` | `informatico-madrid` | ~30 files (marketplace.json, 5 plugin.json manifests, LICENSE x2, GitHub URLs, CLAUDE.md) |
| `smart-ralph` | `ralphharness` | ~16 files (skill directories, comments, descriptions) |
| `smart-ralph` (brand) | `RalphHarness` | ~10 files (README, CONTRIBUTING, issue templates) |
| `Smart Ralph` | `RalphHarness` | ~6 files (docs, skill names) |
| `smart-ralph@smart-ralph` | `ralphharness@informatico-madrid` | 1 file (`.claude/settings.json` enabledPlugins key) |
| `ralph-specum@smart-ralph` | `ralphharness@informatico-madrid` | 1 file (`.claude/settings.json` enabledPlugins key) |

### Directory Rename Mappings

| Original Path | New Path | Method |
|---------------|----------|--------|
| `plugins/ralph-specum/` | `plugins/ralphharness/` | `git mv` |
| `plugins/ralph-speckit/` | `plugins/ralphharness-speckit/` | `git mv` |
| `plugins/ralph-bmad-bridge/` | `plugins/ralphharness-bmad-bridge/` | Content update only (author/description). Directory name unchanged — no `ralph-specum` in original name. |
| `plugins/ralph-specum-codex/` | `plugins/ralphharness-codex/` | `git mv` |
| `plugins/ralphharness/skills/smart-ralph/` | `plugins/ralphharness/skills/ralphharness/` | `git mv` + SKILL.md update |
| `plugins/ralphharness-speckit/skills/smart-ralph/` | `plugins/ralphharness-speckit/skills/ralphharness/` | `git mv` + SKILL.md update |
| `.claude/ralph-specum.local.md` | `.claude/ralphharness.local.md` | File rename + script path updates |

## File Change Matrix

### 1. Plugin Manifests (5 files)

| File | Changes |
|------|---------|
| `plugins/ralphharness/.claude-plugin/plugin.json` | name -> `ralphharness`, author -> `informatico-madrid`, version -> `5.0.0` |
| `plugins/ralphharness-speckit/.claude-plugin/plugin.json` | name -> `ralphharness-speckit`, author -> `informatico-madrid`, version -> `1.0.0` |
| `plugins/ralphharness-bmad-bridge/.claude-plugin/plugin.json` | author -> `informatico-madrid`, description update |
| `plugins/ralphharness-codex/.codex-plugin/plugin.json` | name -> `ralphharness-codex`, author -> `informatico-madrid`, version -> `5.0.0` |
| `.claude-plugin/marketplace.json` | name -> `ralphharness`, owner.name -> `informatico-madrid`, all source paths, all author.name entries |

### 2. Plugin Core - Commands (16 files)

All files in `plugins/ralphharness/commands/`:

| File | Changes |
|------|---------|
| `start.md` | `/ralph-specum:` -> `/ralph-harness:`, `ralph-specum:<name>` -> `ralphharness:<name>`, CLAUDE_PLUGIN_ROOT path |
| `implement.md` | Command prefix updates |
| `cancel.md` | Command prefix, state file references |
| `design.md` | Command prefix updates |
| `requirements.md` | Command prefix updates |
| `research.md` | Command prefix updates |
| `tasks.md` | Command prefix updates |
| `feedback.md` | GitHub issue URL (tzachbon -> informatico-madrid), command prefix |
| `help.md` | Full command reference table rewrite |
| `index.md` | Command prefix |
| `new.md` | Command prefix |
| `refactor.md` | Command prefix |
| `rollback.md` | Command prefix |
| `status.md` | Command prefix |
| `switch.md` | Command prefix |
| `triage.md` | Command prefix |

### 3. Plugin Core - Hook Scripts (10 files)

All files in `plugins/ralphharness/hooks/scripts/`:

| File | Changes |
|------|---------|
| `stop-watcher.sh` | `[ralph-specum]` -> `[ralphharness]` log prefix (40+ occurrences), `.claude/ralph-specum.local.md` -> `.claude/ralphharness.local.md`, command references |
| `load-spec-context.sh` | Log prefix, settings file path, command references |
| `path-resolver.sh` | Settings file path, command references |
| `checkpoint.sh` | Log prefix (15+ occurrences), git commit message patterns |
| `write-metric.sh` | Log prefix |
| `update-spec-index.sh` | Command references |
| `quick-mode-guard.sh` | No changes needed (clean) |
| `test-multi-dir-integration.sh` | Settings file path in test setup |
| `test-path-resolver.sh` | Settings file path in test setup |
| `discover-ci.sh` | Command references |

### 4. Plugin Core - Agents (10 files)

All files in `plugins/ralphharness/agents/`:

| File | Changes |
|------|---------|
| `spec-executor.md` | Skill invocation format `ralph-specum:<name>` -> `ralphharness:<name>` |
| `task-planner.md` | `/ralph-specum:start` -> `/ralph-harness:start` |
| `qa-engineer.md` | Command references |
| Other 7 agents | Fewer references, mostly CLAUDE_PLUGIN_ROOT pattern |

### 5. Plugin Core - Skills (17 files)

All files in `plugins/ralphharness/skills/`:

| File | Changes |
|------|---------|
| `SKILL.md` (root) | Skill name, references |
| `smart-ralph/` -> `ralphharness/` | Directory rename + SKILL.md content update |
| `e2e/SKILL.md` | Skill name references |
| `e2e/mcp-playwright.skill.md` | References |
| `e2e/playwright-env.skill.md` | References |
| `e2e/playwright-session.skill.md` | References |
| `e2e/ui-map-init.skill.md` | References |
| `spec-workflow/SKILL.md` | References |
| `spec-workflow/references/phase-transitions.md` | References |
| `interview-framework/SKILL.md` | References |
| `reality-verification/SKILL.md` | References |
| `communication-style/SKILL.md` | References |
| `context-auditor/SKILL.md` | References |

### 6. Plugin Core - Templates (14+ files)

All files in `plugins/ralphharness/templates/`:

| File | Changes |
|------|---------|
| `settings-template.md` | References, skill invocation format |
| `tasks.md` | Skill invocation patterns |
| `prompts/executor-prompt.md` | References |
| `prompts/research-prompt.md` | References |
| Other 10 templates | Fewer content references |

### 7. Plugin Core - References (20+ files)

All files in `plugins/ralphharness/references/`:

| File | Changes |
|------|---------|
| `coordinator-pattern.md` | Skill invocation patterns |
| `intent-classification.md` | References |
| `quick-mode.md` | Command references |
| `spec-scanner.md` | References |
| Other 16 files | Generally fewer references |

### 8. Plugin Core - Schemas (2 files)

| File | Changes |
|------|---------|
| `plugins/ralphharness/schemas/spec.schema.json` | `$id` -> `"ralphharness"`, title, description text |

### 9. Codex Plugin (65 files)

All files in `plugins/ralphharness-codex/`:

| Sub-category | Files | Changes |
|--------------|-------|---------|
| Agent configs (.toml.template) | 10 | `[agents.ralph-specum-<name>]` -> `[agents.ralphharness-<name>]`, comments |
| Agent config README | 1 | Documentation references to plugin paths and TOML keys |
| `README.md` | 1 | ~40 references to `ralph-specum`, `smart-ralph`, `Ralph Specum`, `Smart Ralph`, `tzachbon` |
| Skills | 32 | Skill name patterns in content |
| Schemas | 2 | `$id`, title, description |
| Scripts | 2 | `resolve_spec_paths.py`, etc. |
| Templates | 6 | Content references |
| Manifest | 1 | name, author, version |

**Note:** `platforms/codex/manifest.json` contains `ralph-specum-codex` but is out of scope per epic.
`platforms/codex/README.md` contains 15+ brand references but is a migration/legacy file; check if in scope per epic.

### 10. Root Documentation (8 files)

| File | Changes |
|------|---------|
| `README.md` | ~150 references: brand, commands, clone URL, plugin names |
| `CLAUDE.md` | ~15 references: architecture overview, plugin structure, commands |
| `CONTRIBUTING.md` | ~5 references: GitHub URLs, clone URL |
| `TROUBLESHOOTING.md` | ~25 references: command examples, GitHub URL |
| `LICENSE` | Copyright: `tzachbon` -> `RalphHarness Project Authors` |
| `README.fork.md` | Delete (no longer needed) |
| `gito-review-classification.md` | Plugin path references |
| `AGENTS.md` | Symlink to CLAUDE.md, follows CLAUDE.md changes |

### 11. Root Config Files (5 files)

| File | Changes |
|------|---------|
| `.claude/settings.json` | `enabledPlugins.ralph-specum@smart-ralph` -> `enabledPlugins.ralphharness@informatico-madrid` |
| `.claude/ralph-specum.local.md` -> `.claude/ralphharness.local.md` | File rename |
| `.gito/config.toml` | Comment with "smart-ralph" -> "RalphHarness" |
| `.serena/project.yml` | `project_name: "smart-ralph"` -> `"RalphHarness"` |
| `.claude/settingsback.localback.jsonBACK` | Historical, check for references |

### 12. GitHub CI/CD + Templates (7 files)

| File | Changes |
|------|---------|
| `.github/workflows/bats-tests.yml` | `plugins/ralph-specum-codex/**` -> `plugins/ralphharness-codex/**` paths |
| `.github/workflows/codex-version-check.yml` | Path triggers, MANIFEST path, PR names |
| `.github/workflows/plugin-version-check.yml` | Generic glob, may not need changes |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Command examples `/ralph-specum:` -> `/ralph-harness:` |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Command examples |
| `.github/ISSUE_TEMPLATE/config.yml` | GitHub repo URL |
| `.agents/plugins/marketplace.json` | name, paths, author references |

### 13. Test Infrastructure (16 files)

| File | Changes |
|------|---------|
| `tests/codex-plugin.bats` | ~30 references to skill names, paths |
| `tests/codex-platform.bats` | ~50 references to plugin paths, skill names |
| `tests/codex-platform-scripts.bats` | ~10 references to codex paths |
| `tests/stop-hook.bats` | `[ralph-specum]` log prefix -> `[ralphharness]` |
| `tests/interview-framework.bats` | ~20 references to plugin paths |
| `tests/helpers/version-sync.sh` | Reads versions from manifests, paths |
| `tests/helpers/setup.bash` | Hardcoded paths to `plugins/ralph-specum/` -> `plugins/ralphharness/` |
| `tests/speckit-helpers/setup.bash` | Hardcoded paths to `plugins/ralph-speckit/` -> `plugins/ralphharness-speckit/` |
| Other 6 .bats files | Check for hardcoded references |

### 14. BMAD Configs + Output (9 files)

| File | Changes |
|------|---------|
| `_bmad/config.toml` | `project_name = "smart-ralph"` -> `project_name = "RalphHarness"` |
| `_bmad/bmm/config.yaml` | Plugin name references |
| `_bmad/cis/config.yaml` | Plugin name references |
| `_bmad/core/config.yaml` | Plugin name references |
| `_bmad/tea/config.yaml` | Plugin name references |
| `_bmad/config.user.toml` | Plugin name references |
| `_bmad/scripts/resolve_customization.py` | No references (verified clean) |
| `_bmad-output/` (3 files) | Auto-generated, out of scope |

### 15. Skills Outside Plugins (8 files)

| File | Changes |
|------|---------|
| `.claude/skills/smart-ralph-review/SKILL.md` | Dozens of `/ralph-specum:` -> `/ralph-harness:`, review output paths |
| `.agents/skills/smart-ralph-review/SKILL.md` | Duplicate of above, same updates |
| `.claude/skills/bmad-party-mode/*_context.md` | Check for command references |
| `.claude/skills/autonomous-adversarial-coordinator/` | Check for command references |

### 16. Other Hidden Configs (5 files)

| File | Changes |
|------|---------|
| `.bmad-harness/tasks/gemini.md` | 0 refs, no changes needed (verified) |
| `.gito/config.toml` | Project comment |
| `.serena/project.yml` | Project name |
| Other bmad-harness | Check for references |

## Directory Rename Plan

All directory renames use `git mv` to preserve git history.

### Step-by-Step

```bash
# Step 1: Rename main plugin directory
git mv plugins/ralph-specum plugins/ralphharness

# Step 2: Rename speckit plugin directory
git mv plugins/ralph-speckit plugins/ralphharness-speckit

# Step 3: Rename codex plugin directory
git mv plugins/ralph-specum-codex plugins/ralphharness-codex

# Step 4: Rename bmad-bridge plugin directory (if directory name needs change)
# Note: bmad-bridge contains no "ralph-specum" in its directory name,
# so the directory itself stays. Only manifest content changes.

# Step 5: Rename smart-ralph skill directories
git mv plugins/ralphharness/skills/smart-ralph plugins/ralphharness/skills/ralphharness
git mv plugins/ralphharness-speckit/skills/smart-ralph plugins/ralphharness-speckit/skills/ralphharness

# Step 6: Rename settings file
git mv .claude/ralph-specum.local.md .claude/ralphharness.local.md

# Step 7: Delete fork documentation
git rm README.fork.md

# Step 8: Rename codex skill directories (16 directories in plugins/ralph-specum-codex/skills/)
# Actual directory names are command-name variants: ralph-specum, ralph-specum-cancel, etc.
# NOTE: These git mv commands run BEFORE the codex directory rename (Phase 2, Step 3).
# After git mv, sed in agent-config .toml.template files will update agent keys.
git mv plugins/ralph-specum-codex/skills/ralph-specum \
          plugins/ralph-specum-codex/skills/ralphharness
git mv plugins/ralph-specum-codex/skills/ralph-specum-cancel \
          plugins/ralph-specum-codex/skills/ralphharness-cancel
git mv plugins/ralph-specum-codex/skills/ralph-specum-design \
          plugins/ralph-specum-codex/skills/ralphharness-design
git mv plugins/ralph-specum-codex/skills/ralph-specum-feedback \
          plugins/ralph-specum-codex/skills/ralphharness-feedback
git mv plugins/ralph-specum-codex/skills/ralph-specum-help \
          plugins/ralph-specum-codex/skills/ralphharness-help
git mv plugins/ralph-specum-codex/skills/ralph-specum-implement \
          plugins/ralph-specum-codex/skills/ralphharness-implement
git mv plugins/ralph-specum-codex/skills/ralph-specum-index \
          plugins/ralph-specum-codex/skills/ralphharness-index
git mv plugins/ralph-specum-codex/skills/ralph-specum-refactor \
          plugins/ralph-specum-codex/skills/ralphharness-refactor
git mv plugins/ralph-specum-codex/skills/ralph-specum-requirements \
          plugins/ralph-specum-codex/skills/ralphharness-requirements
git mv plugins/ralph-specum-codex/skills/ralph-specum-research \
          plugins/ralph-specum-codex/skills/ralphharness-research
git mv plugins/ralph-specum-codex/skills/ralph-specum-rollback \
          plugins/ralph-specum-codex/skills/ralphharness-rollback
git mv plugins/ralph-specum-codex/skills/ralph-specum-start \
          plugins/ralph-specum-codex/skills/ralphharness-start
git mv plugins/ralph-specum-codex/skills/ralph-specum-status \
          plugins/ralph-specum-codex/skills/ralphharness-status
git mv plugins/ralph-specum-codex/skills/ralph-specum-switch \
          plugins/ralph-specum-codex/skills/ralphharness-switch
git mv plugins/ralph-specum-codex/skills/ralph-specum-tasks \
          plugins/ralph-specum-codex/skills/ralphharness-tasks
git mv plugins/ralph-specum-codex/skills/ralph-specum-triage \
          plugins/ralph-specum-codex/skills/ralphharness-triage
```

## Execution Plan

### Phase 1: Safety (Before Any Changes)

1. Create full backup: `git stash` (if clean working tree) or snapshot branch
2. Record pre-change grep counts for audit trail:
   ```bash
   grep -rn "ralph-specum" . --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=.git | wc -l > pre-change-count.txt
   ```
3. Create `verify-rename.sh` verification script
4. Document rollback plan (see Rollback Plan section below)

### Phase 2: Foundation -- Directory Renames + Manifests

1. Rename 4 plugin directories with `git mv`
2. Rename 2 skill directories (`smart-ralph` -> `ralphharness`)
3. Rename settings file
4. Delete `README.fork.md`
5. Update 4 plugin.json files (name, author, version)
6. Update 2 marketplace.json files (owner, paths, authors)
7. Update 2 schema.json files ($id, title, description)
8. **Quick verification**: Check that plugin.json files parse correctly with `jq`

### Phase 3: Core Rename -- Plugin Content

**CRITICAL: sed expression order must be LONGER FIRST.** The colon-suffixed pattern `ralph-specum:` must be processed BEFORE the general pattern `ralph-specum`. Otherwise `ralph-specum:` gets caught by the first substitution, producing `ralphharness:` instead of `ralph-harness:`.

This is the bulk of the work: ~100+ files across the plugin core.

**Prerequisite: Dry-run first on each target directory.** Before applying sed to any directory, run with `sed -n` (print-only) to verify matches:
```bash
find plugins/ralphharness -type f -name '*.md' | head -5 | xargs sed -n \
  -e 's/ralph-specum:/ralph-harness:/g' \
  -e 's/ralph-specum/ralphharness/g' \
  -e 's/smart-ralph/ralphharness/g' \
  -e 's/tzachbon/informatico-madrid/g'
```
Compare output against expected changes in the File Change Matrix. Any unexpected modifications are red flags. Do this for ALL target directories (ralphharness, ralphharness-codex, ralphharness-speckit, root docs) before applying actual changes.

1. Run sed script on `plugins/ralphharness/`:
   ```bash
   find plugins/ralphharness -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \) \
     -exec sed -i \
       -e 's/ralph-specum@smart-ralph/ralphharness@informatico-madrid/g' \
       -e 's/ralph-specum:/ralph-harness:/g' \
       -e 's/ralph-specum/ralphharness/g' \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/Ralph Specum/RalphHarness/g' -e 's/Smart Ralph/RalphHarness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
     {} +
   ```
2. Run sed script on `plugins/ralphharness-codex/`:
   Same patterns, plus update TOML agent config keys:
   ```bash
   find plugins/ralphharness-codex -type f \( -name '*.md' -o -name '*.json' -o -name '*.sh' -o -name '*.toml' -o -name '*.toml*' -o -name '*.yaml' -o -name '*.yml' -o -name '*.py' -o -name '*.bats' -o -name '*.txt' \) \
     -exec sed -i \
     -e 's/ralph-specum:/ralph-harness:/g' \
     -e 's/ralph-specum/ralphharness/g' \
     -e 's/smart-ralph/ralphharness/g' \
     -e 's/Ralph Specum/RalphHarness/g' -e 's/Smart Ralph/RalphHarness/g' \
     -e 's/tzachbon/informatico-madrid/g' \
     {} +
   ```
3. Run sed on `plugins/ralphharness-speckit/`:
   ```bash
   find plugins/ralphharness-speckit -type f \( -name '*.md' -o -name '*.json' -o -name '*.sh' -o -name '*.toml*' \) \
     -exec sed -i \
       -e 's/ralph-speckit/ralphharness-speckit/g' \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
     {} +
   ```
4. Run sed on `plugins/ralphharness-bmad-bridge/`:
   ```bash
   find plugins/ralphharness-bmad-bridge -type f \( -name '*.md' -o -name '*.json' -o -name '*.sh' \) \
     -exec sed -i \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
     {} +
   ```

### Phase 4: External References

1. Root docs:
   ```bash
   sed -i \
     -e 's/ralph-specum/RalphHarness/g' \
     -e 's/Ralph Specum/RalphHarness/g' \
     -e 's/smart-ralph/RalphHarness/g' \
     -e 's/Smart Ralph/RalphHarness/g' \
     -e 's/tzachbon/informatico-madrid/g' \
     README.md CLAUDE.md CONTRIBUTING.md TROUBLESHOOTING.md LICENSE
   ```

2. Root configs:
   ```bash
   sed -i \
     -e 's/ralph-specum/RalphHarness/g' \
     -e 's/Ralph Specum/RalphHarness/g' \
     -e 's/smart-ralph/RalphHarness/g' \
     -e 's/tzachbon/informatico-madrid/g' \
     .claude/settings.json .gito/config.toml .serena/project.yml
   ```

3. GitHub workflows and templates:
   ```bash
   find .github \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) \
     -exec sed -i \
       -e 's/ralph-specum/RalphHarness/g' \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/smart-ralph/RalphHarness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
       {} +
   ```

4. Test files (.bats):
   ```bash
   find tests -name '*.bats' \
     -exec sed -i \
       -e 's/ralph-specum/ralphharness/g' \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
       {} +
   ```

5. BMAD configs:
   ```bash
   find _bmad -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.md' \) \
     -exec sed -i \
       -e 's/ralph-specum/ralphharness/g' \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
       {} +
   ```

6. Skills outside plugins:
   ```bash
   find .claude/skills .agents/skills -name '*.md' -type f \
     -exec sed -i \
       -e 's/ralph-specum/ralphharness/g' \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/smart-ralph/ralphharness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
       {} +
   ```

7. Hooks manifests (JSON files that may contain "Ralph Specum" title-case):
   ```bash
   find plugins -name 'hooks.json' -type f \
     -exec sed -i \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/ralph-specum/ralphharness/g' \
       {} +
   ```

8. Root docs (non-historical):
   ```bash
   find docs -type f -name '*.md' \
     -not -path 'docs/brainstormmejora/*' \
     -not -path 'docs/plans/*' \
     -exec sed -i \
       -e 's/ralph-specum/RalphHarness/g' \
       -e 's/Ralph Specum/RalphHarness/g' \
       -e 's/smart-ralph/RalphHarness/g' \
       -e 's/Smart Ralph/RalphHarness/g' \
       -e 's/tzachbon/informatico-madrid/g' \
       {} +
   ```

### Phase 5: Verification

1. Run `verify-rename.sh` -- expect ZERO matches for all 3 patterns (excluding out-of-scope)
2. Run `bats tests/*.bats` -- expect 100% pass
3. Load plugin with new name: verify Claude Code loads without errors
4. Run `/ralph-harness:help` -- verify commands respond
5. Verify `git log --follow plugins/ralphharness/` shows history

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Missing a file during grep-sed | HIGH | MEDIUM | Comprehensive grep verification before AND after; multi-pattern sed script; automated verification script |
| `.claude/settings.json` not updated -- plugin never loads | CRITICAL | LOW | Update settings.json as part of Phase 2 alongside directory renames |
| CI workflows reference old paths -- CI silently breaks | HIGH | MEDIUM | Update workflows simultaneously with directory renames (Phase 2) |
| Test suite fails due to hardcoded paths | MEDIUM | HIGH | Systematic sed updates to all .bats files (Phase 4) |
| Corrupting state files | HIGH | LOW | State files use generic names (`.ralph-state.json`). No change needed. |
| Version number conflicts in marketplace | LOW | LOW | Update all version numbers per requirements (5.0.0, 1.0.0) |
| Broken git history | HIGH | LOW | Use `git mv` for all directory renames; verify with `git log --follow` |
| Inconsistent sed ordering causing double-replace | MEDIUM | LOW | Careful sed expression ordering: longer patterns first (`ralph-specum:` before `ralph-specum`) |

## Rollback Plan

If any issue is detected during or after the rename:

1. **Immediate rollback**: `git checkout -- .` (revert all unstaged changes)
2. **If committed but not pushed**: `git revert <commit-hash>`
3. **Full rollback**: `git reset --hard HEAD~1` (if single commit)
4. **Plugin restoration**: Re-enable old plugin name in `.claude/settings.json`
5. **Restart Claude Code** with old plugin path

The rollback path is clean because:
- All changes are text-based (no binary files, no logic changes)
- Git history is preserved via `git mv`
- State files are generic and unaffected
- The old plugin name and author remain in historical specs (out of scope)

## Verification Contract

### Pre-flight Checks

Document the baseline counts before any changes:
```bash
# Pattern 1: ralph-specum (case-insensitive, excluding specs/ and historical dirs)
grep -rin "ralph-specum\|Ralph Specum" . \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' \
  --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
  --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=.git \
  --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen | wc -l

# Pattern 2: tzachbon
grep -rn "tzachbon" . \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' \
  --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
  --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=.git \
  --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen | wc -l

# Pattern 3: smart-ralph (case-insensitive to catch "Smart Ralph")
grep -rin "smart-ralph\|Smart Ralph" . \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' \
  --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
  --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=.git \
  --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen | wc -l
```

### Post-flight Checks

All patterns must return **0**:
```bash
grep -rin "ralph-specum\|Ralph Specum\|tzachbon\|smart-ralph\|Smart Ralph" . \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' \
  --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
  --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=.git \
  --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen | wc -l
```
Expected: `0`

### Functional Checks

| Check | Command | Expected |
|-------|---------|----------|
| Plugin name | `jq -r '.name' plugins/ralphharness/.claude-plugin/plugin.json` | `"ralphharness"` |
| Plugin version | `jq -r '.version' plugins/ralphharness/.claude-plugin/plugin.json` | `"5.0.0"` |
| Marketplace owner | `jq -r '.owner.name' .claude-plugin/marketplace.json` | `"informatico-madrid"` |
| New plugin enabled | `jq -r '.enabledPlugins."ralphharness@informatico-madrid"' .claude/settings.json` | `true` |
| Old plugin disabled | `jq -r '.enabledPlugins."ralph-specum@smart-ralph"' .claude/settings.json` | `null` |
| Old settings key gone | `jq -r '.enabledPlugins."ralphharness@smart-ralph"' .claude/settings.json` | `null` |
| Git history preserved | `git log --follow plugins/ralphharness/ | head -3` | Shows existing commits |
| Informatico-madrid present | `grep -r "informatico-madrid" .claude-plugin/marketplace.json plugins/ralphharness/.claude-plugin/plugin.json \| wc -l` | > 0 |
| No README.fork.md | `test -f README.fork.md` | false |
| RalphHarness in README | `grep "RalphHarness" README.md` | match |
| /ralph-harness: present | `grep "/ralph-harness:" plugins/ralphharness/commands/*.md` | > 0 |

### Test Checks

| Check | Command | Expected |
|-------|---------|----------|
| BATS suite | `bats tests/*.bats` | All pass |
| Version sync | `bats tests/helpers/version-sync.sh` | Pass |

### Structured File Validation

After sed replacements, validate all structured files parse correctly:

```bash
# JSON files — each must be valid JSON
for f in $(find plugins .claude-plugin .agents .gito .serena \
  -name '*.json' -not -path '*/node_modules/*' 2>/dev/null); do
  jq . "$f" > /dev/null 2>&1 || echo "INVALID JSON: $f"
done

# TOML files — each must be valid TOML
for f in $(find plugins .gito _bmad .bmad-harness -name '*.toml' 2>/dev/null); do
  python3 -c "import tomllib; tomllib.load(open('$f', 'rb'))" 2>/dev/null \
    || echo "INVALID TOML: $f"
done

# YAML files — each must be valid YAML
for f in $(find plugins _bmad .github .serena -name '*.yaml' -o -name '*.yml' 2>/dev/null); do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null \
    || echo "INVALID YAML: $f"
done
```

### Shell Script Validation

```bash
# All .sh files must pass shellcheck
find plugins .github -name '*.sh' -exec shellcheck {} +
```

### gito Review Classification File

| File | Changes |
|------|---------|
| `gito-review-classification.md` | Plugin path references `plugins/ralph-specum/` -> `plugins/ralphharness/`, GitHub URL updates |

## Hard Invariants

1. **State file naming**: `.ralph-state.json` and `.ralph-progress.md` remain unchanged (generic names, no ralph-specum prefix)
2. **Plugin loading mechanism**: `--plugin-dir` flag and skill invocation format remain identical
3. **Hook watcher loop**: Execution loop logic unchanged (only log prefixes and config paths change)
4. **Spec workflow**: 4-phase POC-first workflow unchanged
5. **State machine**: `.ralph-state.json` structure unchanged

## Unresolved Questions

1. **`.claude/settings.json` key format**: Should the key be `ralphharness@informatico-madrid` or `ralphharness@smart-ralph`? The requirements specify `ralphharness@informatico-madrid` (AC-1.10), but `smart-ralph` as the owner portion could be preserved. Recommendation: use `ralphharness@informatico-madrid` per AC-1.10.

2. **State file naming convention**: The epic mentions `.ralphharness-state.json` but the current codebase uses generic `.ralph-state.json`. These generic names do not contain "ralph-specum" and should remain as-is (no change needed).

3. **Version numbers for derived plugins**: The epic specifies 5.0.0 for the main plugin. The requirements specify 1.0.0 for speckit and 5.0.0 for codex. These are clear in the requirements.md.

4. **Backwards compatibility**: Should we add a shim for `/ralph-specum:*` commands mapping to `/ralph-harness:*`? Recommendation: NO -- this is a clean break, and the project is establishing independence.

## File Change Summary

| Category | Count | Type |
|----------|-------|------|
| **Modify** | ~270 | String replacements across all file types |
| **Create** | 0 | No new files |
| **Delete** | 1 | `README.fork.md` |
| **Rename (directories)** | 4 | `ralph-specum`, `ralph-speckit`, `ralph-bmad-bridge`, `ralph-specum-codex` |
| **Rename (files)** | 3 | `smart-ralph` skill dirs (x2), settings file |
| **Total actionable files** | ~278+ | |
