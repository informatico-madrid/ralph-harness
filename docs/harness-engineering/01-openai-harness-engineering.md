# OpenAI — Harness Engineering

> **Fuente**: https://openai.com/index/harness-engineering/
> **Autor**: Lilian Weng
> **Tipo**: Documento fundacional
> **Fecha de captura**: 2026-05-13

---

## Definición Core

**Harness Engineering** es la disciplina de diseñar el andamiaje — contexto, herramientas, planning artifacts, loops de verificación, memoria, y sandboxing — que rodea a un agente IA y determina si succeeds o fail en tareas reales.

La metáfora: IA = pura sangre, arneses = control para que no salga desbocado.

> **Insight clave de OpenAI**: "Every component here exists because the model can't do it alone — and the best harnesses are designed knowing those components will become unnecessary as models improve."

La implicación directa: **el harness es un documento de deuda técnica** — cada componente que añades hoy es una muleta que debería poder retirarse mañana.

---

## Los 6 Componentes Fundamentales del Harness

### 1. Context Management
El context window es un recurso finito y caro. El harness debe decidir:
- Qué entra en el context en cada momento
- Cuándo comprimir history
- Qué información debe sobrevivir a la compresión

**Hallazgo crítico** (de Claude Code Compaction):
> Lo que sobrevive: current task, recent errors, filenames.
> Lo que se pierde: initial instructions, intermediate decisions, style rules.

**Regla práctica**: Nunca confíes en compaction para reglas críticas — ponlas en CLAUDE.md donde sobreviven a cualquier compresión.

**Herramientas relevantes**:
- LLMLingua (hasta 20x compresión con pérdida mínima)
- Prompt Caching (hasta 90% descuento en tokens cacheados)
- Autonomous Context Compression (el agente decide cuándo comprimir estratégicamente)

### 2. Memory Systems
Patrón de 3 capas (según Letta/MemGPT):
1. **Core memory**: facts activos de la sesión actual
2. **Archival memory**: hechos que pueden retrievearse
3. **Recall memory**: procedural — cómo hacer cosas

**Problema crítico documentado**:
- 60% de destrucción de facts durante compaction
- 54% de behavioral drift por constraint erosion en summarizations encadenadas
- Knowledge Objects (hash-addressed discrete fact tuples) logran 100% accuracy a 252× menor costo que in-context storage

### 3. Tool Design
El diseño de herramientas es **UX del agente**. Las guidelines de Anthropic:
- Naming consistente y predecible
- Schemas estrictos con error surfaces claras
- Valor de retorno que no requiere parsing ad-hoc

**Descubrimiento clave**: Code Execution with MCP demuestra que hasta 98.7% de reducción de tokens es posible cuando los agentes escriben código para interactuar con MCP servers en lugar de llamar herramientas directamente.

### 4. Planning Artifacts
Los agentes necesitan estructura para organizar su trabajo:
- Task breakdowns
- Dependency graphs
- Progress tracking
- Verification contracts

### 5. Verification & Validation
El agente necesita saber si completó correctamente:
- Per-task verification commands
- Global CI state separate from task verification
- Anti-fabrication checks (never trust pasted output)
- Signal-based communication (HOLD, DEADLOCK, etc.)

### 6. Sandboxing
Protección del entorno:
- Git checkpoints before execution
- Rollback capability
- Read-only detection
- Circuit breakers for runaway loops

---

## Papers Clave Referenciados

| Paper | URL | Relevancia |
|-------|-----|------------|
| ReAct: Synergizing Reasoning and Acting | https://arxiv.org/abs/2210.03629 | Patrón Thought/Action/Observation |
| Unrolling the Codex Agent Loop | https://openai.com/index/unrolling-the-codex-agent-loop/ | Descomposición canónica de cada iteración |

---

## Frameworks de Orquestación

| Framework | Stars | Fortalezas |
|-----------|-------|-----------|
| LangGraph | ~30K | Graph-based state machine, checkpoint persistence, supervisor/subagent topologies |
| OpenAI Agents SDK | ~9K | Lightweight, handoffs y guardrails, production successor to Swarm |
| Google ADK | — | Code-first, built-in multi-agent, tool registration, eval pipeline |
| AutoGen | — | Microsoft, multi-agent conversation, complete AgentChat layer |
| CrewAI | — | Dual-layer: autonomous delegation + Flow para deterministic control |
| PydanticAI | — | Type-safe, RunContext dependency injection, tool definitions as Pydantic models |
| Mastra | 22K+ | TypeScript-native, 40+ providers, workflows, RAG pipelines |
| Vercel AI SDK | — | 20M+ monthly downloads, Agent abstraction, ToolLoopAgent |

---

## Memory Systems

| Sistema | Tipo | Diferenciador |
|---------|------|---------------|
| mem0 | Universal | Drop-in, YC-backed, AWS Agent SDK exclusive provider |
| Letta | Stateful | Tres-tier memory (core/archival/recall), agent loop redesign público |
| Zep | Purpose-built | Summarization automático, entity extraction, semantic search |
| Stash | Self-hosted | 8-stage consolidation pipeline, built-in MCP server |
| OpenViking (ByteDance) | Context DB | Hierarchical context delivery, self-evolving layer |

---

## Recursos Comunitarios

| Recurso | URL |
|---------|-----|
| awesome-harness-engineering | https://github.com/ai-boost/awesome-harness-engineering (689 stars) |
