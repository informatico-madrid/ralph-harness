# E2E Anti-Patterns — Canonical Reference

> Used by: coordinator-pattern.md, task-planner.md, spec-executor.md, qa-engineer.md, mcp-playwright.skill.md, playwright-session.skill.md

This is the **single source of truth** for E2E anti-patterns. All other files
reference this list. When adding a new anti-pattern, add it here first, then
reference it from the relevant files.

## TypeScript Module System Anti-Patterns

> **Root cause**: LLMs have a strong CJS bias from training data. ESM is more recent
> and less represented, so agents generate `__dirname` patterns without checking
> `"type": "module"` in package.json.

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| Using `__dirname` in an ESM project without a polyfill | `__dirname` is not defined in ESM modules — causes `ReferenceError` at runtime | Use `fileURLToPath(import.meta.url)` |
| `path.dirname(new URL(import.meta.url).pathname)` | On Windows, `pathname` returns `/C:/path/file.ts` with a leading `/` before the drive letter, breaking the path | Use `fileURLToPath(import.meta.url)` — it handles Windows paths correctly |
| Using `import.meta.url` in a CJS project | `import.meta` is not available in CommonJS — causes `SyntaxError` | Use `__dirname` directly |
| Generating infra files without checking package.json first | Both `global.setup.ts` and `global.teardown.ts` get the same wrong pattern in the same session | Run `jq -r '.type // "commonjs"' package.json` before writing any infrastructure file |
| `process.cwd()` for resolving paths in Playwright config | `cwd()` changes depending on where `npx playwright` is invoked — paths are unstable | Use `fileURLToPath(import.meta.url)` + `path.dirname` for stable file-relative paths |

**ESM canonical pattern** (when `package.json` has `"type": "module"`):
```typescript
import { fileURLToPath } from 'url';
import path from 'path';

const __filename = fileURLToPath(import.meta.url); // always correct on all platforms
const __dirname = path.dirname(__filename);
```

**CJS pattern** (default, when `package.json` has no `"type"` or `"type": "commonjs"`):
```typescript
// __dirname is available natively — no polyfill needed
const configPath = path.join(__dirname, 'playwright/.auth/server-info.json');
```

## Navigation Anti-Patterns

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| `page.goto('/internal/route')` for internal app routes | Bypasses client-side routing and auth state; causes 404, blank pages, or TimeoutErrors | Navigate via UI elements: sidebar clicks, menu items, links |
| Navigating to URLs with `auth_callback`, `code=`, or `state=` params | OAuth tokens are already consumed by the setup process; browser gets auth rejection | Use `new URL(url).origin` to extract the base URL |
| Duplicate `waitForURL` calls for the same expected URL | Dead code; sign of uncertainty about page state | One `waitForURL` per expected navigation state |

**Exception**: `page.goto()` to the **base URL** (app root) is correct for initial navigation and auth flows.

## Selector Anti-Patterns

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| Hand-written CSS selectors or XPath | Break across app versions, fragile to DOM restructuring | Use `getByRole` > `getByTestId` > `browser_generate_locator` |
| Hardcoded `entity_id`, dynamic IDs, or session-specific values | Unstable across test instances and environments | Use semantic selectors: `getByRole`, `getByLabel`, `getByTestId` |
| Inventing selectors from memory without verification | Selector may not match actual DOM; causes silent failures | Read `ui-map.local.md` or use `browser_generate_locator` from live page |
| Shadow DOM traversal by depth (`>>>` chains) | Fragile to DOM restructuring; breaks when HA updates | Use `getByTestId` or `getByRole` (Playwright traverses shadow DOM automatically) |

## Timing Anti-Patterns

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| `waitForTimeout(N)` | Flaky: too short = intermittent failures, too long = slow tests | Use condition-based waits: `waitForSelector`, `waitForURL`, `waitForResponse` |
| No stable state check after navigation | Actions on loading pages cause element-not-found errors | Always `browser_snapshot` + loading indicator check after navigation |

## Auth Anti-Patterns

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| Reusing consumed OAuth/auth callback tokens | Token already used by setup infrastructure; browser gets auth rejection | Use the base URL; let the app handle auth flow from scratch |
| `goto()` to auth-protected routes without established session | App redirects to login or returns 401; test hangs on unexpected state | Complete auth flow first, then navigate via UI |
| Silently re-authenticating mid-flow | Masks auth expiry bugs; test passes but app has a real auth issue | Surface auth expiry as `VERIFICATION_FAIL` |

## Test Quality Anti-Patterns

| Anti-Pattern | Why it fails | Correct pattern |
|---|---|---|
| Tests that only verify `toHaveBeenCalled` with no state/value assertions | Confirms function was called, not that it produced correct results | Assert on real return values and state changes |
| `describe.skip` / `it.skip` without GitHub issue reference | Silently disables tests; failures go unnoticed | `it.skip('TODO: #<issue> — <reason>', ...)` |
| Empty test bodies `it('does X', () => {})` | Always passes, tests nothing | Write real assertions or remove the test |
| Mocking own business logic to make tests pass | Tests verify mocks, not real code | Only mock what the architect marked as mockable in Test Strategy |

## How to Reference This File

In delegation prompts and task descriptions, reference this file as:
```
See: ${CLAUDE_PLUGIN_ROOT}/references/e2e-anti-patterns.md
```

In skill files and agent prompts, use the relative path:
```
See: references/e2e-anti-patterns.md
```
