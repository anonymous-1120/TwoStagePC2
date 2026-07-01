#' Residuals on evaluation data from an SVM regression fit on training data
#'
#' @inheritParams getResLM
#' @return Numeric vector of residuals on `dat_eval`.
getResSVM <- function(dat_train, dat_eval, formula) {
  rsp <- as.character(formula)[2]
  mod_train <- e1071::svm(formula, dat_train, kernel = "radial", cost = 10, gamma = 0.1)
  pred_eval <- stats::predict(mod_train, newdata = dat_eval)
  dat_eval[, rsp] - pred_eval
}
