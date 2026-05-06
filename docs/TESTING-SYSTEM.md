# RalphHarness — Análisis Exhaustivo del Sistema de Testing

## Índice

1. [Flujo Completo de Decisión](#1-flujo-completo-de-decisión)
2. [Cómo se Diseñan los Tests](#2-cómo-se-diseñan-los-tests)
3. [Quién los Ejecuta y Cuándo](#3-quién-los-ejecuta-y-cuándo)
4. [Cómo se Corrige un Test que Falla](#4-cómo-se-corrige-un-test-que-falla)
5. [El Entorno de Tests: Quién lo Prepara y Cómo](#5-el-entorno-de-tests-quién-lo-prepara-y-cómo)
6. [Cómo se Decide el Tipo de Proyecto](#6-cómo-se-decide-el-tipo-de-proyecto)
7. [El Chain E2E: Paso a Paso](#7-el-chain-e2e-paso-a-paso)
8. [Gaps y Limitaciones del Sistema](#8-gaps-y-limitaciones-del-sistema)
9. [Veredicto: ¿Está Preparado para Testing Autónimo?](#9-veredicto-está-preparado-para-testing-autónomo)

---

## 1. Flujo Completo de Decisión

```
USER GOAL
    │
    ▼
product-manager ──→ requirements.md
                        │ Verification Contract
                        │   • project type
                        │   • entry points
                        │   • observable signals (PASS/FAIL)
                        │   • hard invariants
                        │   • seed data
                        │   • dependency map
                        │
                        ▼
architect-reviewer ──→ design.md
                        │ ## Test Strategy (MANDATORY)
                        │   • Test Double Policy
                        │   • Mock Boundary (unit vs integration)
                        │   • Fixtures & Test Data
                        │   • Test Coverage Table
                        │   • Test File Conventions
                        │
                        ▼
task-planner ──→ tasks.md
                    │ POC-first workflow
                    │   Phase 1: Make It Work (NO tests)
                    │   Phase 2: Refactoring (NO tests)
                    │   Phase 3: Testing (unit/integration/E2E)
                    │   Phase 4: Quality Gates
                    │
                    ├── [VERIFY] V1..Vn ──→ qa-engineer (lint/typecheck/build)
                    │
                    ├── VE0 ──→ ui-map-init ──→ ui-map.local.md
                    ├── VE1 ──→ qa-engineer (dev server startup)
                    ├── VE2 ──→ qa-engineer (Playwright E2E flows)
                    ├── VE3 ──→ qa-engineer (cleanup)
                    │
                    ▼
spec-executor + stop-watcher (execution loop)
                        │
                        ├── [VERIFY] ──→ qa-engineer ──→ VERIFICATION_PASS/FAIL
                        │
                        ├── VE ──→ qa-engineer ──→ VERIFICATION_PASS/FAIL/DEGRADED
                        │           │
                        │           └──→ Failure? → repair loop (fixTaskMap) → retry VE2
                        │
                        └── [STORY-VERIFY] ──→ qa-engineer ──→ exploratory verification
```

---

## 2. Cómo se Diseñan los Tests

### 2.1 Product Manager → Verification Contract

El `product-manager` genera `requirements.md` que incluye la sección `## Verification Contract`:

```markdown
## Verification Contract

**Project type**: fullstack | frontend | api-only | cli | library

**Entry points**:
- GET /api/invoices?from=&to=     [surface: api]
- GET /dashboard/invoices           [surface: browser, route: /invoices]
- POST /api/invoices               [surface: api]

**Observable signals**:
- PASS looks like: HTTP 200, array of invoice objects with correct date filtering
- FAIL looks like: HTTP 400 {error: "invalid_range"}, or dashboard shows empty state

**Hard invariants**:
- Auth: unauthenticated request → 401
- Tenant isolation: user A cannot see user B invoices
- Adjacent flow: invoice creation still works

**Seed data**:
- At least 3 invoices with dates in Jan/Feb/Mar 2026
- One invoice per user in multi-tenant scenario

**Dependency map**:
- auth-spec, billing-spec
```

**El project type es la decisión más crítica** — gating determina todo el resto:
- `fullstack` → full Playwright E2E chain + API verification
- `frontend` → Playwright E2E (no API)
- `api-only` → curl/WebFetch, NO Playwright
- `cli` → CLI commands, NO browser
- `library` → unit tests, NO browser

### 2.2 Architect Reviewer → Test Strategy (MANDATORY)

El `architect-reviewer` DEBE llenar `design.md → ## Test Strategy` con:

**Test Double Policy** —taxonomía de exactamente 4 tipos (canónico en architect-reviewer.md):
```
Stub      → predefined data, no behavior, isolates SUT from I/O
Fake      → simplified real implementation (e.g. in-memory DB)
Mock     → verifies INTERACTION (call args, count) — interaction IS the observable
Fixture   → predefined data state (not code)
```

> ⚠️ En el código real NO existen Dummy, Real ni Test Adapter como categorías del Test Double Policy. Usar tipos que no existen en el sistema causaría que un agente genere tests con categorías inválidas en la Mock Boundary.

**Mock Boundary** —tabla por componente:

| Component | Unit test | Integration test |
|-----------|-----------|-----------------|
| InvoiceRepository | Stub (return shaped data) | Fake DB or real test DB |
| EmailNotifier | Mock (assert send called) | Stub |
| InvoiceService | Real | Real with test DB |

**Consistency rule**: si en una celda escribes "mock", la interacción verificable DEBE ser el resultado observable. Si solo te importa el valor de retorno del SUT, eso es un stub, no un mock.

**Fixtures & Test Data**:
```markdown
| Component | State needed | Form |
|-----------|-------------|------|
| InvoiceRepository | 3 invoices (Jan/Feb/Mar), different tenants | Factory function |
| EmailNotifier | None (side-effect only) | N/A |
```

### 2.3 Task Planner → VE Tasks

El `task-planner` genera tasks.md con el workflow POC-first:

```
Phase 1 (Make It Work): NO tests
Phase 2 (Refactoring):  NO tests
Phase 3 (Testing):      Unit + Integration + E2E ← aquí se diseñan los tests
Phase 4 (Quality):      Full CI
```

Los tests de E2E se generan como **VE tasks**:

```markdown
VE0 [VERIFY] UI Map Init: build selector map
  → Genera ui-map.local.md con selectores descubiertos

VE1 [VERIFY] E2E startup: launch infrastructure
  → Inicia dev server, guarda PID

VE2 [VERIFY] E2E check: verify critical user flow
  → Usa ui-map.local.md para selectors
  → Ejecuta flujo crítico via Playwright

VE3 [VERIFY] E2E cleanup: tear down infrastructure
  → Kill por PID, libera puerto
```

---

## 3. Quién los Ejecuta y Cuándo

### 3.1 Taxonomía de Agentes

| Agent | Rol | Qué ejecuta |
|-------|-----|------------|
| `spec-executor` | Implementa tareas de código | NO ejecuta tests directamente |
| `qa-engineer` | Ejecuta verification tasks | [VERIFY], VE, [STORY-VERIFY], VF |
| `stop-watcher` | Loop controller | Detecta señales, activa repair loop |

### 3.2 Ruta de una VE Task

```
tasks.md:  VE2 [VERIFY] E2E check: verify critical user flow
    │
    ▼ spec-executor detecta [VERIFY] tag
    No ejecuta él mismo ──→ Task tool: qa-engineer
                                    │
                                    ▼
                              qa-engineer recibe la tarea vía Task tool y lee las skills:
                              1. playwright-env (resuelve appUrl, auth)
                              2. mcp-playwright (dependency check)
                              3. playwright-session (session lifecycle)
                              │
                              ▼
                              VE0: ui-map-init (solo primera vez)
                              Lee ui-map.local.md para selectors
                              │
                              ▼
                              VE2: Ejecuta flujo crítico
                              browser_navigate → browser_snapshot →
                              browser_generate_locator → browser_verify → ...
                              │
                              ▼
                              Signal: VERIFICATION_PASS / FAIL / DEGRADED
                                    │
                              spec-executor recibe señal
                                    │
                              si PASS → marca task [x] → siguiente task
                              si FAIL → increment taskIteration → retry/fix
                              si DEGRADED → spec-executor ESCALATE → stop-watcher
```

### 3.3 Cuándo Ejecuta [VERIFY]

Los checkpoints [VERIFY] se insertan según complejidad:

| Complejidad | Frecuencia |
|-------------|-----------|
| Pequeña/simple | Cada 3 tareas |
| Mediana | Cada 2-3 tareas |
| Grande/compleja | Cada 2 tareas |

Además, los últimos tasks de Phase 4 son típicamente:
```
V4 [VERIFY] Full local CI: lint + typecheck + test + e2e + build
V5 [VERIFY] CI pipeline passes
V6 [VERIFY] AC checklist
```

> ⚠️ Los nombres exactos (V4/V5/V6) y el número varían según la spec. Lo constante es que hay un checkpoint de CI local completo, un checkpoint de pipeline CI, y un checklist de AC al final.

---

## 4. Cómo se Corrige un Test que Falla

### 4.1 Retry Loop (spec-executor)

```
qa-engineer → VERIFICATION_FAIL
    │
    ▼ spec-executor recibe la señal
    spec-executor incrementa taskIteration++
    Si taskIteration < 5 → reintenta la misma task
    Si taskIteration >= 5 → ESCALATE
```

### 4.2 Fix Task Generation (recovery mode)

Cuando recoveryMode=true y una task falla:

```
1. Coordinator parsea failure output
2. Genera fix task: X.Y.N [FIX X.Y] Fix: <error summary>
3. Inserta después de la task original en tasks.md
4. Ejecuta fix task
5. Reintenta original task
6. Si falla de nuevo → genera otro fix (max 3 fix tasks por original)
```

### 4.3 Verify-Fix-Reverify Loop (VE)

```
VE2 fails → VERIFICATION_FAIL
    │
    ▼
Coordinator genera fix task para VE2
    │
    ▼
Fix task ejecuta: spec-executor corrige código
    │
    ▼
VE2 se re-ejecuta contra código corregido
    │
    ▼
Max 3 fix attempts → si sigue fallando:
VE3 cleanup ejecuta (SIEMPRE)
→ luego ESCALATE a humano
```

**VE3Cleanup Guarantee**: incluso si VE2 falla, VE3 corre. Nunca deja procesos huérfanos.

### 4.4 Mock Quality Failures

Si qa-engineer detecta test quality issues (mock-only, missing real imports):
- Clasificado como `test_quality` en el repair loop del stop-watcher
- Delegate un **test-rewrite task**, NO un implementation fix
- Arregla: imports reales, mock/assertion ratio, state-based assertions

> ⚠️ El routing de `test_quality` al fix correcto (rewrite vs fix) está en el stop-watcher.sh (añadido en sesión previa). El loop de repair lo detecta → clasifica → delega el rewrite task al spec-executor. qa-engineer detecta el problema; el stop-watcher hace el routing correcto.

---

## 5. El Entorno de Tests: Quién lo Prepara y Cómo

### 5.1 Quién Prepara el Entorno

**El humano** prepara:
- MCP server (`@playwright/mcp`) instalado y corriendo con flags correctos
- Variables de entorno exportadas
- `playwright-env.local.md` con configuración local
- Credenciales de auth (nunca en state files)

**playwright-env skill** resuelve:
- `RALPH_APP_URL` → RESOLVED_APP_URL
- `RALPH_AUTH_MODE` → auth mode (none/form/token/cookie/storage-state/basic)
- `RALPH_BROWSER`, `RALPH_HEADLESS`, `RALPH_VIEWPORT`
- `RALPH_SEED_COMMAND` → seed data preparation
- `RALPH_PLAYWRIGHT_ISOLATED` → ephemeral vs persistent profile

### 5.2 Cadena de Resolución del Entorno (5 fuentes)

```
1. Shell env var (RALPH_APP_URL)          ← prioritaria
2. playwright-env.local.md (basePath)
3. .ralph-state.json → playwrightEnv cache (con stale check 2h)
4. requirements.md → Verification Contract → Entry points
5. ESCALATE (no se puede resolver)
```

### 5.3 Auth Modes

| Mode | Cómo | Requiere |
|------|------|----------|
| `none` | Navega directo | appUrl |
| `form` | Login via browser form | RALPH_LOGIN_USER, RALPH_LOGIN_PASS |
| `token` | Inject JWT via localStorage/header | RALPH_AUTH_TOKEN + tokenBootstrapRule |
| `cookie` | Inject session cookie | RALPH_SESSION_COOKIE_NAME/VALUE |
| `storage-state` | Carga state file pre-auth | RALPH_STORAGE_STATE_PATH |
| `basic` | HTTP Basic Auth | RALPH_LOGIN_USER/PASS |
| `oauth/sso` | NO soportado → ESCALATE | Requiere storage-state |

### 5.4 El MCP Server es Responsabilidad del Humano

```
⚠️ El agent NUNCA inicia/killa/restartea el MCP server.
El server es un long-running process configurado por el humano.
El agent SOLO llama browser_* tools del server YA corriendo.
Si el server está mal configurado → ESCALATE.
```

Flags requeridos en MCP server definition:
- `--isolated` → ephemeral profile, no disk cache
- `--caps=testing` → habilita browser_verify_* tools

### 5.5 Seed Data

```bash
# playwright-env.local.md:
seedCommand: npm run seed:e2e -- --tenant test-corp

# Run order:
1. Connectivity check (curl appUrl)
2. Seed command (solo local/staging, NUNCA production)
3. Escribir playwrightEnv a .ralph-state.json
```

---

## 6. Cómo se Decide el Tipo de Proyecto

### 6.1 Decision Tree

```
requirements.md → ## Verification Contract → project type
    │
    ▼
¿El proyecto tiene UI/browser entry point?
    │
    ├── SI → ¿También tiene HTTP API endpoints?
    │         ├── SI  → fullstack (Playwright + WebFetch/curl)
    │         └── NO → frontend (solo Playwright)
    │
    └── NO → ¿Tiene HTTP API endpoints?
              ├── SI  → api-only (curl/WebFetch, NO Playwright)
              └── NO → cli o library (test commands, NO browser)
```

### 6.2 Qué se carga según project type

| Project type | Skills cargados | VE tasks? |
|-------------|-----------------|-----------|
| fullstack | playwright-env → mcp-playwright → playwright-session → ui-map-init | Sí (full chain) |
| frontend | playwright-env → mcp-playwright → playwright-session → ui-map-init | Sí (UI only) |
| api-only | NO playwright | NO VE (API verification) |
| cli | NO playwright | NO VE (CLI verification) |
| library | NO playwright | NO VE (test commands) |

---

## 7. El Chain E2E Paso a Paso

### 7.1 Skill Chain (orden obligatorio)

```
playwright-env.skill.md
    │
    ├── Resuelve appUrl, authMode, allowWrite, isolated
    ├── Connectivity check (curl appUrl)
    ├── Seed command (local/staging)
    ├── Module system detection (ESM vs CJS)
    └── Escribe playwrightEnv → .ralph-state.json
            ↓
mcp-playwright.skill.md
    │
    ├── Dependency check: npx --no-install @playwright/mcp --version
    ├── Si MISSING → Protocol B (degraded) + ESCALATE
    ├── Lock recovery (solo si isolated=false)
    └── Escribe mcpPlaywright → .ralph-state.json
            ↓
playwright-session.skill.md
    │
    ├── Auth flow (según authMode)
    ├── Stable state detection (loading indicators)
    ├── Navigation anti-patterns (NO page.goto() para rutas internas)
    └── Session End: browser_close + escribir lastPlaywrightSession
            ↓
ui-map-init.skill.md (VE0)
    │
    ├── Explora entry points del Verification Contract
    ├── browser_snapshot → accessibility tree
    ├── browser_generate_locator → selectores estables
    └── Escribe ui-map.local.md
            ↓
qa-engineer VE2
    │
    ├── Lee ui-map.local.md
    ├── Executa flujos críticos via browser tools
    ├── Diagnostic protocol si falla: console + network + snapshot
    └── Emite VERIFICATION_PASS/FAIL/DEGRADED
```

### 7.2 Selector Hierarchy (orden de preferencia)

```
1. getByRole()          → accesibilidad semántica, más estable
2. getByLabel()         → inputs con label asociado
3. getByTestId()         → data-testid explícito
4. locator('css')        → último recurso
```

**Anti-patrones reconocidos:**
- `page.goto('/config/integrations')` → NO (bypasses routing/auth)
- `waitForTimeout(2000)` → NO (flaky)
- CSS classes hardcoded → NO
- XPath → NO
- Shadow DOM `>>>` → NO

### 7.3 Session Isolation

| Modo | Perfil | Cache | Lock recovery? |
|------|--------|-------|----------------|
| `isolated=true` (default) | Ephemeral | Sin disk cache | NO needed |
| `isolated=false` | Persistent `~/.cache/ms-playwright/mcp-chrome` | HTTP disk cache persiste | YES, siempre antes de session |

---

## 8. Gaps y Limitaciones del Sistema

### Gap 1: TEST STRATEGY sin validación externa

```
architect-reviewer → design.md → ## Test Strategy
                                           │
                        ❌ No hay validación externa antes de que
                           spec-executor la consuma
```

El checklist mandatory en architect-reviewer.md (añadido al PR actual) fuerza al arquitecto a llenar la sección con checklist antes de marcar design como completo. Esto reduce significativamente el riesgo de Test Strategy vacía, pero no elimina el gap: la validación sigue siendo intra-sistema (mismo LLM), no hay validación formal por un agente independiente.

**Workaround**: spec-executor hace ESCALATE si design.md → Test Strategy está vacía.

> 📌 **Mitigación activa en PR**: el bloque `<mandatory>` con checklist en architect-reviewer.md convierte Gap 1 de "arquitecto puede saltarse Test Strategy" a "arquitecto tiene instrucción explícita con checklist antes de marcar completo". Es la mitigación más concreta aplicada al sistema.

### Gap 2: qa-engineer no ve los skills cargados en VE tasks

```
spec-executor carga los skills para VE tasks
   → El agent que ejecuta VE (qa-engineer) recibe los skills en el prompt
   → Pero mock quality check en qa-engineer no puede ver qué skills se cargaron
```

Esto es un blind spot: si los skillsloaded no coinciden con lo que qa-engineer espera, no hay mecanismo de detección.

### Gap 3: Staleness del ui-map.local.md

```
ui-map.local.md → stale: true cuando:
   - Routing client-side cambia
   - Componente se restructura
   - data-testid se renombra
   - authMode cambia
```

El spec-executor tiene que detectar estos triggers y marcar stale o re-generar. Si no lo hace, VE2 usa selectors rotos silenciosamente.

### Gap 4: oauth/sso no soportado

```
oauth / sso → ESCALATE inmediato
   → El humano debe preparar storage-state pre-auth
   → Ralph no puede negociar flujos OAuth autonomously
```

### Gap 5: Nadie verifica que unit tests respeten la Mock Boundary

> 🔴 **GAP MÁS CRÍTICO DEL SISTEMA**

El test design se define en Mock Boundary (architect-reviewer), pero:
- task-planner genera las tasks de unit tests
- spec-executor escribe los unit tests siguiendo Test Strategy
- qa-engineer solo ejecuta [VERIFY] checkpoints (lint/typecheck/build)

No hay un agente dedicado a verificar que los unit tests siguen la Mock Boundary correctly. La calidad de unit tests depende de que spec-executor siga las instrucciones de Test Strategy.

### Gap 6: Seed data requirement no es automático

```
Verification Contract dice: "Seed data: 3 invoices with dates in Jan/Feb/Mar"
                                     │
                        playwright-env puede ejecutar seedCommand
                        PERO no hay verificación de que el seed fue exitoso
                        antes de correr VE2
```

### Gap 7: El humano es un cuello de botella para el MCP server

```
MCP server se configura fuera de Ralph:
   - Flags (--isolated, --caps=testing)
   - Credenciales como env vars
   - @playwright/mcp instalado
   - storage-state preparado para oauth

Si falta algo → ESCALATE → humano interviene → resume
```

---

## 9. Veredicto: ¿Está Preparado para Testing Autónomo?

### Respuesta corta: SÍ, pero con precondiciones.

### Lo que SÍ puede hacer de forma autónoma:

| Capacidad | Estado |
|-----------|--------|
| Ejecutar lint/typecheck/build checkpoints | ✅ Completamente autónomo |
| Unit tests según Test Strategy | ⚠️ Autonomous SI architect rellena Mock Boundary + spec-executor la aplica correctamente |
| E2E para fullstack/frontend con auth `none` o `form` | ✅ Autonomous (con config correcta) |
| E2E con auth `token` | ✅ Autonomous (si tokenBootstrapRule definido) |
| API verification para api-only | ✅ Autonomous (curl/WebFetch) |
| Recovery/autofix para VE failures | ✅ 3 retries via fixTaskMap |
| Cleanup de procesos huérfanos | ✅ VE3 siempre corre |
| Mock quality detection | ✅ qa-engineer detecta mock-only anti-patterns |
| Exploratory verification [STORY-VERIFY] | ✅ qa-engineer deriva checks del Verification Contract |

### Lo que NO puede hacer de forma autónoma:

| Capacidad | Bloqueador |
|-----------|-----------|
| OAuth/SSO flows | Requiere storage-state pre-auth preparado por humano |
| Determinar project type si Verification Contract está vacío | Requiere humano o análisis de codebase |
| Detectar staleness de ui-map.local.md automáticamente | Requiere juicio del agent + trigger detection |
| Verificar seed data fue exitoso antes de VE2 | No hay pre-check integrado |
| Auto-instalar @playwright/mcp si falta | Política: agent nunca auto-instala |
| Resolver auth si credenciales no están exportadas | ESCALATE |

### Lo que está bien diseñado pero requiere disciplina:

| Área | Evaluación |
|------|-----------|
| Test Double taxonomy (4 tipos: Stub/Fake/Mock/Fixture) | ✅ Robusta si architect la llena correctamente |
| Mock Boundary (unit vs integration) | ✅ Correct separation si se usa |
| Selector hierarchy (getByRole > getByTestId > locator) | ✅ Anti-frágil |
| Verify-fix-reverify loop | ✅ 3 retries + mandatory cleanup |
| DEGRADED mode graceful | ✅ Fallback a static analysis |

### Requisitos para testing completamente autónomo en un proyecto nuevo:

```
1. requirements.md → Verification Contract completo
      • project type declarado
      • entry points específicos
      • observable signals (PASS/FAIL)
      • seed data definido

2. design.md → Test Strategy completo
      • Mock Boundary llena con nombres reales
      • Fixtures & Test Data poblada
      • Test Coverage Table con assertions concretas

3. playwright-env.local.md configurado
      • appUrl resuelto
      • authMode y credenciales como env vars
      • seedCommand si aplica

4. MCP server configurado por humano
      • @playwright/mcp instalado
      • Flags correctos (--isolated --caps=testing)
      • storage-state si oauth

5. Project type ≠ cli/library sin MCP
```

### Conclusión

**El sistema está preparado para testing autónomo de cualquier funcionalidad nueva SI:**
1. Se completa el Verification Contract en requirements.md
2. Se completa la Test Strategy en design.md
3. El humano configura playwright-env.local.md + MCP server antes de la primera VE task

**El sistema NO puede operar sin esas precondiciones** — pero eso es correcto. Un spec-driven system no puede adivinar la URL de la app, el auth flow, o los endpoints. tienen que venir del spec.
    
El gap más significativo no es de autonomía sino de **calidad de la Test Strategy** — depende enteramente de que el architect-reviewer llene correctamente la Mock Boundary table. Si alguien llena "mock" en una celda sin entender la diferencia stub/mock/fake, los unit tests serán incorrectos aunque el resto del sistema funcione.

---

*Generado 2026-04-04 — análisis profundo del sistema de testing de RalphHarness*
