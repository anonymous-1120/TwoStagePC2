# sim_core.R -- shared parallel cluster setup and one-replication estimators

sim_cluster <- function(export_vars = character(0), envir = parent.frame()) {
  ncores <- sim_cluster_cores()
  message(sprintf("Parallel cluster: %d workers (TWOSTAGEPC_NCORES=%s)",
                  ncores, Sys.getenv("TWOSTAGEPC_NCORES", unset = "(default)")))
  cl <- makeCluster(ncores)
  registerDoSNOW(cl)
  if (length(export_vars) > 0) {
    clusterExport(cl, export_vars, envir = envir)
  }
  clusterEvalQ(cl, {
    source("R/utils.R")
    sim_limit_threads()
    source("R/sim_dgp_config.R")
    source("R/sim_estimators.R")
    source("R/sim_core.R")
    if (requireNamespace("keras3", quietly = TRUE)) {
      library(keras3)
      sim_configure_tensorflow()
    }
    invisible(NULL)
  })
  cl
}

#' Run nsim replications per sample size n; checkpoint .Rdata + summary CSV after each n.
#' Within each n, runs in chunks of SIM_PROGRESS_CHUNK with progress + memory logs.
#' @param rep_fun_name name of replication function (must be clusterExport'd to workers).
#' @param checkpoint_objects named list of extra objects to store in the .Rdata checkpoint.
#' @param cl optional parallel cluster (for worker RSS in progress logs).
sim_save_checkpoint <- function(outfile, result_all, ns, nsim, checkpoint_objects) {
  ckpt <- new.env(parent = emptyenv())
  to_save <- c(list(result = result_all, ns = ns, nsim = nsim), checkpoint_objects)
  for (nm in names(to_save)) assign(nm, to_save[[nm]], envir = ckpt)
  save(list = names(to_save), file = outfile, envir = ckpt)
  invisible(nrow(result_all))
}

sim_recycle_cluster <- function(cl, export_vars, envir) {
  if (!is.null(cl)) {
    tryCatch(stopCluster(cl), error = function(e) NULL)
  }
  cl_new <- sim_cluster(export_vars, envir = envir)
  registerDoSNOW(cl_new)
  cl_new
}

sim_run_by_n <- function(ns, nsim, spec, rep_fun_name, outfile, rho_true, meta,
                         checkpoint_objects = list(), cl = NULL,
                         cluster_export = character(0),
                         cluster_envir = parent.frame()) {
  chunk_size <- sim_progress_chunk(nsim)
  recycle_workers <- isTRUE(spec$needs_keras) && length(cluster_export) > 0L
  result_all <- NULL
  if (file.exists(outfile)) {
    ck <- new.env(parent = emptyenv())
    load(outfile, envir = ck)
    if (exists("result", envir = ck, inherits = FALSE)) {
      result_all <- ck$result
      cat(sprintf("Resuming from checkpoint (%d rows) -> %s\n",
                  nrow(result_all), outfile))
    }
  }
  for (n_idx in seq_along(ns)) {
    n_val <- ns[[n_idx]]
    done <- 0L
    if (!is.null(result_all) && "n" %in% colnames(result_all)) {
      done <- sum(result_all[, "n"] == n_val)
    }
    if (done >= nsim) {
      cat(sprintf("\n--- n=%d (%d/%d) | B=%d — already complete (%d rows), skip ---\n",
                  n_val, n_idx, length(ns), nsim, done))
      next
    }
    cat(sprintf("\n--- n=%d (%d/%d) | B=%d | progress chunk=%d%s ---\n",
                n_val, n_idx, length(ns), nsim, chunk_size,
                if (done > 0L) sprintf(" | resume from rep %d", done + 1L) else ""))
    sim_log_progress(sprintf("n=%d start", n_val), cl = cl)
    rep_starts <- seq(if (done > 0L) done + 1L else 1L, nsim, by = chunk_size)
    for (start in rep_starts) {
      if (recycle_workers) {
        cl <- sim_recycle_cluster(cl, cluster_export, cluster_envir)
        sim_log_progress(sprintf("n=%d rep %d+ workers recycled (fresh TF)", n_val, start),
                         cl = cl)
      }
      end <- min(start + chunk_size - 1L, nsim)
      ii_seq <- start:end
      sim_log_progress(
        sprintf("n=%d rep %d-%d/%d running", n_val, start, end, nsim),
        cl = cl
      )
      t0 <- proc.time()
      chunk <- foreach(ii = ii_seq,
                       .combine = "rbind",
                       .packages = spec$pkgs) %dopar% {
        do.call(rep_fun_name, list(ii = ii, n_val = n_val))
      }
      elapsed <- sim_format_elapsed(proc.time() - t0)
      result_all <- if (is.null(result_all)) chunk else rbind(result_all, chunk)
      n_rows <- sim_save_checkpoint(outfile, result_all, ns, nsim, checkpoint_objects)
      write_sim_summary_csv(outfile, rho_true, meta)
      sim_log_progress(
        sprintf("n=%d rep %d-%d/%d done in %s | checkpoint %d rows -> %s",
                n_val, start, end, nsim, elapsed, n_rows, outfile),
        cl = cl
      )
      gc(verbose = FALSE)
    }
    sub <- result_all[result_all[, "n"] == n_val, , drop = FALSE]
    print(compute_metrics(sub, rho_true,
                          sprintf("%s_n%d", meta$method_label, n_val)))
    cat(sprintf("Checkpoint saved (%d rows) -> %s\n", nrow(result_all), outfile))
    gc(verbose = FALSE)
  }
  if (!is.null(cl)) {
    tryCatch(stopCluster(cl), error = function(e) NULL)
  }
  invisible(result_all)
}

