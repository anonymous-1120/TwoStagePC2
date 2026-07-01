# R/ — simulation harness and tooling

| File | Contents |
|------|----------|
| `utils.R` | Sources `lib/`, shared simulation helpers (thread limits, seeds, CPU detection) |
| `sim_core.R` | Cluster setup, `sim_run_one()`, metric computation shared by all `simulations/sim_*.R` drivers |
| `sim_dgp_config.R` | DGP/section constants, paths, seeds — the single source of truth for `B`, `n`, `p`, section names |
| `sim_estimators.R` | Registry mapping estimator name (`ols`/`scad`/`rf`/`dnn`/`ensemble`) to `lib/estimators/` functions |
| `export_metrics.R` | Writes `*_summary.csv` / `*_split_ratio.csv` from a simulation's raw result matrix |
| `install_packages.R`, `install_keras.R` | One-time environment setup (run via `scripts/run_sim_0_install.sh`) |
| `summarize_all.R` | Aggregates all section summaries into `results/aggregated/all_simulations_summary.csv` |
| `generate_paper_tables.R` | Builds `results/tables/table_sim_*.tex` (mirrors `paper/tables/*.tex`) |
| `plot_sim_figures.R` | Builds `results/figures/*.pdf` |
| `render_figures.R` | Optional: renders `simulation_report.pdf` (rmarkdown) |

All three postprocessing scripts (`summarize_all.R`, `generate_paper_tables.R`,
`plot_sim_figures.R`) are run together via `scripts/run_sim_8_postprocess.sh`.
