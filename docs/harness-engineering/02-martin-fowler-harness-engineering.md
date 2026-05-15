# Martin Fowler — Harness Engineering: Three Interlocking Systems

> **Fuente**: https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html
> **Autor**: Martin Fowler
> **Tipo**: Arquitectura y patrones
> **Fecha de captura**: 2026-05-13

---

## Resumen

Martin Fowler descompone el harness en **3 sistemas interlocking** que se alimentan mutuamente. Cada sistema tiene un propósito claro y su ausencia causa fallas predecibles.

---

## Los 3 Sistemas

### 1. Guidance System — Cómo guías al agente

**Propósito**: Proporcionar dirección, constraints y contexto para que el agente se mueva en la dirección correcta.

**Componentes**:
- **System Prompts**: Instrucciones de alto nivel, rol, constraints
- **Context Injection**: Información del entorno inyectada automáticamente
- **Planning Artifacts**: Task breakdowns, dependency graphs, verification contracts
- **Role Definitions**: Qué puede y no puede hacer cada agente

**Principio**: El agente no sabe lo que no sabe. Tu trabajo es darle toda la información que necesita antes de que empiece a trabajar.

**Anti-patrón**: Dejar que el agente "descubra" el entorno por sí mismo. Esto causa errores evitables y gasta tokens innecesariamente.

### 2. Feedback System — Cómo el agente sabe si va bien

**Propósito**: Proporcionar señales de progreso y calidad para que el agente pueda auto-corregirse.

**Componentes**:
- **Tracing**: Registro de cada acción del agente (inputs, outputs, tool calls)
- **Verification Layers**: Checks automáticos después de cada acción
- **Metrics**: Per-task performance data (tiempo, tokens, fabrication detection)
- **Signal Protocol**: Comunicación estructurada entre agentes (HOLD, DEADLOCK, etc.)

**Principio**: Los agentes son biased hacia su primera solución plausible. Necesitan feedback mecánico, no interpretativo, para saber si realmente completaron la tarea.

**Anti-patrón**: Confianza en el output del agente sin verificación independiente. "El agente dice que pasó los tests" ≠ los tests pasaron.

### 3. Recovery System — Qué pasa cuando algo falla

**Propósito**: Detectar fallas temprano, recuperar progreso, y evitar loops infinitos.

**Componentes**:
- **Git Checkpoints**: Snapshot antes de cada ejecución
- **Rollback**: Restaurar a un estado conocido
- **Circuit Breakers**: Parar después de N fallas consecutivas
- **Retry Logic**: Reintentar con contexto diferente
- **State Integrity**: Validar que el estado interno es consistente

**Principio**: Las fallas son inevitables. Lo que separa un harness bueno de uno malo es cómo se recupera.

**Anti-patrón**: Reintentar la misma acción con el mismo contexto esperando resultado diferente (doom loop).

---

## Cómo los Sistemas Interactúan

```
Guidance → define qué hacer
  ↓
Feedback → verifica si se hizo bien
  ↓
Recovery → si falló, recupera y ajusta guidance
  ↓
Guidance → redefine con contexto nuevo
```

Los 3 sistemas forman un **loop de mejora continua**:
1. Guidance define la dirección
2. Feedback mide si la dirección es correcta
3. Recovery ajusta la dirección cuando no lo es

---

## Patrones Arquitectónicos

### Pattern: Pre-Completion Checklist
Antes de que el agente termine, un hook le recuerda verificar su trabajo contra la spec original.

### Pattern: Loop Detection
Cuando el agente edita el mismo archivo N veces sin progreso, inyectar contexto para que reconsider su approach.

### Pattern: Reasoning Sandwich
Usar más compute en planning y verification, menos en execution intermedia.

### Pattern: Context Budget
Token budget por iteración con tiered loading: mandatory → conditional → on-demand.

### Pattern: Veterinarian
Un subsistema que corre diagnósticos sobre el harness mismo. "Harness que verifica el harness."

---

## Implicaciones para RalphHarness

| Sistema Fowler | Componente RalphHarness | Estado |
|----------------|------------------------|--------|
| Guidance | System prompts, role-contracts.md, templates/ | ✅ Implementado |
| Guidance | Context injection (implement.md Step 4) | ✅ Implementado |
| Feedback | verification-layers.md (5 layers) | ✅ Implementado |
| Feedback | Tracing (chat.md, task_review.md) | ✅ Implementado |
| Feedback | Metrics (.metrics.jsonl) | ✅ Implementado |
| Recovery | checkpoint.sh (git checkpoint) | ✅ Implementado |
| Recovery | Circuit breaker (stop-watcher.sh) | ✅ Implementado |
| Recovery | State integrity validation | ✅ Implementado |
| Recovery | Loop detection middleware | ❌ No implementado |
| Feedback | Veterinarian pattern | ❌ No implementado |
| Guidance | Context budget system | ❌ No implementado |
