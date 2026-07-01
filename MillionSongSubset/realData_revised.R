#!/usr/bin/env Rscript
# realData_revised.R -- Million Song Dataset (Section 5)
#
# Reproducible seeds: base S = REALDATA_SEED_BASE (default 3100) or TWOSTAGEPC_REALDATA_SEED.
#   adaptive: S+1..S+4 (OLS, SCAD, DNN, RF); fixed 50/50: S+41..S+45.
# Outputs (under results/realdata/):
#   real_data_results_seed<S>.csv  (primary; includes seed_base, run_seed columns)
#   real_data_results.csv        (copy of primary for pipeline / verify_outputs)
#   real_data_run_meta_seed<S>.json
#   results/tables/table_real_data.tex
#
# Run:
#   bash scripts/run_sim_7_realdata.sh
#   TWOSTAGEPC_REALDATA_SEED=3200 bash scripts/run_sim_7_realdata.sh   # alternate base seed

source("R/utils.R")
source("R/sim_estimators.R")
source("MillionSongSubset/real_data_report.R")

skip_dnn <- function() {
  isTRUE(as.logical(Sys.getenv("SKIP_DNN", "0"))) ||
    isTRUE(as.logical(Sys.getenv("TWOSTAGEPC_SKIP_DNN", "0")))
}

keras_ok <- function() requireNamespace("keras3", quietly = TRUE)

nn_args <- list(units = 64, validation_split = 0, activation = "sigmoid", epochs = 40)

SEED_BASE <- realdata_seed_base()
cat(sprintf("Real data seed base S = %d (override: TWOSTAGEPC_REALDATA_SEED)\n", SEED_BASE))

res_num <- function(res, name) {
  v <- res[[name]]
  if (is.null(v) || length(v) == 0L) return(NA_real_)
  as.numeric(v)[1L]
}

n2_eval <- function(res, n_total) {
  v <- res_num(res, "n2")
  if (is.finite(v) && v > 0) return(v)
  ratio <- res_num(res, "ratio")
  if (is.finite(ratio) && ratio > 0) {
    n1 <- round(n_total * ratio / (1 + ratio))
    return(as.numeric(n_total - n1))
  }
  NA_real_
}

result_row <- function(method, adaptive, skipped, passed, gof_pvalue, estimate,
                       ci_low, ci_high, ci_length, n1_over_n2, n2, K0, run_seed) {
  data.frame(
    seed_base = SEED_BASE,
    run_seed = run_seed,
    method = method,
    adaptive = adaptive,
    skipped = skipped,
    passed = passed,
    gof_pvalue = gof_pvalue,
    estimate = estimate,
    ci_low = ci_low,
    ci_high = ci_high,
    ci_length = ci_length,
    n1_over_n2 = n1_over_n2,
    n2 = n2,
    K0 = K0,
    stringsAsFactors = FALSE
  )
}

new_data <- read.csv("MillionSongSubset/realData_song.csv")
tempo    <- new_data$tempo
loudness <- new_data$loudness
tmp <- new_data[, -c(which(colnames(new_data) == "tempo"),
                     which(colnames(new_data) == "loudness"))]
colnames(tmp) <- paste0("z", seq_len(ncol(tmp)))
datY <- data.frame(loudness = loudness, tmp)
datX <- data.frame(tempo = tempo, tmp)

n <- nrow(new_data)
p <- ncol(tmp)

cat(sprintf("Real data: n = %d, p = %d\n", n, p))

rho_ci <- function(rhat, n2) {
  rhat <- as.numeric(rhat)[1L]
  n2 <- as.numeric(n2)[1L]
  if (!is.finite(rhat) || !is.finite(n2) || n2 <= 0) {
    return(c(ci_low = NA_real_, ci_high = NA_real_, ci_length = NA_real_))
  }
  se <- (1 - rhat^2) / sqrt(n2)
  lo <- rhat - qnorm(0.975) * se
  hi <- rhat + qnorm(0.975) * se
  c(ci_low = lo, ci_high = hi, ci_length = hi - lo)
}

