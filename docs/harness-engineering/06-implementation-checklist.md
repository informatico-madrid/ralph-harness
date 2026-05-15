# Checklist de Implementación de Harness Engineering

> **Fecha**: 2026-05-13
> **Tipo**: Guía práctica paso a paso
> **Fuentes**: OpenAI, Martin Fowler, LangChain, investigación interna del proyecto

---

## Visión General

Implementar Harness Engineering en un proyecto significa construir los 3 sistemas de Martin Fowler:

1. **Guidance System** — Cómo guías al agente
2. **Feedback System** — Cómo el agente sabe si va bien
3. **Recovery System** — Qué pasa cuando algo falla

Cada sistema tiene componentes obligatorios y opcionales. Esta checklist te guía desde 0 hasta un harness funcional.

---

## Fase 0: Preparación del Entorno

### Archivos necesarios en tu proyecto

- [ ] **CLAUDE.md** o **AGENTS.md** — Reglas del proyecto que sobreviven a compaction
- [ ] **`.gitignore`** — Excluir `.ralph-state.json`, `.metrics.jsonl`, `*.lock`
- [ ] **Git repo inicializado** — Necesario para checkpoints
- [ ] **CI commands documentados** — Qué comandos correr para verificar (lint, test, type-check)

### Estructura de directorios

```
mi-proyecto/
├── CLAUDE.md                  # Reglas del proyecto (survives compaction)
├── specs/                     # Specs del proyecto
│   ├── .current-spec          # Spec activa
│   └── mi-feature/
│       ├── requirements.md    # Qué quiere el usuario
│       ├── design.md          # Cómo se va a construir
│       ├── tasks.md           # Lista de tareas con Verify commands
│       ├── chat.md            # Comunicación entre agentes
│       └── task_review.md     # Revisión de calidad
└── .ralph-state.json          # Estado del loop (lo crea el sistema)
```

---

## Fase 1: Guidance System

### 1.1 System Prompt y Reglas

- [ ] **Definir rol del agente** — Qué hace y qué NO hace
- [ ] **Definir constraints de archivos** — Qué puede leer/escribir/modificar
- [ ] **Definir workflow de verificación** — Planning → Build → Verify → Fix
- [ ] **Definir reglas de commit** — Cuándo y cómo commitear
- [ ] **Definir reglas de testing** — Crear tests antes/durante implementación

### 1.2 Context Injection

- [ ] **Directory mapping** — Inyectar estructura de directorios al inicio
- [ ] **Tool discovery** — Detectar herramientas disponibles (Python, Node, etc.)
- [ ] **CI command discovery** — Detectar comandos de verificación del proyecto
- [ ] **Time budget warnings** — Avisar cuando queda poco tiempo

### 1.3 Planning Artifacts

- [ ] **Requirements template** — Formato estándar para requisitos
- [ ] **Design template** — Formato estándar para diseño técnico
- [ ] **Tasks template** — Formato estándar con Verify commands
- [ ] **Verification Contract** — Qué se verifica y cómo por cada tarea

---

## Fase 2: Feedback System

### 2.1 Verification Layers

- [ ] **Layer 0: EXECUTOR_START** — El executor confirma que entiende la tarea
- [ ] **Layer 1: Contradiction Detection** — Verificar que no hay contradicciones
- [ ] **Layer 2: Signal Check** — Confirmar que no hay señales pendientes (HOLD, etc.)
- [ ] **Layer 3: Anti-fabrication** — Ejecutar verify command independientemente, no confiar en output
- [ ] **Layer 4: Artifact Review** — Review automático de archivos generados

### 2.2 Signal Protocol

- [ ] **HOLD** — Para, no delegues más
- [ ] **DEADLOCK** — Impasse, necesito ayuda
- [ ] **BUG_DISCOVERY** — Encontré un bug, crear fix task
- [ ] **HYPOTHESIS** — Propongo root cause theory
- [ ] **EXPERIMENT** — Voy a correr test para validar
- [ ] **FINDING** — Resultado del experimento
- [ ] **ROOT_CAUSE** — Bug confirmado
- [ ] **FIX_PROPOSAL** — Sugiero fix concreto

### 2.3 Tracing y Metrics

- [ ] **Per-task metrics** — Tiempo, tokens, fabrication detection por tarea
- [ ] **Chat protocol** — Registro de comunicación entre agentes
- [ ] **Task review** — Revisión de calidad por tarea
- [ ] **Progress tracking** — Learnings y contexto para siguientes tareas

### 2.4 Self-Verification

- [ ] **Pre-completion checklist** — Hook que fuerza verification antes de terminar
- [ ] **Compare against spec** — Verificar contra la spec original, no contra tu código
- [ ] **Run full test output** — Leer output completo, no solo "passed"
- [ ] **Edge case testing** — No solo happy paths

---

## Fase 3: Recovery System

### 3.1 Git Checkpoints

