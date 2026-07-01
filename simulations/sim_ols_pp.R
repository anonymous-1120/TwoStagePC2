#!/usr/bin/env Rscript
# sim_ols_pp.R -- Adaptive split + P-P statistics (OLS and SCAD; both DGPs).
#
# Usage:
#   Rscript simulations/sim_ols_pp.R [nsim] [n1 n2 ...]              # all estimators in OLS_PP_ESTIMATORS
#   Rscript simulations/sim_ols_pp.R <estimator> [nsim] [n1 ...]     # one of ols, scad

source("R/utils.R")
source("R/sim_estimators.R")
source("R/export_metrics.R")
source("R/sim_core.R")

args <- commandArgs(trailingOnly = TRUE)
estimators <- OLS_PP_ESTIMATORS
if (length(args) >= 1L && args[1] %in% OLS_PP_ESTIMATORS) {
  estimators <- args[1]
  args <- args[-1L]
}
parsed <- sim_parse_nsim_ns(args)
nsim <- parsed$nsim
ns <- parsed$ns

p <- SIM_P_COMPARISON
rho_true <- sim_rho_true()
Sigma <- sim_sigma(p)

cat(sprintf("Adaptive P-P | estimators=%s | rho=%.4f | nsim=%d | n=%s | p=%d\n",
            paste(estimators, collapse = ","), rho_true, nsim,
            paste(ns, collapse = ","), p))

for (est in estimators) {
  spec <- resolve_estimator(est)
  cat(sprintf("\n========== %s ==========\n", toupper(est)))
  cl <- sim_cluster(c("SIM_DGPS", "Sigma", "p", "ns", "nsim", "spec", "est"))
  for (dgp in SIM_DGPS) {
    cat(sprintf("\n=== %s | %s ===\n", dgp, est))
    result <- foreach(ii = seq_len(nsim * length(ns)),
                      .combine = "rbind",
                      .packages = spec$pkgs) %dopar% {
      idx <- (ii - 1L) %/% nsim + 1L
      set.seed(ii * 17L + match(dgp, SIM_DGPS) + 100L * match(est, OLS_PP_ESTIMATORS))
      n <- ns[idx]
      dat <- generate_data(n, p, dgp, Sigma)
      res <- sim_run_one(dat, n, spec, "adaptive")
      c(n = n, res)
    }

    outfile <- results_path_sim(dgp, SECTION_OLS_PP, sprintf("sim_%s_pp_B%d.Rdata", est, nsim))
    save(result, ns, nsim, rho_true, p, dgp, est, file = outfile)
    cat(sprintf("Saved %s\n", outfile))

    for (n_val in ns) {
      sub <- result[result[, "n"] == n_val, , drop = FALSE]
      print(compute_metrics(sub, rho_true, sprintf("%s_pp_%s_n%d", est, dgp, n_val)))
    }
    meta <- sim_meta(dgp, est, "adaptive")
    meta$method_label <- sprintf("%s_%s_pp", dgp, est)
    write_sim_summary_csv(outfile, rho_true, meta)
  }
  stopCluster(cl)
}
