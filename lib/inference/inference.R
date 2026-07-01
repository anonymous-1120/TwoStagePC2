# lib/inference/inference.R -- U-statistic (Tnp/Snp), calCcov, dcPre preselection

dcPre <- function(npreSel = 5) {
  function(datRf, parVar) {
    nParV <- if (!identical(parVar, ".")) length(parVar) else ncol(datRf) - 1
    if (nParV > npreSel) {
      datRf_temp <- datRf
      datRf_temp$res <- NULL
      dcRes <- t(dcov::mdcor(datRf$res, datRf_temp))
      rownames(dcRes) <- colnames(datRf_temp)
      parVarNew <- colnames(datRf_temp)[order(-as.numeric(dcRes))[seq_len(npreSel)]]
      list(preSelected = TRUE, parVarNew = parVarNew, VI = dcRes)
    } else {
      list(preSelected = FALSE, parVarNew = parVar)
    }
  }
}

nm <- function(n, m) {
  nm <- 1
  for (i in n:(n - m + 1)) {
    nm <- nm * i
  }
  nm
}

Cnm <- function(n, m) {
  combinat::nCm(n, m)
}

getTnp <- function(dat, Rsp) {
  n <- nrow(as.matrix(dat))
  p <- ncol(as.matrix(dat)) - 1
  Xdat <- dat[, setdiff(colnames(dat), Rsp)]
  Ydat <- dat[, Rsp]
  Ybar <- mean(Ydat)
  if (p > 1) {
    orderX <- apply(Xdat, 2, order)
  } else {
    orderX <- order(Xdat)
  }
  Ydot <- matrix(Ydat[orderX] - Ybar, ncol = p)
  j.ind <- 2:n
  if (p > 1) {
    p1 <- (n - 2) * (n - 3) * sum(apply(Ydot, 2, cumsum)[-n, ]^2)
    p2 <- 2 * sum((n * j.ind - 2 * n - 2 * j.ind + 2) * rowSums(apply(Ydot, 2, cumsum)[-n, ] * Ydot[-1, ]))
    p3 <- -sum(rowSums(apply(Ydot^2, 2, cumsum)[-n, ]) * (n^2 - 2 * n * j.ind - n + 4 * j.ind - 4))
    p4 <- -n * (n^2 - 3 * n + 8) / 3 * sum(Ydot^2)
    p5 <- 2 * sum(rowSums(Ydot^2) * (0:(n - 1))^2)
    (p1 + p2 + p3 + p4 + p5) / nm(n, 5)
  } else {
    p1 <- (n - 2) * (n - 3) * sum(cumsum(Ydot)[-n]^2)
    p2 <- 2 * sum((n * j.ind - 2 * n - 2 * j.ind + 2) * cumsum(Ydot)[-n] * Ydot[-1])
    p3 <- -sum(cumsum(Ydot^2)[-n] * (n^2 - 2 * n * j.ind - n + 4 * j.ind - 4))
    p4 <- -n * (n^2 - 3 * n + 8) / 3 * sum(Ydot^2)
    p5 <- 2 * sum((Ydot^2) * (0:(n - 1))^2)
    (p1 + p2 + p3 + p4 + p5) / nm(n, 5)
  }
}

psi <- function(x1, x2, x3) {
  (x1 < x3) - (x2 < x3)
}

cn <- function(n) {
  ((1 - 1 / n)^2 + 1 / n^2)^2
}

K1 <- function(x1, x2) {
  x1^2 + x2^2 - 2 * pmax(x1, x2) + 2 / 3
}

getSnp <- function(dat, Rsp) {
  Xdat <- dat[, setdiff(colnames(dat), Rsp)]
  Ydat <- dat[, Rsp]
  n <- nrow(as.matrix(Xdat))
  p <- ncol(as.matrix(Xdat))
  p1 <- 1 / (4 * cn(n) * (n - 1) * n)
  Yd <- array(Ydat - mean(Ydat))
  K0 <- Yd %*% t(Yd)
  diag(K0) <- 0
  K0[lower.tri(K0)] <- 0
  if (p > 1) {
    cdfs <- apply(Xdat, 2, rank) / n
    for (i in 1:(n - 1)) {
      for (j in (i + 1):n) {
        K0[i, j] <- K0[i, j]^2 * sum(K1(cdfs[i, ], cdfs[j, ]))^2
      }
    }
  } else {
    cdfs <- rank(Xdat) / n
    for (i in 1:(n - 1)) {
      for (j in (i + 1):n) {
        K0[i, j] <- K0[i, j]^2 * sum(K1(cdfs[i], cdfs[j]))^2
      }
    }
  }
  sqrt(2 * p1 * sum(K0))
}

calCcov <- function(formula, predT, predE, Train.data, Validation.data, selFun = selFun) {
  Rsp <- as.character(formula)[2]
  Exp <- as.character(formula)[3]
  if (Exp == ".") {
    Xs <- setdiff(colnames(Train.data), Rsp)
  } else if (!stringr::str_detect(Exp, "\\+")) {
    Xs <- Exp
  } else {
    Xs <- c(stringr::str_split(Exp, " \\+ ", simplify = TRUE))
  }
  epsE <- Validation.data[, Rsp] - predE
  ExpX <- Validation.data[, Xs]
  dat <- data.frame(e = epsE, xs = ExpX)
  epsT <- Train.data[, Rsp] - predT
  ExpT <- Train.data[, Xs]
  datT <- data.frame(e = epsT, xs = ExpT)
  colnames(datT)[1] <- "res"
  colnames(dat)[1] <- "res"
  selRes <- selFun(datT, parVar = ExpX)
  if (selRes$preSelected) {
    selDat <- dat[, c("res", na.omit(selRes$parVarNew))]
  } else {
    selDat <- dat
  }
  Tnp <- getTnp(selDat, "res")
  Snp <- getSnp(selDat, "res")
  ne <- length(epsE)
  sqrt(ne * (ne - 1) / 2) * Tnp / Snp
}
