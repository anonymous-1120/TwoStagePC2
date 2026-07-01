#!/bin/bash
# run_sim_4_ols_pp_scad.sh — Step 4: Section 3.2 (SCAD only), parallel adaptive P-P experiment
#
# Writes separate files from the existing OLS run:
#   results/ols_pp/<dgp>/sim_scad_pp_B500.Rdata
#   results/ols_pp/<dgp>/sim_scad_pp_B500_summary.csv
#   results/ols_pp/<dgp>/sim_scad_pp_B500_split_ratio.csv
#
# Does NOT modify sim_ols_pp_B500.* (OLS outputs are left untouched).
#
# Usage:
#   bash scripts/run_sim_4_ols_pp_scad.sh --ncores 64 --quiet
#   bash scripts/run_sim_4_ols_pp_scad.sh --ncores 64 --foreground
#   bash scripts/run_sim_4_ols_pp_scad.sh --force --ncores 64   # overwrite existing SCAD outputs
#
# After completion, refresh figures (adds scad_pp_*.pdf; OLS PDFs unchanged):
#   Rscript R/plot_sim_figures.R
#
# Runtime: ~2–4 h with 64 cores (same order as the original OLS job).

set -euo pipefail
cd "$(dirname "$0")/.."

source ./scripts/run_common.sh

FORCE=0
FILTERED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    *) FILTERED+=("$1"); shift ;;
  esac
done

twostagepc_parse_args "${FILTERED[@]}"

SCAD_MARKERS=(
  "results/ols_pp/sparse_linear/sim_scad_pp_B${SIM_B}.Rdata"
  "results/ols_pp/nonlinear/sim_scad_pp_B${SIM_B}.Rdata"
)

if [[ "$FORCE" -eq 0 ]]; then
  for f in "${SCAD_MARKERS[@]}"; do
    if [[ -f "$f" ]]; then
      echo "Refusing to overwrite existing SCAD output: $f"
      echo "Remove it or re-run with --force"
      exit 1
    fi
  done
fi

twostagepc_init_logging "sim_ols_pp_scad"
twostagepc_log_header "Adaptive P-P (SCAD only, B=${SIM_B})"
log "SCAD outputs: sim_scad_pp_B${SIM_B}.* under results/ols_pp/<dgp>/"
log "OLS outputs unchanged: sim_ols_pp_B${SIM_B}.*"
twostagepc_run_sim_ols_pp_scad
log "=== COMPLETE (run_sim_4_ols_pp_scad) ==="
log "Next: Rscript R/plot_sim_figures.R"
