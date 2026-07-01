#!/usr/bin/env Rscript
# summarize_all.R -- Aggregate simulation summaries from results/<section>/<dgp>/

source("R/utils.R")
source("R/sim_dgp_config.R")
source("R/export_metrics.R")

csv_patterns <- c("sim_*_summary.csv", "sim_gof_calibration_B*.csv", "sim_*_split_ratio.csv")
sections_by_dgp <- c(SECTION_OLS_PP, SECTION_COMPARISON_FIXED, SECTION_COMPARISON_GROWING)

files <- unique(c(
  unlist(lapply(csv_patterns, function(pat) results_glob_gof(pat))),
  unlist(lapply(sections_by_dgp, function(sec) {
    unlist(lapply(csv_patterns, function(pat) results_glob_section(sec, pat)))
  }))
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