row_from_adaptive <- function(label, res, run_seed) {
  passed <- isTRUE(res_num(res, "passed") == 1)
  n2_val <- n2_eval(res, n)
  ci <- if (passed) rho_ci(res_num(res, "rho_hat"), n2_val) else c(ci_low = NA, ci_high = NA, ci_length = NA)
  cat(sprintf("\n--- %s (seed %d) ---\n", label, run_seed))
  cat(sprintf("  Passed: %s | GoF p-value: %.4f | K0 = %.0f\n",
              ifelse(passed, "Yes", "No"), res_num(res, "CauchyP"), res_num(res, "K0")))
  if (passed) {
    cat(sprintf("  Estimate: %.4f | 95%% CI: (%.4f, %.4f) | n1/n2: %.2f | CI len: %.4f\n",
                res_num(res, "rho_hat"), ci["ci_low"], ci["ci_high"],
                res_num(res, "ratio"), ci["ci_length"]))
  }
  result_row(
    method = label, adaptive = TRUE, skipped = FALSE,
    passed = ifelse(passed, 1, 0), gof_pvalue = res_num(res, "CauchyP"),
    estimate = if (passed) res_num(res, "rho_hat") else NA,
    ci_low = ci["ci_low"], ci_high = ci["ci_high"], ci_length = ci["ci_length"],
    n1_over_n2 = if (passed) res_num(res, "ratio") else NA,
    n2 = if (passed) n2_val else NA, K0 = res_num(res, "K0"), run_seed = run_seed
  )
}

row_skipped <- function(label, adaptive = TRUE, run_seed = NA_integer_) {
  cat(sprintf("\n--- %s --- SKIPPED\n", label))
  result_row(
    method = label, adaptive = adaptive, skipped = TRUE,
    passed = NA, gof_pvalue = NA, estimate = NA,
    ci_low = NA, ci_high = NA, ci_length = NA,
    n1_over_n2 = NA, n2 = NA, K0 = NA, run_seed = run_seed
  )
}

row_from_fixed <- function(label, res, ratio = 0.5, run_seed) {
  n2_val <- n2_eval(res, n)
  ci <- rho_ci(res_num(res, "rho_hat"), n2_val)
  cat(sprintf("\n--- %s (seed %d) ---\n", label, run_seed))
  cat(sprintf("  Estimate: %.4f | 95%% CI: (%.4f, %.4f) | n1/n2: %.2f | CI len: %.4f\n",
              res_num(res, "rho_hat"), ci["ci_low"], ci["ci_high"], ratio, ci["ci_length"]))
  result_row(
    method = label, adaptive = FALSE, skipped = FALSE,
    passed = NA, gof_pvalue = NA, estimate = res_num(res, "rho_hat"),
    ci_low = ci["ci_low"], ci_high = ci["ci_high"], ci_length = ci["ci_length"],
    n1_over_n2 = ratio, n2 = n2_val, K0 = NA, run_seed = run_seed
  )
}

gof_args <- list(
  rho_min = ADAPTIVE_RHO_MIN,
  rho_max = ADAPTIVE_RHO_MAX,
  rho_s = ADAPTIVE_RHO_STEP,
  alpha = ADAPTIVE_GOF_ALPHA,
  nsplits = ADAPTIVE_NSPLITS,
  split_method = ADAPTIVE_SPLIT_METHOD
)

run_adaptive <- function(est) {
  spec <- resolve_estimator(est)
  run_seed <- realdata_adaptive_seed(est, SEED_BASE)
  sim_begin_reproducible(run_seed, keras = isTRUE(spec$needs_keras))
  out <- do.call(run_gof_and_estimate, c(list(
    datX, datY, n,
    testModelFun = spec$testModelFun,
    getResFun = spec$getResFun,
    getRes_args = spec$getRes_args,
    formula_x = tempo ~ .,
    formula_y = loudness ~ .
  ), gof_args))
  if (isTRUE(spec$needs_keras)) sim_keras_gc()
  out
}

run_fixed <- function(est, ratio = 0.5) {
  spec <- resolve_estimator(est)
  run_seed <- realdata_fixed_seed(est, SEED_BASE)
  sim_begin_reproducible(run_seed, keras = isTRUE(spec$needs_keras))
  out <- do.call(run_fixed_ratio_estimate, c(list(
    datX, datY, n,
    getResFun = spec$getResFun,
    formula_x = tempo ~ .,
    formula_y = loudness ~ .,
    ratio = ratio
  ), list(getRes_args = spec$getRes_args)))
  if (isTRUE(spec$needs_keras)) sim_keras_gc()
  out
}

