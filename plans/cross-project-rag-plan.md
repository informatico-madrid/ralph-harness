# Cross-Project RAG — Plan de Implementación

**Fecha:** 2026-05-22
**Tipo:** Feature Plan (Fase 3 RAG)
**Estado:** Investigación completada, pendiente spec
**Documento base:** `technical-cross-project-rag-research-2026-05-22.md`

---

## Objetivo

Permitir que RAG recupere contexto de specs de **proyectos externos** al proyecto actual, más allá del `collection_prefix` por proyecto.

---

## Estado Actual

- `allow_cross_project: false` existe en [`rag/config.py`](plugins/ralphharness/rag/config.py) pero no hace nada funcional
- 6 colecciones por proyecto: `{prefix}{project}-{spec_name}`
- `_retrieve_all()` en [`service.py`](plugins/ralphharness/rag/service.py) filtra por prefijo de proyecto → solo retorna resultados del proyecto actual
- No existe `project_name` en el payload de los chunks indexados

---

## Arquitectura Deseada

```
Project A (RalphHarness)          Proyecto B (otro workspace)
┌─────────────────────┐           ┌─────────────────────┐
│ specs/               │           │ specs/               │
│  └── my-spec/       │           │  └── auth-service/   │
└─────────┬───────────┘           └──────────┬──────────┘
          │                                    │
          │  rag_index_task my-spec            │  rag_index_task auth-service
          │  (project_name="ralph-harness")    │  (project_name="backend-api")
          ▼                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  Qdrant (localhost:6333)                                         │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │ sr-ralph-harness-my-spec │  │ sr-backend-api-auth-service  │ │
│  │  project_name: ralph...   │  │  project_name: backend-api  │ │
│  │  spec_name: my-spec       │  │  spec_name: auth-service    │ │
│  └──────────────────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
          │                                    │
          │  rag_cross_retrieve "JWT expired"   │
          │  allow_cross_project: true         │
          ▼
  Recovery de chunks de AMBOS proyectos
  filtrados por allowed_projects o sin filtro si allowlist vacío
```

---

## Plan de Implementación (4 fases, 11h)

### Fase 1 — Cross-Collection Retrieval (MVP) · 4h

Habilitar retrieval sin filtro de prefijo.

| Tarea | Archivo | Descripción |
|-------|---------|-------------|
| F1.1 | `rag/config.py` | Habilitar lógica `allow_cross_project` — hoy es no-op |
| F1.2 | `rag/types.py` | Agregar campo `project_name: str = ""` al dataclass `Chunk` |
| F1.3 | `rag/providers/qdrant.py` | `index()` — incluir `project_name` en payload de cada chunk |
| F1.4 | `rag/providers/faiss.py` | `index()` — incluir `project_name` en metadata de cada vector |
| F1.5 | `rag/service.py` | `_retrieve_all()` — **quitar** filtro por prefijo cuando `allow_cross_project=true`; iterar TODAS las colecciones |
| F1.6 | `rag/providers/qdrant.py` | `retrieve_raw()` — filtrar por `project_name` si `allowed_projects` está definido |
| F1.7 | `tests/` | Tests: `test_cross_project_retrieval`, `test_project_name_in_payload` |

**Criterio de done:** `rag_retrieve` con `allow_cross_project=true` retorna chunks de cualquier proyecto indexado en Qdrant.

---

### Fase 2 — Project Allowlist · 3h

Control granular sobre qué proyectos son accesibles.

| Tarea | Archivo | Descripción |
|-------|---------|-------------|
| F2.1 | `rag/config.py` | Agregar campo `allowed_projects: list[str] = field(default_factory=list)` |
| F2.2 | `rag/config.py` | Soportar env var `RALPH_RAG_ALLOWED_PROJECTS=proj1,proj2` |
| F2.3 | `rag/config.py` | Validación: si `allowed_projects` tiene items, `allow_cross_project` se ignora (allowlist wins) |
| F2.4 | `rag/service.py` | `_retrieve_all()` — filtrar por `project_name IN allowed_projects` cuando la lista no está vacía |
| F2.5 | `tests/` | Tests: `test_allowlist_filter`, `test_env_var_allowed_projects` |

**Criterio de done:** `allowed_projects: [backend-api]` solo retorna chunks con `project_name: backend-api`.

---

### Fase 3 — lib-rag.sh Integration · 2h

Exponer funcionalidad cross-project en Bash entry point.

| Tarea | Archivo | Descripción |
|-------|---------|-------------|
| F3.1 | `hooks/scripts/lib-rag.sh` | Nueva función `rag_cross_retrieve()` que pasa `--allow-cross-project` al CLI |
| F3.2 | `hooks/scripts/lib-rag.sh` | Soportar formato `project_name:collection` en `--collection` (ej: `backend-api:tasks`) |
| F3.3 | `rag/__main__.py` | CLI: parsear `--allow-cross-project` y `--allowed-projects` |
| F3.4 | `tests/` | Tests Bash: `test_rag_cross_retrieve`, `test_project_collection_format` |

