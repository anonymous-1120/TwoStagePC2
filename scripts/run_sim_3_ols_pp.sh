#!/bin/bash
# run_sim_3_ols_pp.sh — Step 3: Section 3.2 (OLS only), adaptive P-P, both DGPs
# Outputs: results/ols_pp/<dgp>/sim_ols_pp_B500.*
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_ols_pp"
twostagepc_log_header "OLS + P-P"
twostagepc_run_sim_ols_pp
log "=== COMPLETE (run_sim_3_ols_pp) ==="
