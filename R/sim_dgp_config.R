# sim_dgp_config.R -- DGPs, simulation constants, and results paths.
# Source with working directory set to the repository root.

# --- Results layout: results/<section>/<dgp>/ (section-first) ---
# Override for isolated runs: TWOSTAGEPC_RESULTS_ROOT=results/sensitivity/foo
RESULTS_ROOT <- Sys.getenv("TWOSTAGEPC_RESULTS_ROOT", unset = "results")
RESULTS_REALDATA <- "realdata"
RESULTS_AGGREGATED <- "aggregated"
RESULTS_FIGURES <- "figures"
RESULTS_EXPORTS <- "exports"

ensure_results_dir <- function(subdir) {
  path <- file.path(RESULTS_ROOT, subdir)
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
  path
}

results_path <- function(subdir, filename) {
  file.path(ensure_results_dir(subdir), filename)
}

results_glob <- function(subdir, pattern) {
  Sys.glob(file.path(RESULTS_ROOT, subdir, pattern))
}

results_glob_dgp_section <- function(dgp, section, pattern) {
  Sys.glob(file.path(RESULTS_ROOT, section, dgp, pattern))
}

results_glob_section <- function(section, pattern) {
  Sys.glob(file.path(RESULTS_ROOT, section, "*", pattern))
}

results_glob_all_sections <- function(dgp, patterns) {
  unique(unlist(lapply(patterns, function(pat) {
    Sys.glob(file.path(RESULTS_ROOT, "*", dgp, pat))
  })))
}

results_path_sim <- function(dgp, section, filename) {
  file.path(ensure_results_dir(file.path(section, dgp)), filename)
}

#' GoF outputs live flat under results/gof/ (both DGPs in one place).
results_path_gof <- function(filename) {
  results_path(SECTION_GOF, filename)
}

results_glob_gof <- function(pattern) {
  results_glob(SECTION_GOF, pattern)
}

#' Canonical GoF calibration summary for paper table/figure (exactly one B, not seed-range variants).
gof_calibration_csv_path <- function(B = SIM_B) {
  results_path_gof(sprintf("sim_gof_calibration_B%d.csv", as.integer(B)))
}

load_gof_calibration_summary <- function(B = SIM_B) {
  path <- gof_calibration_csv_path(B)
  if (!file.exists(path)) return(NULL)
  read.csv(path, stringsAsFactors = FALSE)
}

results_figures_dir <- function() ensure_results_dir(RESULTS_FIGURES)

results_exports_dir <- function() ensure_results_dir(RESULTS_EXPORTS)

results_path_figure <- function(filename) {
  file.path(results_figures_dir(), filename)
}

paper_figures_dir <- function() {
  file.path("..", "paper", "figures")
}

paper_path_figure <- function(filename) {
  file.path(paper_figures_dir(), filename)
}

#' Save a ggplot to results/figures/ (and paper/figures/ when that tree exists).
save_figure_gg <- function(p, filename, width = 7, height = 4) {
  path_results <- results_path_figure(filename)
  ggsave(path_results, p, width = width, height = height)
  paper_root <- file.path("..", "paper")
  if (dir.exists(paper_root)) {
    paper_dir <- paper_figures_dir()
    if (!dir.exists(paper_dir)) dir.create(paper_dir, recursive = TRUE)
    path_paper <- paper_path_figure(filename)
    ggsave(path_paper, p, width = width, height = height)
    message("Wrote ", path_results, " and ", path_paper)
  } else {
    message("Wrote ", path_results)
  }
  invisible(path_results)
}

results_path_export <- function(filename) {
  file.path(results_exports_dir(), filename)
}

# --- DGPs and simulation defaults ---
DGP_SPARSE_LINEAR <- "sparse_linear"
DGP_NONLINEAR <- "nonlinear"
SIM_DGPS <- c(DGP_SPARSE_LINEAR, DGP_NONLINEAR)

SIM_B <- 500L
SIM_NS <- c(500L, 1000L, 2000L, 5000L)
#' Replications per progress log + partial checkpoint (override: TWOSTAGEPC_PROGRESS_CHUNK).
SIM_PROGRESS_CHUNK <- as.integer(Sys.getenv("TWOSTAGEPC_PROGRESS_CHUNK", unset = "25"))

#' DNN training epochs (override: TWOSTAGEPC_DNN_EPOCHS).
sim_dnn_epochs <- function() {
  as.integer(Sys.getenv("TWOSTAGEPC_DNN_EPOCHS", unset = "40"))
}

sim_dnn_nn_args <- function() {
  list(units = 64, validation_split = 0, activation = "sigmoid", epochs = sim_dnn_epochs())
}

