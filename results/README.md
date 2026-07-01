# Simulation outputs

All generated artifacts live under `results/` (section-first layout). This is the
**only** location the pipeline writes to — re-running any script never creates
files outside `results/`.



| Subdirectory | Contents | Produced by |
|--------------|----------|-------------|
| `motivating/` | Motivating example (Table 1, Introduction) | `scripts/run_sim_1_motivating.sh` |
| `gof/` | GoF calibration (both DGPs in one folder) | `scripts/run_sim_2_gof.sh` |
| `ols_pp/<dgp>/` | OLS + SCAD adaptive P-P (Section 3.2) | `scripts/run_sim_3_ols_pp.sh`, `run_sim_4_ols_pp_scad.sh` |
| `comparison/fixed_p/<dgp>/` | Estimator comparison at p=100 (Section 3.3) | `scripts/run_sim_5_comparison.sh` |
| `comparison/growing_p/<dgp>/` | p ≈ 0.9n and p ≈ 1.5n regimes (Section 3.3) | `scripts/run_sim_6_highdim.sh` |
| `realdata/` | Million Song analysis (Section 4) | `scripts/run_sim_7_realdata.sh` |
| `aggregated/` | `all_simulations_summary.csv` | `scripts/run_sim_8_postprocess.sh` |
| `logs/<section>/` | Per-section run logs | any `scripts/run_sim_<N>_*.sh` |
| `exports/` | XLSX spreadsheets (optional) | manual/ad hoc |

