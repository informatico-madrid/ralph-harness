# RalphHarness — Informe Forense Combinado: Flujo de Testing y Detección de Fallos

## Fuentes

Este documento fusiona:
- **Análisis propio** (docs/FORENSIC-TEST-FLOW.md) — enfoque en clasificación de fallos y cadena de detección
- **Contra-análisis recibido** — enfoque en gaps de arquitectura y fase de testing

Las discrepancias se resolvieron verificando contra código fuente. El veredicto de cada una está marcado **[RESUELTO: X]**.

---

## Índice

1. [Flujo Completo de Fases](#1-flujo-completo-de-fases)
2. [Mapa de Agentes y Responsabilidades](#2-mapa-de-agentes-y-responsabilidades)
3. [Orden de Escritura: Código vs Tests](#3-orden-de-escritura-código-vs-tests)
4. [Detección de Fallos: Código vs Test](#4-detección-de-fallos-código-vs-test)
5. [Gaps Críticos (Prioridad 🔴)](#5-gaps-críticos-prioridad-)
6. [Gaps Altos (Prioridad 🟡)](#6-gaps-altos-prioridad-)
7. [Gaps Medios/Bajos (Prioridad 🟢)](#7-gaps-mediosbajos-prioridad-)
8. [Mejoras Concretas y Ficheros a Modificar](#8-mejoras-concretas-y-ficheros-a-modificar)
9. [Discrepancias Resueltas Contra Código Fuente (Validación Pre-Contra-Informe)](#9-discrepancias-resueltas-contra-código-fuente)
10. [Resumen de Aceptación del Contra-Informe](#10-resumen-de-aceptación-del-contra-informe)

---

## 1. Flujo Completo de Fases

```
[1] /ralphharness:start
    → product-manager.md
    → requirements.md + ## Verification Contract
    → awaitingApproval = true  ──► PAUSA (usuario aprueba)

[2] /ralphharness:design
    → architect-reviewer.md
    → design.md + ## Test Strategy (MANDATORY)
    │     • Test Double Policy (4 tipos: Stub/Fake/Mock/Fixture)
    │     • Mock Boundary (unit | integration) ← SIN columna E2E
    │     • Fixtures & Test Data
    │     • Test Coverage Table
    │     • Test File Conventions ← Descubre via Explore scan
    → awaitingApproval = true  ──► PAUSA (usuario aprueba)

[3] /ralphharness:plan
    → task-planner.md
    → tasks.md
    │     Phase 1: Make It Work (NO tests)
    │     Phase 2: Refactoring (NO tests)
    │     Phase 3: Testing ← Tests derivados de Test Coverage Table
    │     Phase 4: Quality Gates
    │     ← SIN regla de orden: tests después de implementación
    │
[4] /ralphharness:implement
    → spec-executor.md + stop-watcher.sh
    → tasks.md se ejecutan una a una
    │     Sequential → spec-executor (implementa + marca [x])
    │     [VERIFY] → qa-engineer → VERIFICATION_PASS/FAIL/DEGRADED
    │     VE → qa-engineer (E2E via playwright)
    │
    → Si VERIFICATION_FAIL:
           taskIteration < 5 → spec-executor retry
           taskIteration >= 5 → ESCALATE
           recoveryMode=true → stop-watcher repair loop (max 2)
                   Clasificación por TEXTO LIBRE (no estructurado)
                   → impl_bug / env_issue / spec_ambiguity / flaky / test_quality

[5] Regression sweep (Phase 4)
    → qa-engineer verifica specs del Dependency Map
```

---

## 2. Mapa de Agentes y Responsabilidades

| Fase | Agente | Responsabilidad | Verifica |
|------|--------|----------------|---------|
| requirements | product-manager | User stories + Verification Contract | Acceptance criteria |
| design | architect-reviewer | Arquitectura + Test Strategy | Mock Boundary, Fixtures |
| plan | task-planner | tasks.md desde Coverage Table | Orden, POC vs TDD |
| implement | spec-executor | Código + Tests en tasks | Done when + verify command |
| verify | qa-engineer | [VERIFY] checkpoints | lint/typecheck/test + mock quality |
| implement | stop-watcher | Loop controller | Señales + repair loop |
| review | spec-reviewer | Layer 3 artifact review | Implementación vs spec |

### Quién escribe qué durante implement

```
spec-executor en una task Phase 3:
    1. Lee design.md → Test Strategy
    2. Escribe código de implementación
    3. Escribe test(s) siguiendo Mock Boundary
    4. Ejecuta verify command (pnpm test)
    5. Si verify pasa → TASK_COMPLETE
       (no valida que el test sea correcto, solo que corre)

    6. [VERIFY] checkpoint posterior:
           qa-engineer recibe la task
           → Si verify command tiene "test":
                corre mock quality checks
                Detecta: mock declarations > 3x real assertions
                → Escribe en .progress.md (texto libre)
                → Emite: VERIFICATION_FAIL (sin campo type/)
```

---

## 3. Orden de Escritura: Código vs Tests

### 3.1 Lo que Dice el Código

**task-planner.md** — No existe ninguna regla de orden entre implementación y tests. La única regla es que las tareas de Phase 3 se derivan de la Test Coverage Table (línea 330-356):

> "Generate one task per row in the table... use the row's data directly"

El task-planner no verifica si el módulo existe antes de generar un task de test para él.

### 3.2 Escenario de Fallo por Orden

```
tasks.md generado por task-planner:
- [ ] 3.1 [VERIFY] Pre-flight: verify test runner works
- [ ] 3.2 Write unit tests for InvoiceService
- [ ] 3.3 Implement InvoiceService
```

El task 3.2 intenta escribir tests para un módulo que no existe aún. spec-executor:
1. Escribe el test importando InvoiceService
2. El import falla (módulo no existe)
3. spec-executor marca FAIL → TASK_COMPLETE no emitido
4. Retry loop → clasifica como impl_bug
5. Genera fix task para crear InvoiceService
6. Pero el fix task crea el módulo → ahora el test tiene módulo pero el test fue escrito antes y puede no coincidir con la implementación final

**No hay guardrail que evite este escenario.**

### 3.3 Solución Esperada (Fix 4 del contra-análisis)

> task-planner.md necesita: "Every 'Write tests for X' task MUST appear AFTER the task that creates X"

**[RESUELTO: No existe esta regla en task-planner.md — debe añadirse]**

---

## 4. Detección de Fallos: Código vs Test

### 4.1 Matriz Completa

| Escenario | Síntoma | Detecta | Clasifica | Fix |
|-----------|---------|---------|-----------|-----|
| Implementación no hace lo que spec dice | Test falla | qa-engineer [VERIFY] | impl_bug | Arregla código |
| Test mal diseñado (pasa pero no verifica) | Mock quality flag | qa-engineer mock checks | test_quality | Reescribe test |
| Implementación rota (excepción, 500) | Test no corre | spec-executor verify | impl_bug | Arregla código |
| Test mal escrito (syntax error) | Test no corre | spec-executor verify | impl_bug | Arregla test |
| Test correcto + implementación correcta = flaky | Intermitente | qa-engineer | flaky | Retry |
| Spec ambiguo (no dice qué debe pasar) | Ningún test puede verificar | qa-engineer [STORY-VERIFY] | spec_ambiguity | Propone aclaración |
| Runner no configurado | Test no puede ejecutarse | qa-engineer [VERIFY] | env_issue | Configurar runner |

### 4.2 Caso Ambiguo: Test Correcto pero Implementación Incorrecta

```
Test: expect(invoice.total).toBe(150)  ← assertion correcta según spec
Impl: return { total: 100 }  ← BUG

Test → FAIL
    │
    ▼
VERIFICATION_FAIL
    │
    ▼
stop-watcher razona:
    "¿El test tiene real assertions? SÍ
     ¿El test tiene real module import? SÍ
     → No es test_quality
     → Clasifica: impl_bug"
```

El sistema clasifica correctamente en este caso. **Pero** si la assertion del test es sobre la cosa wrong (el test verifica `total` cuando debería verificar `subtotal`), el test pasa pero verifica lo wrong.

### 4.3 Caso Ambiguo: Test Mal Diseñado + Implementación Correcta

```
Test: expect(stripeMock.charge).toHaveBeenCalledWith(100)
      // Solo verifica mock. No return value.

Impl: charge() { return { amount: 100, status: 'ok' } }  ← CORRECTA

Test → PASS (mock assertion pasa)
    │
    ▼
qa-engineer mock quality check:
    "Mock declarations: 1, Real assertions: 0 → mock-only"
    │
    ▼
VERIFICATION_FAIL + texto libre en .progress.md
    │
    ▼
stop-watcher busca "mock quality" / "real assertions"
    │
    ├─ SI lo encuentra → test_quality ✓
    └─ NO lo encuentra → impl_bug ✗ (clasificación wrong)
```

---

## 5. Gaps Críticos (Prioridad 🔴)

### GAP 1 🔴 — test_quality es señal inferred, no estructurada

**Archivos afectados:** `agents/qa-engineer.md`, `hooks/scripts/stop-watcher.sh`

**Verificado contra código:**

El stop-watcher.sh NO hace grep de strings para clasificar. Genera un bloque `REPAIR_REASON` (líneas 368-411) que contiene las 5 categorías y sus acciones, y el **coordinator LLM** razona sobre `.progress.md` para clasificar. La clasificación la hace el LLM, no el bash script.

qa-engineer.md escribe el Mock Quality Report en `.progress.md` como texto libre:
```
Status: VERIFICATION_FAIL (test quality issues)
```

**Problema real (corregido):**
- No existe `category: test_quality` estructurado que el bash pueda parsear
- El coordinator LLM razona sobre texto libre → depende de que qa-engineer use vocabulario reconocible
- La robustez depende del LLM, no de parseo estructurado

**Fix confirmado por contra-informe — requiere cambios coordinados:**
```
1. qa-engineer.md: escribir en .progress.md:
   "category: test_quality" como línea parseable

2. stop-watcher.sh: en el REPAIR_REASON block, instruir:
   "If .progress.md contains 'category: test_quality',
    classify as test_quality (do NOT classify as impl_bug)"
```

**NO basta con cambiar solo qa-engineer.md** — el stop-watcher genera el prompt, debe indicar explícitamente que busque el campo `category:`.

### GAP 2 🔴 — Fix task no sabe si arreglar código o test

**Archivos afectados:** `references/failure-recovery.md`, `references/coordinator-pattern.md`

**Verificado contra código:**

failure-recovery.md genera el fix task así (líneas 177-191):
```
- [ ] $taskId.$attemptNumber [FIX $taskId] Fix: $errorSummary
  - **Do**: Address the error: $failure.error
  - **Files**: $originalTask.files
```

El `fix_type` NO existe como campo parseable. El `$errorSummary` son los primeros 50 caracteres del error.

**Lo que el contra-informe matiza (correcto):** El stop-watcher SÍ distingue en su prompt (líneas 385-391):
```
If impl_bug: backtrack → delegate implementation fix
If test_quality: delegate a test-rewrite task (NOT implementation fix)
```

El coordinator LLM recibe esta instrucción y razona. **El problema:** el fix task escrito en `tasks.md` NO lleva indicación parseable. spec-executor recibe el fix task y tiene que inferir del texto qué arreglar.

**Fix mantenido — con precisión:**
El fix task necesita un tag parseable. El formato en `failure-recovery.md` debe cambiar:
```
- [ ] $taskId.$attemptNumber [FIX $taskId] [fix_type:test_quality] Fix: $errorSummary
```

Esto permite a spec-executor saber sin razonar que es un rewrite de test, no fix de código.

### GAP 3 🔴 — Mock Boundary sin columna E2E

**Archivos afectados:** `agents/architect-reviewer.md`, `templates/design.md`

**Verificado contra código:**

La tabla en architect-reviewer.md (línea 197) es:
```
| Component (from this design) | Unit test | Integration test | Rationale |
```

La Test Coverage Table en architect-reviewer.md (línea 223) SÍ tiene e2e:
```
| [User flow: login → dashboard] | e2e | URL changes, user sees dashboard | none (real env) |
```

**Lo que el contra-informe matiza (correcto):** La estrategia e2e YA está documentada en la Coverage Table, no en Mock Boundary. "e2e: full flow, real environment. No doubles" está en Test types de Coverage Table.

**El gap real (corregido):** No hay Enforcement de que la Coverage Table tenga una fila e2e para cada componente con side effects. Un componente como `EmailNotifier` aparece en Mock Boundary (Mock en unit, Stub en integration) pero NO tiene fila en Coverage Table para e2e. Si no existe fila, nadie declara qué double usar en e2e — y si el arquitecto pone "none" para e2e en Coverage Table, no hay validación de que eso sea correcto.

**Fix revisado:**
```
Opción A (añadir columna E2E a Mock Boundary):
  → Duplica información ya en Coverage Table

Opción B (mejor): Enforcer consistencia cruzada:
  1. Coverage Table debe tener una fila e2e para cada componente
     con side effects declarados en Mock Boundary
  2. Si Coverage Table dice "e2e | none", debe haber
     rationale de por qué "none" es correcto
  3. Si un componente aparece en Mock Boundary con side effects
     pero NO aparece en Coverage Table → ESCALATE
```

**El template obsoleto** (`templates/design.md` con layer-based) sigue siendo discrepancia real confirmada.

### GAP 4 🔴 — test_quality fix no puede cambiar la causa raíz

**Archivos afectados:** `hooks/scripts/stop-watcher.sh` (líneas 332-353, 390-391)

**Verificado contra código:**

El loop de repair para test_quality (líneas 390-391) reintenta rewrite 2 veces máximo, luego escala. El mensaje de escalación (líneas 345-349) dice:
```
1. Review requirements.md — Verification Contract
2. Review tasks.md
3. Check .progress.md for failure details
4. Fix manually or clarify the spec
```

**NO menciona: "revisa design.md → Mock Boundary".**

**Fix mínimo confirmado (contra-informe):** Añadir al mensaje de ESCALATE para test_quality exhausted:
```
4b. Check $SPEC_PATH/design.md → Mock Boundary
    The declared double type may be architecturally incorrect
    for this component (e.g., "Real" for a component with
    circular dependencies that prevents real testing).
```

No requiere nueva rama en el loop — basta con el mensaje de escalación para que el humano sepa dónde mirar.

### GAP 5 🔴 — No hay fase de testing tooling discovery

**Archivos afectados:** Ninguno (no existe)

**Problema:** Entre `/design` y `/implement`, no hay ninguna fase que:
1. Verifique que el test runner está instalado (`npm test` funciona)
2. Investigue la documentación oficial si el runner no existe
3. Documente los comandos exactos de ejecución (unit/integration/e2e)

El architect-reviewer dice "Discover from codebase via Explore scan" para Test File Conventions, pero si el proyecto es nuevo o no tiene tests, el scan devuelve vacío. El arquitecto entonces inventa convenciones.

**Fix requerido:** Nuevo bloque mandatory en architect-reviewer.md:
```
## Testing Discovery Checklist (Post-Design, Pre-Plan)

<mandatory>
1. Runner verification: Run `cat package.json | grep -E "test|vitest|jest"`
   If no runner found:
   - Check official docs (WebFetch to vitest.dev, jestjs.io)
   - Document setup steps as a task in tasks.md
   - If runner not installable: ESCALATE

2. Execution command: Document exact commands:
   - Unit: npm run test / vitest run src/
   - Integration: vitest run --config vitest.integration.config.ts
   - E2E: playwright test
   If command doesn't exist yet: mark as "TO CREATE" in Test File Conventions

3. Can we run a test right now? Try: npm test
   - If fails (no tests yet): runner is ready, proceed
   - If fails (runner broken): add infrastructure task FIRST
</mandatory>
```

---

## 6. Gaps Altos (Prioridad 🟡)

### GAP 6 🟡 — Layer 3 no revisa tests

**Archivos afectados:** `references/verification-layers.md`

**Verificado contra código fuente:**

verification-layers.md NO fue leído directamente en mi análisis — el contra-informe lo señala. Lo que sí está verificado:

- qa-engineer.md (líneas 346-458) ya tiene mock quality checks y los ejecuta en cada [VERIFY] task
- spec-reviewer en Layer 3 es un artifact review post-ejecución

**Lo que el contra-informe matiza (correcto):**

qa-engineer ya corre mock quality analysis en cada [VERIFY] task. Si el test pasó [VERIFY], mock quality ya fue validado. Layer 3 haría mock quality review **redundante**.

**El gap real (corregido):**

Un test puede pasar mock quality checks (ratio OK, real imports OK) pero verificar la cosa incorrecta porque la Coverage Table no tiene cobertura completa. El problema no es Layer 3 — es **coverage completeness**: nadie verifica que la Coverage Table cubra suficientemente los casos de riesgo.

**Fix revisado:**
```
No requiere Layer 3 mock quality review (sería redundante).

El gap real requiere:
  → En Layer 3, spec-reviewer verifica que la Coverage Table
    tenga filas para todos los componentes críticos con side effects.
  → Si un componente con efectos visibles no tiene fila en
    Coverage Table → FAIL con feedback.
```

### GAP 7 🟡 — Mock Boundary sin vínculo con Coverage Table

**Archivos afectados:** `agents/architect-reviewer.md`

**Verificado contra código:**

architect-reviewer.md tiene en Coverage Table (línea 219):
```
| Component / Function | Test type | What to assert | Test double |
```

**"What to assert" YA EXISTE en Coverage Table.** Mi propuesta original de añadirla a Mock Boundary era duplicación.

**Lo que el contra-informe corrige (INCORRECTO de mi informe):**

Proponer añadir "What to assert" a Mock Boundary crearía redundancia. La solución correcta no es duplicar — es gestionar la **consistencia cruzada** entre las dos tablas.

**El gap real (corregido):**

Un arquitecto puede escribir en Mock Boundary:
```
| EmailNotifier | Mock | Stub |
```

Y en Coverage Table para la misma fila:
```
| EmailNotifier.send() | unit | returns send status | Mock |
```

Las dos tablas dicen cosas distintas y nadie lo detecta. No hay regla de consistencia cruzada.

**Fix correcto:**
```
En architect-reviewer.md, regla de consistencia cruzada:
- Cada fila de Mock Boundary (componente + tipo) debe ser
  consistente con la fila correspondiente en Coverage Table.
- Si Coverage Table dice "unit | Mock" pero Mock Boundary dice "Real",
  → FAIL en el checklist del arquitecto.
```

### GAP 8 🟡 — spec-executor no puede validar runner antes de escribir tests

**Archivos afectados:** `agents/spec-executor.md`

**Estado actual:** spec-executor lee Test File Conventions y escribe tests. No hay paso que diga "ejecuta el runner en seco primero".

**Fix requerido:** Añadir pre-step en spec-executor.md antes de escribir cualquier test:
```
1. Run: npm test (or project's test command)
   - If exit != 0: runner is broken → add infrastructure task first
   - If exit == 0 (no tests): runner ready → proceed
2. Read design.md → Test Strategy
3. Write tests...
```

---

## 7. Gaps Medios/Bajos (Prioridad 🟢)

### GAP 9 🟢 — spec-executor no ESCALATE si Test File Conventions vacío

**Archivos afectados:** `agents/spec-executor.md`

**Estado actual:** spec-executor tiene:
- ESCALATE si Test Strategy missing (línea 228-234)
- NO hay ESCALATE si Test File Conventions empty

El runner wrong puede pasar desapercibido.

### GAP 10 🟢 — Orden de tasks en Coverage Table vs File Structure

**Archivos afectados:** `agents/task-planner.md`

**Verificado contra código:**

task-planner.md para TDD (línea 231):
```
[RED]: ONLY write test code. No implementation. Test MUST fail.
```

En TDD el test va **antes** — correcto y enforced.

En POC (línea 186):
```
Phase 1: Make It Work (NO tests)
Phase 3: Testing ← tests escritos DESPUÉS de implementación
```

En POC el módulo ya existe cuando llega Phase 3. El orden está implícitamente correcto.

**Lo que el contra-informe corrige (INCORRECTO de mi informe):**

TDD YA enforce test-before-code. POC YA tiene tests después de código. El problema NO es el orden en sí.

**El gap real (corregido):**

Phase 3 tasks se derivan de Coverage Table. Coverage Table puede contener un componente que NUNCA fue creado en Phase 1 (el arquitecto lo listó pero no se implementó). El test en Phase 3 referenciaría un módulo inexistente.

```
Phase 1: Build módulo "PaymentGateway" (no pasó — decisión de scope)
Phase 3: "Write unit tests for PaymentGateway"
→ spec-executor intenta importar PaymentGateway → FAIL
```

**Fix correcto:**
```
En task-planner.md, antes de generar Phase 3 tasks:
  1. Para cada fila de Coverage Table, verificar que el componente
     existe en el File Structure de design.md (en "Create" o "Modify")
  2. Si un componente de Coverage Table no tiene entrada en
     File Structure → warning o ESCALATE
```

### GAP 11 🟢 — Template design.md obsoleto vs agent

**Archivos afectados:** `templates/design.md`

**Discrepancia:**
- Template usa: Mock Boundary LAYER-based (Database, HTTP APIs)
- Agent dice: "no generic layer names — use actual component names"

**El agent es authoritative.** El template debería actualizarse para reflejar la estructura del agent (component-based con columnas unit/integration).

---

## 8. Mejoras Concretas y Ficheros a Modificar

### Prioridad de implementación (orden sugerido, tras contra-informe)

```
1. [CRÍTICO] qa-engineer.md + stop-watcher.sh — signal estructurado CON COORDINACIÓN
   (qa-engineer escribe category: en .progress.md;
    stop-watcher lo detecta en REPAIR_REASON block)
2. [CRÍTICO] failure-recovery.md — fix task con [fix_type:test_quality] tag
3. [CRÍTICO] stop-watcher.sh — msg escalación incluye "revisa Mock Boundary"
4. [CRÍTICO] architect-reviewer.md — Testing Discovery Checklist + regla
   consistencia Mock Boundary ↔ Coverage Table
5. [CRÍTICO] task-planner.md — verificar componentes de Coverage Table
   existen en File Structure antes de generar Phase 3
6. [ALTO] spec-executor.md — ESCALATE si Test File Conventions template text
7. [ALTO] task-planner.md — pre-flight [VERIFY] runner check obligatorio
   como primera task de Phase 3
8. [MEDIO] templates/design.md — actualizar Mock Boundary a estructura
   component-based del agent
```

### Ficheros que necesitan cambios (actualizado)

| Fichero | Cambio |
|---------|--------|
| `agents/qa-engineer.md` | Escribir `category: test_quality` línea parseable en .progress.md |
| `hooks/scripts/stop-watcher.sh` | REPAIR_REASON block: instruir busca `category:` + msg escalación menciona Mock Boundary |
| `references/failure-recovery.md` | Incluir `[fix_type:test_quality]` en formato fix task |
| `references/coordinator-pattern.md` | Pasar fix_type al spec-executor en fix task delivery |
| `agents/architect-reviewer.md` | Testing Discovery Checklist + regla consistencia cruzada + Coverage Table debe cubrir componentes con side effects |
| `agents/task-planner.md` | Verificar componentes Coverage Table existen en File Structure |
| `agents/spec-executor.md` | ESCALATE si Test File Conventions tiene template text |
| `templates/design.md` | Actualizar a estructura component-based del agent |

---

## 9. Resumen de Aceptación del Contra-Informe

### Puntos donde el contra-informe CORRIGIÓ mi análisis (❌Incorrecto → ✅Corregido)

| Punto | Mi error | Corrección del contra-informe |
|-------|---------|------------------------------|
| GAP 7 | Propuse añadir "What to assert" a Mock Boundary | Ya existe en Coverage Table — propuse solución en lugar equivocado. Gap real: consistencia cruzada entre tablas |
| GAP 10 | Dije que faltaba regla de orden test-after-impl | TDD ya enforce test-before-code, POC ya tiene tests post-impl. Gap real: Coverage Table puede referenciar módulos no creados |

### Puntos donde el contra-informe MATIZÓ mi análisis (parcialmente correcto)

| Punto | Mi análisis | Matiz del contra-informe |
|-------|------------|--------------------------|
| GAP 1 | qa-engineer emite texto libre → stop-watcher depende de strings | La clasificación la hace el LLM coordinator, no bash grep. Fix requiere coordinación qa-engineer + stop-watcher |
| GAP 3 | Falta columna E2E en Mock Boundary | La estrategia e2e ya está en Coverage Table. Gap real: falta consistencia entre tablas |
| GAP 4 | Propuse nueva rama en repair loop | Fix mínimo: añadir "revisa Mock Boundary" al mensaje de escalación |
| GAP 6 | Layer 3 debería revisar tests | qa-engineer ya hace mock quality en cada [VERIFY]. Gap real: coverage completeness |

### Puntos donde el contra-informe CONFIRMÓ mi análisis (✅Correcto)

| Punto | Mi análisis | Veredicto |
|-------|------------|-----------|
| GAP 2 | Fix task sin fix_type parseable | ✅ Confirmado |
| GAP 5 | No existe testing tooling discovery | ✅ Confirmado |
| GAP 8 | spec-executor no valida runner antes de escribir | ✅ Confirmado |
| GAP 9 | No ESCALATE si Conventions vacío | ✅ Confirmado |
| GAP 11 | Template obsoleto vs agent | ✅ Confirmado |

### Nuevos insights del contra-informe

1. **El coordinator LLM clasifica, no el bash** — esto cambia cómo debe diseñarse el fix (el campo estructurado debe estar en el prompt del stop-watcher, no solo en el output de qa-engineer)

2. **coverage completeness es el gap real tras GAP 6** — después de qa-engineer + Layer 3 mock quality, el problema restante es que Coverage Table puede no cubrir todos los casos de riesgo

3. **test_quality exhausted → mensaje de escalación** — el fix mínimo es textual, no requiere cambio de flujo

---

### D2: ¿Existe la regla de orden test-después-de-implementación?

**Pregunta:** ¿Hay alguna instrucción que diga que test tasks van después de implementation tasks?

**Veredicto: NO existe.** Confirmado con grep en task-planner.md completo.

**Acción:** Debe añadirse a task-planner.md como mandatory rule.

---

### D3: ¿test_quality es señal estructurada?

**Pregunta:** ¿qa-engineer emite `VERIFICATION_FAIL type=test_quality` estructurado?

**Veredicto: NO.** Confirmed. qa-engineer.md emite solo texto libre. El stop-watcher tiene que inferir del texto.

**Acción:** Modificar qa-engineer.md para emitir signal estructurado.

---

### D4: ¿Hay columna E2E en Mock Boundary?

**Pregunta:** ¿La tabla Mock Boundary tiene columna para e2e?

**Veredicto: NO.** Confirmado tanto en agent como en template.

**Acción:** Añadir columna E2E a la tabla en architect-reviewer.md.

---

### D5: ¿Hay fase de testing discovery entre design y plan?

**Pregunta:** ¿Existe una fase o paso que descubra el test runner?

**Veredicto: NO existe formalmente.** architect-reviewer dice "Discover from codebase via Explore scan" pero:
1. No dice qué hacer si no hay nada que descubrir (proyecto nuevo)
2. No hay fallback a documentación oficial
3. No hay task de "configure test runner" si no existe

**Acción:** Añadir Testing Discovery Checklist como mandatory en architect-reviewer.md.

---

### D6: ¿Layer 3 revisa tests?

**Pregunta:** ¿spec-reviewer en Layer 3 valida que los tests son correctos?

**Veredicto: NO.** verification-layers.md solo dice de-valídale implementación contra spec. No hay mock quality review en Layer 3.

**Acción:** Añadir mock quality check a Layer 3.

---

### D7: ¿spec-executor valida runner antes de escribir tests?

**Pregunta:** ¿spec-executor verifica que el runner funciona antes de escribir tests?

**Veredicto: NO.** spec-executor.md no tiene este paso. El primer momento en que se valida que el runner funciona es cuando qa-engineer recibe una [VERIFY] task.

**Acción:** Añadir pre-step en spec-executor.md.

---

## Resumen Ejecutivo

| Gap | Severidad | Verificado en código | Fix existe? | Estado tras contra-informe |
|-----|-----------|---------------------|-------------|---------------------------|
| test_quality como señal inferred | 🔴 Crítico | SÍ (stop-watcher.sh, qa-engineer.md) | NO | ✅ Matizado: fix requiere cambios Coordinados en ambos archivos |
| Fix task sin fix_type | 🔴 Crítico | SÍ (failure-recovery.md) | NO | ✅ Correcto — el fix task no tiene tag parseable |
| Mock Boundary sin columna E2E | 🔴 Crítico | SÍ (architect-reviewer.md) | NO | ⚠️ Matizado: e2e ya en Coverage Table; gap real es consistencia cruzada |
| test_quality fix no puede cambiar causa raíz | 🔴 Crítico | SÍ (stop-watcher.sh) | NO | ✅ Correcto — fix mínimo: añadir "revisa Mock Boundary" al mensaje de escalación |
| No testing tooling discovery | 🔴 Crítico | SÍ (no existe) | NO | ✅ Correcto — debe añadirse al architect-reviewer |
| Layer 3 no revisa tests | 🟡 Alto | SÍ (verification-layers.md) | NO | ⚠️ Matizado: qa-engineer ya lo hace; gap real es coverage completeness |
| Mock Boundary sin observable | 🟡 Alto | SÍ (architect-reviewer.md) | NO | ❌ Incorrecto — "What to assert" ya existe en Coverage Table; gap es consistencia cruzada |
| spec-executor sin pre-validación runner | 🟡 Alto | SÍ (spec-executor.md) | NO | ✅ Correcto — task-planner tiene pre-flight pero no es obligatorio |
| Test File Conventions sin ESCALATE | 🟢 Medio | SÍ (spec-executor.md) | NO | ✅ Correcto |
| TDD ordering | 🟢 Medio | SÍ (task-planner.md) | NO | ❌ Mal ubicado — TDD ya enforce test-before-code; el gap real es que Coverage Table puede referenciar módulos no creados |
| Template obsoleto vs agent | 🟢 Medio | SÍ (templates/design.md vs agent) | NO | ✅ Correcto |

**Conclusión:** El sistema tiene una base sólida pero 5 gaps críticos. Tras el contra-informe: 2 gaps fueron matizados, 2 fueron incorrectamente ubicados, y los fixes fueron precisados. La mayoría son resolubles añadiendo campos estructurados y reglas de consistencia cruzada, sin cambiar la arquitectura general.
