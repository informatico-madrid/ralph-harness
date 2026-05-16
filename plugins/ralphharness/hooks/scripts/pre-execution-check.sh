#!/usr/bin/env bash
set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────
usage() {
  cat >&2 <<EOF
Usage: $0 --agent AGENT --task TASK [--paths PATHS] [--command CMD] --spec-path PATH

Required:
  --agent      Agent name (e.g. spec-executor)
  --task       Task identifier (e.g. 1.1)
  --spec-path  Spec directory path

Optional:
  --paths      Comma-separated list of intended write paths
  --command    Verify command to inspect for dangerous patterns
EOF
  exit 1
}

# ── Argument parsing ──────────────────────────────────────────────
AGENTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT="$2";     shift 2 ;;
    --task)     TASK="$2";      shift 2 ;;
    --paths)    PATHS="$2";     shift 2 ;;
    --command)  COMMAND="$2";   shift 2 ;;
    --spec-path) SPEC_PATH="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ── Required-flag validation ─────────────────────────────────────
missing=""
[[ -z "${AGENT:-}" ]]     && missing+="--agent "
[[ -z "${TASK:-}" ]]      && missing+="--task "
[[ -z "${SPEC_PATH:-}" ]] && missing+="--spec-path "

if [[ -n "$missing" ]]; then
  echo "Error: missing required flag(s): ${missing}" >&2
  usage
fi

# Default optional flags (set -u requires initialized variables)
PATHS="${PATHS:-}"
COMMAND="${COMMAND:-}"

# ── Severity-rank helpers ─────────────────────────────────────────

# rank() — numeric rank for a risk severity string.
# Mapping: LOW=0, MEDIUM=1, HIGH=2, UNKNOWN=3
# UNKNOWN ranks above HIGH per design (unknown risk should not be downgraded).
rank() {
  case "${1^^}" in
    LOW)      echo 0 ;;
    MEDIUM)   echo 1 ;;
    HIGH)     echo 2 ;;
    UNKNOWN)  echo 3 ;;
    *)        echo 3 ;;   # anything unrecognized defaults to UNKNOWN rank
  esac
}

