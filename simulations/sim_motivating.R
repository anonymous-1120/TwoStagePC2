#!/usr/bin/env Rscript
# sim_motivating.R -- reproduce Table 1 (tab:motivatingExample), the toy
# illustration in the Introduction.
#
# Goal: show that, at a high-dimensional finite sample, a correctly specified
# OLS recovers the partial correlation almost unbiasedly, whereas flexible
# learners (kernel regression, random forest, feedforward neural network)
# overfit and produce non-negligible bias and inflated variance. This motivates
# the proposed sample-splitting + goodness-of-fit procedure.
#
# DGP (Eq. \eqref{eq:motivatingExample} in paper/main.tex):
#   Y = beta * X + gamma' z + eps,
#   X ~ N(1,1),  z_j ~ N(1,1) iid (j = 1..p),  eps ~ t_5,  beta = 1, gamma = 1,
#   p = 30, n = 100.
# Target: rho = corr(X, Y | z). Partial correlation is estimated as
#   rho_hat = cor(X - m_X(z), Y - m_Y(z)),
# where m_X, m_Y are *in-sample* fits (no splitting) so flexible learners overfit.
#
# Outputs (run from the repository root):
#   results/motivating/motivating_results.csv            per-replication rho-hats
#   results/motivating/motivating_summary.csv            Bias / SD / MSE (x10)
#   results/tables/table_motivating.tex                  LaTeX table fragment, mirrors
#                                                         paper/tables/table_motivating.tex
#                                                         (\input by main.tex) in the manuscript repo
#
# Usage:
#   Rscript simulations/sim_motivating.R [B] [skip_dnn]
#   Rscript simulations/sim_motivating.R 500 0   # full reproduction (needs np + keras3)
#   Rscript simulations/sim_motivating.R 500 1   # skip the neural-network row (no keras3)
#
# Dependencies: np (kernel regression, add via R/install_packages.R),
#               randomForest (CRAN), keras3 + TensorFlow (only when skip_dnn=0).
#
# NOTE: this script is intended to be run on the server, not the local laptop.

source("R/utils.R")
source("R/sim_core.R")

## ---------------------------------------------------------------------------
## Configuration
## ---------------------------------------------------------------------------
# Replication ii uses set.seed(ii - 1) (seeds 0, 1, ...).
# Offset so the two nuisance neural nets (for X and Y) get distinct TF seeds.
MOTIVATING_NN_X_SEED_OFFSET <- 500000L

P_MOT <- 30L     # covariate dimension
N_MOT <- 100L    # sample size
TABLE_SCALE <- 10  # table reports 10 x the actual values

args <- commandArgs(trailingOnly = TRUE)
B <- if (length(args) >= 1L && nzchar(args[[1]])) as.integer(args[[1]]) else 500L
skip_dnn <- if (length(args) >= 2L && nzchar(args[[2]])) {
  as.integer(args[[2]]) == 1L
} else {
  identical(Sys.getenv("TWOSTAGEPC_SKIP_DNN", unset = "0"), "1")
}

out_dir <- ensure_results_dir("motivating")
results_csv <- file.path(out_dir, "motivating_results.csv")
summary_csv <- file.path(out_dir, "motivating_summary.csv")
table_path <- file.path("results", "tables", "table_motivating.tex")

FY <- y ~ .
FX <- x ~ .

## ---------------------------------------------------------------------------
## DGP
## ---------------------------------------------------------------------------
motivating_dgp <- function(n, p) {
  X <- rnorm(n, mean = 1, sd = 1)
  Z <- matrix(rnorm(n * p, mean = 1, sd = 1), nrow = n, ncol = p)
  eps <- rt(n, df = 5)
  Y <- 1 * X + as.numeric(Z %*% rep(1, p)) + eps
  zdf <- as.data.frame(Z)
  names(zdf) <- paste0("z", seq_len(p))
  list(
    datY = cbind(data.frame(y = Y), zdf),  # regress Y on z
    datX = cbind(data.frame(x = X), zdf)   # regress X on z
  )
}

## ---------------------------------------------------------------------------
## In-sample residual functions (m_hat fitted on the full sample, no splitting)
## ---------------------------------------------------------------------------
res_lm <- function(dat, formula) {
  rsp <- as.character(formula)[2]
  mod <- lm(formula, data = dat)
  dat[[rsp]] - as.numeric(stats::predict(mod, dat))
}

