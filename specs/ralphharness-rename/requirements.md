# Requirements: RalphHarness Rename

## Goal
Rename el proyecto de Smart Ralph (ralph-specum) a RalphHarness, eliminando todas las referencias a tzachbon/smart-ralph y estableciendo a `informatico-madrid` como propietario independiente.

## User Stories

### US-1: Plugin Principal Funciona con Nuevo Nombre
**Como un** usuario de Claude Code
**Quiero que** el plugin principal se llame `ralphharness` y cargue correctamente tras el rename
**Para que** todos los comandos `/ralphharness:*` funcionen sin errores

**Acceptance Criteria:**
- [ ] AC-1.1: El directorio `plugins/ralph-specum/` se renombra a `plugins/ralphharness/` usando `git mv`
- [ ] AC-1.2: `plugins/ralphharness/.claude-plugin/plugin.json` tiene `name: "ralphharness"`
- [ ] AC-1.3: `plugins/ralphharness/.claude-plugin/plugin.json` tiene `author.name: "informatico-madrid"`
- [ ] AC-1.4: `plugins/ralphharness/.claude-plugin/plugin.json` tiene `version: "5.0.0"`
- [ ] AC-1.5: `.claude/settings.json` actualiza `enabledPlugins.ralph-specum@smart-ralph` a `enabledPlugins.ralphharness@informatico-madrid` (o equivalente)
- [ ] AC-1.6: `jq -r '.name' plugins/ralphharness/.claude-plugin/plugin.json` retorna `"ralphharness"`
- [ ] AC-1.7: El plugin carga en Claude Code sin errores
- [ ] AC-1.8: `.claude/settings.json` no contiene `"ralph-specum"` en `enabledPlugins`
- [ ] AC-1.9: `jq -r '.enabledPlugins."ralph-specum@smart-ralph"' .claude/settings.json` retorna `null` (clave antigua eliminada)
- [ ] AC-1.10: `jq -r '.enabledPlugins."ralphharness@informatico-madrid"' .claude/settings.json` retorna `true` (clave nueva existe)

### US-2: Plugin Speckit Renombrado
**Como un** usuario que usa la metodología spec-kit
**Quiero que** el plugin se llame `ralphharness-speckit`
**Para que** tenga consistencia con el brand RalphHarness

**Acceptance Criteria:**
- [ ] AC-2.1: `plugins/ralphharness-speckit/.claude-plugin/plugin.json` tiene `name: "ralphharness-speckit"`
- [ ] AC-2.2: `author.name` actualizado a `informatico-madrid`
- [ ] AC-2.3: `version` actualizado a `1.0.0`

### US-3: Plugin BMAD Bridge Actualizado
**Como un** usuario que integra BMAD con Ralph
**Quiero que** el plugin BMAD bridge tenga al author `informatico-madrid`
**Para que** refleje la nueva propiedad del proyecto

**Acceptance Criteria:**
- [ ] AC-3.1: `plugins/ralphharness-bmad-bridge/.claude-plugin/plugin.json` tiene `author.name: "informatico-madrid"`
- [ ] AC-3.2: La descripción del plugin no menciona "Smart Ralph" como propiedad externa

### US-4: Marketplace.json Actualizado
**Como un** instalador del plugin
**Quiero que** el marketplace.json refleje la nueva propiedad
**Para que** la instalación y descubrimiento funcionen correctamente

**Acceptance Criteria:**
- [ ] AC-4.1: `name` en marketplace.json cambia de `"smart-ralph"` a `"ralphharness"`
- [ ] AC-4.2: `owner.name` cambia de `"tzachbon"` a `"informatico-madrid"`
- [ ] AC-4.3: Todos los `source` paths apuntan a los nuevos nombres de directorio
- [ ] AC-4.4: Todos los `author.name` en entradas de plugins cambian a `informatico-madrid`
- [ ] AC-4.5: `jq -r '.owner.name' .claude-plugin/marketplace.json` retorna `"informatico-madrid"`

