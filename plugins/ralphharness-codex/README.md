# RalphHarness for Codex

Spec-driven development plugin for OpenAI Codex. Full parity with the Claude Code ralphharness plugin.

Transforms feature requests into structured specs (research, requirements, design, tasks) then executes them task-by-task with fresh context per task.

## Prerequisites

- [OpenAI Codex CLI](https://github.com/openai/codex) installed: `npm install -g @openai/codex`
- A ChatGPT account (Plus, Pro, Team, Edu, or Enterprise) or an OpenAI API key

## Quick Start

After installing (see below), run:

```
$ralphharness-start my-feature "Build a user authentication system"
```

This starts the spec-driven workflow: research, requirements, design, tasks, then implementation.

## Installation

Pick one of the two methods below.

<details>
<summary>Personal install (available in every project)</summary>

Run these commands from any directory. They clone the repo to a temp folder, copy the plugin to your Codex plugins directory, and clean up.

```bash
# 1. Clone the Smart Ralph repo
git clone https://github.com/informatico-madrid/RalphHarness.git /tmp/RalphHarness

# 2. Copy the Codex plugin into your personal plugins directory
mkdir -p ~/.codex/plugins
cp -R /tmp/RalphHarness/plugins/ralphharness-codex ~/.codex/plugins/ralphharness-codex

# 3. Create a marketplace entry so Codex can discover the plugin
mkdir -p ~/.agents/plugins
cat > ~/.agents/plugins/marketplace.json << 'EOF'
{
  "name": "RalphHarness",
  "plugins": [{
    "name": "ralphharness",
    "source": {"source": "local", "path": "~/.codex/plugins/ralphharness-codex"},
    "policy": {"installation": "AVAILABLE"},
    "category": "Productivity"
  }]
}
EOF

# 4. Clean up
rm -rf /tmp/RalphHarness
```

</details>

<details>
<summary>Per-project install (one repo only)</summary>

Run these commands from your project root directory (the repo where you want to use Ralph).

```bash
# 1. Clone the Smart Ralph repo
git clone https://github.com/informatico-madrid/RalphHarness.git /tmp/RalphHarness

# 2. Copy the Codex plugin into your project
mkdir -p ./plugins
cp -R /tmp/RalphHarness/plugins/ralphharness-codex ./plugins/ralphharness-codex

# 3. Create a marketplace entry in your project
mkdir -p ./.agents/plugins
cat > ./.agents/plugins/marketplace.json << 'EOF'
{
  "name": "RalphHarness",
  "plugins": [{
    "name": "ralphharness",
    "source": {"source": "local", "path": "./plugins/ralphharness-codex"},
    "policy": {"installation": "AVAILABLE"},
    "category": "Productivity"
  }]
}
EOF

# 4. Clean up
rm -rf /tmp/RalphHarness
```

</details>

After either method: restart Codex, open the plugin directory, and install `ralphharness`.

### Enable hooks (recommended)

The Stop hook auto-advances through tasks during execution. Add to `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

Without hooks, you run `$ralphharness-implement` once per task manually (see `references/workflow.md` for the fallback workflow).

## Updating

Pull the latest version by re-running the install steps. These commands work from any directory.

```bash
# Pull latest and overwrite
rm -rf /tmp/RalphHarness
git clone https://github.com/informatico-madrid/RalphHarness.git /tmp/RalphHarness
cp -R /tmp/RalphHarness/plugins/ralphharness-codex ~/.codex/plugins/ralphharness-codex
rm -rf /tmp/RalphHarness
# Restart Codex
```

For per-project installs, replace `~/.codex/plugins/ralphharness-codex` with `./plugins/ralphharness-codex` (run from your project root).

Check your version in `.codex-plugin/plugin.json`. Compare against the [latest release](https://github.com/informatico-madrid/RalphHarness/releases).

## Agent configs (optional)

Copy templates from `agent-configs/*.toml.template` into your `.codex/config.toml` for specialized subagents. See `agent-configs/README.md`.

## Skills Reference

| Skill | Description |
|-------|-------------|
| `$ralphharness` | Primary entry point, routing, bootstrap |
| `$ralphharness-start` | Smart start (new or resume spec) |
| `$ralphharness-research` | Parallel research phase |
| `$ralphharness-requirements` | Requirements generation |
| `$ralphharness-design` | Technical design |
| `$ralphharness-tasks` | Task breakdown (fine/coarse) |
| `$ralphharness-implement` | Task execution loop |
| `$ralphharness-status` | Show all specs and progress |
| `$ralphharness-switch` | Switch active spec |
| `$ralphharness-cancel` | Cancel and cleanup |
| `$ralphharness-triage` | Epic decomposition |
| `$ralphharness-index` | Codebase indexing |
| `$ralphharness-refactor` | Spec file updates |
| `$ralphharness-feedback` | Submit feedback/bugs |
| `$ralphharness-help` | Show help and workflow guide |
| `$ralphharness-rollback` | Restore to git checkpoint |

## Hooks

The Stop hook (`hooks/stop-watcher.sh`) enables automatic task-by-task execution. It reads `.ralph-state.json` and outputs `{"decision":"block","reason":"Continue to task N/M"}` to keep the execution loop running.

Requires `[features] codex_hooks = true` in config.toml. See `references/workflow.md` for the manual fallback when hooks are disabled.

<details>
<summary>Migration from old skills (platforms/codex/)</summary>

If you previously installed RalphHarness skills from `platforms/codex/skills/` via `$skill-installer`:

**Step 1: Remove old skills**

```bash
rm -rf ~/.codex/skills/ralphharness*
```

**Step 2: Install the new plugin**

Follow the Installation steps above.

**Step 3: Update references**

Update any scripts, docs, or automation that reference `platforms/codex/` paths to use `plugins/ralphharness-codex/` instead.

**Step 4: Verify**

Run `$ralphharness-status` to confirm the plugin is active and can find your specs.

</details>

## Version

Check `.codex-plugin/plugin.json` for the current version.
