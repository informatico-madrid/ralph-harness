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

# ── Placeholder ──────────────────────────────────────────────────
exit 0
