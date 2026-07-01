#!/bin/bash
# run_sim_comparison_cell.sh — One comparison cell (setting × DGP × learner group)
#
# Settings (3):
#   fixed_p       — p = 100
#   growing_p09   — p = floor(0.9 n)
#   growing_p15   — p = floor(1.5 n); OLS omitted (p > n)
#
# DGPs (2): sparse_linear | nonlinear
#
# Learner groups (split for CPU / OOM):
#   classic — fixed_p: OLS/SCAD/RF fixed + RF adaptive; growing: adaptive + fixed
#   dnn     — fixed_p: DNN fixed + adaptive + ensemble fixed; growing: adaptive + fixed + ensemble
#   all     — classic then dnn
# Fixed_p adaptive OLS/SCAD: Section 3.2 ols_pp (not re-run in fixed_p cells).
#
# Usage:
#   bash scripts/run_sim_comparison_cell.sh --setting fixed_p --dgp sparse_linear --learners classic --ncores 64 --quiet
#   bash scripts/run_sim_comparison_cell.sh --setting growing_p09 --dgp nonlinear --learners classic --heavy-ncores 8 --quiet
#   bash scripts/run_sim_comparison_cell.sh --setting growing_p09 --dgp nonlinear --learners dnn --dnn-ncores 8 --quiet
#   bash scripts/run_sim_comparison_cell.sh --setting growing_p15 --dgp sparse_linear --learners all --ncores 64 --dnn-ncores 8
#
# Per-cell wrappers: run_sim_comparison_<setting>_<dgp>.sh (classic)
#                    run_sim_comparison_<setting>_<dgp>_dnn.sh (dnn)

set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh

SETTING=""
DGP=""
LEARNERS="classic"
FILTERED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --setting)
      if [[ $# -lt 2 ]]; then echo "Usage: --setting fixed_p|growing_p09|growing_p15"; exit 1; fi
      SETTING="$2"
      shift 2
      ;;
    --dgp)
      if [[ $# -lt 2 ]]; then echo "Usage: --dgp sparse_linear|nonlinear"; exit 1; fi
      DGP="$2"
      shift 2
      ;;
    --learners)
      if [[ $# -lt 2 ]]; then echo "Usage: --learners classic|dnn|all"; exit 1; fi
      LEARNERS="$2"
      shift 2
      ;;
    *) FILTERED+=("$1"); shift ;;
  esac
done

if [[ -z "$SETTING" || -z "$DGP" ]]; then
  echo "Usage: bash scripts/run_sim_comparison_cell.sh --setting <fixed_p|growing_p09|growing_p15> --dgp <sparse_linear|nonlinear> [--learners classic|dnn|all] [--ncores N] [--dnn-ncores N] [--quiet]"
  exit 1
fi

twostagepc_parse_args "${FILTERED[@]}"
SETTING="$(twostagepc_normalize_comparison_setting "$SETTING")"

twostagepc_init_logging "comparison_${SETTING}_${DGP}_${LEARNERS}"
twostagepc_log_header "comparison | ${SETTING} | ${DGP} | ${LEARNERS}"
twostagepc_run_comparison_cell "$SETTING" "$DGP" "$LEARNERS"
log "=== COMPLETE (comparison ${SETTING} ${DGP} ${LEARNERS}) ==="
