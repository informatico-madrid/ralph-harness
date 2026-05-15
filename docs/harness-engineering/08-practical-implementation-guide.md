# Guía Práctica de Implementación — Harness Engineering

> **Fecha**: 2026-05-13
> **Tipo**: Guía práctica con ejemplos concretos
> **Fuentes**: awesome-harness-engineering (902 stars), Anthropic, OpenAI, LangChain, Microsoft, Meta

---

## 1. Qué Escribir en AGENTS.md / CLAUDE.md

### El Problema

Los agentes pierden reglas críticas durante compaction. Claude Code compaction destruye:
- **60% de facts** durante compaction cycles
- **54% de behavioral drift** por constraint erosion en summarizations encadenadas
- Lo que sobrevive: current task, recent errors, filenames
- Lo que se pierde: initial instructions, intermediate decisions, style rules

**Regla fundamental**: `AGENTS.md` / `CLAUDE.md` vive en el **system prompt** y sobrevive a cualquier compresión. Todo lo que sea crítico DEBE estar aquí.

### Estructura Recomendada (basada en templates de awesome-harness-engineering)

```markdown
# AGENTS.md — Project Rules

## Project Overview
Breve descripción del proyecto: qué hace, qué stack usa, qué patrones sigue.

## Code Conventions
- Language: TypeScript 5.x with strict mode
- Framework: Next.js 15 App Router
- Style: Functional components, no class components
- State: Zustand for global, React Query for server state
- Testing: Vitest + Playwright

## File Organization
- src/app/ — Next.js App Router pages
- src/components/ — Reusable UI components
- src/lib/ — Business logic and utilities
- src/types/ — Shared TypeScript types

## Constraints
- NEVER modify .ralph-state.json or any state files
- NEVER commit directly to main — always use feature branches
- ALWAYS run `pnpm test` before marking task complete
- ALWAYS run `pnpm lint` and fix errors before committing
- NEVER install new dependencies without explicit approval

## Workflow
1. Planning: Read task, scan codebase, create plan
2. Build: Implement with verification in mind
3. Verify: Run tests, read FULL output, compare against spec
4. Fix: Analyze errors, revisit spec, fix

## Verification Commands
- Lint: `pnpm lint`
- Type check: `pnpm typecheck`
- Unit tests: `pnpm test`
- E2E tests: `pnpm test:e2e`
- Build: `pnpm build`

## Known Issues
- [Issue 1]: Description and workaround
- [Issue 2]: Description and workaround
```

### Hallazgo Clave de LangChain