run_fixed_ensemble <- function(ratio = 0.5) {
  run_seed <- realdata_fixed_seed("ensemble", SEED_BASE)
  sim_begin_reproducible(run_seed, keras = TRUE)
  getRes_wrapper <- function(dat_train, dat_eval, formula) {
    getResEnsemble(dat_train, dat_eval, formula, nn_args = nn_args)
  }
  out <- run_fixed_ratio_estimate(
    datX, datY, n,
    getResFun = getRes_wrapper,
    formula_x = tempo ~ .,
    formula_y = loudness ~ .,
    ratio = ratio
  )
  sim_keras_gc()
  out
}

labels <- c(ols = "OLS", scad = "SCAD", dnn = "DNN", rf = "Random forest",
            ensemble = "Ensemble (SCAD+RF+NN)")

maybe_adaptive <- function(est) {
  label <- paste0(labels[est], " (adaptive)")
  run_seed <- realdata_adaptive_seed(est, SEED_BASE)
  if (est == "dnn" && skip_dnn()) {
    message("Skipping DNN adaptive (SKIP_DNN=1 or --no-dnn)")
    return(row_skipped(label, run_seed = run_seed))
  }
  if (est == "dnn" && !keras_ok()) {
    warning("keras3 not installed; DNN adaptive skipped. Run Rscript R/install_keras.R")
    return(row_skipped(label, run_seed = run_seed))
  }
  row_from_adaptive(label, run_adaptive(est), run_seed)
}

maybe_fixed <- function(est, ratio = 0.5) {
  label <- paste0(labels[est], " (fixed even)")
  run_seed <- realdata_fixed_seed(est, SEED_BASE)
  if (est %in% c("dnn", "ensemble") && skip_dnn()) {
    message("Skipping ", labels[est], " fixed (SKIP_DNN=1 or --no-dnn)")
    return(row_skipped(label, adaptive = FALSE, run_seed = run_seed))
  }
  if (est %in% c("dnn", "ensemble") && !keras_ok()) {
    warning(labels[est], " fixed skipped (keras3 not installed)")
    return(row_skipped(label, adaptive = FALSE, run_seed = run_seed))
  }
  if (est == "ensemble") {
    row_from_fixed(label, run_fixed_ensemble(ratio), ratio = ratio, run_seed = run_seed)
  } else {
    row_from_fixed(label, run_fixed(est, ratio), ratio = ratio, run_seed = run_seed)
  }
}

adaptive_ests <- c("ols", "scad", "dnn", "rf")
fixed_ests <- c("ols", "scad", "dnn", "rf", "ensemble")

adaptive_rows <- lapply(adaptive_ests, maybe_adaptive)
names(adaptive_rows) <- adaptive_ests
fixed_rows <- lapply(fixed_ests, maybe_fixed)
names(fixed_rows) <- fixed_ests

rows <- rbind(
  do.call(rbind, adaptive_rows[adaptive_ests]),
  do.call(rbind, fixed_rows[fixed_ests])
)

realdata_dir <- ensure_results_dir(RESULTS_REALDATA)
seed_csv <- file.path(realdata_dir, realdata_results_csv_name(SEED_BASE))
alias_csv <- file.path(realdata_dir, "real_data_results.csv")
write.csv(rows, seed_csv, row.names = FALSE)
write.csv(rows, alias_csv, row.names = FALSE)

meta_path <- write_real_data_run_meta(SEED_BASE, n, p, out_dir = realdata_dir)
table_tex <- write_real_data_latex_table(rows, n, p, seed_base = SEED_BASE)

cat("\n======= SUMMARY =======\n")
cat(sprintf("  Seed base S = %d\n", SEED_BASE))
cat(sprintf("  Cauchy combination: %s split, K0=%d\n", ADAPTIVE_SPLIT_METHOD, ADAPTIVE_NSPLITS))
cat(sprintf("  Split grid: kappa in [%.2f, %.2f] step %.2f\n",
            ADAPTIVE_RHO_MIN, ADAPTIVE_RHO_MAX, ADAPTIVE_RHO_STEP))
cat(sprintf("  Random forest: ntree=500, mtry=%d\n", max(floor(p / 3), 1L)))
cat("  SCAD: penalty='SCAD', refitted OLS after selection\n")
cat("  DNN: 64 hidden units, sigmoid activation, 40 epochs\n")
cat("  Ensemble: equal-weight average of SCAD, RF, and DNN residuals\n")
cat(sprintf("  CSV (seeded): %s\n", seed_csv))
cat(sprintf("  CSV (alias):  %s\n", alias_csv))
cat(sprintf("  Meta:         %s\n", meta_path))
cat(sprintf("  LaTeX:        %s\n", table_tex))
