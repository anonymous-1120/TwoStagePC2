# utils.R -- shared sources, libraries, and helper functions
#
# Library layout: lib/ccov/, lib/estimators/, lib/inference/
# Entry-point scripts (sim_*.R, run_sim_*.sh) live in the repository root.

source("R/sim_dgp_config.R")

source_lib <- function(subdir, file) {
  source(file.path("lib", subdir, file))
}

source_lib("ccov", "ccov.R")
for (f in list.files(file.path("lib", "estimators"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
source_lib("inference", "inference.R")

suppressPackageStartupMessages({
  library(parallel)
  library(doSNOW)
  library(dplyr)
  library(MASS)
})

#' CPUs visible to this job (Slurm allocation or host).
sim_available_cpus <- function() {
  for (v in c("SLURM_CPUS_PER_TASK", "SLURM_CPUS_ON_NODE", "TWOSTAGEPC_AVAILABLE_CPUS")) {
    raw <- Sys.getenv(v, unset = "")
    if (nzchar(raw)) return(as.integer(raw))
  }
  detectCores()
}

#' Force BLAS / TensorFlow env to single-thread (call before keras3 / tensorflow import).
sim_limit_threads <- function() {
  vars <- c(
    OMP_NUM_THREADS = "1",
    OPENBLAS_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    NUMEXPR_NUM_THREADS = "1",
    OMP_THREAD_LIMIT = "1",
    TF_NUM_INTRAOP_THREADS = "1",
    TF_NUM_INTEROP_THREADS = "1",
    TF_ENABLE_ONEDNN_OPTS = "0"
  )
  do.call(Sys.setenv, as.list(vars))
  invisible(NULL)
}

#' R + TensorFlow/Keras seeds for reproducible DNN / ensemble (call after sim_limit_threads).
sim_set_tensorflow_seed <- function(seed) {
  seed <- as.integer(seed)[1L]
  sim_limit_threads()
  Sys.setenv(
    TF_DETERMINISTIC_OPS = "1",
    TF_CUDNN_DETERMINISTIC = "1",
    PYTHONHASHSEED = as.character(seed),
    CUDA_VISIBLE_DEVICES = ""
  )
  if (requireNamespace("keras3", quietly = TRUE)) {
    if (!"package:keras3" %in% search()) {
      library(keras3)
    }
    sim_configure_tensorflow()
    keras3::set_random_seed(seed)
  }
  if (requireNamespace("reticulate", quietly = TRUE)) {
    tryCatch({
      np <- reticulate::import("numpy")
      np$random$seed(seed)
      tf <- reticulate::import("tensorflow")
      tf$random$set_seed(seed)
    }, error = function(e) NULL)
  }
  invisible(seed)
}

#' Set R and (optionally) TensorFlow RNG before a reproducible learner run.
sim_begin_reproducible <- function(seed, keras = FALSE) {
  seed <- as.integer(seed)[1L]
  set.seed(seed)
  if (isTRUE(keras)) {
    sim_set_tensorflow_seed(seed)
  }
  invisible(seed)
}

#' TensorFlow Python API: 1 intra + 1 inter op thread (call after library(keras3)).
sim_configure_tensorflow <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    return(invisible(NULL))
  }
  tryCatch({
    tf <- reticulate::import("tensorflow")
    tf$config$threading$set_intra_op_parallelism_threads(1L)
    tf$config$threading$set_inter_op_parallelism_threads(1L)
  }, error = function(e) {
    invisible(NULL)
  })
  invisible(NULL)
}

#' Env + TF config for DNN workers (env first, then keras3, then configure).
sim_limit_tensorflow <- function() {
  sim_limit_threads()
  if (requireNamespace("keras3", quietly = TRUE)) {
    if (!"package:keras3" %in% search()) {
      library(keras3)
    }
    sim_configure_tensorflow()
  }
  invisible(NULL)
}

#' Drop Keras/TF graphs and nudge Python + R GC (call after each DNN fit or rho step).
sim_keras_gc <- function() {
  if (requireNamespace("keras3", quietly = TRUE)) {
    tryCatch(keras3::clear_session(), error = function(e) NULL)
  }
  if (requireNamespace("reticulate", quietly = TRUE)) {
    tryCatch(
      reticulate::py_run_string("import gc; gc.collect()"),
      error = function(e) NULL
    )
  }
  gc(verbose = FALSE)
  invisible(NULL)
}

sim_progress_chunk <- function(nsim) {
  raw <- Sys.getenv("TWOSTAGEPC_PROGRESS_CHUNK", unset = "")
  chunk <- if (nzchar(raw)) as.integer(raw) else SIM_PROGRESS_CHUNK
  chunk <- if (is.na(chunk) || chunk < 1L) SIM_PROGRESS_CHUNK else chunk
  as.integer(min(chunk, nsim))
}

sim_proc_kb <- function(path, key) {
  if (!file.exists(path)) return(NA_real_)
  lines <- readLines(path, warn = FALSE)
  hit <- grep(paste0("^", key, ":"), lines, value = TRUE)
  if (length(hit) == 0) return(NA_real_)
  as.numeric(gsub("[^0-9]", "", hit[1]))
}

#' Master + system (+ optional worker cluster) memory in MiB.
sim_memory_snapshot <- function(cl = NULL) {
  master_mb <- sim_proc_kb("/proc/self/status", "VmRSS") / 1024
  avail_mb <- sim_proc_kb("/proc/meminfo", "MemAvailable") / 1024
  total_mb <- sim_proc_kb("/proc/meminfo", "MemTotal") / 1024
  workers_mb <- NULL
  if (!is.null(cl)) {
    workers_mb <- tryCatch(
      unlist(clusterCall(cl, function() {
        line <- grep("^VmRSS:", readLines("/proc/self/status", n = 50), value = TRUE)
        as.numeric(gsub("[^0-9]", "", line)) / 1024
      }), use.names = FALSE),
      error = function(e) NULL
    )
  }
  list(master_mb = master_mb, mem_avail_mb = avail_mb, mem_total_mb = total_mb,
       workers_mb = workers_mb)
}

sim_format_elapsed <- function(proc) {
  secs <- unname(proc[3])
  if (is.na(secs) || secs < 60) sprintf("%.1fs", secs) else sprintf("%.1fm", secs / 60)
}

#' Timestamped progress line with memory; flushed for nohup/log tailing.
sim_log_progress <- function(msg, cl = NULL) {
  snap <- sim_memory_snapshot(cl)
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  worker_line <- ""
  w <- snap$workers_mb
  if (!is.null(w) && length(w) > 0) {
    worker_line <- sprintf(
      " | workers RSS min/mean/max/sum=%.0f/%.0f/%.0f/%.0f MiB",
      min(w), mean(w), max(w), sum(w)
    )
  }
  cat(sprintf(
    "[%s] %s | master=%.0f MiB | sys avail=%.0f/%.0f MiB%s\n",
    ts, msg, snap$master_mb, snap$mem_avail_mb, snap$mem_total_mb, worker_line
  ))
  flush.console()
  invisible(snap)
}

#' Parallel worker count for foreach simulations.
#' Uses TWOSTAGEPC_NCORES when set (bash scripts/run_sim_*.sh caps to allocated CPUs).
sim_cluster_cores <- function(default = NULL) {
  avail <- sim_available_cpus()
  n <- Sys.getenv("TWOSTAGEPC_NCORES", unset = "")
  cores <- if (nzchar(n)) as.integer(n) else if (!is.null(default)) as.integer(default) else avail
  as.integer(min(cores, avail))
}

sim_limit_threads()

z_t <- function(rho) log((1 + rho) / (1 - rho)) / 2

#' Training fraction n1/n (readable split size; internal K-fold still uses kappa = n1/n2).
train_frac <- function(n1, n2) {
  n1 / (n1 + n2)
}

generate_cov_matrix <- function(p, type = "ar", rho_ar = 0.5, n_active = 5) {
  Sigma <- matrix(0, p + 1, p + 1)
  if (type == "ar") {
    for (i in 1:(p + 1))
      for (j in 1:(p + 1))
        Sigma[i, j] <- rho_ar^abs(i - j)
  } else if (type == "block") {
    for (i in 1:(p + 1))
      for (j in 1:(p + 1)) {
        Sigma[i, j] <- rho_ar^abs(i - j)
        if ((i > n_active | j > n_active) & i != j) Sigma[i, j] <- 0
      }
  }
  Sigma
}

generate_data <- function(n, p, model, Sigma) {
  X.z <- mvrnorm(n, rep(0, p + 1), Sigma)
  X <- X.z[, 1]
  z <- X.z[, 2:(p + 1)]
  eps <- rnorm(n)

  if (model == "linear") {
    bgamma <- rnorm(p + 1, 1)
    bgamma[1] <- SIM_BETA_X
    Y <- X.z %*% bgamma + eps
  } else if (model == "sparse_linear") {
    bgamma <- c(rep(1, 5), rep(0, p - 4)) * rnorm(p + 1, 1)
    bgamma[1] <- SIM_BETA_X
    Y <- cbind(X, z) %*% bgamma + eps
  } else if (model == "nonlinear") {
    nl <- SIM_NONLINEAR_COEF
    Y <- SIM_BETA_X * X + nl * (z[, 1]^2 + sin(z[, 2]) + cos(z[, 3]) + abs(z[, 4])) + eps
  }

  datY <- data.frame(y = Y, z = z)
  datX <- data.frame(x = X, z = z)
  list(datX = datX, datY = datY, X = X, z = z, Y = Y)
}

split_params_from_ratio <- function(n1, n2) {
  kappa <- n1 / n2
  # K = floor(kappa) + 1 requires kappa >= 1 (training set at least as large as eval)
  K <- max(2L, floor(kappa) + 1L)
  K0 <- min(K, ADAPTIVE_K0_MAX)
  list(kappa = kappa, K = K, K0 = K0)
}

#' Sample sizes for GoF / partial-correlation splits.
#' @param n2_rule `"rho"`: n1 = ceiling(n * rho_c);
#'   `"n2_sqrt"`: n2 = ceiling(n2_coef * n^(1/2)), n1 = n - n2;
#'   `"n2_sqrt_n1"`: n1 + n2 = n with n2 = ceiling(n2_coef * sqrt(n1));
#'   `"n2_cbrt"`: n2 = ceiling(n2_coef * n^(1/3)).
split_sizes <- function(n, n2_rule = c("rho", "n2_sqrt", "n2_sqrt_n1", "n2_cbrt"),
                        rho_c = 0.5, n2_coef = 2) {
  n2_rule <- match.arg(n2_rule)
  if (n2_rule == "n2_sqrt") {
    n2 <- ceiling(n2_coef * sqrt(n))
    n2 <- max(1L, min(n2, n - 1L))
    n1 <- n - n2
  } else if (n2_rule == "n2_sqrt_n1") {
    n1 <- NA_integer_
    for (cand in seq.int(n - 1L, 1L)) {
      n2 <- ceiling(n2_coef * sqrt(cand))
      if (cand + n2 == n) {
        n1 <- cand
        break
      }
    }
    if (is.na(n1)) {
      n1 <- max(1L, min(n - 1L, round((sqrt(1 + n) - 1)^2)))
    }
    n2 <- n - n1
  } else if (n2_rule == "n2_cbrt") {
    n2 <- ceiling(n2_coef * n^(1 / 3))
    n2 <- max(1L, min(n2, n - 1L))
    n1 <- n - n2
  } else {
    n1 <- ceiling(n * rho_c)
    n2 <- n - n1
  }
  c(n1 = n1, n2 = n2)
}

run_gof_test <- function(datX, datY, n, testModelFun,
                         formula_x = x ~ ., formula_y = y ~ .,
                         rho_c = 0.5, n2_rule = c("rho", "n2_sqrt", "n2_sqrt_n1", "n2_cbrt"),
                         n2_coef = 2, nsplits = 1,
                         split_method = c("kfold", "random"),
                         alpha = 0.05) {
  split_method <- match.arg(split_method)
  n2_rule <- match.arg(n2_rule)
  sz <- split_sizes(n, n2_rule = n2_rule, rho_c = rho_c, n2_coef = n2_coef)
  n1 <- as.integer(unname(sz["n1"]))
  n2 <- as.integer(unname(sz["n2"]))
  sp <- split_params_from_ratio(n1, n2)
  out_K <- if (split_method == "kfold") sp$K else NA_real_
  out_K0 <- if (split_method == "kfold") sp$K0 else nsplits

  testModelX <- testModelFun(formula = formula_x)
  testModelY <- testModelFun(formula = formula_y)

  ccov_args <- list(ne = n2, data = NULL, quiet = TRUE)
  if (split_method == "kfold") {
    ccov_args$split_method <- "kfold"
    ccov_args$K <- sp$K
    ccov_args$K0 <- sp$K0
    ccov_args$kappa <- sp$kappa
  } else {
    ccov_args$split_method <- "random"
    ccov_args$nsplits <- nsplits
  }

  ccov_args$data <- datX
  ccov_args$testModel <- testModelX
  testResX <- do.call(ccovTest, ccov_args)
  ccov_args$data <- datY
  ccov_args$testModel <- testModelY
  testResY <- do.call(ccovTest, ccov_args)

  CauchyP <- combine_cauchy_xy(testResY, testResX)
  c(
    CauchyP = CauchyP,
    rejected = as.numeric(CauchyP <= alpha),
    n1 = n1, n2 = n2,
    ratio = unname(sp$kappa), K = out_K, K0 = out_K0,
    passed = as.numeric(CauchyP > alpha)
  )
}

run_gof_and_estimate <- function(datX, datY, n, testModelFun, getResFun,
                                 formula_x = x ~ ., formula_y = y ~ .,
                                 rho_min = 0.5, rho_max = 0.95, rho_s = 0.05,
                                 nsplits = 2, alpha = 0.05,
                                 split_method = c("kfold", "random"),
                                 getRes_args = list()) {
  split_method <- match.arg(split_method)
  rho_c <- rho_min
  CauchyP <- 0
  n1 <- NA
  n2 <- NA
  K <- NA
  K0 <- NA
  kappa <- NA
  keras_cleanup <- identical(getResFun, getResNeu)
  testModelX <- testModelFun(formula = formula_x)
  testModelY <- testModelFun(formula = formula_y)

  while (TRUE) {
    n1 <- ceiling(n * rho_c)
    n2 <- n - n1
    sp <- split_params_from_ratio(n1, n2)
    kappa <- sp$kappa
    if (split_method == "kfold") {
      K <- sp$K
      K0 <- sp$K0
    } else {
      K <- NA
      K0 <- nsplits
    }

    ccov_args <- list(ne = n2, quiet = TRUE)
    if (split_method == "kfold") {
      ccov_args$split_method <- "kfold"
      ccov_args$K <- sp$K
      ccov_args$K0 <- sp$K0
      ccov_args$kappa <- kappa
    } else {
      ccov_args$split_method <- "random"
      ccov_args$nsplits <- nsplits
    }

    ccov_args$testModel <- testModelX
    ccov_args$data <- datX
    testResX <- do.call(ccovTest, ccov_args)
    ccov_args$testModel <- testModelY
    ccov_args$data <- datY
    testResY <- do.call(ccovTest, ccov_args)

    CauchyP <- combine_cauchy_xy(testResY, testResX)
    rm(testResX, testResY, ccov_args)
    if (keras_cleanup) {
      sim_keras_gc()
    } else {
      gc(verbose = FALSE)
    }

    if (rho_c > rho_max | CauchyP > alpha) break
    rho_c <- rho_c + rho_s
  }

  if (CauchyP > alpha) {
    trainIn <- sample(seq_len(n), n1)
    datXT <- datX[trainIn, , drop = FALSE]
    datXE <- datX[-trainIn, , drop = FALSE]
    datYT <- datY[trainIn, , drop = FALSE]
    datYE <- datY[-trainIn, , drop = FALSE]

    args_x <- c(list(dat_train = datXT, dat_eval = datXE, formula = formula_x), getRes_args)
    args_y <- c(list(dat_train = datYT, dat_eval = datYE, formula = formula_y), getRes_args)
    resX <- do.call(getResFun, args_x)
    resY <- do.call(getResFun, args_y)
    if (is.list(resX)) resX <- resX$resE
    if (is.list(resY)) resY <- resY$resE

    rho_hat <- cor(resY, resX)
    zrho    <- z_t(rho_hat)
    if (keras_cleanup) {
      rm(resX, resY, datXT, datXE, datYT, datYE, args_x, args_y, testModelX, testModelY)
      sim_keras_gc()
    }
    return(c(
      CauchyP = CauchyP, rho_hat = rho_hat, zrho = zrho,
      n1 = n1, n2 = n2, ratio = kappa, K = K, K0 = K0, passed = 1
    ))
  }
  rm(testModelX, testModelY)
  if (keras_cleanup) {
    sim_keras_gc()
  }
  c(
    CauchyP = CauchyP, rho_hat = NA, zrho = NA,
    n1 = NA, n2 = NA, ratio = NA, K = K, K0 = K0, passed = 0
  )
}

run_fixed_ratio_estimate <- function(datX, datY, n, getResFun,
                                     formula_x = x ~ ., formula_y = y ~ .,
                                     ratio = 0.5,
                                     getRes_args = list()) {
  n1 <- round(n * ratio)
  n2 <- n - n1
  trainIn <- sample(1:n, n1)
  datXT <- datX[trainIn, ];  datXE <- datX[-trainIn, ]
  datYT <- datY[trainIn, ];  datYE <- datY[-trainIn, ]

  args_x <- c(list(dat_train = datXT, dat_eval = datXE, formula = formula_x), getRes_args)
  args_y <- c(list(dat_train = datYT, dat_eval = datYE, formula = formula_y), getRes_args)
  resX <- do.call(getResFun, args_x)
  resY <- do.call(getResFun, args_y)
  if (is.list(resX)) resX <- resX$resE
  if (is.list(resY)) resY <- resY$resE

  rho_hat <- cor(resY, resX)
  zrho    <- z_t(rho_hat)
  kappa   <- n1 / n2
  c(rho_hat = rho_hat, zrho = zrho, n1 = n1, n2 = n2, ratio = kappa)
}

compute_metrics <- function(results, rho_true, method_name) {
  rho_hats <- results[, "rho_hat"]
  valid    <- !is.na(rho_hats)
  rho_hats <- rho_hats[valid]

  if (length(rho_hats) == 0) {
    return(data.frame(
      method = method_name, bias = NA, sd = NA, mse = NA,
      ci_coverage = NA, ci_length = NA, proportion = 0,
      avg_n1_over_n = NA, avg_n1 = NA, avg_n2 = NA, avg_K = NA, avg_K0 = NA
    ))
  }

  n2s <- results[valid, "n2"]
  bias <- mean(rho_hats) - rho_true
  sd_rho <- sd(rho_hats)
  mse <- mean((rho_hats - rho_true)^2)

  ci_low  <- rho_hats - qnorm(0.975) * (1 - rho_hats^2) / sqrt(n2s)
  ci_high <- rho_hats + qnorm(0.975) * (1 - rho_hats^2) / sqrt(n2s)
  ci_coverage <- mean(ci_low <= rho_true & rho_true <= ci_high)
  ci_length   <- mean(ci_high - ci_low)

  proportion <- if ("passed" %in% colnames(results))
    mean(results[, "passed"] == 1) else 1.0

  avg_n1_over_n <- if ("n1" %in% colnames(results) && "n2" %in% colnames(results))
    mean(train_frac(results[valid, "n1"], results[valid, "n2"]), na.rm = TRUE) else NA
  avg_n1 <- if ("n1" %in% colnames(results))
    mean(results[valid, "n1"], na.rm = TRUE) else NA
  avg_n2 <- if ("n2" %in% colnames(results))
    mean(results[valid, "n2"], na.rm = TRUE) else NA
  avg_K <- if ("K" %in% colnames(results))
    mean(results[valid, "K"], na.rm = TRUE) else NA
  avg_K0 <- if ("K0" %in% colnames(results))
    mean(results[valid, "K0"], na.rm = TRUE) else NA

  data.frame(
    method = method_name, bias = round(bias, 4),
    sd = round(sd_rho, 4), mse = round(mse, 4),
    ci_coverage = round(ci_coverage, 3),
    ci_length = round(ci_length, 3),
    proportion = round(proportion, 3),
    avg_n1_over_n = round(avg_n1_over_n, 3),
    avg_n1 = round(avg_n1, 1),
    avg_n2 = round(avg_n2, 1),
    avg_K = round(avg_K, 2),
    avg_K0 = round(avg_K0, 2)
  )
}