> "AGENTS.md serves as the agent's procedural memory anchor" — [How We Built Agent Builder's Memory System](https://blog.langchain.com/how-we-built-agent-builders-memory-system/)

LangChain usa AGENTS.md como **memoria procedural** — el agente consulta este archivo para saber CÓMO hacer cosas, no solo QUÉ hacer. Esto es distinto de la memoria semántica (facts) y la memoria episódica (experiencias pasadas).

### Hallazgo Clave de "Codified Context" (283 sesiones, 108K líneas)

> "A 'hot-memory constitution' encoding conventions and multi-agent coordination protocols, 19 domain-specialist agents, and a 'cold-memory knowledge base' of 34 on-demand specification documents."

La distinción es:
- **Hot-memory** (siempre en contexto): Convenciones, reglas, protocolos de coordinación → `AGENTS.md`
- **Cold-memory** (bajo demanda): Specs detallados, documentación de referencia → archivos recuperables

### Alternativas a AGENTS.md Monolítico

| Enfoque | Proyecto | Descripción |
|---------|----------|-------------|
| **Trellis** | [github.com/mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) | Reemplaza CLAUDE.md monolítico con progressive spec system: agentes cargan solo standards, task PRDs, y session journals relevantes al step actual |
| **agentic-stack** | [github.com/codejunkie99/agentic-stack](https://github.com/codejunkie99/agentic-stack) | Portable `.agent/` folder que externaliza memory, skills, y protocols. Adapters traducen a CLAUDE.md, Cursor rules, OpenCode AGENTS.md |
| **DESIGN.md** | [github.com/google-labs-code/design.md](https://github.com/google-labs-code/design.md) | Google Labs: YAML front matter (machine-readable design tokens) + markdown prose (human-readable rationale) |

---

## 2. RAG en Harness Engineering

### El Insight Clave: RAG es un Problema de Diseño de Herramientas

> "Instead of injecting retrieved documents into context at pipeline time, expose three retrieval tools (keyword search, semantic search, chunk read) and let the agent pull information incrementally as each reasoning step requires it." — [A-RAG paper](https://arxiv.org/abs/2602.03442)

**RAG tradicional** (pipeline): Pre-procesas query → retrieves docs → inyectas en context → LLM genera respuesta
**RAG como herramienta** (harness): El agente tiene 3 tools de retrieval y decide cuándo y qué buscar

### Las 3 Herramientas de Retrieval (A-RAG)

| Herramienta | Propósito | Cuándo la usa el agente |
|-------------|-----------|------------------------|
| `keyword_search(query)` | Búsqueda por palabras clave | Cuando sabe exactamente qué término buscar |
| `semantic_search(query)` | Búsqueda por significado | Cuando necesita conceptos relacionados |
| `chunk_read(chunk_id)` | Leer un fragmento específico | Cuando encontró referencia y necesita detalle |

### MCP Servers para RAG en Coding Agents

| Server | Reducción de tokens | Método | URL |
|--------|--------------------|--------|-----|
| **codebase-memory-mcp** | 120× | tree-sitter AST analysis, 66 lenguajes, structured queries | [github.com/DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) |
| **Token Savior** | 77% active tokens, 76% wall time | Navegación por símbolos (functions, classes, call graphs) en lugar de leer archivos completos | [github.com/Mibayy/token-savior](https://github.com/Mibayy/token-savior) |
| **context-mode** | Variable | Intercepta raw tool output, sandboxea bulky data (Playwright snapshots, GitHub issues, logs), recupera via BM25 | [github.com/mksglu/context-mode](https://github.com/mksglu/context-mode) |

### El Patrón "Think in Code"

> "Replacing ten file-read tool calls with one script execution — is a concrete harness pattern for turning context pressure into a programming problem rather than a compression problem." — context-mode

En lugar de leer 10 archivos, el agente escribe un script que procesa los 10 archivos y devuelve solo lo relevante. Esto reduce tokens masivamente.

### RAG para Contexto de Proyecto

El paper "Codified Context" (283 sesiones) demuestra:
- **34 documentos on-demand** como cold-memory knowledge base
- El agente recupera specs solo cuando las necesita
- La hot-memory constitution (AGENTS.md) tiene ~2K tokens
- Los 34 documentos suman ~50K tokens pero nunca se cargan todos a la vez

---

## 3. Configuración de Agentes y Cómo Se Invocan

### Patrones de Multi-Agent (Anthropic: Building Effective Agents)

| Patrón | Cuándo usarlo | Ejemplo |
|--------|--------------|---------|
| **Single agent + tools** | Tareas simples, un dominio | Un agente que escribe código con bash y file tools |
| **Orchestrator + workers** | Tareas que necesitan especialización | Planner → Coder → Reviewer → Fixer |
| **Parallel agents** | Tareas independientes | 16 Claudes compilando un C compiler en paralelo |
| **State machine** | Workflows con branching | LangGraph: conditional edges, checkpoint persistence |

### Cómo Se Invocan los Agentes

#### Claude Agent SDK (Referencia)

```python
from claude_agent_sdk import Agent, Session

# Definir agente con tools y permisos
agent = Agent(
    model="claude-opus-4-6",
    system_prompt="You are a coding agent...",
    tools=["bash", "file_read", "file_write", "grep"],
    allowed_tools=["bash", "file_read", "file_write", "grep"],
    disallowed_tools=["rm -rf /"],  # deny-by-default
    permission_mode="auto",  # or "default", "dontAsk"
    hooks={
        "PreToolUse": my_pre_hook,
        "PostToolUse": my_post_hook,
    }
)

# Invocar con sesión resumible
session = Session(agent=agent)
result = await session.run("Fix the bug in auth.py")
# Guardar sesión para resumir después
session_id = session.id
```

#### LangGraph (Orquestación)

```python
from langgraph.graph import StateGraph, END

# Definir nodos (agentes)
def planner(state):
    # Genera plan de tareas
    return {"tasks": [...]}

def coder(state):
    # Implementa una tarea
    return {"code": "...", "tests_passed": True}

def reviewer(state):
    # Revisa el código
    return {"approved": True}

# Construir grafo
graph = StateGraph(AgentState)
graph.add_node("planner", planner)
graph.add_node("coder", coder)
graph.add_node("reviewer", reviewer)
graph.add_edge("planner", "coder")
graph.add_conditional_edges("coder", "reviewer", 
    lambda state: "approve" if state["tests_passed"] else "revise")
graph.add_edge("reviewer", END)
```

#### Middleware Pattern (LangChain AgentMiddleware)

6 hooks composable que interceptan cada stage del agent loop:

| Hook | Cuándo se ejecuta | Uso típico |
|------|-------------------|-----------|
| `before_agent` | Antes de que el agente empiece | Inyectar contexto del entorno |
| `before_model` | Antes de llamar al LLM | PII redaction, rate limiting |
| `wrap_model_call` | Alrededor de la llamada al LLM | Retry, fallback, model swapping |
| `wrap_tool_call` | Alrededor de cada tool call | Loop detection, validation |
| `after_model` | Después de la respuesta del LLM | Output filtering, logging |
| `after_agent` | Después de que el agente termine | Metrics, cleanup |

### Permisos: 5 Capas de Evaluación (Claude Agent SDK)

```
1. Hooks (PreToolUse) → pueden deny independientemente
2. Deny rules → deny-by-default, explícitamente prohibido
3. Permission mode → auto/default/dontAsk
4. Allow rules → explícitamente permitido
5. canUseTool callback → última chance para deny/approve
```

**Warning de subagentes**: `bypassPermissions` en un subagent hereda permisos del parent. Un subagent con bypass puede hacer cosas que el parent no puede.

---

## 4. Gestión de Contexto

### El Framework de Anthropic

> "Reframe harness design as 'what configuration of context produces the desired behavior?' rather than just prompt wording." — [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

El contexto incluye:
1. **System prompt** — Instrucciones, rol, constraints
2. **Tools** — Definiciones de herramientas (schemas, descriptions)
3. **MCP resources** — Datos externos accesibles
4. **Message history** — Conversación hasta ahora

### Compaction: Qué Sobrevive y Qué Se Pierde

| Sobrevive | Se pierde |
|-----------|-----------|
| Current task description | Initial instructions |
| Recent errors and fixes | Intermediate decisions |
| File names and paths | Style rules |
| Last 3-5 tool results | Earlier context |
| CLAUDE.md / AGENTS.md | Long code blocks |

**Solución**: Mover reglas críticas a `AGENTS.md` (vive en system prompt, sobrevive compaction).

### Compaction Autónoma (vs. Reactiva)

| Tipo | Trigger | Ventaja | Desventaja |
|------|---------|---------|-----------|
| **Reactiva** (default) | Al acercarse al context limit | Simple | Interrumpe al agente mid-subtask, corrompe reasoning |
| **Autónoma** | El agente decide cuándo comprimir | Comprime entre tareas, no mid-subtask | Requiere tool dedicado |

> "Eliminates the failure mode where reactive-at-limit compaction interrupts agents mid-subtask and corrupts in-flight reasoning state." — [Autonomous Context Compression](https://blog.langchain.com/autonomous-context-compression/)

### Context Budget System (Propuesto para RalphHarness)

```
Per-iteration token budget:
├── Mandatory (always loaded):     40% — AGENTS.md, current task, recent errors
├── Conditional (loaded if relevant): 30% — Related specs, dependency context
└── On-demand (loaded when needed):   30% — Full docs, codebase search results
```

### Prompt Caching (90% descuento)

Anthropic y OpenAI soportan prompt caching:
- Cachea system prompts, tool definitions, y documentos largos
- `cache_control` breakpoints para máximo reuse
- Hasta 90% descuento en tokens cacheados
- **Clave**: Poner tools y system prompt al inicio del context para maximizar cache hits

---

## 5. Templates Disponibles

### De awesome-harness-engineering

| Template | Propósito | URL |
|----------|-----------|-----|
| `AGENTS.md` | Instrucciones de proyecto: convenciones, constraints, permisos | [templates/AGENTS.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/AGENTS.md) |
| `PLAN.md` | Artifact de planning con milestones y verification gates | [templates/PLAN.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/PLAN.md) |
| `IMPLEMENT.md` | Log de implementación: decisiones, desviaciones, preguntas abiertas | [templates/IMPLEMENT.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/IMPLEMENT.md) |
| `HARNESS_CHECKLIST.md` | Checklist de review antes de shipping a producción | [templates/HARNESS_CHECKLIST.md](https://github.com/ai-boost/awesome-harness-engineering/blob/main/templates/HARNESS_CHECKLIST.md) |

### De OpenAI (Long-Horizon Tasks)

OpenAI introduce 3 artifacts reutilizables para tareas de larga duración:

| Artifact | Propósito | Contenido |
|----------|-----------|-----------|
| `Plan.md` | Plan de milestones | Objetivo, milestones, dependencias, verification gates |
| `Implement.md` | Log de implementación | Decisiones tomadas, desviaciones del plan, preguntas abiertas |
| `Documentation.md` | Documentación generada | API docs, README updates, changelog |

### De Anthropic (Effective Harnesses for Long-Running Agents)

Patrón de handoff entre sesiones:

```
Initializer Agent (corre una vez):
├── Set up environment
├── Create feature list
├── Initial git commit
└── Hand off to Coding Agent

Coding Agent (múltiples sesiones):
├── Make incremental progress
├── Git commit after each session
├── Pass test gates
└── Update feature list
```

**Cross-session state**: Feature lists, git commits, y test gates son el mecanismo de handoff.

---

## 6. Product.md — ¿Es Necesario?

### Respuesta Corta: No como archivo separado, pero sí como concepto

Ninguno de los proyectos de referencia usa un archivo `product.md` explícito. Sin embargo, el CONCEPTO de product context sí aparece en múltiples formas:

| Forma | Dónde vive | Qué contiene |
|-------|-----------|-------------|
| **Project Overview** en AGENTS.md | System prompt | Qué hace el producto, para quién, stack |
| **Requirements.md** (RalphHarness) | `specs/<name>/requirements.md` | User stories, acceptance criteria |
| **PRD** (BMad) | `_bmad-output/` | Product Requirements Document completo |
| **Feature List** (Anthropic) | Cross-session state | Features completadas vs pendientes |

### Recomendación

Si tu proyecto ya tiene `specs/<name>/requirements.md` o un PRD en BMad, **no necesitas un product.md separado**. Lo que sí necesitas es:

1. **Project Overview en AGENTS.md** — 5-10 líneas sobre qué es el producto
2. **Requirements por spec** — Ya lo tienes en RalphHarness
3. **Feature list como cross-session state** — Para handoff entre sesiones

---

## 7. Casos de Estudio de Producción

### Microsoft Azure SRE Agent (35,000+ incidentes)

> "Shifting from 100+ bespoke tools and a prescriptive prompt to a filesystem-based context engineering system. Exposing everything (source code, runbooks, query schemas, past investigation notes) as files and letting the agent use read_file, grep, find, and shell outperformed specialized tooling — Intent Met score rose from 45% to 75% on novel incidents."

**Lección**: Menos tools especializados, más acceso a filesystem. El agente es mejor navegando archivos que aprendiendo N APIs custom.

### Meta REA (Ranking Engineer Agent)

> "Hibernate-and-wake checkpointing for resuming interrupted 6-hour tasks without losing context."

**Lección**: Para tareas que exceden el context window, necesitas checkpointing explícito. El agente "hiberna" guardando estado, y "despierta" restaurándolo.

### Stripe Minions (1,300+ PRs/semana)

> "Blueprints interleave deterministic code nodes with agentic subtasks. A centralized 500-tool MCP server (Toolshed) serves the whole fleet. Pre-warmed devboxes prove that investments in human developer productivity pay equal dividends for agents."

**Lección**: Un MCP server centralizado para tools es más eficiente que tools dispersos. Pre-warm sandboxes para eliminar cold-start latency.

### Anthropic: 16 Claudes compilando C compiler

> "Agents claim tasks via files in current_tasks/, git forces collision resolution naturally, and a continuous restart loop spawns fresh sessions that resume where predecessors left off. Key lesson: verbose test output pollutes agent context — the feedback loop must emit only a few summary lines, log detail to file."

**Lección**: 
1. File-based task claiming funciona mejor que un orchestrator centralizado
2. Test output verbose contamina el contexto — emitir solo resumen
3. Restart loop con fresh sessions > sesiones infinitas

---

## 8. Artículos Clave Adicionales (No cubiertos en docs 01-07)

| Artículo | Fuente | Insight clave |
|----------|--------|---------------|
| [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) | Anthropic | "Every harness component assumes the model can't do something; those assumptions expire" |
| [Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | Anthropic | "What configuration of context produces the desired behavior?" |
| [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | Anthropic | Initializer → Coding Agent handoff con feature lists y git commits |
| [The Anatomy of an Agent Harness](https://blog.langchain.com/the-anatomy-of-an-agent-harness/) | LangChain | 5 primitives: filesystem, code execution, sandbox, memory, context management |
| [How Middleware Lets You Customize](https://blog.langchain.com/how-middleware-lets-you-customize-your-agent-harness/) | LangChain | 6 composable hooks: before/after agent, model, tool |
| [Harness Engineering for Coding Agent Users](https://martinfowler.com/articles/harness-engineering.html) | Birgitta Böckeler | Feedforward guides + feedback sensors; harnessability as architecture criterion |
| [A Practical Guide to Building AI Agents](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/) | OpenAI | Single vs multi-agent, tool design, layered guardrails |
| [Harness Engineering: Structured Workflows](https://developers.redhat.com/articles/2026/04/07/harness-engineering-structured-workflows-ai-assisted-development) | Red Hat | 4 pillars: vibes, specs, skills, agents |
| [Context Engineering Lessons from Azure SRE](https://techcommunity.microsoft.com/blog/appsonazureblog/context-engineering-lessons-from-building-azure-sre-agent/4481200/) | Microsoft | 100+ bespoke tools → filesystem-based: 45% → 75% Intent Met |
| [How We Built Agent Builder's Memory System](https://blog.langchain.com/how-we-built-agent-builders-memory-system/) | LangChain | AGENTS.md = procedural memory anchor; HITL approval for every memory write |
| [Continual Learning for AI Agents](https://blog.langchain.com/continual-learning-for-ai-agents/) | LangChain | 3 layers: model weights, harness behavior, contextual memory |
| [Building an Agentic Memory System for GitHub Copilot](https://github.blog/ai-and-ml/github-copilot/building-an-agentic-memory-system-for-github-copilot/) | GitHub | "Memory quality is mostly a freshness and invalidation problem" |
| [Skill Issue: Harness Engineering for Coding Agents](https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents) | HumanLayer | "Most agent failures are configuration problems, not model limitations" |
| [Natural-Language Agent Harnesses](https://arxiv.org/abs/2603.25723) | Paper | Externalize control logic as portable NL artifacts executed by shared runtime |
| [Building AI Coding Agents for the Terminal](https://arxiv.org/abs/2603.05344) | Paper (OpenDev) | Eager-construction scaffolding, compound multi-model, 5-layer safety |
