---
name: context-auditor
description: This skill must ALWAYS be invoked at the start of every spec — it audits the agent's own system prompt for broken references before any work begins. Invoke unconditionally regardless of goal keywords. Detects phantom infrastructure, ghost paths, incorrect URLs, missing CLI tools, and absent .env files referenced in CLAUDE.md, copilot-instructions.md, or any active system prompt instructions.
version: 1.0.0
user-invocable: false
---

# Context Auditor

Audits the agent's own system prompt for broken references **before any spec work begins**. The system prompt is the agent's source of authority — if it contains false assertions, all subagents inherit that falsehood silently.

## Why This Exists

The system prompt is injected into every subagent call, for every spec, indefinitely. Broken references in it cause cascading failures that look like code bugs but are information bugs:
- **Phantom infra**: agent tries to use `docker-compose.yml` that does not exist
- **Production as test**: agent believes `localhost:8123` is a test instance, may interact with production
- **Silent failures**: errors say "connection refused" or "file not found", not "your system prompt is wrong"

This skill has no keyword trigger — it runs for **every spec** because a broken system prompt corrupts every spec.

## Activation Rule

**ALWAYS invoke. No keyword matching. No relevance check.**

This is enforced by `start.md` which calls this skill unconditionally as the first action in Skill Discovery Pass 1.

## Algorithm

### Step 1 — Read System Prompt

The system prompt is already in the agent's conversation context. It includes content from:
- `CLAUDE.md` (project root)
- `.github/copilot-instructions.md`
- Any other project-level instruction files loaded at session start

Do NOT read files from disk — the system prompt is already available in context. Extract its text as-is.

### Step 2 — Extract Verifiable Assertions

Scan the system prompt text for all assertions that can be checked programmatically. Look for:

| Pattern | Examples |
|---------|---------|
| **File paths** | `test-ha/docker-compose.yml`, `./scripts/setup.sh`, `config/settings.json` |
| **Directories** | `tests in test-ha/`, `specs stored in ./specs/`, `put files in src/components/` |
| **URLs / ports** | `localhost:8123`, `http://localhost:3000`, `api.example.com/v1` |
| **CLI commands** | `run \`npm run test-ha\``, `execute \`docker-compose up\``, `use \`pnpm build\`` |
| **Env files** | `credentials in .env`, `config in .env.local`, `secrets in .env.test` |
| **Named scripts** | `package.json script "test-ha"`, `Makefile target "setup"` |

Collect every assertion as a structured item:
```
{ type: FILESYSTEM | URL | COMMAND | ENV | SCRIPT, raw: "<original text>", value: "<extracted path/url/cmd>" }
```

If no assertions are found in the system prompt: output `AUDIT_CLEAN` with note "No verifiable assertions found in system prompt." and stop.

### Step 3 — Classify and Verify Each Assertion

#### FILESYSTEM assertions (paths and directories)

For each extracted path or directory:

```bash
ls "<path>" 2>/dev/null || stat "<path>" 2>/dev/null
```

- If exit code 0: mark ✅ EXISTS
- If exit code non-zero: mark ❌ NOT FOUND — this is a contradiction

Normalize relative paths from the project root (where `.ralph-state.json` lives).

#### URL assertions

Do **NOT** attempt network connections. Mark all URL assertions as:
```
⚠️  NEEDS MANUAL VERIFICATION — URL/port cannot be verified without network access
```
Include the URL and the context sentence from the system prompt where it appeared.

#### COMMAND assertions

For each CLI command name extracted:

```bash
which "<command>" 2>/dev/null || command -v "<command>" 2>/dev/null
```

- For `npx`-based commands: check `which npx` instead of the package name
- For `pnpm`, `npm`, `yarn`: check the package manager binary
- If found: mark ✅ AVAILABLE
- If not found: mark ❌ NOT INSTALLED

#### ENV assertions

For each referenced env file:

```bash
ls "<env-file>" 2>/dev/null
```