### US-5: Prefijo de Comandos Actualizado
**Como un** usuario interactuando con Claude Code
**Quiero que** todos los comandos usen el prefijo `/ralphharness:` en lugar de `/ralph-specum:`
**Para que** la experiencia de uso refleje el nuevo nombre

**Acceptance Criteria:**
- [ ] AC-5.1: Todos los comandos en `plugins/ralphharness/commands/*.md` referencian `/ralphharness:` en lugar de `/ralph-specum:`
- [ ] AC-5.2: Las invocaciones de skill `ralph-specum:<name>` cambian a `ralphharness:<name>` en todos los archivos (agents, commands, templates, references, skills)
- [ ] AC-5.3: `grep "/ralphharness:" plugins/ralphharness/commands/*.md` retorna > 0 resultados
- [ ] AC-5.4: `grep -rin "ralph-specum:" plugins/ralphharness/` retorna 0 resultados

### US-6: Referencias a tzachbon Eliminadas
**Como un** maintainer del proyecto
**Quiero que** no queden referencias a `tzachbon` en los archivos en scope
**Para que** el proyecto se perciba como independiente

**Acceptance Criteria:**
- [ ] AC-6.1: `grep -r "tzachbon" .claude-plugin/ plugins/ README.md CLAUDE.md CONTRIBUTING.md LICENSE .github/ 2>/dev/null` retorna 0 resultados
- [ ] AC-6.2: URL de GitHub en `.github/ISSUE_TEMPLATE/config.yml` actualizada
- [ ] AC-6.3: `plugins/ralphharness/commands/feedback.md` URL de issues actualizada (o eliminada)
- [ ] AC-6.4: `LICENSE` copyright actualizado a `"RalphHarness Project Authors"`

### US-7: Documentación Principal Reescrita
**Como un** nuevo usuario descubriendo el proyecto
**Quiero que** README.md, CLAUDE.md y demás docs hablen de RalphHarness
**Para que** no haya confusiones sobre el nombre y propiedad del proyecto

**Acceptance Criteria:**
- [ ] AC-7.1: `README.md` menciona "RalphHarness" en el título y throughout
- [ ] AC-7.2: `CLAUDE.md` actualiza Overview, Plugin Structure, y comandos de ejemplo
- [ ] AC-7.3: `README.fork.md` eliminada
- [ ] AC-7.4: `CONTRIBUTING.md` URLs actualizadas
- [ ] AC-7.5: `TROUBLESHOOTING.md` URLs de comandos actualizadas

### US-8: Scripts de Hook Actualizados
**Como un** usuario que ejecuta specs
**Quiero que** los scripts de hook funcionen con los nuevos nombres
**Para que** no haya errores durante la ejecución

**Acceptance Criteria:**
- [ ] AC-8.1: `plugins/ralphharness/hooks/scripts/` actualiza `[ralph-specum]` a `[ralphharness]` en log prefixes
- [ ] AC-8.2: Ruta `.claude/ralph-specum.local.md` cambia a `.claude/ralphharness.local.md` en todos los scripts (stop-watcher, load-spec-context, path-resolver, test-* files)
- [ ] AC-8.3: `plugins/ralphharness/hooks/scripts/checkpoint.sh` actualiza commit message patterns
- [ ] AC-8.4: `plugins/ralphharness/hooks/scripts/update-spec-index.sh` actualiza referencias a comandos
- [ ] AC-8.5: `plugins/ralphharness/hooks/hooks.json` actualiza `"Ralph Specum"` a `"RalphHarness"` en description (si aplica)
- [ ] AC-8.6: `plugins/ralphharness-codex/hooks/hooks.json` actualiza `"Ralph Specum"` a `"RalphHarness"` en description (si aplica)

### US-9: Archivos de Estado y Configuración Renombrados
**Como un** usuario con specs existentes
**Quiero que** los archivos de configuración locales usen el nuevo nombre
**Para que** las configuraciones persistan correctamente

