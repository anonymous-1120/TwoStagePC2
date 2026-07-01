#!/bin/bash
# verify_outputs.sh -- Check simulation artifacts (reproduction repository)
set -euo pipefail
cd "$(dirname "$0")/.."
R="results"
missing=0
check() {
  if [[ -f "$1" ]]; then
    echo "  OK  $1"
  else
    echo "  MISS $1"
    missing=$((missing + 1))
  fi
}

echo "=== Motivating example (Table 1, optional until run) ==="
check "$R/motivating/motivating_summary.csv"
check "$R/tables/table_motivating.tex"

echo ""
echo "=== Section 1: GoF ==="
check "$R/gof/sim_gof_calibration_B500.csv"
check "$R/gof/sim_gof_all_B500_pvalues.csv"
check "$R/figures/gof_size_power.pdf"

echo ""
echo "=== Section 3.2: OLS/SCAD adaptive P-P ==="
check "$R/ols_pp/sparse_linear/sim_ols_pp_B500_summary.csv"
check "$R/ols_pp/nonlinear/sim_ols_pp_B500_summary.csv"
check "$R/figures/ols_pp_sparse_linear.pdf"

echo ""
echo "=== Section 3.3: Estimator comparison — fixed p (optional until run) ==="
check "$R/comparison/fixed_p/sparse_linear/sim_sparse_linear_scad_fixed_B500.Rdata"
check "$R/ols_pp/sparse_linear/sim_scad_pp_B500_summary.csv"

echo ""
echo "=== Section 3.3 (Supplement): Estimator comparison — growing p (optional until run) ==="
check "$R/comparison/growing_p/sparse_linear/sim_p09_scad_adaptive_sparse_linear_B500.Rdata"
check "$R/comparison/growing_p/sparse_linear/sim_p15_scad_adaptive_sparse_linear_B500.Rdata"

echo ""
echo "=== Real data (optional until run) ==="
check "$R/realdata/real_data_results.csv"

echo ""
echo "=== Aggregated (optional until postprocess) ==="
check "$R/aggregated/all_simulations_summary.csv"

echo ""
echo "=== Paper LaTeX tables (optional until postprocess; mirrors paper/tables/) ==="
check "$R/tables/table_sim_gof.tex"
check "$R/tables/table_sim_pp.tex"
check "$R/tables/table_sim_B.tex"
check "$R/tables/table_sim_C.tex"
check "$R/tables/table_real_data.tex"

echo ""
if [[ "$missing" -eq 0 ]]; then
  echo "All checked files present."
  exit 0
else
  echo "$missing file(s) missing (expected if later sections not run yet)."
  exit 1
fi
