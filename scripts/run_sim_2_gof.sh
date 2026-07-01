#!/bin/bash
# run_sim_2_gof.sh — Step 2: Section 3.1, GoF size / power (both DGPs)
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_gof"
twostagepc_log_header "GoF calibration"
twostagepc_run_sim_gof
log "=== COMPLETE (run_sim_2_gof) ==="