# Multivariate Nadaraya--Watson kernel regression. A normal-reference (plug-in)
# bandwidth is used instead of cross-validation: with p = 30 covariates CV is
# intractable, and the curse of dimensionality (which is exactly what the toy
# example illustrates) is already evident under the rule-of-thumb bandwidth.
#
# np >= 0.70 exposes bwmethod = "normal-reference"; conda r-np 0.60 only allows
# cv.ls / cv.aic, so we apply Silverman's rule and pass bandwidths via npreg().
kernel_normal_reference_bw <- local({
  bw_template <- new.env(parent = emptyenv())
  function(xdat, ydat) {
    xmat <- as.matrix(xdat)
    n <- nrow(xmat)
    d <- ncol(xmat)
    sdj <- apply(xmat, 2, stats::sd)
    sdj[sdj == 0] <- 1e-6
    h <- ((4 / (d + 2))^(1 / (d + 4))) * n^(-1 / (d + 4)) * sdj

    np_ver <- utils::packageVersion("np")
    if (np_ver >= "0.70") {
      return(np::npregbw(
        xdat = xdat, ydat = ydat, regtype = "lc", bwmethod = "normal-reference"
      ))
    }

    if (is.null(bw_template$obj)) {
      bw_template$obj <- np::npregbw(
        xdat = xmat[, 1, drop = FALSE],
        ydat = ydat,
        regtype = "lc",
        bwmethod = "cv.ls",
        nmulti = 1L
      )
    }
    bw <- bw_template$obj
    bw$bw <- h
    bw$ndim <- d
    bw$ncon <- d
    bw
  }
})

res_kernel <- function(dat, formula) {
  if (!requireNamespace("np", quietly = TRUE)) {
    stop("Package 'np' is required for kernel regression. Run R/install_packages.R.")
  }
  rsp <- as.character(formula)[2]
  preds <- setdiff(names(dat), rsp)
  bw <- kernel_normal_reference_bw(dat[preds], dat[[rsp]])
  fit <- np::npreg(bws = bw, txdat = dat[preds], tydat = dat[[rsp]])
  dat[[rsp]] - as.numeric(fitted(fit))
}

res_rf <- function(dat, formula) {
  rsp <- as.character(formula)[2]
  rf <- randomForest::randomForest(
    formula,
    data = dat,
    ntree = 500,
    mtry = max(floor(P_MOT / 3), 1),
    importance = FALSE
  )
  # In-sample predictions (predict on training data) so the forest overfits.
  dat[[rsp]] - as.numeric(stats::predict(rf, newdata = dat))
}

# Single hidden layer feedforward net (ReLU hidden, linear output), trained to
# (over)fit in-sample -- mirroring the architecture described for the toy
# example. Reproducible via sim_set_tensorflow_seed().
res_nn <- function(dat, formula, seed, units = 64L, epochs = 150L, batch_size = 16L) {
  sim_set_tensorflow_seed(seed)
  rsp <- as.character(formula)[2]
  x <- model.matrix(formula, dat)
  x <- x[, setdiff(colnames(x), "(Intercept)"), drop = FALSE]
  y <- dat[[rsp]]

  network <- keras3::keras_model_sequential() %>%
    keras3::layer_dense(units = units, activation = "relu", input_shape = c(ncol(x))) %>%
    keras3::layer_dense(units = 1L, activation = "linear")
  keras3::compile(network, optimizer = keras3::optimizer_adam(learning_rate = 0.01), loss = "mse")
  keras3::fit(network, x, y, epochs = epochs, batch_size = batch_size, verbose = 0)

  pred <- as.numeric(keras3::predict_on_batch(network, x))
  res <- y - pred
  rm(network, x, y, pred)
  sim_keras_gc()
  res
}

motivating_one_rep <- function(ii) {
  set.seed(ii - 1L)
  dat <- motivating_dgp(N_MOT, P_MOT)

  ols <- cor(res_lm(dat$datX, FX), res_lm(dat$datY, FY))

  kernel <- tryCatch(
    cor(res_kernel(dat$datX, FX), res_kernel(dat$datY, FY)),
    error = function(e) NA_real_
  )

  rf <- cor(res_rf(dat$datX, FX), res_rf(dat$datY, FY))

  nn <- if (!skip_dnn) {
    tryCatch({
      eX <- res_nn(dat$datX, FX, seed = ii - 1L + MOTIVATING_NN_X_SEED_OFFSET)
      eY <- res_nn(dat$datY, FY, seed = ii - 1L)
      cor(eX, eY)
    }, error = function(e) NA_real_)
  } else {
    NA_real_
  }

  data.frame(rep = ii, ols = ols, kernel = kernel, rf = rf, nn = nn)
}

