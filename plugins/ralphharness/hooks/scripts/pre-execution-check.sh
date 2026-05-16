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

# ── Placeholder ──────────────────────────────────────────────────
exit 0