**Acceptance Criteria:**
- [ ] AC-9.1: `.claude/ralph-specum.local.md` renombrado a `.claude/ralphharness.local.md`
- [ ] AC-9.2: Todas las referencias en hook scripts apuntan al nuevo nombre de archivo
- [ ] AC-9.3: Archivos de estado `.ralph-state.json` y `.ralph-progress.md` mantienen nombres genéricos (no necesitan cambio)

### US-10: CI/CD y GitHub Integration Actualizados
**Como un** maintainer que confía en las CI pipelines
**Quiero que** los workflows de GitHub y templates de issues usen los nuevos nombres
**Para que** las PRs trigger tests correctamente y los issues muestren comandos correctos

**Acceptance Criteria:**
- [ ] AC-10.1: `.github/workflows/bats-tests.yml` actualiza paths de `plugins/ralph-specum-codex/`
- [ ] AC-10.2: `.github/workflows/codex-version-check.yml` actualiza paths y PR names
- [ ] AC-10.3: `.github/ISSUE_TEMPLATE/bug_report.yml` actualiza comandos de ejemplo
- [ ] AC-10.4: `.github/ISSUE_TEMPLATE/feature_request.yml` actualiza comandos de ejemplo
- [ ] AC-10.5: `.agents/plugins/marketplace.json` actualizado con nuevos nombres de directorio

### US-11: Archivos de Skill Renombrados
**Como un** usuario que usa skills especializadas
**Quiero que** las skills se invoquen con el prefijo `ralphharness:`
**Para que** la experiencia sea consistente con el nuevo brand

**Acceptance Criteria:**
- [ ] AC-11.1: `plugins/ralphharness/skills/smart-ralph/` renombrado a `plugins/ralphharness/skills/ralphharness/`
- [ ] AC-11.2: `plugins/ralphharness/skills/*/SKILL.md` actualiza skill name y referencias
- [ ] AC-11.3: Agent files (`spec-executor.md`, `task-planner.md`, `qa-engineer.md`) actualizan invocaciones de skill
- [ ] AC-11.4: Template files actualizan invocaciones `ralph-specum:<name>` → `ralphharness:<name>`

### US-12: Pruebas Actualizadas
**Como un** developer que ejecuta tests
**Quiero que** los tests pasen tras el rename
**Para que** tener confianza en que el proyecto funciona

**Acceptance Criteria:**
- [ ] AC-12.1: `tests/codex-plugin.bats` actualiza referencias a skill names y paths
- [ ] AC-12.2: `tests/codex-platform.bats` actualiza ~50 referencias hardcodeadas
- [ ] AC-12.3: `tests/codex-platform-scripts.bats` actualiza paths de codex
- [ ] AC-12.4: `tests/stop-hook.bats` actualiza log prefix `[ralph-specum]` → `[ralphharness]`
- [ ] AC-12.5: `tests/interview-framework.bats` actualiza paths de plugin
- [ ] AC-12.6: `tests/helpers/version-sync.sh` actualiza lectura de versiones de manifests
- [ ] AC-12.7: `bats tests/*.bats` pasan sin errores
- [ ] AC-12.8: Grep final post-rename confirma 0 referencias a `ralph-specum`, `Ralph Specum`, `tzachbon`, `smart-ralph` en archivos in-scope:
  ```bash
  grep -rin "ralph-specum\|Ralph Specum\|tzachbon\|smart-ralph" . \
    --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' \
    --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
    --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=research --exclude-dir=.roo --exclude-dir=.cursor \
    --exclude-dir=.gemini --exclude-dir=.qwen --exclude-dir=.git | wc -l
  ```
  retorna `0`

### US-13: Plugin Codex Renombrado
**Como un** usuario de Codex que usa Ralph
**Quiero que** el plugin `ralph-specum-codex` se renombre a `ralphharness-codex`
**Para que** sea parte consistente del nuevo brand RalphHarness

