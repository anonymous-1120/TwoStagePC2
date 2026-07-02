#!/usr/bin/env Rscript
# summarize_all.R -- Aggregate simulation summaries from results/<section>/<dgp>/

source("R/utils.R")
source("R/sim_dgp_config.R")
source("R/export_metrics.R")

# Only "*_summary.csv" files share the estimator-performance schema (model, estimator,
# method, bias, sd_rho, mse, ci_coverage, ci_length, gof_pass_rate, avg_n1_over_n, avg_K,
# avg_K0, ...) documented in README.md's "Inspect CSV columns" section, so those are the
# only files combined here. GoF calibration (sim_gof_calibration_B*.csv) and split-ratio
# (sim_*_split_ratio.csv) files have unrelated schemas and are already written to their
# own dedicated paths by sim_gof.R / the adaptive drivers -- rbind-ing them together with
# the summary rows fails ("invalid number of columns") since the column sets don't match.
csv_pattern <- "sim_*_summary.csv"
sections_by_dgp <- c(SECTION_OLS_PP, SECTION_COMPARISON_FIXED, SECTION_COMPARISON_GROWING)

files <- unique(c(
  results_glob_gof(csv_pattern),
  unlist(lapply(sections_by_dgp, function(sec) results_glob_section(sec, csv_pattern)))
))

if (length(files) == 0) {
  stop("No summary CSV files under results/<section>/<dgp>/. Run simulations first.")
}

dfs <- lapply(files, function(f) {
  df <- read.csv(f, stringsAsFactors = FALSE)
  df$source_file <- f
  df
})

combined <- do.call(rbind, dfs)
outfile <- results_path(RESULTS_AGGREGATED, "all_simulations_summary.csv")
write.csv(combined, outfile, row.names = FALSE)
cat(sprintf("Wrote %d rows to %s\n", nrow(combined), outfile))
