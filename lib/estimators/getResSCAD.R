#' Residuals on evaluation data from SCAD/MCP (ncvreg); optional refit on selected predictors
#'
#' @inheritParams getResLM
#' @param alpha,penalty Passed to [ncvreg::ncvreg].
#' @param refit If `1`, refit OLS on predictors with nonzero coefficients; otherwise use ncvreg predictions.
#' @return Numeric vector of residuals on `dat_eval`.
getResSCAD <- function(dat_train, dat_eval, alpha = 1, penalty = "SCAD", refit = 1, formula) {
  rsp <- as.character(formula)[2]
  mat_train <- model.matrix(formula, dat_train)[, setdiff(colnames(dat_train), rsp)]
  mat_eval <- model.matrix(formula, dat_eval)[, setdiff(colnames(dat_eval), rsp)]
  lasso_cv_lam <- ncvreg::cv.ncvreg(mat_train, dat_train[, rsp], alpha = alpha, penalty = penalty)$lambda.min
  lasso_mod <- ncvreg::ncvreg(
    mat_train, dat_train[, rsp],
    alpha = alpha, penalty = penalty, lambda = lasso_cv_lam
  )

  if (refit) {
    dat_train_sel <- data.frame(cbind(
      dat_train[, rsp],
      dat_train[, setdiff(colnames(dat_train), rsp)][, which(as.array(!lasso_mod$beta[-1] == 0))]
    ))
    dat_eval_sel <- data.frame(cbind(
      dat_eval[, rsp],
      dat_eval[, setdiff(colnames(dat_eval), rsp)][, which(as.array(!lasso_mod$beta[-1] == 0))]
    ))
    colnames(dat_train_sel)[1] <- rsp
    colnames(dat_eval_sel)[1] <- rsp

    getResLM(dat_train = dat_train_sel, dat_eval = dat_eval_sel, formula = formula)
  } else {
    pred_eval <- stats::predict(lasso_mod, mat_eval)
    dat_eval[, rsp] - pred_eval
  }
}