# max_risk() — returns the higher-ranked risk string from two inputs.
max_risk() {
  local a_r=$(rank "$1")
  local b_r=$(rank "$2")
  if (( a_r >= b_r )); then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

# ── Exit-code constants ──────────────────────────────────────────
# 0   — allow (pre-execution check passed)
# 2   — block/confirm (risky operation, awaiting security-decision)
# N   — other non-zero = error (generic failure)

# ── Layer 1 — Role-contract Access Matrix parser ─────────────────

# layer1_role_contract <agent> <paths>
#   Resolves references/role-contracts.md, extracts the Access Matrix
#   table, looks up the agent row, and classifies the given comma-
#   separated paths as clear / violation / UNKNOWN.
#   Prints: RISK:<severity>|REASON:<reason>
layer1_role_contract() {
  local role="$1"
  local paths="$2"

  # Enable extglob for advanced glob patterns
  shopt -s extglob

  # ── 1. Resolve role-contracts.md location ──────────────────────
  local rc_path=""
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    rc_path="${CLAUDE_PLUGIN_ROOT}/references/role-contracts.md"
  else
    rc_path="$(cd "$(dirname "$0")/.." && pwd)/references/role-contracts.md"
  fi

  # ── 2. Existence check ─────────────────────────────────────────
  if [[ ! -f "$rc_path" ]]; then
    printf 'RISK:UNKNOWN|REASON:role-contracts.md not found at %s' "$rc_path"
    return 0
  fi

  # ── 3. Extract Access Matrix table via awk ──────────────────────
  local matrix
  matrix=$(awk '
    /^## Access Matrix/ { capture=1; print; next }
    capture && /^## / { exit }
    capture { print }
  ' "$rc_path")

  if [[ -z "$matrix" ]]; then
    printf 'RISK:UNKNOWN|REASON:Access Matrix section not found in role-contracts.md'
    return 0
  fi

  # ── 4. Look up the agent row ───────────────────────────────────
  #    The table row format: | agent | reads | writes | denylist |
  local agent_col="" reads_col="" writes_col="" denylist_col=""
  local found=0

  while IFS= read -r row; do
    # Skip header/separator lines and the section heading
    [[ "$row" =~ ^\|?--- ]] && continue
    [[ "$row" =~ ^##\ Access\ Matrix ]] && continue

    # Split on pipe and trim whitespace
    local cols=()
    local tmp="$row"
    while [[ -n "$tmp" ]]; do
      local part="${tmp%%|*}"
      cols+=("$part")
      tmp="${tmp#*|}"
    done

    # We expect at least 4 columns
    [[ ${#cols[@]} -lt 4 ]] && continue

    local c_role c_reads c_writes c_deny
    # Trim leading/trailing whitespace
    # cols[0] is empty (leading pipe), actual data starts at cols[1]
    c_role=$(echo "${cols[1]}" | xargs)
    c_reads=$(echo "${cols[2]}" | xargs)
    c_writes=$(echo "${cols[3]}" | xargs)
    c_deny=$(echo "${cols[4]}" | xargs)

    # Substring match for agent names (e.g. "coordinator" matches "coordinator (human)")
    local c_role_lower="${c_role,,}"
    local role_lower="${role,,}"
    if [[ "$c_role_lower" == *"$role_lower"* ]]; then
      agent_col="$c_role"
      reads_col="$c_reads"
      writes_col="$c_writes"
      denylist_col="$c_deny"
      found=1
      break
    fi
  done <<< "$matrix"

  # ── 5. Agent not found ─────────────────────────────────────────
  if (( ! found )); then
    printf 'RISK:UNKNOWN|REASON:agent %q not found in Access Matrix' "$role"
    return 0
  fi

  # ── 6. Classify each provided path ─────────────────────────────
  #    Returns the highest severity risk across all paths.

  # --paths absent → UNKNOWN (cannot prove writes are in-bounds)
  if [[ -z "$paths" || "$paths" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:UNKNOWN|REASON:no paths provided'
    return 0
  fi

  local worst_risk="clear"
  local reasons=()

  IFS=',' read -ra path_arr <<< "$paths"

  for p in "${path_arr[@]}"; do
    p=$(echo "$p" | xargs)          # trim whitespace
    [[ -z "$p" ]] && continue

    # --- Check denylist first ---
    # Normalize denylist: strip backticks, handle N/A and None
    local denylist_norm="${denylist_col//\`/}"
    if [[ "${denylist_norm,,}" != *"na"* && "${denylist_norm,,}" != *"none"* && "${denylist_norm,,}" != *"(read-only)"* ]]; then
      # Split on comma, check each entry
      IFS=',' read -ra deny_arr <<< "$denylist_norm"
      for d in "${deny_arr[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -z "$d" ]] && continue
        # Strip parenthetical exceptions: "file (except foo)"
        local deny_base="${d%% (*}"
        deny_base=$(echo "$deny_base" | xargs)
        if [[ -z "$deny_base" || "$deny_base" == "n/a" || "$deny_base" == "none" ]]; then
          continue
        fi
        # Check if there's an exception that covers this path
        local exception="${d##* (}"
        exception="${exception%%)}"
        if [[ -n "$exception" && "$exception" != "$d" ]]; then
          # Path is excepted — not a violation
          continue
        fi
        # extglob glob match (pattern can contain * wildcards)
        if [[ "$p" == $deny_base ]]; then
          worst_risk="violation"
          reasons+=("path $p is in denylist for $agent_col")
          break
        fi
      done
    fi

    # --- Check writes permission (only for agents with explicit writes) ---
    # Normalize writes_col: strip backticks and check read-only patterns
    local writes_norm="${writes_col//\`/}"
    if [[ "$writes_norm" == "*_\(read-only\)*" || "$writes_norm" == "*(read-only)*" ]]; then
      # Agent is read-only; any write attempt is a violation.
      if [[ -n "$p" ]]; then
        if [[ "$worst_risk" != "violation" ]]; then
          worst_risk="violation"
        fi
        reasons+=("agent $agent_col is read-only")
      fi
    elif [[ "${writes_norm}" != *"All"* && -n "$writes_col" ]]; then
      # Check if path is in the writes column using extglob
      local writes_for_split="${writes_col//\`/}"
      IFS=',' read -ra write_arr <<< "$writes_for_split"
      local in_writes=0
      for w in "${write_arr[@]}"; do
        w=$(echo "$w" | xargs)
        # Strip parenthetical exceptions: e.g. ".ralph-state.json (awaitingApproval)"
        local w_base="${w%% (*}"
        w_base=$(echo "$w_base" | xargs)
        if [[ -z "$w_base" || "$w_base" == "n/a" ]]; then
          continue
        fi
        # extglob glob match — pattern can contain * wildcards
        if [[ "$p" == $w_base ]]; then
          in_writes=1
          break
        fi
      done

      if (( ! in_writes )); then
        # Path not in writes — report as violation since the agent
        # is attempting to write to a file it is not authorized for.
        worst_risk="violation"
        reasons+=("path $p not in writes for $agent_col")
      fi
    fi
    # "All" writes = no check needed
  done

  # ── 7. Output result ───────────────────────────────────────────
  local reason_str=""
  if (( ${#reasons[@]} > 0 )); then
    reason_str=$(printf '%s; ' "${reasons[@]}")
    reason_str="${reason_str%; }"
  else
    reason_str="all paths within $agent_col permissions"
  fi

  printf 'RISK:%s|REASON:%s' "$worst_risk" "$reason_str"
  return 0
}

# ── Layer 2 — Dangerous shell pattern detection ─────────────────

# layer2_shell_pattern <command>
#   Scans a shell command for known-dangerous patterns using ERE.
#   Returns:
#     RISK:HIGH|REASON:shell pattern <name> found
#     RISK:LOW|REASON:none
layer2_shell_pattern() {
  local cmd="${1:-}"

  # Absent command -> no risk
  if [[ -z "$cmd" || "$cmd" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:LOW|REASON:none'
    return 0
  fi

  # Pattern 1: rm -rf / rm -fr / rm -r -f
  if [[ "$cmd" =~ rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]* || "$cmd" =~ rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]* || "$cmd" =~ rm[[:space:]]+-r[[:space:]]+-[[:space:]]*f ]]; then
    printf 'RISK:HIGH|REASON:shell pattern rm -rf found'
    return 0
  fi

  # Pattern 2: sudo
  if [[ "$cmd" =~ (^|[[:space:];|])sudo([[:space:]]|$) ]]; then
    printf 'RISK:HIGH|REASON:shell pattern sudo found'
    return 0
  fi

  # Pattern 3: chmod 777
  if [[ "$cmd" =~ chmod[[:space:]]+777 ]]; then
    printf 'RISK:HIGH|REASON:shell pattern chmod 777 found'
    return 0
  fi

  # Pattern 4: curl|wget piped to sh|bash
  # Note: bash ERE does not support matching literal pipe via regex,
  # so we check for the keyword combo with a pipe separator using
  # bash string matching instead of ERE.
  local fetch_shell_pattern='(curl|wget).*(sh|bash)'
  if [[ "$cmd" =~ $fetch_shell_pattern && "$cmd" == *"|"* ]]; then
    printf 'RISK:HIGH|REASON:shell pattern fetch-pipe-shell found'
    return 0
  fi

  # Pattern 5: eval
  if [[ "$cmd" =~ (^|[[:space:];|])eval([[:space:]]|$) ]]; then
    printf 'RISK:HIGH|REASON:shell pattern eval found'
    return 0
  fi

  printf 'RISK:LOW|REASON:none'
  return 0
}

# ── Layer 3 — Baseline risk classifier ──────────────────────────

# layer3_risk
#   Provides a baseline risk classification based on task structure.
#   Does NOT re-derive Layer 1 or Layer 2 outcomes — those are
#   merged by the combiner.
#
#   Returns:
#     RISK:UNKNOWN|REASON:no paths provided          — no --paths
#     RISK:LOW|REASON:read-only task                  — --paths present, no command
#     RISK:MEDIUM|REASON:task modifies files           — --paths present, command present
layer3_risk() {
  # --paths absent → UNKNOWN (cannot classify a task with no file targets)
  if [[ -z "${PATHS:-}" || "$PATHS" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:UNKNOWN|REASON:no paths provided'
    return 0
  fi

  # --paths present, no command → task touches files but does nothing risky
  if [[ -z "${COMMAND:-}" || "$COMMAND" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:LOW|REASON:read-only task'
    return 0
  fi

  # --paths present with a command → task modifies files + executes something
  printf 'RISK:MEDIUM|REASON:task modifies files'
  return 0
}

# ── Max-severity combiner ────────────────────────────────────────

# combine_risk <l1_verdict> <l2_verdict> <l3_verdict>
#   Combines the three layer verdicts using max-severity policy.
#   Layer 1 violations SHORT-CIRCUIT: they produce a hard-block before
#   the combiner considers other layers (hard-block, layer role-contract).
#   Otherwise: max_risk() across layers (UNKNOWN > HIGH > MEDIUM > LOW).
#
#   Prints:
#     VERDICT:block|LAYER:role-contract|DRIVING_LAYER:role-contract   — Layer 1 short-circuit
#     VERDICT:confirm|LAYER:<layer>|DRIVING_LAYER:<layer>             — combined risk
#     VERDICT:allow|LAYER:none|DRIVING_LAYER:none                     — clean result
combine_risk() {
  local l1_verdict="${1:-}"
  local l2_verdict="${2:-}"
  local l3_verdict="${3:-}"

  # Extract risk value from each layer verdict
  # Format: RISK:<value>|REASON:<reason> → extract <value> only
  local l1_risk="${l1_verdict#RISK:}"
  l1_risk="${l1_risk%%|*}"
  local l2_risk="${l2_verdict#RISK:}"
  l2_risk="${l2_risk%%|*}"
  local l3_risk="${l3_verdict#RISK:}"
  l3_risk="${l3_risk%%|*}"

  # Default missing risks to LOW
  l2_risk="${l2_risk:-LOW}"
  l3_risk="${l3_risk:-LOW}"

  # ── Short-circuit: Layer 1 violation → hard-block ─────────────
  if [[ "$l1_risk" == "violation" ]]; then
    printf 'VERDICT:block|LAYER:role-contract|DRIVING_LAYER:role-contract|RISK:HIGH'
    return 2
  fi

  # ── Max-severity: combine remaining layers ─────────────────────
  # Map layer-internal "clear" to LOW for ranking; normalize UNKNOWN
  [[ "$l1_risk" == "clear" ]] && l1_risk="LOW"
  local best_risk="${l1_risk:-LOW}"
  local best_layer="role-contract"

  # Layer 1 clear/UNKNOWN → contributes to comparison
  if (( $(rank "$best_risk") < $(rank "$l2_risk") )); then
    best_risk="$l2_risk"
    best_layer="shell-pattern"
  fi

  if (( $(rank "$best_risk") < $(rank "$l3_risk") )); then
    best_risk="$l3_risk"
    best_layer="task-baseline"
  fi

  # Map risk to verdict + driving layer
  local verdict
  local driving_layer

  case "$best_risk" in
    LOW|MEDIUM)
      verdict="allow"
      driving_layer="none"
      ;;
    HIGH)
      verdict="confirm"
      driving_layer="$best_layer"
      ;;
    UNKNOWN|*)
      verdict="confirm"
      driving_layer="$best_layer"
      ;;
  esac

  printf 'VERDICT:%s|LAYER:%s|DRIVING_LAYER:%s|RISK:%s' \
    "$verdict" "$driving_layer" "$driving_layer" "$best_risk"
  return 0
}

# ── ConfirmRisky policy ─────────────────────────────────────────

# confirm_risky <combined_risk> <driving_layer>
#   Maps the combined risk to a final verdict:
#     LOW/MEDIUM  → allow, exit 0
#     HIGH/UNKNOWN → confirm, exit 2
#     block       → hard-block (bypasses confirm), exit 2
#
#   Outputs:
#     - Human-readable reason to stderr
#     - Structured verdict line (decision=... layer=... risk=...) to stdout
#     - Sets exit code per verdict

confirm_risky() {
  local risk="${1:-LOW}"
  local layer="${2:-none}"
  local reason="${3:-}"

  local decision exit_code
  case "$risk" in
    block)
      decision="block"
      exit_code=2
      ;;
    HIGH|UNKNOWN)
      decision="confirm"
      exit_code=2
      ;;
    LOW|MEDIUM|*)
      decision="allow"
      exit_code=0
      ;;
  esac

  # Human-readable reason to stderr
  # Human-readable reason to stderr
  printf '%s: %s (layer=%s, risk=%s)\n' \
    "$decision" "${reason:-no reason}" "$layer" "$risk" >&2

  # Structured verdict to stdout (one key=value per line for reliable extraction)
  printf 'decision=%s\nlayer=%s\nrisk=%s\n' \
    "$decision" "$layer" "$risk"

  exit "$exit_code"
}

# ── Main flow ────────────────────────────────────────────────────

# Run all three layers
L1_OUTPUT=$(layer1_role_contract "$AGENT" "$PATHS") || true
L2_OUTPUT=$(layer2_shell_pattern "${COMMAND:-}") || true
L3_OUTPUT=$(layer3_risk) || true

# Combine risks using max-severity policy
COMBINED=$(combine_risk "$L1_OUTPUT" "$L2_OUTPUT" "$L3_OUTPUT") || true

# Extract verdict, risk, layer, and reason from combined output
# Format: VERDICT:<v>|LAYER:<l>|DRIVING_LAYER:<dl>|RISK:<r>
COMBINED_VERDICT="${COMBINED%%|*}"
COMBINED_VERDICT="${COMBINED_VERDICT#VERDICT:}"
COMBINED_RISK="${COMBINED##*RISK:}"
COMBINED_LAYER="${COMBINED##*LAYER:}"
COMBINED_LAYER="${COMBINED_LAYER%%|*}"

# Layer 1 block bypasses confirm_risky — hard-stop immediately
if [[ "$COMBINED_VERDICT" == "block" ]]; then
  printf 'block: role-contract violation (layer=%s, risk=%s)\n' \
    "$COMBINED_LAYER" "$COMBINED_RISK" >&2
  printf 'decision=block layer=%s risk=%s\n' \
    "$COMBINED_LAYER" "$COMBINED_RISK"

  # Emit security-decision event before block exit
  local decision="${COMBINED_VERDICT:-block}"
  [[ -z "$decision" ]] && decision="block"
  payload=$(jq -c -n \
    --arg type "security-decision" \
    --arg decision "$decision" \
    --arg layer "$COMBINED_LAYER" \
    --arg risk "$COMBINED_RISK" \
    --arg agent "${AGENT:-unknown}" \
    --arg task "${TASK:-unknown}" \
    --arg paths "${PATHS:-}" \
    --arg command "${COMMAND:-}" \
    --arg reason "automated security decision" \
    --arg timestamp "$(date -u +%FT%TZ)" \
    --argjson iteration "$iteration" \
    '{
      type: $type,
      decision: (if $decision == "" then "allow" else $decision end),
      layer: $layer,
      risk: $risk,
      agent: $agent,
      task: $task,
      path: (if $paths == "" then null else $paths end),
      command: (if $command == "" then null else $command end),
      reason: $reason,
      timestamp: $timestamp,
      iteration: $iteration
    }')
  if ! append_signal "$SPEC_PATH" "$payload"; then
    {
      echo ""
      echo "## $(date -u +%Y-%m-%d)"
      echo "- WARN: security-decision append_signal failed for block — audit trail incomplete"
    } >> "${SPEC_PATH}/.progress.md"
    exit 3
  fi

  exit 2
fi

# ── Emit security-decision event ─────────────────────────────────
# Capture confirm_risky output and exit code without aborting (set -e).
CR_OUTPUT=$(confirm_risky "$COMBINED_RISK" "$COMBINED_LAYER" "") || true

# Parse the structured verdict line: decision=X layer=Y risk=Z
decision_line=$(echo "$CR_OUTPUT" | grep '^decision=')
decision=""
if [[ -n "$decision_line" ]]; then
  decision=$(echo "$decision_line" | cut -d= -f2)
fi

# Resolve iteration from .ralph-state.json globalIteration, default 1
iteration=1
if [[ -f "${SPEC_PATH}/.ralph-state.json" ]]; then
  _iter=$(jq -r '.globalIteration // 1' "${SPEC_PATH}/.ralph-state.json" 2>/dev/null) || true
  [[ -n "${_iter:-}" && "${_iter}" != "null" ]] && iteration=$_iter
fi

# Source signal helpers (resolved relative to script directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-signals.sh"

# Build and emit the security-decision event
payload=$(jq -c -n \
  --arg type "security-decision" \
  --arg decision "${decision}" \
  --arg layer "$COMBINED_LAYER" \
  --arg risk "$COMBINED_RISK" \
  --arg agent "${AGENT:-unknown}" \
  --arg task "${TASK:-unknown}" \
  --arg paths "${PATHS:-}" \
  --arg command "${COMMAND:-}" \
  --arg reason "automated security decision" \
  --arg timestamp "$(date -u +%FT%TZ)" \
  --argjson iteration "$iteration" \
  '{
    type: $type,
    decision: (if $decision == "" then "allow" else $decision end),
    layer: $layer,
    risk: $risk,
    agent: $agent,
    task: $task,
    path: (if $paths == "" then null else $paths end),
    command: (if $command == "" then null else $command end),
    reason: $reason,
    timestamp: $timestamp,
    iteration: $iteration
  }')

if ! append_signal "$SPEC_PATH" "$payload"; then
  {
    echo ""
    echo "## $(date -u +%Y-%m-%d)"
    echo "- WARN: security-decision append_signal failed — audit trail incomplete"
  } >> "${SPEC_PATH}/.progress.md"
  exit 3
fi