**Criterio de done:** desde Bash: `rag_cross_retrieve "query" 5` retorna chunks cross-project.

---

### Fase 4 — Audit & Observability · 2h

Visibilidad sobre quién consulta qué proyecto.

| Tarea | Archivo | Descripción |
|-------|---------|-------------|
| F4.1 | `rag/observability.py` | Agregar campo `cross_project_query` a `retrieval-metrics.log` con `project_name` origen |
| F4.2 | `rag/service.py` | Emitir `RETRIEVAL_FAILED` con `phase: cross-project` cuando allowlist check falla |
| F4.3 | `rag/config.py` | Agregar `cross_project_audit: bool = False` — si true, loguear cada query cross-project |
| F4.4 | `rag-doctor.md` | Actualizar output para mostrar estadisticas cross-project (colecciones por proyecto, queries por proyecto) |

**Criterio de done:** `rag-doctor` muestra breakdown por proyecto y `retrieval-metrics.log` incluye `cross_project_query: true/false`.

---

## Open Questions (Pendientes de Decisión)

| # | Pregunta | Opciones | Recomendación |
|---|----------|---------|---------------|
| OQ1 | ¿Cómo descubrir proyectos externos? | A) Glob patterns en config<br>B) Qdrant `list_collections()`<br>C) Registro centralizado en `~/.cache` | B + A combinados |
| OQ2 | ¿Migrar colecciones existentes? | A) Backfill con re-indexación<br>B) Skip y solo nuevos specs llevan `project_name`<br>C) Patch in-place con Qdrant set payload | B (no romper existente) |
| OQ3 | ¿Staleness threshold por proyecto o global? | Por proyecto permite proyectos activos de excluir inactivos | Por proyecto |
| OQ4 | ¿Qué pasa si `allowed_projects` está vacío Y `allow_cross_project=true`? | A) Todas las colecciones<br>B) Error<br>C) Solo el proyecto actual | A (comportamiento actual con prefijo) |

---

## Archivos a Modificar

| Archivo | Cambios |
|---------|---------|
| `plugins/ralphharness/rag/config.py` | `allowed_projects`, `cross_project_audit`, lógica `allow_cross_project` |
| `plugins/ralphharness/rag/types.py` | Campo `project_name` en `Chunk` |
| `plugins/ralphharness/rag/service.py` | `_retrieve_all()` sin filtro prefijo, filtrado por allowlist |
| `plugins/ralphharness/rag/providers/qdrant.py` | `project_name` en payload, `retrieve_raw()` con filtro |
| `plugins/ralphharness/rag/providers/faiss.py` | `project_name` en metadata |
| `plugins/ralphharness/rag/__main__.py` | CLI flags `--allow-cross-project`, `--allowed-projects` |
| `plugins/ralphharness/hooks/scripts/lib-rag.sh` | `rag_cross_retrieve()`, soporte `project:collection` |
| `plugins/ralphharness/commands/rag-doctor.md` | Estadísticas cross-project |
| `plugins/ralphharness/rag/observability.py` | Métricas cross-project |
| `tests/test_cross_project.py` | Nuevo archivo |

---

## Dependencias

- `qdrant-client` — para `list_collections()` y payload filtering
- No requiere nuevos paquetes

---

## Descartados del Proyecto (❌)

Según brainstorming (`brainstorming-session-2026-05-20-09-04.md`, líneas 551-576), estas features fueron descartadas con razones técnicas válidas y NO deben considerarse para future specs:

| Feature | Razón de descarte |
|---------|-------------------|
| Multi-modal RAG | Specs son markdown puro, no tienen imágenes |
| RAG con Memory | Función del LLM, no responsabilidad del plugin |
| RAG con Tool Use | Redundante — agents ya usan tools directamente |
| Background Service | Plugin no corre servicios en background |
| Re-ranking advanced | Optimización prematura, no core feature |
| Graph RAG (original) | "Specs no tienen relaciones graph naturales" — complejidad excesiva |

---

## Postergados para Fase 3 Advanced

El roadmap del brainstorming (líneas 611-615) define una **Fase 3: Advanced** con la condición "Solo si Fase 1 y 2 tienen éxito". Solo Cross-Project RAG tiene plan creado:

| Feature | Status |
|---------|--------|
| Cross-Project RAG | ✅ Plan creado (este documento) |
| Graph RAG Lite | ❌ Sin plan — descartado por complejidad excesiva |
| Agentic RAG | ❌ Sin plan — agents ya tienen loop de reflexión |

**Condición para activar Fase 3:** validar que Fase 1 y Fase 2 tienen adopción y métricas positivas antes de considerar Graph RAG o Agentic RAG.

---

*Plan generado: 2026-05-22*
*Basado en: `_bmad-output/planning-artifacts/research/technical-cross-project-rag-research-2026-05-22.md`*