sim_run_one <- function(dat, n, spec, method, estimator = NULL,
                        nn_args = sim_dnn_nn_args()) {
  if (!is.null(estimator) && estimator == "ensemble") {
    getRes_wrapper <- function(dat_train, dat_eval, formula) {
      getResEnsemble(dat_train, dat_eval, formula, nn_args = nn_args)
    }
    tmp <- run_fixed_ratio_estimate(
      dat$datX, dat$datY, n,
      getResFun = getRes_wrapper,
      ratio = 0.5
    )
    return(c(CauchyP = NA, tmp, K = NA, K0 = NA, passed = 1))
  }
  if (method == "adaptive") {
    out <- run_gof_and_estimate(
      dat$datX, dat$datY, n,
      testModelFun = spec$testModelFun,
      getResFun = spec$getResFun,
      rho_min = ADAPTIVE_RHO_MIN,
      rho_max = ADAPTIVE_RHO_MAX,
      rho_s = ADAPTIVE_RHO_STEP,
      alpha = ADAPTIVE_GOF_ALPHA,
      nsplits = ADAPTIVE_NSPLITS,
      split_method = ADAPTIVE_SPLIT_METHOD,
      getRes_args = spec$getRes_args
    )
    if (identical(spec$getResFun, getResNeu)) {
      sim_keras_gc()
    }
    out
  } else {
    tmp <- run_fixed_ratio_estimate(
      dat$datX, dat$datY, n,
      getResFun = spec$getResFun,
      ratio = 0.5,
      getRes_args = spec$getRes_args
    )
    c(CauchyP = NA, tmp, K = NA, K0 = NA, passed = 1)
  }
}

sim_parse_args <- function(min_args, usage) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < min_args) stop(usage)
  args
}

sim_parse_nsim_ns <- function(args, nsim_idx = 1L, ns_start_idx = 2L) {
  nsim <- if (length(args) >= nsim_idx) as.integer(args[nsim_idx]) else SIM_B
  ns <- if (length(args) >= ns_start_idx) as.integer(args[ns_start_idx:length(args)]) else SIM_NS
  list(nsim = nsim, ns = ns)
}

sim_gof_settings <- function() {
  list(
    n2_rule = GOF_N2_RULE,
    n2_coef = GOF_N2_COEF,
    split_method = GOF_SPLIT_METHOD,
    nsplits = GOF_NSPLITS,
    alpha = GOF_ALPHA
  )
}

