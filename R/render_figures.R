#!/usr/bin/env Rscript
# render_figures.R -- Optional combined PDF report (Visualization.Rmd).
# Individual figures: Rscript R/plot_sim_figures.R

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  stop("Install rmarkdown: install.packages('rmarkdown')")
}

source("R/sim_dgp_config.R")
out_dir <- results_figures_dir()
rmarkdown::render(
  "Visualization.Rmd",
  output_format = "pdf_document",
  output_file = "simulation_report.pdf",
  output_dir = out_dir,
  quiet = FALSE
)
cat(sprintf("Wrote %s/simulation_report.pdf\n", out_dir))
