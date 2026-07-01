#' Residuals on evaluation data from an OLS fit on training data
#'
#' @param dat_train,dat_eval Data frames with the same columns; training and hold-out sets.
#' @param formula Model formula; left-hand side is the response column.
#' @return Numeric vector of residuals (observed minus fitted) on `dat_eval`.
getResLM <- function(dat_train, dat_eval, formula) {
  rsp <- as.character(formula)[2]
  mod <- lm(formula, data = dat_train)
  pred_eval <- stats::predict(mod, dat_eval)
  dat_eval[, rsp] - pred_eval
}
