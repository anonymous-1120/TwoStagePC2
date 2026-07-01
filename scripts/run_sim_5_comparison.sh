#!/bin/bash
# run_sim_5_comparison.sh — Step 5: Section 3.3, fixed p=100, both DGPs, fixed-ratio only
# Adaptive OLS/SCAD: Section 3.2 ols_pp. For a single cell (or a quick smoke test with
# small B/n), use run_sim_comparison_cell.sh or override TWOSTAGEPC_SIM_B / TWOSTAGEPC_SIM_NS.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_comparison"
twostagepc_log_header "estimator comparison"
twostagepc_run_sim_comparison
log "=== COMPLETE (run_sim_5_comparison) ==="
