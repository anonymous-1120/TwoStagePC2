# TwoStagePC — Reproduction Code

R code to reproduce the Monte Carlo simulations, the motivating example, and the Million Song real-data analysis for the manuscript on partial correlation estimation with goodness-of-fit adaptive splitting.

**Working directory:** clone this repository and run all commands from its root. All scripts are invoked from the repository root (working directory never changes), so every path below is root-relative regardless of which script or folder is doing the sourcing.

> **Runtime warning:** the full B=500 pipeline is long. GoF and adaptive P-P sections take hours; the growing-p (high-dimensional) estimator comparison with DNN can take **several days, up to about a week**, even on a multi-core server. There is no single "run everything" command — run each numbered section below, ideally in `tmux`/`screen`. See [§ Runtime expectations](#runtime-expectations) before launching a long section unattended.

## Data

| File | Description |
|------|-------------|
| `MillionSongSubset/realData_song.csv` | Post-processed covariates and outcomes used in the real-data example (committed in this repo). |
| Million Song Dataset (raw) | Publicly available at [millionsongdataset.com](http://millionsongdataset.com). Optional preprocessing: `MillionSongSubset/realData_pre.R` (requires Bioconductor `rhdf5`). |

## Environment setup

R ≥ 4.0 recommended.

### CRAN packages (required)

```bash
Rscript R/install_packages.R
```

Covers: `parallel`, `doSNOW`, `dplyr`, `MASS`, `ncvreg`, `randomForest`, `ggplot2`, `np` (kernel regression, motivating example only), …

**CRAN mirror:** `R/install_packages.R` sets `repos = "https://cloud.r-project.org"`. Interactive `install.packages("…")` without `repos=` fails on many servers with `trying to use CRAN without setting a mirror`; either use the project script or pass `repos=` explicitly.

### keras3 + Python TensorFlow (optional; needed for DNN and ensemble)

DNN and ensemble (NN leg) require **`keras3`** (R) with a Python TensorFlow backend via `reticulate`. Do **not** install the legacy CRAN package `keras`.

```bash
# Step A — reticulate (R <-> Python bridge)
# On Anaconda R, prefer conda (CRAN source build of reticulate often fails):
conda install -y -c conda-forge r-reticulate

# Step B — keras3 R package + Python backend (TensorFlow + Keras 3)
Rscript R/install_keras.R
```

Manual equivalent:

```bash
Rscript -e 'install.packages("keras3", repos = "https://cloud.r-project.org")'
Rscript -e 'library(keras3); install_keras(backend = "tensorflow")'
```

Verify before running DNN jobs:

```bash
Rscript -e 'library(keras3); cat("backend:", backend(), "\n")'
```

If keras3 is unavailable, skip DNN and ensemble: `bash scripts/run_sim_<N>_*.sh --no-dnn`.

### Parallelism and CPU limits

Simulation drivers use `parallel::makeCluster()` with `foreach` (`R/sim_core.R`). To avoid oversubscription (many R workers × multi-threaded BLAS / TensorFlow → apparent freeze), `scripts/run_common.sh` pins `OMP_NUM_THREADS=1`, `OPENBLAS_NUM_THREADS=1`, `MKL_NUM_THREADS=1`, `TF_NUM_INTRAOP_THREADS=1`, `TF_NUM_INTEROP_THREADS=1`, and caps the R worker count to the CPUs available on the machine (`nproc`).

- `--ncores` defaults to **auto** (all CPUs on the machine); pass an explicit value to use fewer.
- For DNN jobs, prefer fewer workers if you still see high load (e.g. `--ncores 8`) even with thread limits.

### Gotchas

- Never use variable name `nm` (conflicts with `nm()` in `lib/inference/inference.R`).
- Use **keras3**, not the legacy `keras` package (`R/install_keras.R`).
- If your machine happens to be a Slurm-allocated node, `scripts/run_common.sh` auto-detects `SLURM_CPUS_PER_TASK`/`SLURM_CPUS_ON_NODE` and caps parallel workers accordingly — no special submission script is needed; just run the same `bash scripts/run_sim_<N>_*.sh` commands as on any Linux server (e.g. inside `tmux`/`screen`, or your own `srun`/job script).

## Quick start (smoke test)

```bash
git clone https://github.com/anonymous-1120/TwoStagePC2.git
cd TwoStagePC2

Rscript R/install_packages.R
# Optional (DNN / ensemble): see § Environment setup above

# Quick smoke test: override B and n to a small size instead of the full B=500 grid
TWOSTAGEPC_SIM_B=10 TWOSTAGEPC_SIM_NS="500" bash scripts/run_sim_5_comparison.sh --no-dnn --ncores 4 --quiet
Rscript MillionSongSubset/realData_revised.R
```

## Full reproduction (B = 500, n ∈ {500, 1000, 2000, 5000})

```bash
tmux new -s twostagepc
bash scripts/run_sim_0_install.sh --ncores 64 --quiet       # CRAN packages, one-time setup
bash scripts/run_sim_1_motivating.sh --quiet               # Table 1 (Introduction)
bash scripts/run_sim_2_gof.sh --ncores 64 --quiet           # Section 3.1
bash scripts/run_sim_3_ols_pp.sh --ncores 64 --quiet        # Section 3.2 (OLS)
bash scripts/run_sim_4_ols_pp_scad.sh --ncores 64 --quiet   # Section 3.2 (SCAD)
bash scripts/run_sim_5_comparison.sh --ncores 64 --quiet    # Section 3.3, fixed p=100
bash scripts/run_sim_6_highdim.sh --ncores 64 --quiet       # Section 3.3 supplement, growing p; add --no-dnn if keras3 not installed
bash scripts/run_sim_7_realdata.sh --quiet                  # Section 4
bash scripts/run_sim_8_postprocess.sh --quiet               # tables, figures, verify
```

Monitor any running section with `cat results/DASHBOARD.txt` (progress table, refreshed as each section starts/finishes) or `tail -f results/logs/<section>/*.log`.

To re-run a single cell within Section 3.3 (e.g. after fixing one failed job) without redoing the whole section:

```bash
bash scripts/run_sim_comparison_cell.sh --setting growing_p15 --dgp nonlinear --learners dnn --dnn-ncores 8 --quiet
```

For a quick smoke test of any section rather than the full grid, override `TWOSTAGEPC_SIM_B` (replications) and/or `TWOSTAGEPC_SIM_NS` (sample sizes) — no separate smoke script is needed:

```bash
TWOSTAGEPC_SIM_B=10 TWOSTAGEPC_SIM_NS="500" bash scripts/run_sim_5_comparison.sh --no-dnn --ncores 4 --quiet
```

## Layout

The repository root only holds top-level docs/config; everything else is grouped by role:

```
├── simulations/           # simulation drivers, run via scripts/run_sim_<N>_*.sh:
│                          #   sim_gof.R, sim_ols_pp.R, sim_comparison.R, sim_highdim_pn.R,
│                          #   sim_motivating.R (Table 1)
├── MillionSongSubset/     # real-data analysis + input:
│                          #   realData_revised.R (driver), realData_pre.R (optional HDF5
│                          #   preprocessing), realData_song.csv (preprocessed input),
│                          #   real_data_report.R (LaTeX table + run-metadata helpers)
├── scripts/               # numbered entry points run_sim_0_install.sh .. run_sim_8_postprocess.sh,
│                          # run_common.sh (shared bash helpers: arg parsing, logging, dashboard,
│                          # parallelism -- sourced by every run_sim_*.sh, never run directly),
│                          # verify_outputs.sh, plus one optional/advanced script not part of
│                          # the main numbered sequence:
│                          #   run_sim_comparison_cell.sh (re-run a single comparison cell)
├── R/                     # simulation harness/tooling, not run directly except the two
│                          # install_*.R helpers -- see R/README.md for the full split from lib/
├── lib/                   # core method implementation (GoF test, estimators, inference, ccov)
│                          # -- see lib/README.md
└── results/               # simulation output, not shipped -- reproduce by running the scripts
                            # above; nothing under it is committed. See results/README.md.
```

Two simulation DGPs: **sparse linear** and **sparse nonlinear**. True partial correlation: **ρ = √(3/7)**.

## Paper section ↔ script ↔ output mapping

| Paper item | Script | Output |
|--------|---------|--------|
| Table 1 (Introduction, motivating example) | `scripts/run_sim_1_motivating.sh` | `results/motivating/`, `results/tables/table_motivating.tex` |
| §3.1 GoF size/power (Fig. `sim_gof_size_power`, Table S1) | `scripts/run_sim_2_gof.sh` | `results/gof/`, `results/tables/table_sim_gof.tex` |
| §3.2 Adaptive P–P (Table `sim_pp`) | `scripts/run_sim_3_ols_pp.sh`, `scripts/run_sim_4_ols_pp_scad.sh` | `results/ols_pp/<dgp>/`, `results/tables/table_sim_pp*.tex` |
| §3.3 Estimator comparison, fixed p=100 (Tables S `sim_B`/`sim_C`) | `scripts/run_sim_5_comparison.sh` | `results/comparison/fixed_p/<dgp>/`, `results/tables/table_sim_B.tex`, `table_sim_C.tex` |
| §3.3 Estimator comparison, growing p (Tables `sim_highdim_*_p15`, S `sim_highdim_*_p09`) | `scripts/run_sim_6_highdim.sh` | `results/comparison/growing_p/<dgp>/`, `results/tables/table_sim_highdim_*.tex` |
| §4 Real data (Table `realData`) | `scripts/run_sim_7_realdata.sh` | `results/realdata/`, `results/tables/table_real_data.tex` |
| Aggregated CSV | `scripts/run_sim_8_postprocess.sh` (→ `R/summarize_all.R`) | `results/aggregated/all_simulations_summary.csv` |

Figures, produced by `scripts/run_sim_8_postprocess.sh` (→ `R/plot_sim_figures.R`):

| Figure | Used in | Section |
|--------|---------|---------|
| `results/figures/gof_size_power.pdf` | `main.tex` | §3.1 |
| `results/figures/ols_pp_sparse_linear.pdf` | `main.tex` | §3.2 |
| `results/figures/split_ratio_distribution.pdf` | `main.tex` | §3.2 |
| `results/figures/coverage_cilength_linear.pdf` | `supplement.tex` | §3.3 (Supplement) |
| `results/figures/ols_pp_nonlinear.pdf` | *(not referenced by the manuscript)* | — extra diagnostic from the same run, harmless to ignore |

Both `results/tables/*.tex` and `results/figures/*.pdf` are **git-ignored** (`.gitignore`) and regenerated by `R/generate_paper_tables.R`/`simulations/sim_motivating.R` and `R/plot_sim_figures.R` respectively — nothing under `results/` is shipped in this repository.

## Expected outputs

| Path | Section |
|------|---------|
| `results/motivating/` | Motivating example (Table 1) |
| `results/gof/` | GoF calibration (both DGPs) |
| `results/ols_pp/<dgp>/` | OLS + SCAD adaptive P-P |
| `results/comparison/fixed_p/<dgp>/` | p=100 estimator comparison |
| `results/comparison/growing_p/<dgp>/` | p≈0.9n and p≈1.5n regimes |
| `results/realdata/` | Million Song analysis |
| `results/aggregated/` | `all_simulations_summary.csv` |
| `results/tables/` | LaTeX table fragments (mirror `paper/tables/`) |
| `results/logs/<section>/` | Per-section run logs + status |
| `results/DASHBOARD.txt` | Pipeline progress dashboard |

Adaptive runs write `*_split_ratio.csv` (selected $n_1/n_2$ distribution over $B=500$).

### Figures and tables (after postprocess)

```bash
Rscript R/plot_sim_figures.R          # -> results/figures/*.pdf
Rscript R/generate_paper_tables.R     # -> results/tables/*.tex
Rscript R/render_figures.R            # optional: simulation_report.pdf (rmarkdown)
```

Spreadsheet exports belong in `results/exports/`.

## How to summarize

```bash
Rscript R/summarize_all.R            # -> results/aggregated/all_simulations_summary.csv
bash scripts/run_sim_8_postprocess.sh --quiet
bash scripts/verify_outputs.sh       # exit 0 if checked files present
```

Inspect CSV columns:

- `bias`, `sd_rho`, `mse` — **estimator** performance (not test-statistic SD)
- `ci_coverage`, `ci_length` — interval validity vs efficiency trade-off
- `gof_pass_rate` — fraction passing GoF (adaptive only)
- `avg_n1_over_n` — mean selected training fraction n₁/n
- `avg_K`, `avg_K0` — K-fold Cauchy parameters

GoF calibration (`results/gof/sim_gof_calibration_B500.csv`; $n_2=\lceil 2\sqrt{n_1}\rceil$, seeds 1352–1851):

- `sparse_linear_scad_type1` → rejection rate ≈ **0.05** (overall 5.5%)
- `sparse_linear_ols_type1` → mild inflation ≈ **0.07–0.12** (overall 9.1%; motivates Comment 7 response)
- `nonlinear_*_power` → rejection rate increases with $n$ (power)

## Validation checklist

After runs complete, check:

1. **Motivating example** (`results/motivating/motivating_summary.csv`): OLS has the smallest |bias| and SD among the four learners (see the "Introduction-claim check" printed at the end of `simulations/sim_motivating.R`'s log).
2. **Type I error** (`results/gof/sim_gof_calibration_B500.csv`): `*_type1` designs, `rejection_rate` near 0.05.
3. **Power** (`results/gof/sim_gof_calibration_B500.csv`): `*_power` designs, `rejection_rate` increases with n.
4. **Sparse linear DGP** (`model == "sparse_linear"` in comparison summaries): adaptive SCAD/RF/DNN have high `gof_pass_rate`; `mse` competitive with fixed.
5. **Nonlinear DGP** (`model == "nonlinear"`): adaptive SCAD `gof_pass_rate` ≈ 0; adaptive DNN/RF have valid `ci_coverage`.
6. **High-dimensional** (`results/comparison/growing_p/<dgp>/*_summary.csv`): compare `p09` vs `p15` regimes, adaptive vs fixed.
7. **Ensemble** (`results/comparison/<fixed_p|growing_p>/<dgp>/*ensemble*_summary.csv`): fixed-ratio SCAD+RF+NN vs adaptive learners.
8. **Real data** (`results/realdata/real_data_results.csv`): SCAD and RF adaptive report `gof_pvalue`, `n1_over_n2`, `K`, `K0`; compare RF adaptive vs RF fixed `estimate` and CI.

## Runtime expectations

Rough wall-clock time on a ~64-core Linux server:

| Script | ~time |
|-----|-------|
| `scripts/run_sim_1_motivating.sh` | a few minutes without DNN; ~30–60 min with DNN |
| `scripts/run_sim_2_gof.sh` | 1–2 hours |
| `scripts/run_sim_3_ols_pp.sh` (+ `run_sim_4_ols_pp_scad.sh`) | 2–4 hours each |
| `scripts/run_sim_5_comparison.sh` | several hours (see per-cell rows below) |
| `scripts/run_sim_6_highdim.sh` | **several days, up to about a week**, mainly driven by the DNN cells at the largest n and p ≈ 1.5n |
| Each fixed-p comparison SCAD/RF cell | 30–90 min |
| Each fixed-p comparison DNN cell | 2–8 hours |
| `scripts/run_sim_7_realdata.sh` | 10–60 min |

Use `tmux` or `screen` for any run longer than your terminal session; do not kill the session while a section is in progress. Reduce scope with `--no-dnn` (skips DNN/ensemble) or by running one `--setting`/`--dgp` cell at a time via `scripts/run_sim_comparison_cell.sh` if you only need to spot-check the logic rather than reproduce every cell.

## Artifacts to check or archive

If you reproduce on a shared/remote machine and want to copy results back to your own computer:

```
results/motivating/*
results/**/*_B500.Rdata
results/**/*_summary.csv
results/gof/sim_gof_calibration_B500.csv
results/aggregated/all_simulations_summary.csv
results/realdata/real_data_results.csv
results/tables/*.tex
results/figures/*.pdf
results/logs/**/*
results/DASHBOARD.txt
```

All of `results/` (CSV, JSON, `.Rdata`, tables, figures) is gitignored and regenerated on demand.
