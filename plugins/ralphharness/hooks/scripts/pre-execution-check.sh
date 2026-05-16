#!/usr/bin/env bash
set -euo pipefail

# ── Argument parsing ───────────────────────────────────────────────
AGENT=""
TASK=""
PATHS=""
COMMAND=""
SPEC_PATH=""

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

# Required-flag validation
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

# ═══════════════════════════════════════════════════════════════════
# SECTION: Constants — Severity rank, exit codes, shell patterns
# ═══════════════════════════════════════════════════════════════════

# ── Severity rank ─────────────────────────────────────────────────
# rank() maps risk severity to numeric value for comparison.
# Order: LOW(0) < MEDIUM(1) < HIGH(2) < UNKNOWN(3)
# UNKNOWN ranks above HIGH — indeterminacy must never be downgraded.
rank() {
  case "${1^^}" in
    LOW)      echo 0 ;;
    MEDIUM)   echo 1 ;;
    HIGH)     echo 2 ;;
    UNKNOWN)  echo 3 ;;
    *)        echo 3 ;;
  esac
}

# max_risk() returns the higher-ranked risk string from two inputs.
max_risk() {
  local a_r=$(rank "$1")
  local b_r=$(rank "$2")
  if (( a_r >= b_r )); then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

# ── Exit-code contract ────────────────────────────────────────────
# 0   — allow (pre-execution check passed)
# 2   — block/confirm (risky operation, awaiting security-decision)
# N   — other non-zero = error (generic failure)

# ── Dangerous shell pattern ERE set ───────────────────────────────
# Patterns detected by Layer 2, in priority order.
# Each pattern maps to risk level HIGH.
SHELL_PATTERNS=(
  # Pattern 1: rm with force flag in any order (rm -rf, rm -fr, rm -r -f)
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*'
  'rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*'
  'rm[[:space:]]+-r[[:space:]]+-[[:space:]]*f'
  # Pattern 2: sudo execution
  '(^|[[:space:];|])sudo([[:space:]]|$)'
  # Pattern 3: world-writable permissions
  'chmod[[:space:]]+777'
  # Pattern 4: fetch-then-execute (curl/wget piped to sh/bash)
  '(curl|wget).*(sh|bash)'
  # Pattern 5: eval (dynamic code execution)
  '(^|[[:space:];|])eval([[:space:]]|$)'
)

# ═══════════════════════════════════════════════════════════════════
# SECTION: Helpers
# ═══════════════════════════════════════════════════════════════════

# resolve_role_contracts_path
#   Resolves the path to references/role-contracts.md.
#   Inputs:   (none — uses CLAUDE_PLUGIN_ROOT env var and SCRIPT_DIR)
#   Outputs:  Prints the resolved path to stdout.
#   Returns:  0 always (caller must check file existence).
resolve_role_contracts_path() {
  local rc_path=""
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    rc_path="${CLAUDE_PLUGIN_ROOT}/references/role-contracts.md"
  else
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    rc_path="${script_dir}/references/role-contracts.md"
  fi
  printf '%s' "$rc_path"
}

# emit_unknown — Single source of truth for indeterminate states.
#   Every indeterminate condition (missing contract, parse error, missing
#   paths, unknown agent) routes here.  Never fail-open: UNKNOWN always
#   maps to confirm (exit 2) via the combiner + ConfirmRisky path.
#
#   Inputs:
#     $1 — Reason string (naming the indeterminate condition)
#     $2 — Optional spec path for WARN to .progress.md (empty = skip WARN)
#
#   Outputs (stdout): RISK:UNKNOWN|REASON:<reason>
#   Returns: 0 always.
#
#   Contract: Only this function may produce RISK:UNKNOWN.  No code path
#   outside this function sets UNKNOWN, ensuring fail-safe behaviour.
emit_unknown() {
  local reason="${1:-indeterminate state}"
  local spec_path="${2:-}"

  printf 'RISK:UNKNOWN|REASON:%s' "$reason"

  # Optional: WARN to .progress.md (only when we have a spec dir)
  if [[ -n "$spec_path" && -f "${spec_path}/.progress.md" ]]; then
    {
      echo ""
      echo "## $(date -u +%Y-%m-%d)"
      echo "- WARN: indeterminate — $reason"
    } >> "${spec_path}/.progress.md"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# SECTION: Layer Functions
# ═══════════════════════════════════════════════════════════════════

# layer1_role_contract — Role-contract Access Matrix parser
#
#   Inputs:
#     $1 — Agent name (e.g. "spec-executor")
#     $2 — Comma-separated list of intended write paths
#
#   Outputs (stdout): RISK:<severity>|REASON:<reason>
#   Return: 0 always (caller inspects RISK value)
#
#   Risk values:
#     clear   — all paths within agent's Writes, none in Denylist
#     violation — Denylist match or Writes miss (maps to HIGH in combiner)
#     UNKNOWN — role-contracts.md missing, agent not found, or no paths given
#
#   Contract: Never outputs "block" directly. The combiner maps
#   "violation" → "block". Never outputs anything other than
#   RISK:<clear|violation|UNKNOWN>|REASON:<string>.
layer1_role_contract() {
  local role="$1"
  local paths="$2"

  # 1. Resolve role-contracts.md
  local rc_path
  rc_path=$(resolve_role_contracts_path)

  # 2. Existence check
  if [[ ! -f "$rc_path" ]]; then
    emit_unknown "role-contracts.md not found at $rc_path" "$SPEC_PATH"
    return 0
  fi

  # 3. Extract Access Matrix table via awk
  local matrix
  matrix=$(awk '
    /^## Access Matrix/ { capture=1; print; next }
    capture && /^## / { exit }
    capture { print }
  ' "$rc_path")

  if [[ -z "$matrix" ]]; then
    emit_unknown "Access Matrix section not found in role-contracts.md" "$SPEC_PATH"
    return 0
  fi

  # Enable extglob for glob matching
  shopt -s extglob

  # 4. Look up the agent row
  local agent_col="" writes_col="" denylist_col=""
  local found=0

  while IFS= read -r row; do
    [[ "$row" =~ ^\|?--- ]] && continue
    [[ "$row" =~ ^##\ Access\ Matrix ]] && continue

    local cols=()
    local tmp="$row"
    while [[ -n "$tmp" ]]; do
      local part="${tmp%%|*}"
      cols+=("$part")
      tmp="${tmp#*|}"
    done

    [[ ${#cols[@]} -lt 4 ]] && continue

    local c_role c_writes c_deny
    c_role=$(echo "${cols[1]}" | xargs)
    c_writes=$(echo "${cols[3]}" | xargs)
    c_deny=$(echo "${cols[4]}" | xargs)

    # Substring match for agent names
    if [[ "${c_role,,}" == *"${role,,}"* ]]; then
      agent_col="$c_role"
      writes_col="$c_writes"
      denylist_col="$c_deny"
      found=1
      break
    fi
  done <<< "$matrix"

  if (( ! found )); then
    emit_unknown "agent $role not found in Access Matrix" "$SPEC_PATH"
    return 0
  fi

  # --paths absent → UNKNOWN
  if [[ -z "$paths" || "$paths" =~ ^[[:space:]]*$ ]]; then
    emit_unknown "no paths provided" "$SPEC_PATH"
    return 0
  fi

  local worst_risk="clear"
  local reasons=()

  IFS=',' read -ra path_arr <<< "$paths"

  for p in "${path_arr[@]}"; do
    p=$(echo "$p" | xargs)
    [[ -z "$p" ]] && continue

    # --- Check denylist first ---
    local denylist_norm="${denylist_col//\`/}"
    if [[ "${denylist_norm,,}" != *"na"* && "${denylist_norm,,}" != *"none"* && "${denylist_norm,,}" != *"(read-only)"* ]]; then
      IFS=',' read -ra deny_arr <<< "$denylist_norm"
      for d in "${deny_arr[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -z "$d" ]] && continue
        local deny_base="${d%% (*}"
        deny_base=$(echo "$deny_base" | xargs)
        if [[ -z "$deny_base" || "$deny_base" == "n/a" || "$deny_base" == "none" ]]; then
          continue
        fi
        local exception="${d##* (}"
        exception="${exception%%)}"
        if [[ -n "$exception" && "$exception" != "$d" ]]; then
          continue
        fi
        if [[ "$p" == $deny_base ]]; then
          worst_risk="violation"
          reasons+=("path $p is in denylist for $agent_col")
          break
        fi
      done
    fi

    # --- Check writes permission ---
    local writes_norm="${writes_col//\`/}"
    if [[ "$writes_norm" == *"(read-only)"* || "$writes_norm" == *"_\(read-only\)*" ]]; then
      if [[ -n "$p" ]]; then
        if [[ "$worst_risk" != "violation" ]]; then
          worst_risk="violation"
        fi
        reasons+=("agent $agent_col is read-only")
      fi
    elif [[ "${writes_norm}" != *"All"* && -n "$writes_col" ]]; then
      local writes_for_split="${writes_col//\`/}"
      IFS=',' read -ra write_arr <<< "$writes_for_split"
      local in_writes=0
      for w in "${write_arr[@]}"; do
        w=$(echo "$w" | xargs)
        local w_base="${w%% (*}"
        w_base=$(echo "$w_base" | xargs)
        if [[ -z "$w_base" || "$w_base" == "n/a" ]]; then
          continue
        fi
        if [[ "$p" == $w_base ]]; then
          in_writes=1
          break
        fi
      done

      if (( ! in_writes )); then
        worst_risk="violation"
        reasons+=("path $p not in writes for $agent_col")
      fi
    fi
  done

  # Output result
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

# layer2_shell_pattern — Dangerous shell pattern detection
#
#   Inputs:
#     $1 — Shell command to inspect (from task's Verify field)
#
#   Outputs (stdout): RISK:<severity>|REASON:<reason>
#   Return: 0 always (caller inspects RISK value)
#
#   Risk values:
#     HIGH — dangerous pattern detected (rm -rf, sudo, chmod 777,
#            curl/wget piped to sh/bash, eval)
#     LOW  — no dangerous pattern or command absent
#
#   Contract: Never outputs "block". Only outputs RISK:HIGH|REASON:...
#   or RISK:LOW|REASON:none.
layer2_shell_pattern() {
  local cmd="${1:-}"

  if [[ -z "$cmd" || "$cmd" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:LOW|REASON:none'
    return 0
  fi

  # Pattern 4 (curl/wget pipe) requires both the keyword combo AND
  # a literal pipe character — bash ERE doesn't match |, so we
  # check separately.
  local has_pipe=0
  [[ "$cmd" == *"|"* ]] && has_pipe=1

  for pattern in "${SHELL_PATTERNS[@]}"; do
    # Fetch-pipe needs extra pipe check
    if [[ "$pattern" == *"curl"* ]] && (( ! has_pipe )); then
      continue
    fi
    if [[ "$cmd" =~ $pattern ]]; then
      local pattern_name=""
      case "$pattern" in
        *"rm"*)       pattern_name="rm -rf" ;;
        *"sudo"*)     pattern_name="sudo" ;;
        *"chmod"*)    pattern_name="chmod 777" ;;
        *curl*|*wget*) pattern_name="fetch-pipe-shell" ;;
        *"eval"*)     pattern_name="eval" ;;
      esac
      printf 'RISK:HIGH|REASON:shell pattern %s found' "$pattern_name"
      return 0
    fi
  done

  printf 'RISK:LOW|REASON:none'
  return 0
}

# layer3_risk — Baseline risk classifier
#
#   Inputs: (reads global PATHS and COMMAND variables)
#
#   Outputs (stdout): RISK:<severity>|REASON:<reason>
#   Return: 0 always
#
#   Risk values:
#     UNKNOWN — no --paths provided (cannot classify task)
#     LOW     — --paths present, no command (read-only file task)
#     MEDIUM  — --paths present with command (file modification + execution)
#
#   Contract: Does NOT re-derive Layer 1 or Layer 2 outcomes.
#   Only examines task structure (paths + command presence).
layer3_risk() {
  if [[ -z "${PATHS:-}" || "$PATHS" =~ ^[[:space:]]*$ ]]; then
    emit_unknown "no paths provided" "$SPEC_PATH"
    return 0
  fi

  if [[ -z "${COMMAND:-}" || "$COMMAND" =~ ^[[:space:]]*$ ]]; then
    printf 'RISK:LOW|REASON:read-only task'
    return 0
  fi

  printf 'RISK:MEDIUM|REASON:task modifies files'
  return 0
}

# ═══════════════════════════════════════════════════════════════════
# SECTION: Combiner + Policy
# ═══════════════════════════════════════════════════════════════════

# combine_risk — Max-severity risk combiner with Layer 1 short-circuit
#
#   Inputs:
#     $1 — Layer 1 verdict (RISK:<clear|violation|UNKNOWN>|REASON:...)
#     $2 — Layer 2 verdict (RISK:<HIGH|LOW>|REASON:...)
#     $3 — Layer 3 verdict (RISK:<UNKNOWN|LOW|MEDIUM>|REASON:...)
#
#   Outputs (stdout): VERDICT:<v>|LAYER:<l>|DRIVING_LAYER:<dl>|RISK:<r>
#   Return: 2 for Layer 1 violation (caller ignores return value), 0 otherwise
#
#   Verdict values:
#     block    — Layer 1 violation (hard-block, short-circuits)
#     confirm  — HIGH or UNKNOWN combined risk
#     allow    — LOW or MEDIUM combined risk
#
#   Contract: Layer 1 "violation" short-circuits to block with exit 2.
#   Otherwise combines all layers via max_risk. Returns 0 on allow/confirm.
combine_risk() {
  local l1_verdict="${1:-}"
  local l2_verdict="${2:-}"
  local l3_verdict="${3:-}"

  # Extract risk value from each layer verdict
  local l1_risk="${l1_verdict#RISK:}"
  l1_risk="${l1_risk%%|*}"
  local l2_risk="${l2_verdict#RISK:}"
  l2_risk="${l2_risk%%|*}"
  local l3_risk="${l3_verdict#RISK:}"
  l3_risk="${l3_risk%%|*}"

  l2_risk="${l2_risk:-LOW}"
  l3_risk="${l3_risk:-LOW}"

  # Short-circuit: Layer 1 violation → hard-block
  if [[ "$l1_risk" == "violation" ]]; then
    printf 'VERDICT:block|LAYER:role-contract|DRIVING_LAYER:role-contract|RISK:HIGH'
    return 2
  fi

  # Map layer-internal "clear" to LOW for ranking
  [[ "$l1_risk" == "clear" ]] && l1_risk="LOW"
  local best_risk="${l1_risk:-LOW}"
  local best_layer="role-contract"

  if (( $(rank "$best_risk") < $(rank "$l2_risk") )); then
    best_risk="$l2_risk"
    best_layer="shell-pattern"
  fi

  if (( $(rank "$best_risk") < $(rank "$l3_risk") )); then
    best_risk="$l3_risk"
    best_layer="task-baseline"
  fi

  local verdict driving_layer
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

# confirm_risky — ConfirmRisky policy: map combined risk to final verdict
#
#   Inputs:
#     $1 — Combined risk string (block, HIGH, UNKNOWN, LOW, MEDIUM)
#     $2 — Driving layer (role-contract, shell-pattern, none)
#     $3 — Human-readable reason (optional)
#
#   Outputs:
#     stderr: decision:reason (layer=l, risk=r)
#     stdout: "decision=d\nlayer=l\nrisk=r"
#   Return: 0 always (main flow sets exit code)
#
#   Decision mapping:
#     block -> decision=block, exit 2 (hard-block, bypasses ConfirmRisky)
#     HIGH/UNKNOWN -> decision=confirm, exit 2 (pause for human review)
#     LOW/MEDIUM -> decision=allow, exit 0 (proceed)
#
#   Contract: Does NOT call exit. Main flow handles exit codes.
#   Always outputs structured verdict to stdout and reason to stderr.
confirm_risky() {
  local risk="${1:-LOW}"
  local layer="${2:-none}"
  local reason="${3:-}"

  local decision
  case "$risk" in
    block)
      decision="block"
      ;;
    HIGH|UNKNOWN)
      decision="confirm"
      ;;
    LOW|MEDIUM|*)
      decision="allow"
      ;;
  esac

  printf '%s: %s (layer=%s, risk=%s)\n' \
    "$decision" "${reason:-no reason}" "$layer" "$risk" >&2

  printf 'decision=%s\nlayer=%s\nrisk=%s\n' \
    "$decision" "$layer" "$risk"
}

# ═══════════════════════════════════════════════════════════════════
# SECTION: Main flow
# ═══════════════════════════════════════════════════════════════════

# Source signal helpers early (needed by both block and non-block paths)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-signals.sh"

# Run all three layers
L1_OUTPUT=$(layer1_role_contract "$AGENT" "$PATHS") || true
L2_OUTPUT=$(layer2_shell_pattern "${COMMAND:-}") || true
L3_OUTPUT=$(layer3_risk) || true

# Combine risks using max-severity policy
COMBINED=$(combine_risk "$L1_OUTPUT" "$L2_OUTPUT" "$L3_OUTPUT") || true

# Extract verdict, risk, layer from combined output
COMBINED_VERDICT="${COMBINED%%|*}"
COMBINED_VERDICT="${COMBINED_VERDICT#VERDICT:}"
COMBINED_RISK="${COMBINED##*RISK:}"
COMBINED_LAYER="${COMBINED##*LAYER:}"
COMBINED_LAYER="${COMBINED_LAYER%%|*}"

# Resolve iteration from .ralph-state.json globalIteration, default 1
iteration=1
if [[ -f "${SPEC_PATH}/.ralph-state.json" ]]; then
  _iter=$(jq -r '.globalIteration // 1' "${SPEC_PATH}/.ralph-state.json" 2>/dev/null) || true
  [[ -n "${_iter:-}" && "${_iter}" != "null" ]] && iteration=$_iter
fi

# ── Layer 1 block bypass — hard-stop ──────────────────────────────
if [[ "$COMBINED_VERDICT" == "block" ]]; then
  printf 'block: role-contract violation (layer=%s, risk=%s)\n' \
    "$COMBINED_LAYER" "$COMBINED_RISK" >&2
  printf 'decision=block layer=%s risk=%s\n' \
    "$COMBINED_LAYER" "$COMBINED_RISK"

  decision="${COMBINED_VERDICT:-block}"
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
      echo "- WARN: security-decision append_signal failed for block - audit trail incomplete"
    } >> "${SPEC_PATH}/.progress.md"
    exit 3
  fi

  exit 2
fi

# ── Emit security-decision event ──────────────────────────────────
CR_OUTPUT=$(confirm_risky "$COMBINED_RISK" "$COMBINED_LAYER" "") || true

decision_line=$(echo "$CR_OUTPUT" | grep '^decision=')
decision=""
if [[ -n "$decision_line" ]]; then
  decision=$(echo "$decision_line" | cut -d= -f2)
fi

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

printf 'decision=%s layer=%s risk=%s\n' "$decision" "$COMBINED_LAYER" "$COMBINED_RISK"

case "$decision" in
  allow) exit 0 ;;
  block|confirm) exit 2 ;;
  *) exit 2 ;;
esac
