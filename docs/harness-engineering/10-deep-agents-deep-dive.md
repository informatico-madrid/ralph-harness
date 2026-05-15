# Deep Agents (LangChain) — Deep Dive

> **Fecha**: 2026-05-13
> **Fuente**: Análisis directo del código fuente en [github.com/langchain-ai/deepagents](https://github.com/langchain-ai/deepagents)
> **Tipo**: Caso de estudio con implementación concreta extraída del código real

---

## 1. Resumen Ejecutivo

Deep Agents es el framework de LangChain para construir agentes de larga duración que operan sobre código y sistemas de archivos. Su innovación principal es la **arquitectura de middleware componible** sobre LangGraph, donde cada capability (filesystem, summarization, execution) se encapsula en un middleware con hooks `wrap_model_call` y `wrap_tool_call` que interceptan y transforman las requests antes de que lleguen al LLM.

**Lecciones clave para RalphHarness**:
- Middleware componible > monolito de agent prompt
- Summarización automática con offload a backend (no perder historia)
- Eviction de resultados grandes al filesystem (prevenir context overflow)
- Permisos de filesystem a nivel de middleware (no en el prompt)
- Backend protocol abstracto (StateBackend, FilesystemBackend, SandboxBackend, CompositeBackend)

---

## 2. Arquitectura General

### 2.1 Factory Pattern: `create_deep_agent()`

```python
from deepagents import create_deep_agent

agent = create_deep_agent(
    model="anthropic:claude-sonnet-4-6",
    middleware=[
        FilesystemMiddleware(backend=CompositeBackend(
            default=StateBackend(),
            routes={"/memories/": StoreBackend()}
        )),
        create_summarization_tool_middleware("anthropic:claude-sonnet-4-6", backend),
    ],
)
```

El factory `create_deep_agent()` construye un agente LangGraph con:
1. **Model resolution**: String → `BaseChatModel` via `resolve_model()`
2. **Middleware stack**: Lista de `AgentMiddleware` que se ejecutan en orden
3. **Tool description overrides**: `_apply_tool_description_overrides()` para personalizar descripciones sin mutar las tools originales
4. **Default middleware**: Si no se especifica, añade `SummarizationMiddleware` + `FilesystemMiddleware`

### 2.2 Flujo de Ejecución

```
User Message
    │
    ▼
┌─────────────────────────────────┐
│  Middleware Stack (wrap_model_call) │
│  1. FilesystemMiddleware          │
│     - Inject system prompt        │
│     - Filter tools (execute)      │
│     - Evict large HumanMessages   │
│  2. SummarizationMiddleware       │
│     - Check token threshold       │
│     - Truncate tool args          │
│     - Summarize if needed         │
│     - Offload to backend          │
│  3. SummarizationToolMiddleware   │
│     - Inject compact nudge        │
└──────────────┬──────────────────┘
               │
               ▼
         LLM Call
               │
               ▼
┌─────────────────────────────────┐
│  Tool Execution                  │
│  - FilesystemMiddleware          │
│    wrap_tool_call:               │
│    - Evict large ToolMessages    │
│      to filesystem               │
└─────────────────────────────────┘
```

---

## 3. Middleware System — Implementación Concreta

### 3.1 `AgentMiddleware` Base Class

Cada middleware hereda de `AgentMiddleware[StateSchema, ContextT, ResponseT]`:

```python
class AgentMiddleware:
    state_schema = AgentState  # Pydantic model for state
    
    tools: list[BaseTool]  # Tools provided by this middleware
    
    def wrap_model_call(self, request, handler):
        """Intercept before LLM call. Return ModelResponse or ExtendedModelResponse."""
        return handler(request)
    
    async def awrap_model_call(self, request, handler):
        """Async variant."""
        return await handler(request)
    
    def wrap_tool_call(self, request, handler):
        """Intercept tool execution. Return ToolMessage or Command."""
        return handler(request)
    
    async def awrap_tool_call(self, request, handler):
        """Async variant."""
        return await handler(request)
```

**Key insight**: `wrap_model_call` recibe un `ModelRequest` y un `handler`. Puede modificar el request (messages, system_prompt, tools) y pasar el modificado al handler. Si necesita actualizar state, devuelve `ExtendedModelResponse` con un `Command(update={...})`.

### 3.2 `ModelRequest.override()`

El método `override()` crea una copia del request con campos modificados:

```python
# Modificar messages sin tocar el original
request = request.override(messages=truncated_messages)

# Modificar system prompt
request = request.override(system_message=new_system_message)

# Filtrar tools
request = request.override(tools=filtered_tools)
```

**Patrón inmutable**: Nunca se muta el request original. Siempre se crea una copia via `override()`.

---

## 4. SummarizationMiddleware — Implementación Detallada

### 4.1 Arquitectura Dual

```
SummarizationMiddleware (auto)          SummarizationToolMiddleware (manual)
├── wrap_model_call:                    ├── wrap_model_call:
│   1. Get effective messages           │   └── Inject compact nudge in system prompt
│   2. Truncate tool args               │
│   3. Check token threshold            ├── tools:
│   4. Offload to backend               │   └── compact_conversation tool
│   5. Generate summary                 │
│   6. Build new messages               ├── _run_compact:
│   7. Return ExtendedModelResponse     │   ├── Check eligibility (50% of auto-trigger)
│                                       │   ├── Partition messages
│                                       │   ├── Generate summary
│                                       │   ├── Offload to backend
│                                       │   └── Return Command with state update
```

### 4.2 Token Threshold System

```python
# Configuración por fracción del context window
trigger=("fraction", 0.85),  # Summarize at 85% of max_input_tokens
keep=("fraction", 0.10),     # Keep last 10% of context

# Configuración por tokens absolutos
trigger=("tokens", 170000),
keep=("messages", 6),

# Auto-detección desde model profile
compute_summarization_defaults(model) → {
    "trigger": ("fraction", 0.85),  # if model has max_input_tokens
    "keep": ("fraction", 0.10),
    "truncate_args_settings": {...}
}
```

### 4.3 Tool Argument Truncation (Pre-Summarization)

Antes de la summarización completa, hay una optimización más ligera:

```python
class TruncateArgsSettings:
    trigger: ContextSize | None     # When to truncate
    keep: ContextSize               # What to preserve
    max_length: int = 2000          # Max chars per arg
    truncation_text: str = "...(argument truncated)"
```

Solo trunca los `args` de `AIMessage.tool_calls` en mensajes **antes** de la ventana de keep. Especialmente targeting `write_file` y `edit_file` que suelen tener argumentos muy largos.

### 4.4 Backend Offload

Cuando se summariza, los mensajes evicted se guardan en el backend:

```python
# Path: /conversation_history/{thread_id}.md
# Formato: Markdown con timestamps
## Summarized at 2026-05-13T17:00:00Z

[HumanMessage content...]
[AIMessage content...]
[ToolMessage content...]
```

El summary message incluye la referencia al archivo offloaded:

```
You are in the middle of a conversation that has been summarized.
The full conversation history has been saved to /conversation_history/abc123.md
should you need to refer back to it for details.

<summary>
[condensed summary here]
</summary>
```

### 4.5 Non-Mutating State

**Crítico**: La summarización NO modifica `state["messages"]`. En su lugar, trackea el evento en `_summarization_event`:

```python
SummarizationState:
    _summarization_event: Annotated[NotRequired[SummarizationEvent], PrivateStateAttr]

SummarizationEvent:
    cutoff_index: int
    summary_message: HumanMessage
    file_path: str | None
```

Cuando se necesita la lista efectiva de mensajes, se reconstruye:

```python
def _apply_event_to_messages(messages, event):
    if event is None:
        return list(messages)
    # summary_message + messages[cutoff_index:]
    return [event["summary_message"], *messages[event["cutoff_index"]:]]
```

### 4.6 ContextOverflowError Fallback

Si el LLM rechaza la request por exceso de tokens:

```python
try:
    return handler(request.override(messages=truncated_messages))
except ContextOverflowError:
    pass  # Fallback to summarization

# Step 3: Perform summarization
cutoff_index = self._determine_cutoff_index(truncated_messages)
messages_to_summarize, preserved = self._partition_messages(...)
# ... summarize and retry
```

### 4.7 Compact Tool Eligibility Gate

El `compact_conversation` tool no se puede usar demasiado pronto:

```python
def _is_eligible_for_compaction(self, messages):
    # Must be at ~50% of auto-summarization trigger
    for kind, value in trigger_conditions:
        if kind == "tokens":
            threshold = int(value * 0.5)
            if lc._should_summarize_based_on_reported_tokens(messages, threshold):
                return True
        elif kind == "fraction":
            threshold = int(max_input_tokens * value * 0.5)
            # ...
```

---

## 5. FilesystemMiddleware — Implementación Detallada

### 5.1 Tools Proporcionadas

| Tool | Tipo | Descripción |
|------|------|-------------|
| `ls` | read | Lista archivos en directorio |
| `read_file` | read | Lee archivo con paginación (offset/limit) |
| `write_file` | write | Crea/escribe archivo |
| `edit_file` | write | Reemplazo exacto de strings |
| `glob` | read | Búsqueda por patrón glob |
| `grep` | read | Búsqueda de texto literal |
| `execute` | read+write | Ejecuta comandos shell (solo si backend soporta `SandboxBackendProtocol`) |

### 5.2 Sistema de Permisos

```python
@dataclass
class FilesystemPermission:
    operations: list[FilesystemOperation]  # ["read", "write"]
    paths: list[str]                        # ["/src/**", "/tests/**"]
    mode: Literal["allow", "deny"] = "allow"

# Ejemplo: Solo lectura en producción
permissions = [
    FilesystemPermission(operations=["read"], paths=["/"], mode="allow"),
    FilesystemPermission(operations=["write"], paths=["/production/"], mode="deny"),
]
```

Los permisos se checkean en cada tool invocation via `_check_fs_permission()`, usando `wcmatch.glob` para matching de patrones.

### 5.3 Large Result Eviction

Cuando un ToolMessage excede el token limit:

```python
tool_token_limit_before_evict: int = 20000  # ~20K tokens

# Si el resultado es grande:
1. Escribir contenido completo al backend: /large_tool_results/{tool_call_id}
2. Reemplazar el ToolMessage con preview + referencia:
   "Tool result too large, saved to /large_tool_results/abc123
    Preview:
    [first 5 lines]
    ... [N lines truncated] ...
    [last 5 lines]"
```

**Tools excluidas de eviction**: `ls`, `glob`, `grep`, `read_file`, `edit_file`, `write_file` — porque tienen truncación propia o nunca exceden limits.

### 5.4 HumanMessage Eviction

Similar al tool result eviction, pero para mensajes del usuario:

```python
human_message_token_limit_before_evict: int = 50000

# Si el último HumanMessage es muy grande:
1. Escribir contenido al backend: /conversation_history/{uuid}.md
2. Taggear el mensaje con lc_evicted_to: path
3. En wrap_model_call, reemplazar mensajes taggeados con preview truncado
```

Usa `Overwrite` command para actualizar atómicamente el canal de messages en LangGraph.

### 5.5 Backend Protocol

```python
class BackendProtocol:
    def read(self, path, offset, limit) -> ReadResult
    def write(self, path, content) -> WriteResult
    def edit(self, path, old, new, replace_all) -> EditResult
    def ls(self, path) -> LsResult
    def glob(self, pattern, path) -> GlobResult
    def grep(self, pattern, path, glob) -> GrepResult

class SandboxBackendProtocol(BackendProtocol):
    def execute(self, command, timeout) -> ExecuteResult
```

**CompositeBackend** para rutas híbridas:

```python
backend = CompositeBackend(
    default=StateBackend(),           # Ephemeral in agent state
    routes={
        "/memories/": StoreBackend(),  # Persistent via LangGraph Store
        "/data/": FilesystemBackend(root_dir="/data"),
    }
)
```

### 5.6 Dynamic System Prompt

El system prompt se construye dinámicamente según las tools disponibles:

```python
# Si execute tool está disponible Y el backend lo soporta:
prompt = FILESYSTEM_SYSTEM_PROMPT + EXECUTION_SYSTEM_PROMPT

# Si el backend no soporta execution:
filtered_tools = [t for t in tools if t.name != "execute"]
```

---

## 6. Lecciones para RalphHarness

### 6.1 Middleware > Prompt Engineering

Deep Agents pone lógica operacional (summarization, eviction, permissions) en **middleware con hooks**, no en el system prompt. RalphHarness podría beneficiarse de un sistema similar donde:

- **Summarization**: En vez de confiar en que el coordinator lea `.progress.md` y decida, un middleware podría truncar automáticamente el contexto cuando exceda un threshold.
- **Eviction**: Resultados grandes de tools (ej: `rg` output, test output) podrían evictarse al filesystem automáticamente.
- **Permissions**: Role contracts (Spec 3 del roadmap) podrían implementarse como middleware que filtra tools según el agente.

### 6.2 Non-Mutating State Pattern

Deep Agents NO modifica `state["messages"]` durante summarization. En su lugar, trackea eventos en campos privados (`_summarization_event`). RalphHarness tiene un problema similar con state drift (Gap C3) — la solución de Deep Agents sugiere que los cambios de estado deberían ser atómicos y trackeables, no distribuidos en múltiples archivos.

### 6.3 Backend Abstraction

El `BackendProtocol` de Deep Agents es una abstracción limpia que permite:
- StateBackend (ephemeral, en memoria del agente)
- FilesystemBackend (disco local)
- StoreBackend (LangGraph Store, persistente)
- CompositeBackend (rutas a diferentes backends)
- SandboxBackend (Docker, Kubernetes, Daytona)

RalphHarness actualmente asume filesystem local. Para soportar ejecución remota o en sandbox, necesitaría una abstracción similar.

### 6.4 Tool Argument Truncation

La truncación de argumentos grandes en tool calls viejos es una optimización simple pero efectiva. RalphHarness podría implementar algo similar: cuando el contexto del coordinator crece demasiado, truncar los argumentos de tool calls antiguos (ej: contenido de `write_file` en tareas ya completadas).

### 6.5 Compact Tool Pattern

Darle al agente un tool `compact_conversation` para que decida cuándo compactar es elegante. RalphHarness podría ofrecer un tool similar al spec-executor para que decida cuándo hacer checkpoint o cleanup de su contexto.

---

## 7. Comparación con RalphHarness

| Aspecto | Deep Agents | RalphHarness |
|---------|-------------|--------------|
| **Arquitectura** | Middleware componible sobre LangGraph | Agent prompts + coordinator loop |
| **Summarización** | Automática con backend offload | Manual (coordinator lee .progress.md) |
| **Context overflow** | Middleware intercepta + retry | Circuit breaker (Spec 4) |
| **Permisos** | FilesystemPermission en middleware | Role contracts en agent prompts (Spec 3) |
| **State management** | LangGraph state + DeltaChannel | .ralph-state.json + tasks.md checkmarks |
| **Tool execution** | Backend protocol abstracto | Directo (filesystem local) |
| **Large results** | Auto-eviction al filesystem | Sin manejo (context overflow risk) |
| **Paralelismo** | LangGraph inherent | [P] tasks con TeamCreate |
| **Verificación** | No explícita | 5-layer verification (Spec 1) |

---

## 8. Código Clave Referenciado

| Archivo | Propósito |
|---------|-----------|
| `deepagents/_api.py` | `create_deep_agent()` factory |
| `deepagents/_tools.py` | Tool name extraction + description overrides |
| `deepagents/middleware/summarization.py` | SummarizationMiddleware + SummarizationToolMiddleware |
| `deepagents/middleware/filesystem.py` | FilesystemMiddleware + tools + permissions + eviction |
| `deepagents/backends/protocol.py` | BackendProtocol + SandboxBackendProtocol |
| `deepagents/backends/composite.py` | CompositeBackend con routes |
| `deepagents/backends/state.py` | StateBackend (ephemeral) |
