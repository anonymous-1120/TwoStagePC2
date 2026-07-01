#!/bin/bash
# run_sim_7_realdata.sh — Step 7: Million Song real-data analysis (Section 4)
#
# Writes:
#   results/realdata/real_data_results_seed<S>.csv  (S = REALDATA_SEED_BASE or TWOSTAGEPC_REALDATA_SEED)
#   results/realdata/real_data_results.csv          (alias)
#   results/realdata/real_data_run_meta_seed<S>.json
#   paper/tables/table_real_data.tex
#
# Usage:
#   bash scripts/run_sim_7_realdata.sh              # adaptive OLS/SCAD/DNN/RF + fixed 50/50 + ensemble
#   bash scripts/run_sim_7_realdata.sh --no-dnn     # skip DNN + ensemble (no keras3 / TensorFlow)
#   TWOSTAGEPC_REALDATA_SEED=3200 bash scripts/run_sim_7_realdata.sh --quiet
#
# DNN requires: Rscript R/install_keras.R
# Expected runtime: ~10--60 min (DNN slower). Re-run postprocess to refresh sim tables:
#   bash scripts/run_sim_8_postprocess.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh
twostagepc_parse_args "$@"
twostagepc_init_logging "sim_realdata"
twostagepc_log_header "real data"
twostagepc_run_realdata
log "=== COMPLETE (run_sim_7_realdata) ==="