sim_gof_settings_label <- function(settings = sim_gof_settings()) {
  n2_part <- switch(settings$n2_rule,
                    n2_cbrt = sprintf("n2=%g*n^(1/3)", settings$n2_coef),
                    n2_sqrt_n1 = sprintf("n2=%g*sqrt(n1)", settings$n2_coef),
                    n2_sqrt = sprintf("n2=%g*sqrt(n)", settings$n2_coef),
                    sprintf("rho_c=%g", 0.5))
  sprintf("%s | %s nsplits=%d", n2_part, settings$split_method, settings$nsplits)
}

sim_matrix_col <- function(result, name) {
  if (name %in% colnames(result)) {
    return(result[, name])
  }
  alt <- paste0(name, ".", name)
  if (alt %in% colnames(result)) {
    return(result[, alt])
  }
  stop(sprintf("missing column %s in simulation result", name), call. = FALSE)
}

sim_gof_one_rep <- function(ii, nsim, ns, design, p, Sigma, settings) {
  idx <- (ii - 1L) %/% nsim + 1L
  rep <- ((ii - 1L) %% nsim) + 1L
  set.seed(GOF_SEED_START + rep - 1L)
  n <- ns[idx]
  dat <- generate_data(n, p, design$dgp, Sigma)
  spec <- resolve_estimator(design$est)
  res <- run_gof_test(
    dat$datX, dat$datY, n,
    testModelFun = spec$testModelFun,
    n2_rule = settings$n2_rule,
    n2_coef = settings$n2_coef,
    split_method = settings$split_method,
    nsplits = settings$nsplits,
    alpha = settings$alpha
  )
  c(n = n, res)
}

sim_gof_pvalues_df <- function(result, design, nsim) {
  rep <- ((seq_len(nrow(result)) - 1L) %% nsim) + 1L
  data.frame(
    design = design$label,
    dgp = design$dgp,
    kind = design$kind,
    n = sim_matrix_col(result, "n"),
    rep = rep,
    seed = GOF_SEED_START + rep - 1L,
    gof_pvalue = sim_matrix_col(result, "CauchyP"),
    rejected = sim_matrix_col(result, "rejected"),
    n1 = sim_matrix_col(result, "n1"),
    n2 = sim_matrix_col(result, "n2"),
    ratio = sim_matrix_col(result, "ratio"),
    stringsAsFactors = FALSE
  )
}

sim_gof_print_rates <- function(result, ns) {
  for (n_val in ns) {
    sub <- result[result[, "n"] == n_val, , drop = FALSE]
    cat(sprintf("  n=%d: rejection rate = %.3f\n",
                n_val, mean(sub[, "rejected"], na.rm = TRUE)))
  }
}

sim_gof_calibration_summary <- function(all_results, designs, ns) {
  by_label <- setNames(designs, vapply(designs, function(x) x$label, ""))
  rows <- list()
  for (label in names(all_results)) {
    result <- all_results[[label]]
    dspec <- by_label[[label]]
    for (n_val in ns) {
      sub <- result[result[, "n"] == n_val, , drop = FALSE]
      rows[[length(rows) + 1]] <- data.frame(
        design = label,
        dgp = dspec$dgp,
        kind = dspec$kind,
        n = n_val,
        rejection_rate = round(mean(sub[, "rejected"], na.rm = TRUE), 3),
        avg_K = round(mean(sub[, "K"], na.rm = TRUE), 2),
        avg_K0 = round(mean(sub[, "K0"], na.rm = TRUE), 2),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

sim_gof_write_design <- function(result, design, nsim, ns, p, settings) {
  outfile <- results_path_gof(sprintf("sim_gof_%s_B%d.Rdata", design$label, nsim))
  save(result, ns, nsim, p, settings, design, file = outfile)
  pval_path <- results_path_gof(sprintf("sim_gof_%s_B%d_pvalues.csv", design$label, nsim))
  write.csv(sim_gof_pvalues_df(result, design, nsim), pval_path, row.names = FALSE)
  cat(sprintf("Saved %s\n", outfile))
  cat(sprintf("Saved %s\n", pval_path))
  sim_gof_print_rates(result, ns)
  invisible(list(rdata = outfile, pvalues = pval_path))
}
