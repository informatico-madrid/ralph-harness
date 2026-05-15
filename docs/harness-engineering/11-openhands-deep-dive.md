# OpenHands Software Agent SDK — Deep Dive

> **Fecha**: 2026-05-13
> **Fuente**: Análisis directo del código fuente en [github.com/OpenHands/software-agent-sdk](https://github.com/OpenHands/software-agent-sdk) (v1.22.0) + [github.com/OpenHands/OpenHands](https://github.com/OpenHands/OpenHands) (v1.7.0)
> **Tipo**: Caso de estudio con implementación concreta extraída del código real

---

## 1. Resumen Ejecutivo

OpenHands SDK es un framework Python componible para construir agentes de software. A diferencia de Deep Agents (middleware sobre LangGraph), OpenHands usa una **arquitectura de Agent con mixins** donde la lógica se organiza en clases base con herencia múltiple. Su innovación principal es el **sistema de eventos inmutable** con condensation automática, **ejecución paralela de tools**, y un **sistema de critic** que evalúa acciones antes de ejecutarlas.

**Lecciones clave para RalphHarness**:
- Event log inmutable con condensation (vs. chat.md mutable)
- Ejecución paralela de tools con `_ActionBatch` prepare/emit/finalize
- Critic system para evaluar acciones antes de ejecución
- Condenser automático con `CondensationRequest` events
- Skills marketplace con auto-detección por marcadores de proyecto
- Security analyzer con risk levels y confirmation policy

---

## 2. Arquitectura General

### 2.1 Estructura del SDK

```
software-agent-sdk/
├── openhands-sdk/          # Core SDK
│   └── openhands/sdk/
│       ├── agent/          # Agent, AgentBase, ACPAgent, CriticMixin
│       ├── context/        # AgentContext, Condenser, skills
│       ├── conversation/   # Conversation, ConversationState
│       ├── critic/         # Critic evaluation system
│       ├── event/          # Event types + Condensation
│       ├── hooks/          # Pre/post execution hooks
│       ├── llm/            # LLM abstraction
│       ├── mcp/            # MCP tool integration
│       ├── security/       # SecurityAnalyzer + Risk levels
│       ├── skills/         # Skill marketplace
│       ├── subagent/       # Sub-agent delegation
│       ├── tool/           # Tool definitions + builtins
│       └── workspace/      # Workspace management
├── openhands-tools/        # Built-in tools
│   └── openhands/tools/
│       ├── file_editor/    # FileEditorTool
│       ├── terminal/       # TerminalTool
│       └── task_tracker/   # TaskTrackerTool
├── openhands-workspace/    # Workspace abstractions
└── openhands-agent-server/ # Remote agent server (Docker/K8s)
```

### 2.2 Quick Start Pattern

```python
from openhands.sdk import LLM, Agent, Conversation, Tool
from openhands.tools.file_editor import FileEditorTool
from openhands.tools.terminal import TerminalTool
from openhands.tools.task_tracker import TaskTrackerTool

llm = LLM(model="anthropic/claude-sonnet-4-5-20250929", api_key=os.getenv("LLM_API_KEY"))

agent = Agent(
    llm=llm,
    tools=[
        Tool(name=TerminalTool.name),
        Tool(name=FileEditorTool.name),
        Tool(name=TaskTrackerTool.name),
    ],
)

conversation = Conversation(agent=agent, workspace=os.getcwd())
conversation.send_message("Write 3 facts about the current project into FACTS.txt.")
conversation.run()
```

### 2.3 Flujo de Ejecución

```
User Message
    │
    ▼
Conversation.send_message()
    │
    ▼
Agent.step()
    │
    ├── 1. Check pending actions (confirmation mode)
    ├── 2. Check blocked messages (hooks)
    ├── 3. Prepare LLM messages (with condenser)
    │       │
    │       ├── Condensation needed? → emit CondensationRequest, return
    │       └── Normal path → _messages list
    │
    ├── 4. LLM call (make_llm_completion)
    │       ├── FunctionCallValidationError → error message, return
    │       ├── LLMMalformedConversationHistoryError → condensation retry
    │       └── LLMContextWindowExceedError → condensation retry
    │
    ├── 5. Classify response
    │       ├── TOOL_CALLS → _handle_tool_calls()
    │       ├── CONTENT → _handle_content_response()
    │       └── REASONING_ONLY / EMPTY → _handle_no_content_response()
    │
    └── 6. Execute actions
            ├── _ActionBatch.prepare()
            │   ├── Truncate at FinishTool
            │   ├── Partition blocked vs executable
            │   └── ParallelToolExecutor.execute_batch()
            ├── _ActionBatch.emit()
            └── _ActionBatch.finalize()
                ├── Check iterative refinement
                └── Mark finished if done
```

---

## 3. Agent Class — Implementación Detallada

### 3.1 Jerarquía de Clases

```python
class Agent(CriticMixin, ResponseDispatchMixin, AgentBase):
    """Main agent implementation."""
    
    llm: LLM                           # Language model
    tools: list[Tool]                   # Tool definitions
    system_prompt: str | None           # Inline system prompt override
    system_prompt_filename: str         # Jinja2 template (default: "system_prompt.j2")
    system_prompt_kwargs: dict          # Extra template variables
    tool_concurrency_limit: int         # Parallel tool execution limit
    condenser: Condenser | None         # Context condensation
    agent_context: AgentContext | None   # Dynamic context (skills, secrets)
```

**Mixin Pattern**:
- `CriticMixin`: Añade `_should_evaluate_with_critic()` y `_evaluate_with_critic()`
- `ResponseDispatchMixin`: Añade `_handle_tool_calls()`, `_handle_content_response()`, `_handle_no_content_response()`
- `AgentBase`: Inicialización de estado, system prompt rendering

### 3.2 System Prompt con Jinja2 + Dynamic Context

```python
def init_state(self, state, on_event):
    # Static system message (cacheable across conversations)
    system_prompt = TextContent(text=self.static_system_message)
    
    # Dynamic context (NOT cached — changes per conversation)
    dynamic_context = self.get_dynamic_context(state)
    # Includes: secrets from secret_registry, agent_context suffix
    
    event = SystemPromptEvent(
        source="agent",
        system_prompt=system_prompt,
        tools=list(self.tools_map.values()),
        dynamic_context=TextContent(text=dynamic_context),
    )
    on_event(event)
```

**Patrón de cache**: El system prompt estático se marca con cache control points. El dynamic context se añade como segundo content block SIN cache marker, permitiendo que el prompt estático se cache entre conversaciones.

### 3.3 Security Integration

```python
@model_validator(mode="before")
@classmethod
def _add_security_prompt_as_default(cls, data):
    # Always enable llm_security_analyzer in system prompt kwargs
    kwargs = data.get("system_prompt_kwargs") or {}
    kwargs.setdefault("llm_security_analyzer", True)
    data["system_prompt_kwargs"] = kwargs
    return data
```

El security analyzer se inyecta automáticamente en el system prompt template.

---

## 4. Event System — Implementación Detallada

### 4.1 Tipos de Eventos

```python
# Core events
SystemPromptEvent     # System prompt + tools + dynamic context
MessageEvent          # User/assistant messages
ActionEvent           # Tool call with action, thought, security_risk
ObservationEvent      # Tool execution result
AgentErrorEvent       # Error during tool execution
TokenEvent            # Token usage tracking

# Condensation events
Condensation          # Condensed history replacement
CondensationRequest   # Request to trigger condensation

# Review events
UserRejectObservation # Action blocked by hook
```

### 4.2 Event Log Inmutable

El event log es una secuencia inmutable (`EventLog`) respaldada por archivo. Los eventos se append pero nunca se modifican. La condensation crea una vista alternativa del history sin mutar el log original.

**Contraste con RalphHarness**: RalphHarness usa `chat.md` (archivo mutable con append atómico via flock). OpenHands usa un event log inmutable con condensation. La ventaja del event log es que permite replay y auditoría completa.

### 4.3 ActionEvent con Security Risk

```python
@dataclass
class ActionEvent:
    action: Action                    # The tool action to execute
    thought: list[TextContent]        # LLM's reasoning
    reasoning_content: str            # Extended reasoning
    thinking_blocks: list             # Claude thinking blocks
    tool_name: str                    # Tool identifier
    tool_call_id: str                 # Unique call ID
    tool_call: MessageToolCall        # Original tool call from LLM
    llm_response_id: str             # LLM response ID
    security_risk: SecurityRisk       # Risk assessment
    summary: str                      # Human-readable action summary
    critic_result: CriticResult | None  # Optional critic evaluation
```

El campo `security_risk` viene del LLM (que lo incluye en sus tool call arguments) y es validado por el security analyzer:

```python
def _extract_security_risk(self, arguments, read_only_tool, security_analyzer):
    if read_only_tool:
        return SecurityRisk.UNKNOWN  # Skip for read-only tools
    
    if security_analyzer is None:
        return SecurityRisk.UNKNOWN  # No analyzer configured
    
    raw = arguments.pop("security_risk", None)
    if raw is None:
        return SecurityRisk.UNKNOWN  # LLM didn't provide it
    
    return SecurityRisk(raw)  # Validates enum value
```

---

## 5. Parallel Tool Execution — Implementación Detallada

### 5.1 `_ActionBatch` Lifecycle

```python
@dataclass(frozen=True, slots=True)
class _ActionBatch:
    action_events: list[ActionEvent]
    has_finish: bool
    blocked_reasons: dict[str, str]
    results_by_id: dict[str, list[Event]]
    
    @classmethod
    def prepare(cls, action_events, state, executor, tool_runner, tools):
        # 1. Truncate at FinishTool (discard calls after finish)
        action_events, has_finish = cls._truncate_at_finish(action_events)
        
        # 2. Partition blocked vs executable
        blocked_reasons = {}
        executable = []
        for ae in action_events:
            reason = state.pop_blocked_action(ae.id)
            if reason is not None:
                blocked_reasons[ae.id] = reason
            else:
                executable.append(ae)
        
        # 3. Execute in parallel
        executed_results = executor.execute_batch(executable, tool_runner, tools)
        results_by_id = dict(zip([ae.id for ae in executable], executed_results))
        
        return cls(action_events, has_finish, blocked_reasons, results_by_id)
    
    def emit(self, on_event):
        for ae in self.action_events:
            if ae.id in self.blocked_reasons:
                on_event(UserRejectObservation(...))
            else:
                for event in self.results_by_id[ae.id]:
                    on_event(event)
    
    def finalize(self, on_event, check_iterative_refinement, mark_finished):
        if not self.has_finish or last_action_blocked:
            return
        should_continue, followup = check_iterative_refinement(last_action)
        if should_continue and followup:
            on_event(MessageEvent(source="user", llm_message=...))
        else:
            mark_finished()
```

### 5.2 ParallelToolExecutor

```python
class ParallelToolExecutor:
    def __init__(self, max_workers: int):
        self._max_workers = max_workers
    
    def execute_batch(self, action_events, tool_runner, tools):
        # Execute tools in parallel using ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=self._max_workers) as pool:
            futures = {
                pool.submit(tool_runner, ae): ae.id
                for ae in action_events
            }
            results = {}
            for future in as_completed(futures):
                ae_id = futures[future]
                results[ae_id] = future.result()
        return [results[ae.id] for ae in action_events]  # Preserve order
```

**Contraste con RalphHarness**: RalphHarness soporta ejecución paralela via `[P]` task markers y `TeamCreate`/`TaskCreate`, pero a nivel de tareas completas, no a nivel de tool calls individuales dentro de un step.

---

## 6. Condenser System — Implementación Detallada

### 6.1 Condenser Interface

```python
class Condenser:
    def condense(self, events: list[Event]) -> list[Message]:
        """Transform event history into LLM messages."""
        raise NotImplementedError
    
    def handles_condensation_requests(self) -> bool:
        """Whether this condenser can handle CondensationRequest events."""
        return False
```

### 6.2 LLMSummarizingCondenser

```python
class LLMSummarizingCondenser(Condenser):
    llm: LLM
    max_size: int = 240      # Max events before condensation
    keep_first: int = 2       # Always keep first N events (system prompt)
    
    def condense(self, events):
        if len(events) <= self.max_size:
            return self._events_to_messages(events)
        # Summarize older events, keep recent + system prompt
        summary = self._summarize(events[:self.max_size])
        return [summary] + self._events_to_messages(events[-keep:])
    
    def handles_condensation_requests(self) -> bool:
        return True
```

### 6.3 Condensation Flow on Context Overflow

```python
# In Agent.step():
try:
    llm_response = make_llm_completion(self.llm, _messages, tools=...)
except LLMContextWindowExceedError:
    if self.condenser and self.condenser.handles_condensation_requests():
        on_event(CondensationRequest())  # Trigger condensation
        return  # Next iteration will use condensed history
    raise  # No condenser → propagate error
```

**Patrón**: El condenser se invoca de dos formas:
1. **Proactiva**: `prepare_llm_messages()` llama al condenser si el history es largo
2. **Reactiva**: Cuando el LLM rechaza por context overflow, se emite `CondensationRequest`

### 6.4 prepare_llm_messages Utility

```python
def prepare_llm_messages(events, condenser, llm):
    """Convert events to LLM messages, applying condensation if needed."""
    if condenser is not None:
        messages = condenser.condense(events)
    else:
        messages = _events_to_messages(events)
    return messages
```

---

## 7. Critic System — Implementación Detallada

### 7.1 CriticMixin

```python
class CriticMixin:
    def _should_evaluate_with_critic(self, action: Action) -> bool:
        """Determine if an action should be evaluated by the critic."""
        # Only evaluate write actions, not read-only
        return not action.is_read_only
    
    def _evaluate_with_critic(self, conversation, action_event) -> CriticResult | None:
        """Run critic evaluation on the proposed action."""
        # Uses a separate LLM call to evaluate the action
        # Returns None if no issues found
        # Returns CriticResult with suggestions if issues detected
```

El critic evalúa acciones **antes** de la ejecución. Si detecta problemas, el `ActionEvent` se enriquece con `critic_result`:

```python
if self._should_evaluate_with_critic(action):
    critic_result = self._evaluate_with_critic(conversation, action_event)
    if critic_result is not None:
        action_event = action_event.model_copy(
            update={"critic_result": critic_result}
        )
```

**Contraste con RalphHarness**: RalphHarness tiene el external-reviewer que evalúa **después** de la ejecución (via task_review.md). El critic de OpenHands evalúa **antes**. Ambos patrones son complementarios.

---

## 8. Hooks System — Implementación Detallada

### 8.1 Hook Types

```python
# Pre-execution hooks
class UserPromptSubmitHook:
    """Called before processing a user message. Can block the message."""
    def on_user_prompt_submit(self, message: str) -> str | None:
        # Return None to allow, or reason string to block
        pass

# Action hooks  
class ActionHook:
    """Called before executing an action. Can block the action."""
    def on_action(self, action: Action) -> str | None:
        # Return None to allow, or reason string to block
        pass
```

### 8.2 Blocked Actions in State

```python
class ConversationState:
    def pop_blocked_action(self, action_id: str) -> str | None:
        """Pop a blocked action reason. Returns None if not blocked."""
    
    def pop_blocked_message(self, message_id: str) -> str | None:
        """Pop a blocked message reason. Returns None if not blocked."""
```

Los hooks pueden bloquear acciones o mensajes. Las razones se almacenan en el state y se procesan en el siguiente step.

### 8.3 Confirmation Policy

```python
def _requires_user_confirmation(self, state, action_events):
    # Rules:
    # 1. Confirmation mode is enabled
    # 2. Every action requires confirmation
    # 3. Single FinishAction → never requires confirmation
    # 4. Single ThinkAction → never requires confirmation
    
    if len(action_events) == 1 and isinstance(action_events[0].action, (FinishAction, ThinkAction)):
        return False
    
    # Check security risks
    risks = [risk for _, risk in state.security_analyzer.analyze_pending_actions(action_events)]
    
    if any(state.confirmation_policy.should_confirm(risk) for risk in risks):
        state.execution_status = ConversationExecutionStatus.WAITING_FOR_CONFIRMATION
        return True
    return False
```

---

## 9. Skills System — Implementación Detallada

### 9.1 AgentContext con Skills

```python
from openhands.sdk.context import AgentContext

agent = Agent(
    llm=llm,
    tools=tools,
    agent_context=AgentContext(load_public_skills=True),
)
```

### 9.2 Skill Auto-Detection

Las skills se activan automáticamente por marcadores de proyecto:

| Marcador | Skill | Descripción |
|----------|-------|-------------|
| `uv.lock` | uv | Package management con uv |
| `deno.json`, `deno.jsonc`, `deno.lock` | deno | Runtime/package management con Deno |
| `.openhands/microagents/` | Custom | Micro-agentes específicos del proyecto |

### 9.3 Skill Marketplace

Las skills públicas vienen del [OpenHands/extensions](https://github.com/OpenHands/extensions) marketplace. El SDK las descarga y carga dinámicamente.

**Contraste con RalphHarness**: RalphHarness tiene el concepto de skills en `.roo/skills/` pero no tiene auto-detección por marcadores de proyecto. Podría beneficiarse de un sistema similar donde skills como "python-uv", "node-pnpm", etc. se activen automáticamente según los archivos del proyecto.

---

## 10. Tool System — Implementación Detallada

### 10.1 ToolDefinition

```python
class ToolDefinition:
    name: str
    action_type: type[Action]  # Pydantic model for arguments
    
    def action_from_arguments(self, arguments: dict) -> Action:
        """Validate arguments and create Action instance."""
        return self.action_type(**arguments)
    
    @property
    def annotations(self) -> ToolAnnotations:
        """Tool metadata including readOnlyHint."""
```

### 10.2 Built-in Tools

| Tool | Descripción | Tipo |
|------|-------------|------|
| `TerminalTool` | Ejecuta comandos shell en el workspace | Read+Write |
| `FileEditorTool` | Lee, escribe, edita archivos | Read+Write |
| `TaskTrackerTool` | Trackea progreso de tareas | Read+Write |
| `FinishTool` | Señala que el agente terminó | Read |
| `ThinkTool` | Permite al agente pensar sin actuar | Read |

### 10.3 MCP Tool Integration

```python
from openhands.sdk.mcp.tool import MCPToolDefinition

# MCP tools se integran como ToolDefinitions normales
# con inputSchema del MCP server
class MCPToolDefinition(ToolDefinition):
    mcp_tool: MCPTool  # Reference to MCP tool definition
```

### 10.4 Tool Call Normalization

```python
def normalize_tool_call(requested_name, arguments, available_tools):
    """Handle tool aliasing and fallbacks."""
    # 1. Direct match
    if requested_name in available_tools:
        return requested_name, arguments
    
    # 2. Alias resolution (e.g., "bash" → "terminal")
    # 3. Terminal fallback (unknown commands → terminal)
```

---

## 11. Lecciones para RalphHarness

### 11.1 Event Log Inmutable vs. Chat.md Mutable

OpenHands usa un event log inmutable donde los eventos se append pero nunca se modifican. La condensation crea vistas alternativas sin mutar el log original. RalphHarness usa `chat.md` (archivo mutable).

**Recomendación**: Considerar migrar de chat.md a un event log estructurado. Los HOLD signals serían eventos con tipo, no texto que se interpreta. Esto resolvería el Gap C2 (HOLD signals ignorados) de forma mecánica.

### 11.2 Critic Before Execution vs. Review After Execution

OpenHands evalúa acciones **antes** de ejecutarlas (critic). RalphHarness evalúa **después** (external-reviewer). Ambos son complementarios:

- **Before**: Previene acciones destructivas (ej: escribir en archivos prohibidos)
- **After**: Verifica que el resultado es correcto (ej: tests pasan, código limpio)

**Recomendación**: Añadir un pre-execution critic al spec-executor que evalúe security_risk de las acciones. Esto complementaría el role-boundaries (Spec 3) con una capa de verificación mecánica.

### 11.3 Parallel Tool Execution

OpenHands ejecuta múltiples tool calls del mismo LLM response en paralelo. RalphHarness solo ejecuta tareas en paralelo (via `[P]` markers), no tool calls individuales.

**Recomendación**: Para el spec-executor, permitir ejecución paralela de tool calls independientes (ej: leer múltiples archivos a la vez). Esto reduciría el tiempo de ejecución de tareas que hacen muchas lecturas.

### 11.4 Condensation vs. Summarization

OpenHands usa `CondensationRequest` events para triggerar condensation reactiva (cuando el LLM rechaza por context overflow). Deep Agents usa `SummarizationMiddleware` proactiva (cuando el threshold se alcanza).

**Recomendación**: RalphHarness podría implementar ambos patrones:
- **Proactivo**: El coordinator detecta que el contexto es largo y trunca .progress.md o chat.md
- **Reactivo**: Cuando el LLM falla por context overflow, se triggera condensation automática

### 11.5 Skills Auto-Detection

OpenHands detecta automáticamente qué skills cargar según los marcadores del proyecto. RalphHarness no tiene este mecanismo.

**Recomendación**: Añadir auto-detección de skills al spec-executor basada en archivos del proyecto:
- `pyproject.toml` → Python/uv/poetry skills
- `package.json` → Node/pnpm/npm skills
- `Makefile` → Make skills
- `.github/workflows/` → CI/CD skills

Esto reduciría la necesidad de que el coordinator especifique comandos de verificación manualmente (relacionado con el Gap C4: CI snapshot separation).

### 11.6 Confirmation Policy con Security Risk

OpenHands tiene un sistema de confirmation policy basado en security risk levels. RalphHarness tiene role boundaries (Spec 3) pero no tiene risk levels.

**Recomendación**: Añadir risk levels a las acciones del spec-executor:
- `LOW`: Read-only operations (ls, read, grep)
- `MEDIUM`: Write operations within spec scope (edit files in spec paths)
- `HIGH`: Write operations outside spec scope (edit files not in spec)
- `CRITICAL`: Destructive operations (delete files, force push)

Las operaciones HIGH y CRITICAL requerirían confirmation (del coordinator o del human).

---

## 12. Comparación con RalphHarness

| Aspecto | OpenHands SDK | RalphHarness |
|---------|---------------|--------------|
| **Arquitectura** | Agent con mixins + event log | Agent prompts + coordinator loop |
| **Eventos** | Event log inmutable + condensation | chat.md mutable + flock |
| **Paralelismo** | Tool calls paralelos por step | Tareas paralelas via [P] markers |
| **Critic** | Pre-execution evaluation | Post-execution review (external-reviewer) |
| **Condensation** | Proactiva + reactiva (CondensationRequest) | Manual (coordinator lee .progress.md) |
| **Security** | SecurityRisk enum + confirmation policy | Role contracts (Spec 3) |
| **Skills** | Marketplace + auto-detection | Manual en .roo/skills/ |
| **System prompt** | Jinja2 template + dynamic context | Hardcoded en agent .md files |
| **Tool execution** | Backend-agnostic (local, Docker, K8s) | Local filesystem only |
| **Verificación** | No explícita | 5-layer verification (Spec 1) |
| **HOLD signals** | N/A (usa hooks + blocked actions) | Text-based en chat.md (Gap C2) |

---

## 13. Código Clave Referenciado

| Archivo | Propósito |
|---------|-----------|
| `openhands/sdk/agent/agent.py` | Agent class principal con step(), _execute_actions(), _ActionBatch |
| `openhands/sdk/agent/base.py` | AgentBase con init_state(), system prompt rendering |
| `openhands/sdk/agent/critic_mixin.py` | CriticMixin para pre-execution evaluation |
| `openhands/sdk/agent/parallel_executor.py` | ParallelToolExecutor con ThreadPoolExecutor |
| `openhands/sdk/agent/response_dispatch.py` | ResponseDispatchMixin + classify_response() |
| `openhands/sdk/conversation/state.py` | ConversationState con blocked actions/messages |
| `openhands/sdk/event/` | Event types + Condensation + CondensationRequest |
| `openhands/sdk/event/condenser.py` | LLMSummarizingCondenser |
| `openhands/sdk/security/` | SecurityAnalyzer + SecurityRisk enum |
| `openhands/sdk/context/agent_context.py` | AgentContext con skills auto-detection |
| `openhands/sdk/hooks/` | Pre/post execution hooks |
| `openhands/tools/terminal/` | TerminalTool |
| `openhands/tools/file_editor/` | FileEditorTool |
| `openhands/tools/task_tracker/` | TaskTrackerTool |