## ---------------------------------------------------------------------------
## True partial correlation (large-sample reference; analytic value sqrt(3/8))
## ---------------------------------------------------------------------------
true_rho <- local({
  set.seed(20240601L)
  big <- 2e5L
  dat <- motivating_dgp(big, P_MOT)
  eY <- res_lm(dat$datY, FY)
  eX <- res_lm(dat$datX, FX)
  cor(eX, eY)
})
analytic_rho <- sqrt(1 / (1 + 5 / 3))  # Var(t_5) = 5/3, Var(X) = 1
message(sprintf("True partial correlation: large-sample OLS = %.4f (analytic sqrt(3/8) = %.4f)",
                true_rho, analytic_rho))

## ---------------------------------------------------------------------------
## Monte Carlo loop (parallel, chunked like sim_core.R)
## ---------------------------------------------------------------------------
method_names <- c("Ordinary least squares", "Kernel regression",
                  "Random forest", "Feedforward neural network")

motivating_pkgs <- c("np", "randomForest")
if (!skip_dnn) motivating_pkgs <- c(motivating_pkgs, "keras3")

export_vars <- c(
  "motivating_dgp", "res_lm", "res_kernel", "res_rf", "res_nn",
  "kernel_normal_reference_bw", "motivating_one_rep",
  "P_MOT", "N_MOT", "FX", "FY", "skip_dnn", "MOTIVATING_NN_X_SEED_OFFSET"
)
cluster_envir <- environment()
chunk_size <- sim_progress_chunk(B)
recycle_workers <- !skip_dnn
motivating_cluster_cores <- function() {
  if (skip_dnn) return(sim_cluster_cores())
  n <- Sys.getenv("MOTIVATING_NCORES", unset = "")
  if (!nzchar(n)) n <- Sys.getenv("DNN_NCORES", unset = "32")
  as.integer(min(as.integer(n), sim_available_cpus()))
}

motivating_aggregate <- function(per_rep) {
  rhohat <- as.matrix(per_rep[, c("ols", "kernel", "rf", "nn")])
  bias <- colMeans(rhohat, na.rm = TRUE) - true_rho
  sdev <- apply(rhohat, 2L, sd, na.rm = TRUE)
  mse <- colMeans((rhohat - true_rho)^2, na.rm = TRUE)
  data.frame(
    method = method_names,
    bias = TABLE_SCALE * bias,
    sd = TABLE_SCALE * sdev,
    mse = TABLE_SCALE * mse,
    row.names = NULL
  )
}

motivating_write_checkpoint <- function(per_rep, n_done, elapsed = "") {
  per_rep <- per_rep[order(per_rep$rep), , drop = FALSE]
  out <- per_rep
  out$true_rho <- true_rho
  write.csv(out, results_csv, row.names = FALSE)
  summary_df <- motivating_aggregate(per_rep)
  write.csv(summary_df, summary_csv, row.names = FALSE)
  cat(sprintf(
    "Checkpoint %d/%d reps%s -> %s (%d rows)\n",
    n_done, B, if (nzchar(elapsed)) paste0(" in ", elapsed) else "", results_csv, nrow(per_rep)
  ))
  print(format(summary_df, digits = 2, nsmall = 2), row.names = FALSE)
  invisible(summary_df)
}

message(sprintf(
  "Running B = %d replications (n = %d, p = %d, skip_dnn = %s, workers = %d, chunk = %d) ...",
  B, N_MOT, P_MOT, skip_dnn, motivating_cluster_cores(), chunk_size
))

if (!skip_dnn) {
  dnn_nc <- motivating_cluster_cores()
  Sys.setenv(TWOSTAGEPC_NCORES = as.character(dnn_nc))
}

cl <- sim_cluster(export_vars, envir = cluster_envir)
per_rep <- NULL
t0 <- proc.time()
for (start in seq(1L, B, by = chunk_size)) {
  if (recycle_workers) {
    cl <- sim_recycle_cluster(cl, export_vars, cluster_envir)
    sim_log_progress(sprintf("rep %d+ workers recycled (fresh TF)", start), cl = cl)
  }
  end <- min(start + chunk_size - 1L, B)
  sim_log_progress(sprintf("rep %d-%d/%d running", start, end, B), cl = cl)
  chunk <- foreach(ii = start:end,
                   .combine = "rbind",
                   .packages = motivating_pkgs) %dopar% {
    motivating_one_rep(ii)
  }
  per_rep <- if (is.null(per_rep)) chunk else rbind(per_rep, chunk)
  elapsed <- sim_format_elapsed(proc.time() - t0)
  motivating_write_checkpoint(per_rep, end, elapsed)
  sim_log_progress(sprintf("rep %d-%d/%d done in %s", start, end, B, elapsed), cl = cl)
  gc(verbose = FALSE)
}
stopCluster(cl)

per_rep <- per_rep[order(per_rep$rep), , drop = FALSE]
rhohat <- as.matrix(per_rep[, c("ols", "kernel", "rf", "nn")])

