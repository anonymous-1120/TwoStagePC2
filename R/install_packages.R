#!/usr/bin/env Rscript
# Install CRAN packages required by the reproduction code.

pkgs <- c(
  "parallel", "doSNOW", "dplyr", "MASS", "ggplot2", "reshape2",
  "stringr", "ncvreg", "randomForest", "combinat", "glmnet",
  "e1071", "xgboost", "dcov", "knitr", "rmarkdown", "np"
)
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
repos <- "https://cloud.r-project.org"
if (length(missing) > 0) {
  install.packages(missing, repos = repos)
}

still_missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(still_missing) > 0) {
  cat("Still missing after CRAN install:", paste(still_missing, collapse = ", "), "\n")
  cat("On Anaconda R, compile failures (stringi, fs, ...) are common. Try conda-forge, e.g.:\n")
  conda_pkgs <- intersect(still_missing, c("stringr", "glmnet", "rmarkdown", "ggplot2", "reshape2"))
  if (length(conda_pkgs) > 0) {
    cat(sprintf("  conda install -y -c conda-forge %s\n",
                paste0("r-", conda_pkgs, collapse = " ")))
  }
  if ("stringr" %in% still_missing) {
    stop("stringr is required (lib/inference/inference.R). Install via conda above, then re-run.",
         call. = FALSE)
  }
}
cat("CRAN packages ready. For DNN / ensemble: Rscript R/install_keras.R (keras3 + TensorFlow).\n")