**Acceptance Criteria:**
- [ ] AC-13.1: Directorio `plugins/ralph-specum-codex/` renombrado a `plugins/ralphharness-codex/` con `git mv`
- [ ] AC-13.2: `plugins/ralphharness-codex/.codex-plugin/plugin.json` actualiza name, author, version
- [ ] AC-13.3: `plugins/ralphharness-codex/` grep-sed de `ralph-specum` → `ralphharness`
- [ ] AC-13.4: `.claude-plugin/marketplace.json` actualiza source path de codex a nuevo directorio
- [ ] AC-13.5: `.agents/plugins/marketplace.json` actualiza source path de codex
- [ ] AC-13.6: `.github/workflows/bats-tests.yml` actualiza paths de codex
- [ ] AC-13.7: `.github/workflows/codex-version-check.yml` actualiza paths y PR names
- [ ] AC-13.8: Skills bajo `platforms/codex/skills/ralph-specum*` NO se tocan (out of scope, separate location)
      — CRITICAL DISTINCTION: `platforms/codex/skills/` directories are OUT of scope, BUT
        `plugins/ralphharness-codex/skills/` directories ARE in scope (tasks 1.4-1.7, 2.14)

### US-14: Configuraciones Externas Actualizadas
**Como un** usuario que tiene configuraciones BMAD, gito, y otras herramientas
**Quiero que** los archivos de configuración externos reflejen el nuevo nombre
**Para que** la integración con otras herramientas no se rompa

