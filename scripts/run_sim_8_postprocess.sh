#!/bin/bash
# run_sim_8_postprocess.sh — Step 8: summarize, paper tables, figures, verify
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_postprocess"
twostagepc_log_header "post-process"
twostagepc_run_postprocess
log "=== COMPLETE (run_sim_8_postprocess) ==="
