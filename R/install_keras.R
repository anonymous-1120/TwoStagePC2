#!/usr/bin/env Rscript
# Install keras3 (R) + TensorFlow/Keras (Python) for DNN and ensemble simulations.
#
# Anaconda R note: if install.packages("reticulate") fails to compile, use:
#   conda install -c conda-forge r-reticulate
# then re-run this script.

repos <- "https://cloud.r-project.org"

if (!requireNamespace("reticulate", quietly = TRUE)) {
  message("Installing reticulate from CRAN...")
  install.packages("reticulate", repos = repos)
}
if (!requireNamespace("reticulate", quietly = TRUE)) {
  stop(
    "reticulate is required but not installed. On Anaconda R try:\n",
    "  conda install -c conda-forge r-reticulate\n",
    "then: Rscript R/install_keras.R",
    call. = FALSE
  )
}

if (!requireNamespace("keras3", quietly = TRUE)) {
  message("Installing keras3 from CRAN...")
  install.packages("keras3", repos = repos)
}
if (!requireNamespace("keras3", quietly = TRUE)) {
  stop("keras3 installation failed.", call. = FALSE)
}

library(keras3)
message("Installing Python backend (tensorflow) via keras3::install_keras() ...")
install_keras(backend = "tensorflow")

cat("\nkeras3 ready.\n")
cat("Verify:\n")
cat('  Rscript -e \'library(keras3); cat(backend(), "\\n")\'\n')