**Acceptance Criteria:**
- [ ] AC-14.1: `_bmad/bmm/config.yaml` actualizado con nuevos nombres de plugin
- [ ] AC-14.2: `_bmad/config.toml` actualizado con nuevos nombres
- [ ] AC-14.3: `.gito/config.toml` actualizado con nuevos nombres
- [ ] AC-14.4: `.claude/skills/smart-ralph-review/SKILL.md` actualiza comandos `/ralph-specum:*` → `/ralphharness:*`

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | Rename directorio `plugins/ralph-specum/` a `plugins/ralphharness/` con `git mv` | High | `git log --follow plugins/ralphharness/` muestra historial |
| FR-2 | Rename directorio `plugins/ralph-speckit/` a `plugins/ralphharness-speckit/` con `git mv` | High | Directorio existe con nuevo nombre |
| FR-3 | Actualizar plugin.json principal: name, author, version | High | jq validates new values |
| FR-4 | Actualizar plugin.json speckit: name, author, version | High | jq validates new values |
| FR-5 | Actualizar plugin.json bmad-bridge: author | High | jq validates author |
| FR-6 | Actualizar .claude-plugin/marketplace.json: name, owner, sources, authors | High | All jq checks pass |
| FR-7 | grep-sed `ralph-specum` → `ralphharness` en archivos in-scope | High | 0 resultados en grep |
| FR-8 | grep-sed `ralph-speckit` → `ralphharness-speckit` en archivos in-scope | High | 0 resultados en grep |
| FR-9 | grep-sed `tzachbon` → `informatico-madrid` en archivos in-scope | High | 0 resultados en grep |
| FR-10 | grep-sed `smart-ralph` → `ralphharness` en archivos in-scope | High | 0 resultados en grep |
| FR-11 | grep-sed `ralph-specum:` → `ralphharness:` en archivos in-scope | High | 0 resultados en grep |
| FR-12 | Actualizar ruta `ralph-specum.local.md` → `ralphharness.local.md` en hook scripts | High | grep returns 0 |
| FR-13 | Rename `.claude/ralph-specum.local.md` a `.claude/ralphharness.local.md` | High | File exists with new name |
| FR-14 | Rename skill dir `skills/smart-ralph/` → `skills/ralphharness/` | Medium | Directory renamed, SKILL.md updated |
| FR-15 | Actualizar `.claude/settings.json` enabledPlugins entry | Critical | Plugin loads without errors |
| FR-16 | Actualizar `.agents/plugins/marketplace.json` | Medium | Paths point to new directories |
| FR-17 | Actualizar GitHub workflows paths | Medium | `git grep -l "ralph-specum-codex" .github/workflows/` returns 0 |
| FR-18 | Actualizar GitHub issue templates | Medium | Command examples updated |
| FR-19 | Reescribir README.md con nuevo brand | High | Contains "RalphHarness", no "smart-ralph" |
| FR-20 | Reescribir CLAUDE.md con nuevo brand | High | All references updated |
| FR-21 | Eliminar README.fork.md | High | File does not exist |
| FR-22 | Actualizar LICENSE con nuevo copyright | Medium | "RalphHarness Project Authors" |
| FR-23 | Actualizar CONTRIBUTING.md URLs | Medium | GitHub URLs point to new owner |
| FR-24 | Actualizar TROUBLESHOOTING.md | Medium | Command examples updated |
| FR-25 | Actualizar `_bmad/bmm/config.yaml` | Medium | Plugin names updated |
| FR-26 | Actualizar `_bmad/config.toml` | Medium | Plugin names updated |
| FR-27 | Actualizar `.gito/config.toml` | Low | References updated |
| FR-28 | Actualizar `.claude/skills/smart-ralph-review/SKILL.md` | Medium | Commands updated |
| FR-29 | Actualizar tests/*.bats hardcodeadas | High | All tests pass |
| FR-30 | Actualizar specs/.index/ auto-generated files | Low | Index regenerates correctly |
| FR-31 | Actualizar `plugins/ralphharness-codex/` contenido (65 files) | High | grep-sed `ralph-specum` → `ralphharness` |
| FR-32 | Actualizar GitHub workflows paths para codex | Medium | CI triggers use new paths |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Git History | `git log` continuity | `git log --follow` preserves history for all renamed directories |
| NFR-2 | Plugin Load Time | Time for Claude Code to load plugin | < 2 seconds after rename |
| NFR-3 | Test Pass Rate | bats test suite | 100% tests pass after rename |
| NFR-4 | Reference Completeness | grep coverage | 0 matches for "ralph-specum", "tzachbon", "smart-ralph" in in-scope files |

## Glossary
- **RalphHarness**: Nuevo nombre del proyecto independiente, marca `informatico-madrid`
- **ralph-specum**: Nombre actual del plugin principal (a eliminar)
- **smart-ralph**: Nombre antiguo del repositorio propietario (a eliminar)
- **tzachbon**: Owner anterior del repositorio (a eliminar)
- **informatico-madrid**: Nuevo owner/maintainer del proyecto
- **Codex skills**: Skills bajo `platforms/codex/skills/` — OUT de scope (se dejan con nombre actual)
- **User specs**: Archivos bajo `specs/**/*.md` y `specs/**/*.progress.md` — HISTÓRICOS (no se actualizan)
- **State files**: `.ralph-state.json`, `.ralph-progress.md` — nombres genéricos, no necesitan cambio

## Out of Scope
- **Codex skills** (`platforms/codex/skills/ralph-specum*`) — permanecen con nombre actual
- **Specs de usuario** (`specs/**/*.md`, `specs/**/*.progress.md`) — históricos, contienen PR/issue URLs que cambian
- **BMAD output auto-generated** (`_bmad-output/**/*.md`) — artifacts generados automáticamente
- **Historical docs** (`docs/brainstormmejora/`, `docs/plans/`, `research/`, `plans/*.md`) — contexto histórico
- **Active docs NOT excluded** — `docs/ARCHITECTURE.md`, `docs/FORENSIC-COMBINED.md`, `docs/TESTING-SYSTEM.md` ARE in scope and must be renamed. These contain "Ralph Specum" title-case that was missed by lowercase-only grep patterns.
- **Review reports** (`_bmad-output/reviews/**`) — revisiones históricas
- **Version bump exact mapping** — epic dice 5.0.0 para ralph-specum principal pero no especifica versiones para plugins derivados (speckit, bmad-bridge, codex)
- **IDE config directories** (`.roo/`, `.cursor/`, `.gemini/`, `.qwen/`) — contienen referencias que deben ser excluidas de verificaciones grep (no requieren rename)

## Dependencies
- `.claude/settings.json` debe actualizarse SIMULTÁNEAMENTE con el rename del directorio, o el plugin no cargará
- `plugins/ralphharness-codex/` (antes `plugins/ralph-specum-codex/`) es un plugin completo (60+ archivos) que coexiste con el plugin principal; las workflows de CI lo referencian
- `specs/.index/` es auto-generado — necesita regeneración post-rename (no requiere cambios manuales)
- `.agents/plugins/marketplace.json` es un sistema paralelo a `.claude-plugin/marketplace.json` — si se actualiza uno, se debe actualizar el otro

## Success Criteria
- [ ] Plugin carga en Claude Code sin errores
- [ ] `/ralphharness:help` responde correctamente
- [ ] `/ralphharness:new test-spec` crea un spec funcional
- [ ] `bats tests/*.bats` pasa todos los tests
- [ ] `git log --follow plugins/ralphharness/` muestra historial completo
- [ ] 0 referencias a `ralph-specum`, `Ralph Specum`, `tzachbon`, `smart-ralph` en archivos in-scope (verify: `grep -rin "ralph-specum\|Ralph Specum\|tzachbon\|smart-ralph" . --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=.git --exclude-dir=docs/brainstormmejora --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=research --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen | wc -l` returns 0)
- [ ] `README.md` es coherente con nuevo brand RalphHarness
- [ ] `marketplace.json` actualizado en ambos sistemas (`.claude-plugin/` y `.agents/plugins/`)
- [ ] Todas las 4 direcciones de directorio renombradas con `git mv` e historial preservado
- [ ] Configs BMAD actualizados (`_bmad/` directory)

## Risk Register

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| `.claude/settings.json` no actualizado → plugin no carga | CRITICAL | Medium | Actualizar PRIMERO, antes de renombrar directorio |
| grep-sed incomplete → referencias residuales | HIGH | Medium | Usar sed script con todas las sustituciones; verificar con grep final |
| Renombrar `plugins/ralph-specum-codex/` sin actualizar workflows → CI rota | HIGH | Medium | Actualizar workflows SIMULTÁNEAMENTE con rename de directorio |
| Referencias en test files hardcodeadas → tests fallan | HIGH | High | Actualizar todos los files de test sistemáticamente |
| `smart-ralph` skill directory no renombrado → inconsistencia | MEDIUM | Low | Incluir en sed global `smart-ralph` → `ralphharness` |
| `.agents/plugins/marketplace.json` olvidado → silencioso | MEDIUM | Medium | Listar explícitamente en checklist de rename |
| User specs con PR URLs antiguas → confusión | LOW | Low | Documentar explícitamente que son históricos |

## Verification Contract

**Project type**: `library`

**Entry points**:
- `plugins/ralphharness/.claude-plugin/plugin.json` — manifest principal
- `plugins/ralphharness/commands/*.md` — 16 command files
- `plugins/ralphharness/hooks/scripts/*.sh` — 8+ hook scripts
- `plugins/ralphharness/skills/*/SKILL.md` — 17 skill files
- `plugins/ralphharness/agents/*.md` — 10 agent files
- `plugins/ralphharness/templates/*` — 15+ template files
- `.claude/settings.json` — plugin enablement
- `.claude-plugin/marketplace.json` — marketplace registry
- `.agents/plugins/marketplace.json` — parallel registry
- `README.md`, `CLAUDE.md` — documentation
- `.github/workflows/*.yml` — CI pipelines
- `tests/*.bats` — test suite

**Observable signals**:
- PASS: `claude --plugin-dir plugins/ralphharness` carga sin error
- PASS: `jq -r '.name' plugins/ralphharness/.claude-plugin/plugin.json` = `"ralphharness"`
- PASS: `jq -r '.version' plugins/ralphharness/.claude-plugin/plugin.json` = `"5.0.0"`
- PASS: `jq -r '.owner.name' .claude-plugin/marketplace.json` = `"informatico-madrid"`
- PASS: `jq -r '.enabledPlugins."ralphharness@informatico-madrid"' .claude/settings.json` = `true`
- PASS: Final grep (all in-scope dirs):
  ```bash
  grep -rin "ralph-specum\|Ralph Specum\|tzachbon\|smart-ralph" . \
    --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' \
    --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora \
    --exclude-dir=docs/plans --exclude-dir=plans --exclude-dir=research \
    --exclude-dir=.roo --exclude-dir=.cursor --exclude-dir=.gemini --exclude-dir=.qwen --exclude-dir=.git
  ```
  retorna 0 lineas
- PASS: `jq -r '.enabledPlugins."ralph-specum@smart-ralph"' .claude/settings.json` = `null`
- PASS: `git log --follow plugins/ralphharness/ | head -3` muestra commits existentes
- PASS: `grep -r "informatico-madrid" .claude-plugin/marketplace.json plugins/ralphharness/.claude-plugin/plugin.json | wc -l` > 0
- FAIL: Plugin no carga → error en CLI output de Claude Code
- FAIL: Comandos `/ralph-specum:` aún responden → referencia obsoleta
- FAIL: `README.fork.md` existe → cleanup incompleto
- FAIL: `jq -r '.enabledPlugins."ralph-specum@smart-ralph"' .claude/settings.json` != `null` → clave antigua persiste

**Hard invariants**:
- Auth/session: N/A (plugin local, no auth)
- Permissions: N/A
- Adjacent flows: Los specs existentes (`.ralph-state.json`) deben seguir funcionando — no cambiar nombres de state files
- Git history: `git log --follow` debe preservar historial de directorios renombrados

**Seed data**:
- `.claude/settings.json` con `enabledPlugins` entries
- At least one existing spec in `specs/` with `.ralph-state.json`
- `plugins/ralph-specum/` directory exists before rename
- Git repo initialized with commits (for `git mv` verification)

**Dependency map**:
- `.claude/settings.json` ↔ `plugins/ralphharness/` — plugin enablement
- `.claude-plugin/marketplace.json` ↔ `plugins/ralphharness/` — discovery
- `.agents/plugins/marketplace.json` ↔ `plugins/ralphharness-codex/` — parallel discovery
- `.github/workflows/` ↔ `plugins/ralphharness-codex/` — CI triggers
- `specs/.index/` ↔ `plugins/ralphharness/` — auto-generated, needs regeneration

**Escalate if**:
- `.claude/settings.json` format changes require human decision (backup before modification)
- CI pipeline breaks post-rename — investigate before continuing
- Any `git mv` fails due to uncommitted changes — pause and clean working tree
- Version bump decisions for speckit (1.0.0 vs 0.6.0) and codex (5.0.0 vs 4.11.0) need clarification

## Version Decisions (Resolved)
- `ralphharness-speckit` version: `1.0.0` (AC-2.3)
- `ralphharness-codex` version: `5.0.0` (task 2.5)
- `settings.json` key: `ralphharness@informatico-madrid` (AC-1.10)
- Codex rename: `plugins/ralph-specum-codex/` → `plugins/ralphharness-codex/` (tasks 1.3, 2.5, 13.x)
- State file naming: `.ralphharness-state.json` NOT intentional — state file naming follows plugin name convention (AC-1.5)

## Next Steps
1. Aprobación de requirements.md por el user
2. Ejecutar script de rename en fase de implementación (task-planner breaks into tasks)
3. Verify con grep final: `grep -rin "ralph-specum\|Ralph Specum\|tzachbon\|smart-ralph" . --include='*.md' --include='*.json' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.toml' --exclude-dir=specs --exclude-dir=_bmad-output --exclude-dir=docs/brainstormmejora --exclude-dir=docs/plans --exclude-dir=plans`
4. Ejecutar `bats tests/*.bats` para confirmar tests pasan
5. Regenerar `specs/.index/` post-rename

<!-- Changed: Fixed adversarial review findings — added AC-1.9/AC-1.10 for settings.json verification, AC-12.8 for final grep, expanded observable signals, appended learnings to progress.md -->
