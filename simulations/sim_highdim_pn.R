#!/usr/bin/env Rscript
# sim_highdim_pn.R -- Growing p: p = floor(0.9n) or floor(1.5n).
# Checkpoints: saves .Rdata + summary CSV after each n (not only at the end).

source("R/utils.R")
source("R/sim_estimators.R")
source("R/export_metrics.R")
source("R/sim_core.R")

args <- sim_parse_args(5L, paste(
  "Usage: Rscript simulations/sim_highdim_pn.R <dgp> <regime> <estimator> <method> <nsim> [n ...]"
))

dgp <- parse_dgp(args[1])
regime <- args[2]
if (!regime %in% c("p09", "p15")) stop("regime must be p09 or p15")
estimator <- args[3]
method <- args[4]
nsim <- as.integer(args[5])
ns <- if (length(args) >= 6) as.integer(args[6:length(args)]) else SIM_NS

if (estimator == "ensemble" && method != SIM_ENSEMBLE_METHOD) {
  stop("ensemble estimator only supports method=", SIM_ENSEMBLE_METHOD)
}

spec <- resolve_estimator(estimator)
if (spec$needs_keras && !requireNamespace("keras3", quietly = TRUE)) {
  stop("keras3 required for estimator: ", estimator, " (run: Rscript R/install_keras.R)")
}
if (spec$needs_keras) library(keras3)
if (spec$needs_keras) sim_configure_tensorflow()

rho_true <- sim_rho_true()
nn_args <- sim_dnn_nn_args()
if (identical(estimator, "dnn") || identical(estimator, "ensemble")) {
  spec$getRes_args <- modifyList(spec$getRes_args, nn_args)
}
dnn_epoch_tag <- ""
if (identical(estimator, "dnn") && nzchar(Sys.getenv("TWOSTAGEPC_DNN_EPOCHS", unset = ""))) {
  dnn_epoch_tag <- sprintf("_epochs%d", sim_dnn_epochs())
}

cat(sprintf("Growing-p | DGP=%s | %s | %s/%s | rho=%.4f | nsim=%d | n=%s\n",
            dgp, regime, estimator, method, rho_true, nsim, paste(ns, collapse = ",")))

if (estimator == "ols") {
  for (n_val in ns) {
    if (!ols_feasible(n_val, highdim_p(n_val, regime))) {
      stop(sprintf("OLS infeasible: n=%d, p=%d (%s)", n_val, highdim_p(n_val, regime), regime))
    }
  }
}

outfile <- results_path_sim(
  dgp, SECTION_COMPARISON_GROWING,
  sprintf("sim_%s_%s_%s_%s%s_B%d.Rdata", regime, estimator, method, dgp, dnn_epoch_tag, nsim)
)
meta <- sim_meta(dgp, estimator, method)
meta$method_label <- sprintf("%s_%s_%s_%s", regime, dgp, estimator, method)

rep_fun_growing_p <- function(ii, n_val) {
  if (spec$needs_keras) Sys.setenv(CUDA_VISIBLE_DEVICES = "")
  set.seed(ii * 211L + match(dgp, SIM_DGPS))
  p <- highdim_p(n_val, regime)
  Sigma <- sim_sigma(p)
  dat <- generate_data(n_val, p, dgp, Sigma)
  res <- sim_run_one(dat, n_val, spec, method, estimator = estimator, nn_args = nn_args)
  if (spec$needs_keras) {
    sim_keras_gc()
  }
  c(n = n_val, p = p, res)
}

cluster_export <- c("dgp", "regime", "estimator", "method", "nsim", "spec", "nn_args",
                    "rep_fun_growing_p")
cl <- NULL
if (!spec$needs_keras) {
  cl <- sim_cluster(cluster_export, envir = environment())
}

result <- sim_run_by_n(
  ns = ns, nsim = nsim, spec = spec, rep_fun_name = "rep_fun_growing_p",
  outfile = outfile, rho_true = rho_true, meta = meta,
  checkpoint_objects = list(rho_true = rho_true, dgp = dgp, regime = regime,
                            estimator = estimator, method = method),
  cl = cl, cluster_export = cluster_export, cluster_envir = environment()
)

cat(sprintf("Results saved to %s (%d rows)\n", outfile, nrow(result)))
if (spec$needs_keras) sim_keras_gc()
