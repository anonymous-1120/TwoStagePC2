#!/usr/bin/env Rscript
# sim_gof.R -- GoF test size (Type I) and power; both DGPs.
#
# Usage: Rscript simulations/sim_gof.R [nsim] [n1 n2 ...]
# Prefer: bash scripts/run_sim_2_gof.sh [--ncores 64]  (sets TWOSTAGEPC_NCORES)

source("R/utils.R")
source("R/sim_estimators.R")
source("R/sim_core.R")

parsed <- sim_parse_nsim_ns(commandArgs(trailingOnly = TRUE))
nsim <- parsed$nsim
ns <- parsed$ns
settings <- sim_gof_settings()
p <- SIM_P_COMPARISON
Sigma <- sim_sigma(p)

cat(sprintf("GoF calibration | nsim=%d | n=%s | p=%d | %s\n",
            nsim, paste(ns, collapse = ","), p, sim_gof_settings_label(settings)))

cl <- sim_cluster(c("GOF_DESIGNS", "Sigma", "p", "settings", "ns", "nsim"))
all_results <- list()

for (d in GOF_DESIGNS) {
  cat(sprintf("\n=== %s ===\n", d$label))
  spec <- resolve_estimator(d$est)
  result <- foreach(ii = seq_len(nsim * length(ns)),
                    .combine = "rbind",
                    .packages = spec$pkgs) %dopar% {
    sim_gof_one_rep(ii, nsim, ns, d, p, Sigma, settings)
  }
  all_results[[d$label]] <- result
  sim_gof_write_design(result, d, nsim, ns, p, settings)
}
stopCluster(cl)

summary_df <- sim_gof_calibration_summary(all_results, GOF_DESIGNS, ns)
combined_pval_path <- results_path_gof(sprintf("sim_gof_all_B%d_pvalues.csv", nsim))
combined_pvals <- do.call(rbind, lapply(GOF_DESIGNS, function(d) {
  sim_gof_pvalues_df(all_results[[d$label]], d, nsim)
}))
write.csv(combined_pvals, combined_pval_path, row.names = FALSE)
cat(sprintf("Saved %s\n", combined_pval_path))

calibration_path <- results_path_gof(sprintf("sim_gof_calibration_B%d.csv", nsim))
write.csv(summary_df, calibration_path, row.names = FALSE)
cat(sprintf("Saved %s\n", calibration_path))
print(summary_df)
