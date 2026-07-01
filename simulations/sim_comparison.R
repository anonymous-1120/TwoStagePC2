#!/usr/bin/env Rscript
# sim_comparison.R -- Fixed p=100; fixed-ratio runs for Section 3 tables.
# Adaptive OLS/SCAD at fixed p are in Section 3.2 (simulations/sim_ols_pp.R → results/ols_pp/).
# Checkpoints: saves .Rdata + summary CSV after each n (not only at the end).

source("R/utils.R")
source("R/sim_estimators.R")
source("R/export_metrics.R")
source("R/sim_core.R")

args <- sim_parse_args(4L, paste(
  "Usage: Rscript simulations/sim_comparison.R <dgp> <estimator> <method> <nsim> [n ...]"
))

dgp <- parse_dgp(args[1])
estimator <- args[2]
method <- args[3]
nsim <- as.integer(args[4])
ns <- if (length(args) >= 5) as.integer(args[5:length(args)]) else SIM_NS

if (estimator == "ensemble" && method != SIM_ENSEMBLE_METHOD) {
  stop("ensemble estimator only supports method=", SIM_ENSEMBLE_METHOD)
}

spec <- resolve_estimator(estimator)
if (spec$needs_keras && !requireNamespace("keras3", quietly = TRUE)) {
  stop("keras3 required for estimator: ", estimator, " (run: Rscript R/install_keras.R)")
}
if (spec$needs_keras) library(keras3)
if (spec$needs_keras) sim_configure_tensorflow()

p <- SIM_P_COMPARISON
rho_true <- sim_rho_true()
Sigma <- sim_sigma(p)
nn_args <- sim_dnn_nn_args()
if (identical(estimator, "dnn")) {
  spec$getRes_args <- modifyList(spec$getRes_args, nn_args)
}

dnn_epoch_tag <- ""
if (identical(estimator, "dnn") && nzchar(Sys.getenv("TWOSTAGEPC_DNN_EPOCHS", unset = ""))) {
  dnn_epoch_tag <- sprintf("_epochs%d", sim_dnn_epochs())
}

cat(sprintf("Fixed-p | DGP=%s | %s/%s | rho=%.4f | p=%d | nsim=%d | n=%s%s\n",
            dgp, estimator, method, rho_true, p, nsim, paste(ns, collapse = ","),
            if (nzchar(dnn_epoch_tag)) sprintf(" | dnn_epochs=%d", sim_dnn_epochs()) else ""))

outfile <- results_path_sim(
  dgp, SECTION_COMPARISON_FIXED,
  sprintf("sim_%s_%s_%s%s_B%d.Rdata", dgp, estimator, method, dnn_epoch_tag, nsim)
)
meta <- sim_meta(dgp, estimator, method)

rep_fun_fixed_p <- function(ii, n_val) {
  if (spec$needs_keras) Sys.setenv(CUDA_VISIBLE_DEVICES = "")
  set.seed(ii * 107 - 1 + match(dgp, SIM_DGPS))
  dat <- generate_data(n_val, p, dgp, Sigma)
  res <- sim_run_one(dat, n_val, spec, method, estimator = estimator, nn_args = nn_args)
  if (spec$needs_keras) {
    sim_keras_gc()
  }
  c(n = n_val, p = p, res)
}

cluster_export <- c("dgp", "estimator", "method", "nsim", "spec", "p", "Sigma",
                    "nn_args", "rep_fun_fixed_p")
cl <- NULL
if (!spec$needs_keras) {
  cl <- sim_cluster(cluster_export, envir = environment())
}

result <- sim_run_by_n(
  ns = ns, nsim = nsim, spec = spec, rep_fun_name = "rep_fun_fixed_p",
  outfile = outfile, rho_true = rho_true, meta = meta,
  checkpoint_objects = list(rho_true = rho_true, p = p, dgp = dgp,
                            estimator = estimator, method = method),
  cl = cl, cluster_export = cluster_export, cluster_envir = environment()
)

cat(sprintf("Results saved to %s\n", outfile))
