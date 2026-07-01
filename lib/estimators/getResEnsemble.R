#' Ensemble residual learner: average SCAD, RF, and neural network predictions.
#'
#' @inheritParams getResLM
#' @param nn_args Named list passed to `getResNeu` (units, epochs, etc.).
#' @return Numeric vector of residuals on `dat_eval`.
getResEnsemble <- function(dat_train, dat_eval, formula, nn_args = list()) {
  rsp <- as.character(formula)[2]

  res_scad <- getResSCAD(dat_train = dat_train, dat_eval = dat_eval, formula = formula)
  res_rf <- getResRF(dat_train = dat_train, dat_eval = dat_eval, formula = formula)

  nn_call <- c(
    list(dat_train = dat_train, dat_eval = dat_eval, formula = formula),
    nn_args
  )
  res_nn <- do.call(getResNeu, nn_call)
  if (is.list(res_nn)) res_nn <- res_nn$resE

  pred_scad <- dat_eval[, rsp] - res_scad
  pred_rf <- dat_eval[, rsp] - res_rf
  pred_nn <- dat_eval[, rsp] - res_nn

  pred_ens <- (pred_scad + pred_rf + pred_nn) / 3
  dat_eval[, rsp] - pred_ens
}