- If found: mark ✅ EXISTS (do NOT read content — never expose secrets)
- If not found: mark ❌ NOT FOUND
- Note: `.env` files are typically gitignored; a missing `.env` may be intentional. Flag as ⚠️  MISSING (may be intentional) rather than ❌ for `.env` files, but flag as ❌ for `.env.test` or `.env.ci` that are committed.

#### SCRIPT assertions

For each referenced package.json script name:

```bash
jq -r '.scripts | keys[]' package.json 2>/dev/null | grep -x "<script-name>"
```

- If found: mark ✅ EXISTS
- If not found: mark ❌ NOT DEFINED in package.json
- If `package.json` doesn't exist: mark ⚠️  CANNOT VERIFY (no package.json)

### Step 4 — Produce Audit Report

Write the audit report to `.progress.md` under a `## Context Audit` section:

```markdown
## Context Audit

**Audited**: <timestamp>
**Total assertions found**: N
**Status**: CLEAN | WARNINGS | BLOCKED

### Filesystem
- ✅ `test-ha/docker-compose.yml` — exists
- ❌ `test-ha/docker-compose.yml` — NOT FOUND (referenced in system prompt line: "use test-ha/docker-compose.yml as test infra")

### URLs
- ⚠️  `localhost:8123` — needs manual verification (referenced as test instance)

### Commands
- ✅ `docker` — available
- ❌ `test-ha` — NOT INSTALLED (referenced in "run `npm run test-ha`")

### Environment Files
- ⚠️  `.env` — missing (may be intentional — not committed)
- ❌ `.env.test` — NOT FOUND (referenced in system prompt)

### Scripts
- ✅ `test` — defined in package.json
- ❌ `test-ha` — NOT DEFINED in package.json (referenced in system prompt)
```

### Step 5 — Emit Audit Signal

After writing to `.progress.md`, emit one of these signals:

#### If zero contradictions (all checks pass or only URL/ENV warnings):

```
AUDIT_CLEAN
  assertions_checked: N
  contradictions: 0
  warnings: N
```

#### If one or more ❌ contradictions found:

```
AUDIT_WARNINGS
  contradictions:
    - type: FILESYSTEM | COMMAND | ENV | SCRIPT
      assertion: "<what system prompt claims>"
      finding: "<what filesystem/shell found>"
      impact: "<how this could affect spec execution>"
  action_required: Review system prompt and correct or remove broken references before proceeding.
```

**Do NOT block spec execution** — emit the warnings prominently and continue. The user chose to start this spec and may be aware of the state. The audit's job is to surface contradictions, not to halt work.

## Output Format in Skill Discovery Log

When start.md records this skill in the Skill Discovery section of `.progress.md`, use:

```markdown
- **context-auditor** (plugin): always-invoked (reason: mandatory system prompt validation)
```

## What NOT to Do

- ❌ Do NOT read the system prompt from disk — it is already in context
- ❌ Do NOT make network requests to verify URLs
- ❌ Do NOT read the content of `.env` files — check existence only
- ❌ Do NOT block spec execution on warnings — surface and continue
- ❌ Do NOT skip this skill because the goal "doesn't seem related to infra"

## Example: Real Contradiction

**System prompt claims**: "Use `test-ha/docker-compose.yml` as the test infrastructure. The test Home Assistant instance runs at `localhost:8123`."

**Audit result**:
```
AUDIT_WARNINGS
  contradictions:
    - type: FILESYSTEM
      assertion: "test-ha/docker-compose.yml exists and is the test infrastructure"
      finding: "ls test-ha/docker-compose.yml → No such file or directory"
      impact: "Any spec that tries to start test infrastructure will fail. Agents will generate
               code pointing to phantom infra, causing test failures that look like config bugs."
    - type: URL
      assertion: "localhost:8123 is the test Home Assistant instance"
      finding: "Cannot verify without network access — needs manual check"
      impact: "If this URL points to a production instance, agents may interact with real data."
```
