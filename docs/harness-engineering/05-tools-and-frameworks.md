# Herramientas y Frameworks para Harness Engineering

> **Fecha**: 2026-05-13
> **Tipo**: Catálogo de ecosistema
> **Fuentes**: OpenAI, LangChain, Martin Fowler, awesome-harness-engineering

---

## Frameworks de Orquestación

| Framework | Lenguaje | Stars | Fortalezas | Mejor para |
|-----------|----------|-------|-----------|------------|
| **LangGraph** | Python | ~30K | Graph-based state machine, checkpoint persistence, supervisor/subagent | Agentes complejos con state management |
| **OpenAI Agents SDK** | Python | ~9K | Lightweight, handoffs y guardrails | Agentes OpenAI nativos |
| **Google ADK** | Python | — | Code-first, built-in multi-agent, eval pipeline | Ecosistema Google |
| **AutoGen** | Python | — | Microsoft, multi-agent conversation | Conversaciones multi-agente |
| **CrewAI** | Python | — | Dual-layer: autonomous + Flow deterministic | Equipos de agentes con roles |
| **PydanticAI** | Python | — | Type-safe, RunContext DI, Pydantic models | Agentes type-safe |
| **Mastra** | TypeScript | 22K+ | 40+ providers, workflows, RAG pipelines | Proyectos TypeScript |
| **Vercel AI SDK** | TypeScript | — | 20M+ downloads/mes, ToolLoopAgent | Web apps con agentes |

---

## Memory Systems

| Sistema | Tipo | Diferenciador | Mejor para |
|---------|------|---------------|------------|
| **mem0** | Universal | Drop-in, YC-backed, AWS exclusive | Integración rápida |
| **Letta** | Stateful | 3-tier memory (core/archival/recall) | Agentes con memoria persistente |
| **Zep** | Purpose-built | Auto-summarization, entity extraction | Conversaciones largas |
| **Stash** | Self-hosted | 8-stage consolidation, MCP server | Privacidad / on-premise |
| **OpenViking** | Context DB | Hierarchical context, self-evolving | Context delivery avanzado |

---

## Observabilidad y Tracing

| Herramienta | Para qué | URL |
|-------------|----------|-----|
| **LangSmith** | Tracing, eval, deployment de agentes | https://smith.langchain.com |
| **Harbor** | Orquestación de benchmarks y sandboxes | https://harborframework.com |
| **Daytona** | Sandboxes aislados para testing | https://www.daytona.io |

---

## Compresión de Contexto

| Herramienta | Reducción | Método | URL |
|-------------|-----------|--------|-----|
| **LLMLingua** | Hasta 20x | Compresión con pérdida mínima | github.com/microsoft/LLMLingua |
| **Prompt Caching** | Hasta 90% descuento | Cache de tokens idénticos | Provider-native (Anthropic, OpenAI) |
| **Autonomous Context Compression** | Variable | El agente decide cuándo comprimir | Paper: Letta/MemGPT |

---

## Benchmarks

| Benchmark | Tareas | Enfoque | URL |
|-----------|--------|---------|-----|
| **Terminal-Bench 2.0** | 89 | Terminal mastery (coding, ML, security) | https://www.tbench.ai |
| **Terminal-Bench 3.0** | En desarrollo | Next frontier | https://www.tbench.ai |
| **SWE-bench** | 2,294 | Real GitHub issues | https://www.swebench.com |
| **HumanEval** | 164 | Code generation | OpenAI |

---

## Recursos Comunitarios

| Recurso | Descripción | URL |
|---------|-------------|-----|
| **awesome-harness-engineering** | Catálogo curado (689 stars) | https://github.com/ai-boost/awesome-harness-engineering |
| **Deep Agents CLI** | Agent de coding de LangChain (Python) | https://github.com/langchain-ai/deepagents |
| **Deep Agents CLI** | Agent de coding de LangChain (JS) | https://github.com/langchain-ai/deepagentsjs |
| **Codex Plugin CC** | Plugin de Codex para Claude Code | https://github.com/openai/codex-plugin-cc |
| **OpenAI Skills** | Skills oficiales de OpenAI | https://github.com/openai/skills |

---

## Guías de Prompting por Modelo

| Modelo | Guía | URL |
|--------|------|-----|
| **GPT-5.x Codex** | Codex Prompting Guide | https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide |
| **Claude** | Prompting Best Practices | https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices |
| **Claude** | Adaptive Thinking | https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking |
| **Gemini** | Thinking Modes | https://ai.google.dev/gemini-api/docs/thinking |

---

## Papers Fundacionales

| Paper | Año | Relevancia | URL |
|-------|-----|-----------|-----|
| **ReAct** | 2022 | Patrón Thought/Action/Observation | https://arxiv.org/abs/2210.03629 |
| **Unrolling the Codex Agent Loop** | 2025 | Descomposición canónica de iteraciones | https://openai.com/index/unrolling-the-codex-agent-loop/ |
| **Harness Engineering (OpenAI)** | 2025 | Documento fundacional de la disciplina | https://openai.com/index/harness-engineering/ |
| **Harness Engineering (Fowler)** | 2025 | 3 sistemas interlocking | https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html |
| **Improving Deep Agents (LangChain)** | 2026 | Caso de estudio con resultados | https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering |
| **RLMs** | 2026 | Métodos para minar traces eficientemente | https://alexzhang13.github.io/blog/2025/rlm/ |