SECTION_GOF <- "gof"
SECTION_OLS_PP <- "ols_pp"
# Unified estimator comparison: fixed p vs growing p under results/comparison/.
SECTION_COMPARISON_FIXED <- "comparison/fixed_p"
SECTION_COMPARISON_GROWING <- "comparison/growing_p"
# Legacy aliases (do not write new files here)
SECTION_HIGHDIM_PN <- SECTION_COMPARISON_GROWING
SECTION_COMPARISON <- SECTION_COMPARISON_FIXED

# Adaptive split search: n1/n from ADAPTIVE_RHO_MIN to ADAPTIVE_RHO_MAX by ADAPTIVE_RHO_STEP.
ADAPTIVE_RHO_MIN <- 0.5
ADAPTIVE_RHO_MAX <- 0.95
ADAPTIVE_RHO_STEP <- 0.05
ADAPTIVE_GOF_ALPHA <- 0.05

adaptive_rho_grid <- function() {
  seq(ADAPTIVE_RHO_MIN, ADAPTIVE_RHO_MAX, by = ADAPTIVE_RHO_STEP)
}

# GoF calibration (Section 1): n2 = ceil(GOF_N2_COEF * sqrt(n1)), n1+n2=n; single random split.
GOF_N2_RULE <- "n2_sqrt_n1"
GOF_N2_COEF <- 2
GOF_SPLIT_METHOD <- "random"
GOF_NSPLITS <- 1L
GOF_ALPHA <- 0.05
# Replication seeds: rep r in 1..B uses set.seed(GOF_SEED_START + r - 1); default 1352..1851 for B=500.
GOF_SEED_START <- 1352L

# Adaptive P-P module (Section 3.2): OLS and SCAD, both DGPs.
OLS_PP_ESTIMATORS <- c("ols", "scad")

# Adaptive sections (ols_pp, comparison, …): random train--test splits + Cauchy combine.
ADAPTIVE_SPLIT_METHOD <- "random"
ADAPTIVE_NSPLITS <- 3L
# Legacy K-fold cap (used only when ADAPTIVE_SPLIT_METHOD == "kfold").
ADAPTIVE_K0_MAX <- 3L
GOF_DESIGNS <- list(
  list(dgp = DGP_SPARSE_LINEAR, est = "ols",  kind = "type1",
       label = "sparse_linear_ols_type1"),
  list(dgp = DGP_SPARSE_LINEAR, est = "scad", kind = "type1",
       label = "sparse_linear_scad_type1"),
  list(dgp = DGP_NONLINEAR, est = "ols",  kind = "power",
       label = "nonlinear_ols_power"),
  list(dgp = DGP_NONLINEAR, est = "scad", kind = "power",
       label = "nonlinear_scad_power")
)

SIM_P_COMPARISON <- 100L
SIM_BETA_X <- 1
#' Scale on nonlinear terms in DGP_NONLINEAR (Z1^2, sin, cos, |Z4|); >1 strengthens GoF H1 signal.
SIM_NONLINEAR_COEF <- 1
SIM_RHO_TRUE <- sqrt(3 / 7)

# Shared learner grid for fixed-$p$ and growing-$p$ under results/comparison/{fixed_p,growing_p}/.
SIM_ESTIMATOR_LEARNERS <- c("ols", "scad", "rf", "dnn")
SIM_ENSEMBLE_METHOD <- "fixed"  # ensemble only under fixed-ratio DML

# Real data (Section 5): per-run base seed S (override TWOSTAGEPC_REALDATA_SEED).
# Adaptive: S+1..S+4 (OLS, SCAD, DNN, RF); fixed 50/50: S+41..S+45.
REALDATA_SEED_BASE <- 4200L
REALDATA_ADAPTIVE_OFFSETS <- c(ols = 1L, scad = 2L, dnn = 3L, rf = 4L)
REALDATA_FIXED_OFFSETS <- c(ols = 41L, scad = 42L, dnn = 43L, rf = 44L, ensemble = 45L)

highdim_p <- function(n, regime) {
  switch(regime,
         p09 = max(as.integer(floor(0.9 * n)), 5L),
         p15 = max(as.integer(floor(1.5 * n)), 5L),
         stop("Unknown regime: ", regime))
}

sim_sigma <- function(p, type = "block") {
  generate_cov_matrix(p, type = type, rho_ar = 0.5, n_active = 5)
}

sim_rho_true <- function() SIM_RHO_TRUE

parse_dgp <- function(dgp) {
  if (!dgp %in% SIM_DGPS) stop("Unknown DGP: ", dgp, " (use sparse_linear or nonlinear)")
  dgp
}

parse_section <- function(section) {
  valid <- c(SECTION_GOF, SECTION_OLS_PP, SECTION_COMPARISON_FIXED, SECTION_COMPARISON_GROWING)
  if (!section %in% valid) stop("Unknown section: ", section)
  section
}

sim_meta <- function(dgp, estimator, method) {
  list(
    model = dgp,
    estimator = estimator,
    method = method,
    rho_true = sim_rho_true(),
    method_label = sprintf("%s_%s_%s", dgp, estimator, method)
  )
}
