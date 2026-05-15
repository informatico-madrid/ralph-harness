# Investigación Previa del Proyecto — Harness Engineering

> **Fecha**: 2026-05-13
> **Tipo**: Índice de investigación interna
> **Alcance**: Documentos generados el 2026-05-01 durante la investigación de dominio

---

## Resumen

El proyecto ya realizó una investigación exhaustiva sobre Harness Engineering el **1 de mayo de 2026**. Esta investigación produjo 4 documentos que mapean el estado del arte contra la implementación actual de RalphHarness.

---

## Documentos de Investigación

### 1. Investigación de Dominio

**Archivo**: `_bmad-output/planning-artifacts/research/domain-harness-engineering-research-2026-05-01.md`

**Contenido**:
- Síntesis del conocimiento disponible sobre la disciplina
- 6 componentes fundamentales del harness (según OpenAI)
- Panorama de frameworks de orquestación (LangGraph, OpenAI SDK, etc.)
- Memory systems (mem0, Letta, Zep, Stash, OpenViking)
- Papers clave y recursos comunitarios

**Hallazgo clave**: *"Esto es harness engineering rudimentario. La oportunidad es formalizarlo."*

### 2. Diagnóstico de Implementación

**Archivo**: `plans/harness-implementation-diagnostic-2026-05-01.md`

**Contenido**:
- Análisis de mecanismos de control existentes en el loop de ejecución
- 5 componentes analizados: stop-watcher.sh, spec-executor.md, implement.md, cancel.md, checkpoint.sh
- Problemas específicos detectados por componente
- Oportunidades de "Harness-Building Tools"

**Hallazgo clave**: El harness existe y funciona, pero tiene brechas significativas en verificación, race conditions, y repair loop.

### 3. Brainstorming (50 Ideas)

**Archivo**: `_bmad-output/planning-artifacts/brainstorming/harness-engineering-implementation-brainstorm-2026-05-01.md`

**Contenido**:
- 50 ideas de implementación generadas
- 7 ideas top priorizadas
- 43 ideas adicionales categorizadas

### 4. Integración con Roadmap

**Archivo**: `_bmad-output/planning-artifacts/integration/harness-engineering-roadmap-integration-2026-05-01.md`

**Contenido**:
- Mapeo cruzado: Harness Engineering ↔ Engine Roadmap
- 25 gaps identificados y categorizados por severidad
- Fases de implementación propuestas
- Conflicto conceptual: "Smart Ralph ES el harness" vs. "Smart Ralph PROVEE herramientas"

**Hallazgo clave**: Hay 25 gaps entre lo que Harness Engineering recomienda y lo que RalphHarness implementa. 8 son críticos.

---

## Los 25 Gaps (Resumen)

### Críticos (8)

| Gap | Componente HE | Descripción |
|-----|--------------|-------------|
| WAL para State Writes | Agent Loop | Atomic writes con tmpfile+rename+flock |
| Signal Bus Architecture | Agent Loop | Reemplazar transcript-dependent detection con .signals/ directory |
| Declarative Harness Manifest | Todos | harness.yaml que declara qué componentes quiere el proyecto |
| Compaction Survival | Context + Memory | Proteger facts críticos a través de compaction cycles |
| Mechanical HOLD Detection | Agent Loop | grep-based check en lugar de LLM interpretation |
| State Drift Detection | Agent Loop | Pre-loop validation de tasks.md vs .ralph-state.json |
| Schema Completeness | State | nativeTaskMap, nativeSyncEnabled, nativeSyncFailureCount en schema |
| CI Snapshot Separation | Verification | Separar task verification de global CI state |

### Altos (4)

| Gap | Componente HE | Descripción |
|-----|--------------|-------------|
| Context Budget System | Context Delivery | Token budget por iteración con tiered loading |
| Veterinarian Pattern | Meta-Harness | Health-check del harness mismo |
| Parallel Group Validation | Agent Loop | Validar que TODAS las tareas [P] completaron |
| Mechanical Role Enforcement | Authorization | Hooks que previenen edición de archivos prohibidos |

### Medios (7)

| Gap | Componente HE | Descripción |
|-----|--------------|-------------|
| Harness Template Library | DX | 3-5 templates (minimal/standard/strict/experimental) |
| Harness Testing Framework | DX | Tests para el harness |
| ralph harness init | DX | Comando para scaffoldear harness |
| ralph harness doctor | DX | Diagnosticar salud del harness |
| Orphan Lock Reaper | Tool Design | Limpiar .lock files huérfanos |
| Epic State Cleanup on Cancel | Agent Loop | cancel.md no actualiza estado del epic |
| CI Drift Integration | Verification | check_ci_drift() existe pero nunca se llama |

### Deseables (6)

| Gap | Componente HE | Descripción |
|-----|--------------|-------------|
| Harness Evolution Protocol | Meta-Harness | Workflow post-failure |
| Failure Pattern Mining | Meta-Harness | Analizar .metrics.jsonl cross-spec |
| Harness Debt Tracker | Meta-Harness | Marcar componentes como muletas |
| Signal Replay | Meta-Harness | Flight data recorder |
| Harness Linter | DX | Validar harness.yaml + scripts |
| Harness Diff on Upgrade | DX | Mostrar cambios al upgrade |

---

## Fases de Implementación Propuestas

### Fase 2: Signal Bus + Harness Manifest (post-Spec 7)
1. Signal Bus Architecture — nuevo spec
2. Declarative Harness Manifest — nuevo spec
3. WAL para State Writes — nuevo spec o extensión

### Fase 3: Ecosistema HE
1. Context Budget System
2. Veterinarian Pattern
3. Parallel Group Validation
4. Mechanical Role Enforcement
5. Harness Template Library

### Fase 4: Meta-Harness y DX
1. Harness Testing Framework
2. ralph harness init / doctor
3. Harness Evolution Protocol
4. Failure Pattern Mining
5. Harness Debt Tracker
6. Compaction Survival

---

## Conflicto Conceptual

El documento de integración identifica la tensión fundamental:

> **"Smart Ralph ES el harness" vs. "Smart Ralph PROVEE herramientas"**

El roadmap actual trata a Smart Ralph como el harness mismo (mejora interna del engine). Pero la premisa del brainstorming dice: *"Smart Ralph ES el pura sangre, no el arnés."*

**Ambas capas son necesarias**:
1. ✅ Engine interno robusto (lo que hacen Specs 1-7 del roadmap)
2. ❌ Capa de herramientas para que proyectos construyan sus propios arneses (lo que falta)

---

## Estado Actual de los Gaps vs. Roadmap

| Gap del Roadmap | Gaps HE que cubre | Gaps HE que NO cubre |
|-----------------|-------------------|---------------------|
| Spec 1: engine-state-hardening | Schema, HOLD detection, State drift, CI separation | WAL, Signal Bus, Compaction |
| Spec 2: prompt-diet-refactor (CANCELLED) | Context Budget (parcialmente) | — |
| Spec 3: role-boundaries | Mechanical Role (prompt-based, no mechanical) | Hash integrity, flock wrapper |
| Spec 4: loop-safety-infra | Checkpoint, Circuit breaker, Metrics, Read-only | Veterinarian, CI Drift call |
| Spec 5: bmad-bridge-plugin | Ninguno | Harness Manifest, Templates |
| Spec 6: collaboration-resolution | BUG_DISCOVERY, Chat signals | Signal Bus |
| Spec 7: pair-debug-auto-trigger | Loop Detection (parcialmente) | Doom Loop middleware |
