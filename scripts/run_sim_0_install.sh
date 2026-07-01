#!/bin/bash
# run_sim_0_install.sh — Step 0: install CRAN dependencies
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_install"
twostagepc_log_header "install_packages"
twostagepc_run_install
log "=== COMPLETE (run_sim_0_install) ==="