## ---------------------------------------------------------------------------
## Final aggregate: Bias / SD / MSE of the estimator (x10)
## ---------------------------------------------------------------------------
summary_df <- motivating_aggregate(per_rep)
per_rep$true_rho <- true_rho
write.csv(per_rep, results_csv, row.names = FALSE)
message("Wrote ", results_csv)
write.csv(summary_df, summary_csv, row.names = FALSE)
message("Wrote ", summary_csv)

## ---------------------------------------------------------------------------
## LaTeX table -> paper/tables/table_motivating.tex
## ---------------------------------------------------------------------------
write_motivating_table <- function(summary_df, out_path, B, p, n) {
  fmt <- function(x) if (is.na(x)) "$\\cdot$" else sprintf("%.2f", x)
  # Footnote when the OLS bias rounds to 0.00 at two decimals, so a near-zero
  # entry is not mistaken for an exact zero.
  ols_idx <- which(summary_df$method == "Ordinary least squares")
  add_note <- length(ols_idx) == 1L && !is.na(summary_df$bias[ols_idx]) &&
    abs(round(summary_df$bias[ols_idx], 2)) < 0.005
  body <- vapply(seq_len(nrow(summary_df)), function(i) {
    r <- summary_df[i, ]
    bias_cell <- fmt(r$bias)
    if (add_note && i == ols_idx) bias_cell <- paste0(bias_cell, "\\tnote{a}")
    sprintf("%s & %s & %s & %s \\\\", r$method, bias_cell, fmt(r$sd), fmt(r$mse))
  }, character(1))
  tex <- c(
    "% Generated by sim_motivating.R (do not edit by hand)",
    "\\begin{table}[htbp]\\small",
    "\\centering",
    sprintf(paste0(
      "\\caption{Bias, standard deviation (SD) of the estimator, and mean squared error (MSE) ",
      "for the estimates of $\\corr(X,Y\\mid \\z)$ under four learners for the toy ",
      "model~\\eqref{eq:motivatingExample} ($p=%d$, $n=%d$, $t_5$ noise). Each entry is the ",
      "average over %d replications, multiplied by $10$.}"), p, n, B),
    "\\label{tab:motivatingExample}",
    "\\begin{threeparttable}",
    "\\begin{tabular}{l r r r}",
    "\\toprule",
    "Regression methods & Bias & SD & MSE \\\\",
    "\\midrule",
    body,
    "\\bottomrule",
    "\\end{tabular}"
  )
  if (add_note) {
    tex <- c(tex,
      "\\begin{tablenotes}\\footnotesize",
      sprintf("\\item[a] The OLS bias is $%.3f$ on this scale (rounded to $0.00$).",
              summary_df$bias[ols_idx]),
      "\\end{tablenotes}")
  }
  tex <- c(tex, "\\end{threeparttable}", "\\end{table}")
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(tex, out_path)
}

write_motivating_table(summary_df, table_path, B, P_MOT, N_MOT)
message("Wrote ", table_path)

## ---------------------------------------------------------------------------
## Consistency check against the Introduction statement:
##   "apart from OLS, the other three nonparametric approaches exhibit
##    non-negligible biases and inflated variances."
## ---------------------------------------------------------------------------
cat("\n================ Motivating-example summary (x10) ================\n")
print(format(summary_df, digits = 2, nsmall = 2), row.names = FALSE)
cat("\n")

ols <- summary_df[summary_df$method == "Ordinary least squares", ]
others <- summary_df[summary_df$method != "Ordinary least squares" & !is.na(summary_df$bias), ]
if (nrow(others) > 0L) {
  ok_bias <- abs(ols$bias) < min(abs(others$bias))
  ok_sd <- ols$sd < min(others$sd)
  verdict <- if (ok_bias && ok_sd) "PASS" else "CHECK"
  cat(sprintf(
    "Introduction-claim check: OLS has the smallest |bias| (%s) and smallest SD (%s) -> %s\n",
    ok_bias, ok_sd, verdict))
  cat("  OLS:    bias=", sprintf("%.2f", ols$bias), " SD=", sprintf("%.2f", ols$sd), "\n", sep = "")
  for (i in seq_len(nrow(others))) {
    cat("  ", others$method[i], ": bias=", sprintf("%.2f", others$bias[i]),
        " SD=", sprintf("%.2f", others$sd[i]), "\n", sep = "")
  }
  if (verdict != "PASS") {
    cat("  -> Re-examine paper/main.tex Introduction wording around tab:motivatingExample.\n")
  }
} else {
  cat("Introduction-claim check: skipped (no non-OLS rows; was skip_dnn set and kernel/rf NA?).\n")
}
cat("==================================================================\n")
