#' Residuals on evaluation data from LASSO (glmnet); optional refit on selected predictors
#'
#' @inheritParams getResLM
#' @param refit If `1`, refit OLS on predictors with nonzero LASSO coefficients; otherwise use glmnet predictions.
#' @return Numeric vector of residuals on `dat_eval`.
getResLASSO <- function(dat_train, dat_eval, formula, refit = 1) {
  rsp <- as.character(formula)[2]
  mat_train <- model.matrix(formula, dat_train)[, setdiff(colnames(dat_train), rsp)]
  mat_eval <- model.matrix(formula, dat_eval)[, setdiff(colnames(dat_eval), rsp)]
  lasso_cv_lam <- glmnet::cv.glmnet(mat_train, dat_train[, rsp], alpha = 1)$lambda.min
  lasso_mod <- glmnet::glmnet(mat_train, dat_train[, rsp], alpha = 1, lambda = lasso_cv_lam)

  if (refit) {
    dat_train_sel <- cbind(
      dat_train[, rsp],
      dat_train[, setdiff(colnames(dat_train), rsp)][, which(as.array(!lasso_mod$beta == 0))]
    )
    dat_eval_sel <- cbind(
      dat_eval[, rsp],
      dat_eval[, setdiff(colnames(dat_eval), rsp)][, which(as.array(!lasso_mod$beta == 0))]
    )
    colnames(dat_train_sel)[1] <- rsp
    colnames(dat_eval_sel)[1] <- rsp

    getResLM(dat_train = dat_train_sel, dat_eval = dat_eval_sel, formula = formula)
  } else {
    pred_eval <- stats::predict(lasso_mod, mat_eval)
    dat_eval[, rsp] - pred_eval
  }
}
