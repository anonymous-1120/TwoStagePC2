#!/bin/bash
# run_sim_1_motivating.sh -- Step 1: reproduce Table 1 (tab:motivatingExample),
# the toy illustration in the Introduction (Section 1).
#
# Writes:
#   results/motivating/motivating_results.csv            (per-replication rho-hats)
#   results/motivating/motivating_summary.csv            (Bias / SD / MSE, x10)
#   results/tables/table_motivating.tex                  (mirrors paper/tables/table_motivating.tex,
#                                                          \input by paper/main.tex in the manuscript repo)
#
# Usage (run from the repository root; DNN rows are slow -- prefer a server):
#   bash scripts/run_sim_1_motivating.sh                 # B=500, all four learners
#   bash scripts/run_sim_1_motivating.sh --no-dnn        # skip the neural-network row (no keras3)
#   bash scripts/run_sim_1_motivating.sh --b 100         # quick smoke run with B=100
#   bash scripts/run_sim_1_motivating.sh --b 500 --quiet
#
# Dependencies:
#   CRAN:   randomForest, np   (Rscript R/install_packages.R)
#   DNN:    keras3 + TensorFlow (Rscript R/install_keras.R); skip with --no-dnn
#
# Expected runtime: a few minutes without DNN; ~30-60 min with DNN (B=500).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./scripts/run_common.sh

B=500
SKIP_DNN=0
FILTERED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-dnn) SKIP_DNN=1; shift ;;
    --b)
      if [[ $# -lt 2 ]]; then echo "Usage: --b B"; exit 1; fi
      B="$2"; shift 2 ;;
    *) FILTERED+=("$1"); shift ;;
  esac
done
twostagepc_parse_args "${FILTERED[@]}"
export SKIP_DNN
export TWOSTAGEPC_SKIP_DNN="$SKIP_DNN"

twostagepc_configure_parallelism
if [[ "${SKIP_DNN}" -eq 0 ]]; then
  export DNN_NCORES="${MOTIVATING_NCORES:-32}"
  export TWOSTAGEPC_NCORES="${DNN_NCORES}"
fi
twostagepc_init_logging "sim_motivating"
twostagepc_log_header "motivating example (Table 1)"
log "B=${B} SKIP_DNN=${TWOSTAGEPC_SKIP_DNN}"

run_one "sim_motivating" simulations/sim_motivating.R "$B" "$TWOSTAGEPC_SKIP_DNN"

log "Table written to results/tables/table_motivating.tex"
log "Inspect the Introduction-claim check at the end of the run log."
log "=== COMPLETE (run_sim_1_motivating) ==="
