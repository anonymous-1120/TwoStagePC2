# lib/ccov/ccov.R -- cumulative covariance GoF test (splits, Cauchy combine, ccovTest)

CAUCHY_P_LO <- 0.005
CAUCHY_P_HI <- 0.995

clip_pvalue <- function(p, lo = CAUCHY_P_LO, hi = CAUCHY_P_HI) {
  pmax(lo, pmin(hi, p))
}

cauchy_combine_pvalues <- function(p) {
  p <- clip_pvalue(p)
  0.5 - atan(mean(tan((0.5 - p) * pi))) / pi
}

combine_cauchy_xy <- function(testResY, testResX) {
  nfold <- length(testResY$singleSplit.results)
  p.v <- numeric(2 * nfold)
  for (i in seq_len(nfold)) {
    p.v[2 * i - 1] <- testResY$singleSplit.results[[i]]$p.value
    p.v[2 * i]     <- testResX$singleSplit.results[[i]]$p.value
  }
  cauchy_combine_pvalues(p.v)
}

ccov_pvalue <- function(testn) {
  1 - 2 * abs(0.5 - pnorm(testn))
}

ccov_sin <- function(testModel, datset, ne, selFun) {
  nr <- nrow(datset)
  nt <- nr - ne
  trainIn <- sample(seq_len(nr), nt)
  datT <- datset[trainIn, , drop = FALSE]
  datE <- datset[-trainIn, , drop = FALSE]
  testMod <- testModel(Train.data = datT, Validation.data = datE, selFun = selFun)
  list(norm = testMod$testn, p.value = ccov_pvalue(testMod$testn))
}

partition_folds <- function(n, K) {
  base <- n %/% K
  rem <- n %% K
  sizes <- rep(base, K)
  if (rem > 0) sizes[seq_len(rem)] <- sizes[seq_len(rem)] + 1
  folds <- rep(seq_len(K), times = sizes)
  folds <- sample(folds)
  split(seq_len(n), folds)
}

ccov_kfold_sin <- function(testModel, datset, fold_id, K, selFun) {
  fold_list <- partition_folds(nrow(datset), K)
  evalIn <- fold_list[[fold_id]]
  trainIn <- setdiff(seq_len(nrow(datset)), evalIn)
  datT <- datset[trainIn, , drop = FALSE]
  datE <- datset[evalIn, , drop = FALSE]
  testMod <- testModel(Train.data = datT, Validation.data = datE, selFun = selFun)
  list(norm = testMod$testn, p.value = ccov_pvalue(testMod$testn))
}

ccov_kfold_multi <- function(testModel, data, K, K0, selFun) {
  K0 <- min(K0, K)
  spliDat <- vector("list", K0)
  for (j in seq_len(K0)) {
    spliDat[[j]] <- ccov_kfold_sin(
      testModel = testModel,
      datset = data,
      fold_id = j,
      K = K,
      selFun = selFun
    )
  }
  pvdat <- vapply(spliDat, function(x) x$p.value, numeric(1))
  list(
    meanPv = mean(pvdat),
    medianPv = stats::median(pvdat),
    minPv = min(pvdat),
    CauchyP = cauchy_combine_pvalues(pvdat),
    spliDat = spliDat,
    K = K,
    K0 = K0
  )
}

ccov_multi <- function(testModel, data, nsplits, ne, selFun,
                       split_method = c("random", "kfold"),
                       K = NULL, K0 = NULL) {
  split_method <- match.arg(split_method)
  if (split_method == "kfold") {
    if (is.null(K) || is.null(K0)) {
      stop("K-fold splitting requires both K and K0.")
    }
    return(ccov_kfold_multi(
      testModel = testModel,
      data = data,
      K = K,
      K0 = K0,
      selFun = selFun
    ))
  }
  spliDat <- vector("list", nsplits)
  for (j in seq_len(nsplits)) {
    spliDat[[j]] <- ccov_sin(
      testModel = testModel,
      selFun = selFun,
      datset = data,
      ne = ne
    )
  }
  pvdat <- vapply(spliDat, function(x) x$p.value, numeric(1))
  list(
    meanPv = mean(pvdat),
    medianPv = stats::median(pvdat),
    minPv = min(pvdat),
    CauchyP = cauchy_combine_pvalues(pvdat),
    spliDat = spliDat
  )
}

ccovTest <- function(testModel, data, nsplits = 2, selFun = dcPre(),
                     ne = max(ceiling(3 * nrow(data)^(1/4)), 10),
                     ratio = 1 - ne / nrow(data),
                     split_method = c("random", "kfold"),
                     K = NULL, K0 = NULL, kappa = NULL,
                     quiet = FALSE) {
  split_method <- match.arg(split_method)
  if (!missing(ne) && !missing(ratio)) {
    if (abs(ratio + ne / nrow(data) - 1) <= 1e-2) {
      warning("specify 'ne' or 'ratio' but not both")
    } else {
      stop("specify 'ne' or 'ratio' but not both")
    }
  } else if (missing(ne) && !missing(ratio)) {
    ne <- floor((1 - ratio) * nrow(data))
  }
  if (split_method == "kfold") {
    if (is.null(K) && !is.null(kappa)) K <- floor(kappa) + 1
    if (is.null(K0) && !is.null(K)) K0 <- min(K, 3L)
    if (is.null(K) || is.null(K0)) {
      stop("K-fold splitting requires K and K0 (or kappa to derive K).")
    }
  }
  testRes <- ccov_multi(
    testModel = testModel,
    data = data,
    nsplits = nsplits,
    ne = ne,
    selFun = selFun,
    split_method = split_method,
    K = K,
    K0 = K0
  )
  if (!quiet) {
    message(paste("P-value (Cauchy combination): ", testRes$CauchyP))
  }
  invisible(list(
    pmean = testRes$meanPv,
    pmedian = testRes$medianPv,
    CauchyP = testRes$CauchyP,
    pmin = testRes$minPv,
    singleSplit.results = testRes$spliDat,
    K = testRes$K,
    K0 = testRes$K0
  ))
}