- [ ] **Pre-loop checkpoint** — `git add -A && git commit -m "checkpoint: before execution"`
- [ ] **Store SHA in state** — Guardar checkpoint SHA en `.ralph-state.json`
- [ ] **Rollback command** — `git reset --hard <SHA>` para restaurar

### 3.2 Circuit Breakers

- [ ] **Consecutive failure limit** — Parar después de N fallas consecutivas (default: 5)
- [ ] **Time limit** — Parar después de N horas (default: 48h)
- [ ] **Global iteration limit** — Parar después de N iteraciones totales
- [ ] **Per-task retry limit** — Parar después de N reintentos por tarea (default: 5)

### 3.3 State Integrity

- [ ] **Pre-loop validation** — Verificar que tasks.md checkmarks = taskIndex
- [ ] **WAL for state writes** — Atomic writes con tmpfile+rename
- [ ] **Role enforcement** — Hooks que previenen edición de archivos prohibidos
- [ ] **Hash integrity** — Detectar modificaciones no autorizadas al state file

### 3.4 Loop Detection

- [ ] **Per-file edit counter** — Trackear cuántas veces se edita cada archivo
- [ ] **Doom loop detection** — Avisar después de N edits al mismo archivo sin progreso
- [ ] **Approach reconsideration** — Inyectar contexto para reconsider approach

---

## Fase 4: DX (Developer Experience)

### 4.1 Comandos de Gestión

- [ ] **`harness init`** — Crear arnés nuevo con preguntas interactivas
- [ ] **`harness doctor`** — Diagnosticar salud del arnés actual
- [ ] **`harness status`** — Ver progreso de la ejecución actual
- [ ] **`harness rollback`** — Restaurar al checkpoint anterior
- [ ] **`harness cancel`** — Cancelar y limpiar

### 4.2 Declarative Harness Manifest

- [ ] **`harness.yaml`** — Archivo que declara qué componentes quiere el proyecto
- [ ] **Schema validation** — Validar que harness.yaml es correcto
- [ ] **Template library** — 3-5 templates (minimal/standard/strict/experimental)
- [ ] **Harness linter** — Validar referencias rotas, señales inconsistentes

### 4.3 Meta-Harness

- [ ] **Veterinarian pattern** — Health-check del harness mismo
- [ ] **Harness evolution protocol** — Workflow post-failure: detect → diagnose → propose → review → apply
- [ ] **Failure pattern mining** — Analizar .metrics.jsonl cross-spec para patrones
- [ ] **Harness debt tracker** — Marcar componentes como muletas con fecha de retiro

---

## Niveles de Implementación

### Nivel 1: Mínimo Viable (Lo esencial para empezar)

| Componente | Qué necesitas |
|------------|---------------|
| Guidance | CLAUDE.md con reglas + system prompt con workflow Planning→Build→Verify→Fix |
| Feedback | 1 verification layer: correr tests después de cada tarea |
| Recovery | Git checkpoint manual antes de empezar |

### Nivel 2: Funcional (Lo que RalphHarness tiene hoy)

| Componente | Qué incluye |
|------------|-------------|
| Guidance | 10 agentes especializados + role contracts + templates |
| Feedback | 5 verification layers + signal protocol + metrics |
| Recovery | Auto-checkpoint + circuit breaker + state integrity |

### Nivel 3: Avanzado (Lo que falta por implementar)

| Componente | Qué añade |
|------------|-----------|
| Guidance | Context budget + loop detection + time budgeting |
| Feedback | Veterinarian pattern + trace analyzer + failure mining |
| Recovery | WAL writes + mechanical role enforcement + harness doctor |

### Nivel 4: Ecosistema (Futuro)

| Componente | Qué añade |
|------------|-----------|
| Guidance | harness.yaml declarativo + template library |
| Feedback | Harness testing framework + signal replay |
| Recovery | Harness evolution protocol + debt tracker + A/B testing |

---

## Cómo Empezar Hoy (Sin RalphHarness)

Si quieres implementar harness engineering en tu proyecto SIN usar RalphHarness:

### Paso 1: Crear CLAUDE.md
```markdown
# Project Rules

## Workflow
1. Planning: Read task, scan codebase, create plan
2. Build: Implement with verification in mind
3. Verify: Run tests, read FULL output, compare against spec
4. Fix: Analyze errors, revisit spec, fix

## Constraints
- Never modify .ralph-state.json
- Always run tests before marking task complete
- Commit after each task
- Compare against original spec, not your own code
```

### Paso 2: Crear git checkpoint
```bash
git add -A && git commit -m "checkpoint: before agent execution"
echo $SHA > .checkpoint-sha
```

### Paso 3: Añadir pre-completion hook
En tu system prompt:
```
Before marking any task complete:
1. Run the project's test suite
2. Read the FULL output (not just "passed")
3. If any test fails, fix and re-run
4. Compare your solution against the original task spec
```

### Paso 4: Medir
Correr tu agente en Terminal-Bench o tu propio benchmark antes y después de cada cambio al harness.
