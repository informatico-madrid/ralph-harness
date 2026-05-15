# LangChain — Improving Deep Agents with Harness Engineering

> **Fuente**: https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering
> **Autor**: Vivek Trivedy
> **Fecha original**: Febrero 17, 2026
> **Tipo**: Caso de estudio con resultados cuantificables
> **Fecha de captura**: 2026-05-13

---

## TLDR

LangChain mejoró su coding agent **13.7 puntos** (de 52.8% a 66.5%) en Terminal-Bench 2.0 **cambiando solo el harness**, sin cambiar el modelo (gpt-5.2-codex). Esto demuestra que el harness es el factor más importante en rendimiento de agentes.

---

## El Objetivo del Harness Engineering

> "The goal of a harness is to mold the inherently spiky intelligence of a model for tasks we care about."

Harness Engineering es sobre **sistemas**, no sobre prompts. Estás construyendo tooling alrededor del modelo para optimizar:
- Task performance
- Token efficiency
- Latencia
- Fiabilidad

---

## Setup del Experimento

- **Benchmark**: Terminal-Bench 2.0 (89 tareas across ML, debugging, biology, etc.)
- **Modelo**: gpt-5.2-codex (fijo durante todo el experimento)
- **Orquestación**: Harbor (spins up sandboxes via Daytona)
- **Observabilidad**: LangSmith (traces, latency, token counts, costs)
- **Baseline**: 52.8% con prompt default + tools estándar

---

## Las 3 Categorías de Knobs

### 1. System Prompt
Instrucciones de alto nivel que definen cómo el agente aborda problemas.

### 2. Tools
Funciones disponibles para el agente (bash, file operations, etc.)

### 3. Middleware (Hooks)
**El knob más impactante.** Hooks alrededor de model y tool calls que:
- Interceptan antes/después de cada acción
- Inyectan contexto adicional
- Detectan patrones problemáticos
- Fuerzan verificación

---

## El Trace Analyzer Skill

Flujo para análisis repetible de errores:

1. **Fetch** experiment traces from LangSmith
2. **Spawn** parallel error analysis agents → main agent synthesizes findings
3. **Aggregate** feedback and make targeted changes to the harness

Funciona como **boosting** en ML: enfocarse en los errores de runs anteriores para mejorar iterativamente.

**Warning**: Cambios que overfitean a una tarea son malos para generalización y pueden causar regresiones en otras tareas.

---

## Qué Mejoró el Rendimiento

### 1. Build & Self-Verify (+mayor impacto)

Los modelos NO tienen tendencia natural a verificar su trabajo. El patrón más común de falla:
> El agente escribió una solución, re-leyó su propio código, confirmó que "se ve bien", y paró.

**Solución**: Añadir guidance al system prompt con 4 fases:

1. **Planning & Discovery**: Leer la tarea, escanear codebase, crear plan basado en spec + cómo verificar
2. **Build**: Implementar con verificación en mente. Crear tests si no existen (happy paths + edge cases)
3. **Verify**: Correr tests, leer output completo, comparar contra la spec original (no contra tu propio código)
4. **Fix**: Analizar errores, revisitar la spec original, corregir

**Middleware clave**: `PreCompletionChecklistMiddleware` — intercepta al agente antes de salir y le recuerda hacer verification pass contra la Task spec. Similar a un **Ralph Wiggum Loop** donde un hook fuerza al agente a continuar ejecutando.

### 2. Context Engineering a Nombre del Agente

Los agentes no conocen su entorno. Hay que inyectar contexto:

- **Directory Context & Tooling**: `LocalContextMiddleware` corre al inicio para mapear el cwd y directorios. Corre bash commands para encontrar tools (Python installations, etc.). Reduce error surface y ayuda a **onboardear** al agente.
- **Teaching Agents to Write Testable Code**: Añadir prompting que diga que su trabajo será medido contra tests programáticos. Specs que mencionan file paths deben seguirse exactamente. Stress edge-cases para evitar solo "happy path".
- **Time Budgeting**: Inyectar time budget warnings para que el agente termine y pase a verification. Los agentes son malos estimando tiempo.

> **"The purpose of the harness engineer: prepare and deliver context so agents can autonomously complete work."**

### 3. Loop Detection para Doom Loops

Los agentes pueden ser miópicos una vez deciden un plan → "doom loops" con pequeñas variaciones al mismo approach roto (10+ veces en algunos traces).

**Solución**: `LoopDetectionMiddleware` que trackea per-file edit counts via tool call hooks. Añade contexto como "...consider reconsidering your approach" después de N edits al mismo archivo.

**Nota importante**: Este es un design heuristic que worka alrededor de problemas percibidos del modelo. A medida que los modelos mejoren, estos guardrails serán innecesarios.

### 4. Reasoning Budget (Compute Allocation)

Modelos de reasoning pueden correr por horas. Hay que decidir cuánto compute gastar en cada subtask.

**Heurística**: "Reasoning Sandwich" — xhigh-high-xhigh
- **Planning**: xhigh reasoning (entender el problema completamente)
- **Execution**: high reasoning (implementar eficientemente)
- **Verification**: xhigh reasoning (catch mistakes)

**Resultado**: xhigh en todo = 53.9% (timeouts), high en todo = 63.6%, sandwich = 66.5%

**Tendencia futura**: Adaptive Reasoning (Claude, Gemini) donde el modelo decide cuánto compute gastar.

---

## Practical Takeaways

### 1. Context Engineering on Behalf of Agents
Context assembly es difícil para agentes hoy, especialmente en entornos nuevos. Onboardear modelos con:
- Directory structures
- Available tools
- Coding best practices
- Problem-solving strategies

### 2. Help Agents Self-Verify Their Work
Los modelos están biased hacia su primera solución plausible. Prompt agresivamente para:
- Correr tests
- Refinar soluciones
- Comparar contra la spec original

### 3. Tracing as a Feedback Signal
Traces permiten a los agentes auto-evaluarse y debuggearse. Es importante debuggear tooling y reasoning juntos (ej: modelos van por caminos equivocados porque les falta una tool o instrucciones).

### 4. Detect and Fix Bad Patterns in the Short Term
Los modelos no son perfectos. El trabajo del harness designer es diseñar alrededor de shortcomings actuales mientras planea para modelos más inteligentes en el futuro. Blind retries y no verificar trabajo son buenos ejemplos.

### 5. Tailor Harnesses to Models
Diferentes modelos requieren diferente prompting. Una test run con Claude Opus 4.6 scored 59.6% con un harness version anterior — competitive pero peor que Codex porque no se corrió el mismo Improvement Loop con Claude.

---

## Open Research Areas

- **Multi-model systems**: Codex, Gemini, y Claude juntos
- **Memory primitives**: Continual learning para que agentes mejoren autónomamente
- **Cross-model harness measurement**: Cómo cambios en el harness afectan diferentes modelos
- **RLMs**: Métodos para minar traces más eficientemente

---

## Recursos

| Recurso | URL |
|---------|-----|
| Deep Agents CLI (Python) | https://github.com/langchain-ai/deepagents |
| Deep Agents CLI (JS) | https://github.com/langchain-ai/deepagentsjs |
| LangSmith Traces Dataset | https://smith.langchain.com/public/29393299-8f31-48bb-a949-5a1f5968a744/d |
| Harbor Framework | https://harborframework.com |
| Daytona Sandboxes | https://www.daytona.io |
| Codex Prompting Guide | https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide |
| Claude Prompting Best Practices | https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices |
