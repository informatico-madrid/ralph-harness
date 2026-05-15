# Research: Signal Event Log + CI Auto-Detection

> **Spec**: signal-log-and-ci-autodetect (Phase 6)
> **Fecha**: 2026-05-14
> **Tipo**: Research condensado de documentación existente + análisis de código fuente

---

## 1. Resumen Ejecutivo

Spec 6 aborda dos gaps del engine roadmap:

1. **Gap C2 (HOLD signals ignorados)**: El check mecánico actual usa `grep` sobre texto en `chat.md`. Es frágil: resolved signals se marcan `[RESOLVED]` pero el grep podría matchear falsos positivos. Un **signal event log JSONL** (`signals.jsonl`) reemplaza el grep con `jq` sobre datos estructurados — eliminando interpretación LLM.

2. **Gap C4 (CI snapshot separation)**: Spec 1 añadió la regla conceptual, Spec 4 añadió `ciCommands` al schema. Pero los comandos CI se descubren manualmente desde el Verification Contract. Un script **`detect-ci-commands.sh`** auto-descubre comandos desde marcadores del proyecto.

**Complejidad**: LOW-MEDIUM. Añadir un nuevo archivo (signals.jsonl) y un script (detect-ci-commands.sh). No se reestructura nada existente.

**Beneficio**: HIGH. (a) HOLD check 100% mecánico sin falsos positivos. (b) chat.md limpio para colaboración. (c) CI commands auto-descubiertos.

---

## 2. Estado Actual — Análisis de Código Fuente

### 2.1 Signal System Actual (chat.md)

**Archivo**: `plugins/ralphharness/templates/chat.md`

12 tipos de señales definidas:

| Signal | Tipo | Uso |
|--------|------|-----|
| OVER | Colaboración | Task/turn completo |
| ACK | Colaboración | Acknowledged |
| CONTINUE | Colaboración | Work in progress |
| HOLD | **Control** | Bloqueo — no delegar |
| PENDING | **Control** | Evaluando — no avanzar |
| STILL | Colaboración | Heartbeat |
| ALIVE | Colaboración | Check-in |
| CLOSE | Colaboración | Thread cerrado |
| URGENT | **Control** | Atención inmediata |
| DEADLOCK | **Control** | No se puede avanzar |
| INTENT-FAIL | **Control** | Pre-warning antes de FAIL |
| SPEC-ADJUSTMENT | **Control** | Propuesta de enmienda |
| SPEC-DEFICIENCY | **Control** | Decisión humana requerida |

**Problema**: Control y colaboración están MEZCLADOS en el mismo archivo.

### 2.2 HOLD Check Actual (grep)

**Archivo**: `plugins/ralphharness/commands/implement.md` (línea ~302)

```bash
count=$(grep -c '^\[HOLD\]$\|^\[PENDING\]$\|^\[URGENT\]$' "$SPEC_PATH/chat.md" 2>/dev/null || true)
```

**Resolución**: `[HOLD]` → `[RESOLVED]` (el grep no matchea `[RESOLVED]`)

**Problemas del grep approach**:
1. **Falsos positivos**: Si alguien escribe `[HOLD]` en un comentario o discusión (no como signal), el grep lo detecta
2. **No hay status explícito**: Resolved se infiere por cambio de texto, no por campo estructurado
3. **No hay timestamp**: No se puede saber cuándo se emitió una signal
4. **No hay auditoría**: No se puede replay el historial de signals
5. **chat.md crece**: Con signals + colaboración, el archivo se hace largo y el grep escanea todo

### 2.3 Chat Protocol (coordinator-pattern.md)

**Archivo**: `plugins/ralphharness/references/coordinator-pattern.md` (línea ~162)

4 pasos antes de cada delegación:
1. Check existence de chat.md
2. Read new messages desde `chat.executor.lastReadLine`
3. Update lastReadLine en `.ralph-state.json`
4. Apply signal rules (tabla de 12 signals)

**Atomic append** con flock (fd 200):
```bash
(
  exec 200>"$SPEC_PATH/chat.md.lock"
  flock -e 200 || exit 1
  cat >> "$SPEC_PATH/chat.md" << 'MSGEOF'
### [YYYY-MM-DD HH:MM:SS] Coordinator → External-Reviewer
MSGEOF
) 200>"$SPEC_PATH/chat.md.lock"
```

### 2.4 Schema Actual

**Archivo**: `plugins/ralphharness/schemas/spec.schema.json`

Campos relevantes ya existentes:
- `ciCommands: string[]` — lista de comandos CI (añadido por Spec 4)
- `chat.executor.lastReadLine: integer` — cursor de lectura del executor
- `chat.reviewer.lastReadLine: integer` — cursor de lectura del reviewer
- `nativeTaskMap: object` — mapa de taskIndex a native IDs (añadido por Spec 1)
- `nativeSyncEnabled: boolean` — sync activo (añadido por Spec 1)

**Campos que faltan para signals.jsonl**:
- `signals.lastProcessedLine: integer` — cursor de lectura del signal log
- No hay schema para el formato de signals.jsonl

### 2.5 Channel Map

**Archivo**: `plugins/ralphharness/references/channel-map.md`

| Canal | Escritores | Lock |
|-------|-----------|------|
| chat.md | coordinator, reviewer | flock fd 200 |
| task_review.md | reviewer only | no lock needed |
| tasks.md | spec-executor, reviewer | flock fd 201 |

**Falta**: signals.jsonl no está en el channel map.

### 2.6 CI Discovery Actual

**Archivo**: `plugins/ralphharness/references/coordinator-pattern.md` (sección CI Snapshot)

Spec 4 añadió CI command discovery desde:
1. Verification Contract en requirements.md (manual)
2. Project config files (package.json scripts, pyproject.toml lint config, Makefile targets)

Pero no hay **script de auto-detección**. El coordinator tiene que leer y parsear manualmente.

---

## 3. Referencia Externa — OpenHands SDK

**Fuente**: `docs/harness-engineering/11-openhands-deep-dive.md`

### 3.1 Event Log Inmutable

```python
# Core events
SystemPromptEvent    # System prompt + tools + dynamic context
MessageEvent         # User/assistant messages
ActionEvent          # Tool call with action, thought, security_risk
ObservationEvent     # Tool execution result
AgentErrorEvent      # Error during tool execution
TokenEvent           # Token usage tracking

# Condensation events
Condensation         # Condensed history replacement
CondensationRequest  # Request to trigger condensation

# Review events
UserRejectObservation  # Action blocked by hook
```

**Key insight**: El event log es **inmutable** — eventos se append pero nunca se modifican. La condensation crea vistas alternativas sin mutar el log original.

**Contraste con RalphHarness**: chat.md es mutable. Las signals se "resuelven" cambiando texto. Con signals.jsonl, las signals serían eventos con `status: active/resolved` — no se edita el evento, se append un nuevo evento de resolución.

### 3.2 ActionEvent con Security Risk

```python
class ActionEvent:
    action: Action
    thought: str
    security_risk: SecurityRisk | None  # LOW, MEDIUM, HIGH, CRITICAL
    critic_result: CriticResult | None
```

**Lección**: Cada evento puede tener metadata enriquecida. En RalphHarness, cada signal JSONL puede tener `task`, `from`, `reason`, `security_risk` — no solo el nombre de la signal.

### 3.3 Skills Auto-Detection

| Marcador | Skill | Descripción |
|----------|-------|-------------|
| `uv.lock` | uv | Package management con uv |
| `deno.json`, `deno.jsonc`, `deno.lock` | deno | Runtime/package management con Deno |
| `.openhands/microagents/` | Custom | Micro-agentes específicos del proyecto |

**Lección**: La auto-detección se basa en **marcadores de archivo** — no en configuración explícita. RalphHarness puede usar el mismo patrón para CI commands.

### 3.4 Condensation

```python
class LLMSummarizingCondenser:
    max_size: int = 240      # Max events before condensation
    keep_first: int = 2      # Always keep first N events (system prompt)
```

**Lección**: El condenser mantiene los primeros N eventos (system prompt) y condensa el resto. Para signals.jsonl, esto significa que las signals antiguas se pueden archivar sin perder las recientes.

---

## 4. Referencia Externa — Deep Agents (LangChain)

**Fuente**: `docs/harness-engineering/10-deep-agents-deep-dive.md`

### 4.1 FilesystemMiddleware — Tool Result Eviction

```python
tool_token_limit_before_evict: int = 20000  # ~20K tokens

# Si el resultado es grande:
1. Escribir contenido completo al backend: /large_tool_results/{tool_call_id}
2. Reemplazar el ToolMessage con preview + referencia
```

**Lección**: Resultados grandes se evictan al filesystem. Para signals.jsonl, si el log crece mucho, se puede archivar signals antiguas a `.signals-archive/` manteniendo solo las recientes en el archivo activo.

### 4.2 SummarizationMiddleware — Proactive Condensation

```python
class SummarizationMiddleware:
    trigger: ContextSize  # When to summarize (e.g., 85% of window)
```

**Lección**: La condensación es proactiva (antes del overflow) no reactiva. Para signals.jsonl, se puede truncar proactivamente cuando el archivo excede un threshold.

---

## 5. Diseño Propuesto — Signal Event Log

### 5.1 Formato JSONL

Cada línea en `signals.jsonl` es un JSON object:

```json
{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"active","timestamp":"2026-05-14T10:00:00Z","reason":"Implementation does not match spec. Verify command fails with exit code 1."}
{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"resolved","timestamp":"2026-05-14T10:05:00Z","reason":"Executor fixed the implementation. Verify now passes."}
{"type":"control","signal":"DEADLOCK","from":"spec-executor","to":"coordinator","task":"task-2.3","status":"active","timestamp":"2026-05-14T11:00:00Z","reason":"Cannot resolve conflict between requirements and implementation."}
```

**Campos**:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `type` | string | `"control"` (siempre — colaboración va en chat.md) |
| `signal` | string | HOLD, PENDING, URGENT, DEADLOCK, INTENT-FAIL, SPEC-ADJUSTMENT, SPEC-DEFICIENCY, ACK, CONTINUE, OVER, CLOSE, ALIVE, STILL |
| `from` | string | Quien emite: coordinator, external-reviewer, spec-executor, human |
| `to` | string | Destinatario: coordinator, external-reviewer, spec-executor, all |
| `task` | string | Task ID (e.g., "task-1.1") o "all" |
| `status` | string | `"active"` o `"resolved"` |
| `timestamp` | string | ISO 8601 UTC |
| `reason` | string | Texto explicativo |

### 5.2 Separación de Concerns

| Canal | Contenido | Formato |
|-------|-----------|---------|
| `signals.jsonl` | Control signals (HOLD, PENDING, DEADLOCK, etc.) | JSONL — mecánico, `jq` check |
| `chat.md` | Colaboración rica (hipótesis, experimentos, findings, debate arquitectónico) | Markdown — humano-legible |

**Por qué separar**:
1. El coordinator necesita check mecánico → JSONL con `jq` es más fiable que grep sobre Markdown
2. chat.md se mantiene legible para humanos — no contaminado con `[HOLD]` markers
3. signals.jsonl es auditable — se puede replay el historial completo
4. chat.md puede evolucionar independientemente para casos de colaboración rica

### 5.3 HOLD Check con jq

**Reemplazo del grep**:

```bash
# ANTES (Spec 1 — grep sobre chat.md):
count=$(grep -c '^\[HOLD\]$\|^\[PENDING\]$\|^\[URGENT\]$' "$SPEC_PATH/chat.md" 2>/dev/null || true)

# DESPUÉS (Spec 6 — jq sobre signals.jsonl):
count=$(jq -r 'select(.signal=="HOLD" or .signal=="PENDING" or .signal=="DEADLOCK" or .signal=="URGENT") | select(.status=="active")' "$SPEC_PATH/signals.jsonl" 2>/dev/null | wc -l)
```

**Ventajas**:
- `status: active/resolved` es explícito — no se depende de cambiar texto
- No hay falsos positivos — `jq` filtra por campos, no por patrones de texto
- Se puede consultar por task: `select(.task=="task-1.1")`
- Se puede consultar por emisor: `select(.from=="external-reviewer")`

### 5.4 Atomic Append para signals.jsonl

```bash
(
  exec 202>"$SPEC_PATH/signals.jsonl.lock"
  flock -e 202 || exit 1
  echo '{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"active","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","reason":"..."}' >> "$SPEC_PATH/signals.jsonl"
) 202>"$SPEC_PATH/signals.jsonl.lock"
```

**fd 202** — distinto de chat.md (fd 200) y tasks.md (fd 201).

### 5.5 Resolución de Signals

En vez de editar el evento original (como OpenHands — inmutable), se **append un nuevo evento** con `status: resolved`:

```json
{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"active","timestamp":"2026-05-14T10:00:00Z","reason":"Verify fails."}
{"type":"control","signal":"HOLD","from":"external-reviewer","to":"coordinator","task":"task-1.1","status":"resolved","timestamp":"2026-05-14T10:05:00Z","reason":"Fixed. Verify passes."}
```

El `jq` check filtra `select(.status=="active")` — el evento resolved no bloquea.

### 5.6 Schema Changes

Añadir a `spec.schema.json`:

```json
"signals": {
  "type": "object",
  "description": "Signal event log state",
  "properties": {
    "lastProcessedLine": {
      "type": "integer",
      "minimum": 0,
      "default": 0,
      "description": "Last processed line in signals.jsonl (coordinator cursor)"
    }
  }
}
```

### 5.7 Channel Map Update

Añadir a `channel-map.md`:

| Canal | Escritores | Lock |
|-------|-----------|------|
| signals.jsonl | coordinator, external-reviewer, spec-executor | flock fd 202 |
| signals.jsonl.lock | — | Lock file only |

---

## 6. Diseño Propuesto — CI Auto-Detection

### 6.1 detect-ci-commands.sh

Script que se ejecuta al inicio de cada spec (en implement.md Step 3, antes del loop).

**Marcadores soportados**:

| Marcador | Comandos detectados | Prioridad |
|----------|-------------------|-----------|
| `pyproject.toml` | ruff check, ruff format, mypy, pytest | Alta (Python) |
| `setup.cfg` | flake8, mypy, pytest | Baja (Python legacy) |
| `package.json` | pnpm lint, pnpm check-types, pnpm test, npm lint, npm test | Alta (Node) |
| `Makefile` | make lint, make test, make check | Media (genérico) |
| `Cargo.toml` | cargo clippy, cargo test, cargo fmt --check | Alta (Rust) |
| `go.mod` | go vet, go test ./..., golint | Alta (Go) |
| `.github/workflows/*.yml` | Comandos CI del workflow | Baja (referencia) |

**Lógica de detección**:

```bash
#!/usr/bin/env bash
# detect-ci-commands.sh — Auto-detect CI commands from project markers
# Output: JSON array of command strings, written to .ralph-state.json ciCommands

SPEC_PATH="$1"
COMMANDS=()

# Python — pyproject.toml
if [[ -f "pyproject.toml" ]]; then
  # Check for ruff
  if grep -q '"ruff"' pyproject.toml 2>/dev/null || grep -q 'ruff' pyproject.toml 2>/dev/null; then
    COMMANDS+=("ruff check .")
    COMMANDS+=("ruff format --check .")
  fi
  # Check for mypy
  if grep -q '"mypy"' pyproject.toml 2>/dev/null || grep -q 'mypy' pyproject.toml 2>/dev/null; then
    COMMANDS+=("mypy .")
  fi
  # pytest is default for Python
  if [[ -f "pytest.ini" ]] || grep -q '"pytest"' pyproject.toml 2>/dev/null || grep -q 'pytest' pyproject.toml 2>/dev/null; then
    COMMANDS+=("pytest")
  fi
fi

# Node — package.json
if [[ -f "package.json" ]]; then
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    if [[ -f "pnpm-lock.yaml" ]]; then
      COMMANDS+=("pnpm lint")
    elif [[ -f "yarn.lock" ]]; then
      COMMANDS+=("yarn lint")
    else
      COMMANDS+=("npm run lint")
    fi
  fi
  if jq -e '.scripts["check-types"]' package.json >/dev/null 2>&1; then
    COMMANDS+=("pnpm check-types")
  fi
  if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    if [[ -f "pnpm-lock.yaml" ]]; then
      COMMANDS+=("pnpm test")
    else
      COMMANDS+=("npm test")
    fi
  fi
fi

# Makefile
if [[ -f "Makefile" ]]; then
  if grep -q '^lint:' Makefile 2>/dev/null; then
    COMMANDS+=("make lint")
  fi
  if grep -q '^test:' Makefile 2>/dev/null; then
    COMMANDS+=("make test")
  fi
  if grep -q '^check:' Makefile 2>/dev/null; then
    COMMANDS+=("make check")
  fi
fi

# Rust — Cargo.toml
if [[ -f "Cargo.toml" ]]; then
  COMMANDS+=("cargo clippy")
  COMMANDS+=("cargo test")
  COMMANDS+=("cargo fmt --check")
fi

# Go — go.mod
if [[ -f "go.mod" ]]; then
  COMMANDS+=("go vet ./...")
  COMMANDS+=("go test ./...")
fi

# Write to .ralph-state.json
if [[ ${#COMMANDS[@]} -gt 0 ]]; then
  CMD_JSON=$(printf '%s\n' "${COMMANDS[@]}" | jq -R . | jq -s .)
  jq --argjson cmds "$CMD_JSON" '.ciCommands = $cmds' \
    "$SPEC_PATH/.ralph-state.json" > /tmp/state.json && \
    mv /tmp/state.json "$SPEC_PATH/.ralph-state.json"
  echo "CI commands detected: ${COMMANDS[*]}"
else
  echo "No CI commands auto-detected from project markers"
fi
```

### 6.2 Integración en implement.md

En Step 3 (pre-loop setup), después de state integrity validation:

```bash
# Auto-detect CI commands from project markers
bash "$PLUGIN_ROOT/hooks/scripts/detect-ci-commands.sh" "$SPEC_PATH"
```

### 6.3 Fallback

Si `detect-ci-commands.sh` no detecta nada:
1. El coordinator usa los comandos del Verification Contract (requirements.md) — comportamiento actual
2. Log: `"No CI commands auto-detected — falling back to Verification Contract"`

---

## 7. Archivos Afectados

| Archivo | Cambio | Tipo |
|---------|--------|------|
| `templates/signals.jsonl` | **NUEVO** — Template vacío con header comment | Creación |
| `hooks/scripts/detect-ci-commands.sh` | **NUEVO** — Script de auto-detección | Creación |
| `commands/implement.md` | Reemplazar grep HOLD check → jq check. Añadir detect-ci-commands.sh call. | Modificación |
| `references/coordinator-pattern.md` | Chat Protocol: añadir Signal Protocol (leer signals.jsonl antes de chat.md). Actualizar atomic append pattern. | Modificación |
| `references/channel-map.md` | Añadir signals.jsonl al channel registry (fd 202) | Modificación |
| `schemas/spec.schema.json` | Añadir `signals.lastProcessedLine` | Modificación |
| `templates/chat.md` | Actualizar signal legend: control signals → signals.jsonl, chat.md → colaboración rica | Modificación |
| `agents/spec-executor.md` | Actualizar `<chat>` protocol: control signals → signals.jsonl, colaboración → chat.md | Modificación |
| `agents/external-reviewer.md` | Actualizar signal emission: HOLD/PENDING/DEADLOCK → signals.jsonl, debate → chat.md | Modificación |
| `agents/qa-engineer.md` | Actualizar Section 0 Step 2: check signals.jsonl en vez de chat.md para HOLD/PENDING/DEADLOCK | Modificación |

---

## 8. Riesgos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| `jq` no disponible en el sistema | Baja | Alto — HOLD check falla | Fallback a grep si jq no existe. Log warning. |
| signals.jsonl crece mucho en specs largas | Media | Bajo — performance | Archivar signals resolved a `.signals-archive/` cuando el archivo excede 500 líneas |
| Agentes escriben signals en formato incorrecto | Media | Medio — jq falla | Template signals.jsonl con ejemplo. Validación en el append script. |
| Race condition entre coordinator y reviewer escribiendo signals | Baja | Medio — línea corrupta | flock fd 202 (mismo patrón que chat.md fd 200) |
| detect-ci-commands.sh detecta comandos que no existen | Media | Bajo — CI snapshot falla | Verificar que el comando existe con `command -v` antes de añadirlo |

---

## 9. Dependencias

- **Spec 1** (engine-state-hardening) ✅ — grep-based HOLD check existe, se reemplaza
- **Spec 3** (role-boundaries) ✅ — role contracts definen quién puede escribir signals.jsonl
- **Spec 4** (loop-safety-infra) ✅ — `ciCommands` ya existe en schema, se popula automáticamente

---

## 10. Mejoras Descubiertas en Revisión Adicional

### 10.1 discover-ci.sh YA EXISTE — Ampliar, No Reemplazar

**Archivo**: [`plugins/ralphharness/hooks/scripts/discover-ci.sh`](plugins/ralphharness/hooks/scripts/discover-ci.sh:1)

El script `discover-ci.sh` **ya existe** y hace:
- Escanea `.github/workflows/*.yml` → extrae comandos CI (`- run:`)
- Escanea `tests/*.bats` → extrae test runners (`bats`, `test`, `./tests/`)
- Clasifica por categoría: `test`, `lint`, `build`, `typecheck`
- Output: JSON array `[{command, category}, ...]`

**Lo que NO hace** (gap):
- No detecta `pyproject.toml` → ruff/mypy/pytest
- No detecta `package.json` → pnpm lint/test/check-types
- No detecta `Makefile` → make lint/test/check
- No detecta `Cargo.toml` → cargo clippy/test/fmt
- No detecta `go.mod` → go vet/test
- No detecta `.env.example` o `tox.ini` para configuraciones

**Mejora**: `detect-ci-commands.sh` debe **ampliar** `discover-ci.sh`:
1. Primero ejecutar `discover_ci_commands` para comandos desde workflows
2. Luego escanear marcadores de proyecto (`pyproject.toml`, `package.json`, etc.) para detectar built-in toolchains
3. Unificar deduplicación antes de escribir a `.ralph-state.json`

```bash
# Fases de detección:
# Phase 1: discover-ci.sh (workflows, bats) — ya existe
# Phase 2: detect-ci-commands.sh (marcadores de proyecto) — mejora propuesta
# Phase 3: Unificar y escribir ciCommands
```

### 10.2 Schema — ciCommands Ya Existe, Añadir category

**Archivo**: [`plugins/ralphharness/schemas/spec.schema.json`](plugins/ralphharness/schemas/spec.schema.json:335)

`ciCommands` ya existe como `string[]`. El `discover-ci.sh` output actual es `[{command, category}]` pero se almacena solo como strings planas.

**Mejora**: Cambiar `ciCommands: string[]` → `ciCommands: [{command: string, category: string}]` para mantener la categoría y permitir CI snapshot diferenciado por tipo (lint vs test vs build).

### 10.3 Channel Map — Añadir signals.jsonl

**Archivo**: `plugins/ralphharness/references/channel-map.md`

signals.jsonl necesita su entrada en el channel registry:
- fd 202 (distinto de chat.md fd 200 y tasks.md fd 201)
- Lock file: `signals.jsonl.lock`
- Escritores: coordinator, external-reviewer, spec-executor
- Lectores: coordinator (antes de cada delegación), todos los agentes para verificar bloqueo

---
