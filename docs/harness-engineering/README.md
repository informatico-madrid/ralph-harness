# Harness Engineering — Documentación de Referencia

> **Fecha**: 2026-05-13
> **Propósito**: Centralizar toda la investigación y guías sobre Harness Engineering para consulta durante el desarrollo de features relacionadas.

---

## Índice de Documentos

| # | Documento | Fuente | Descripción |
|---|-----------|--------|-------------|
| 1 | [01-openai-harness-engineering.md](01-openai-harness-engineering.md) | OpenAI / Lilian Weng | Documento fundacional de la disciplina |
| 2 | [02-martin-fowler-harness-engineering.md](02-martin-fowler-harness-engineering.md) | Martin Fowler | Arquitectura de 3 sistemas interlocking |
| 3 | [03-langchain-deep-agents.md](03-langchain-deep-agents.md) | LangChain / Vivek Trivedi | Caso de estudio: Top 30 → Top 5 en Terminal-Bench |
| 4 | [04-terminal-bench-benchmark.md](04-terminal-bench-benchmark.md) | Stanford × Laude | Benchmark estándar para agentes |
| 5 | [05-tools-and-frameworks.md](05-tools-and-frameworks.md) | Varios | Ecosistema de herramientas y frameworks |
| 6 | [06-implementation-checklist.md](06-implementation-checklist.md) | Síntesis | Checklist para implementar harness en un proyecto |
| 7 | [07-existing-research.md](07-existing-research.md) | Proyecto interno | Investigación previa del proyecto (2026-05-01) |
| 8 | [08-practical-implementation-guide.md](08-practical-implementation-guide.md) | awesome-harness-engineering + Anthropic + OpenAI + LangChain | **Guía práctica**: AGENTS.md, RAG, agentes, contexto, templates |
| 9 | [09-reference-implementations.md](09-reference-implementations.md) | awesome-harness-engineering (902 stars) | **Proyectos de éxito** para copiarse, con lecciones transferibles |
| 10 | [10-deep-agents-deep-dive.md](10-deep-agents-deep-dive.md) | LangChain Deep Agents (código fuente) | **Deep dive**: Middleware componible, summarization, eviction, backend protocol |
| 11 | [11-openhands-deep-dive.md](11-openhands-deep-dive.md) | OpenHands SDK (código fuente) | **Deep dive**: Event log inmutable, parallel tools, critic, condensation, skills |

---

## Guía Rápida: Qué Leer Según Tu Necesidad

| Necesidad | Documento(s) |
|-----------|-------------|
| Entender el concepto | 01 (OpenAI) → 02 (Fowler) |
| Ver resultados medibles | 03 (LangChain: +13.7pts) |
| Qué escribir en AGENTS.md | **08** sección 1 |
| Cómo usar RAG en harness | **08** sección 2 |
| Cómo configurar e invocar agentes | **08** sección 3 |
| Cómo manejar contexto y compaction | **08** sección 4 |
| Templates disponibles | **08** sección 5 |
| ¿Necesito un product.md? | **08** sección 6 |
| Casos de estudio de producción | **08** sección 7 |
| Proyectos open-source para copiarse | **09** |
| Medir tu agente | 04 (Terminal-Bench) |
| Elegir herramientas | 05 (Catálogo) |
| Empezar a implementar | 06 (Checklist) |
| Qué ya investigamos | 07 (Investigación interna) |
| Middleware componible + summarization | **10** (Deep Agents deep dive) |
| Event log + parallel tools + critic | **11** (OpenHands deep dive) |

---

## Links Originales

| Fuente | URL |
|--------|-----|
| OpenAI — Harness Engineering | https://openai.com/index/harness-engineering/ |
| Martin Fowler — Harness Engineering | https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html |
| LangChain — Improving Deep Agents | https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering |
| Terminal-Bench Leaderboard | https://www.tbench.ai/leaderboard/terminal-bench/2.0 |
| awesome-harness-engineering (902 stars) | https://github.com/ai-boost/awesome-harness-engineering |
| Anthropic — Effective Context Engineering | https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents |
| Anthropic — Harness Design Long-Running | https://www.anthropic.com/engineering/harness-design-long-running-apps |
| Anthropic — Effective Harnesses Long-Running | https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents |
| Anthropic — Building Effective Agents | https://www.anthropic.com/research/building-effective-agents |
| Anthropic — Writing Effective Tools | https://www.anthropic.com/engineering/writing-effective-tools-for-agents |
| Anthropic — Beyond Permission Prompts | https://www.anthropic.com/engineering/beyond-permission-prompts |
| OpenAI — Practical Guide to Building AI Agents | https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/ |
| LangChain — Anatomy of an Agent Harness | https://blog.langchain.com/the-anatomy-of-an-agent-harness/ |
| LangChain — Middleware for Agent Harness | https://blog.langchain.com/how-middleware-lets-you-customize-your-agent-harness/ |
| Red Hat — Harness Engineering Structured Workflows | https://developers.redhat.com/articles/2026/04/07/harness-engineering-structured-workflows-ai-assisted-development |
| Birgitta Böckeler — Harness for Coding Agent Users | https://martinfowler.com/articles/harness-engineering.html |
| Microsoft — Azure SRE Context Engineering | https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200/ |
| Meta — Ranking Engineer Agent (REA) | https://engineering.fb.com/2026/03/17/developer-tools/ranking-engineer-agent-rea-autonomous-ai-system-accelerating-meta-ads-ranking-innovation/ |
| ReAct Paper | https://arxiv.org/abs/2210.03629 |
| A-RAG Paper | https://arxiv.org/abs/2602.03442 |
| Codified Context Paper | https://arxiv.org/abs/2602.20478 |

---

## Investigación Interna del Proyecto

| Documento | Ruta |
|-----------|------|
| Investigación de dominio | `_bmad-output/planning-artifacts/research/domain-harness-engineering-research-2026-05-01.md` |
| Diagnóstico de implementación | `plans/harness-implementation-diagnostic-2026-05-01.md` |
| Integración con roadmap | `_bmad-output/planning-artifacts/integration/harness-engineering-roadmap-integration-2026-05-01.md` |

---

## Templates Disponibles

| Template | URL |
|----------|-----|
| AGENTS.md | [awesome-harness-engineering/templates/AGENTS.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/AGENTS.md) |
| PLAN.md | [awesome-harness-engineering/templates/PLAN.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/PLAN.md) |
| IMPLEMENT.md | [awesome-harness-engineering/templates/IMPLEMENT.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/IMPLEMENT.md) |
| HARNESS_CHECKLIST.md | [awesome-harness-engineering/templates/HARNESS_CHECKLIST.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/HARNESS_CHECKLIST.md) |
