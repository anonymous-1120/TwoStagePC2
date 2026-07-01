#!/bin/bash
# run_sim_6_highdim.sh — Step 6: Section 3.3 supplement, estimator comparison, growing p
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_highdim"
twostagepc_log_header "high-dim p~n"
twostagepc_run_sim_highdim_pn
log "=== COMPLETE (run_sim_6_highdim) ==="
