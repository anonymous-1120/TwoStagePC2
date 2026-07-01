#' Residuals on evaluation data from a random forest fit on training data
#'
#' @inheritParams getResLM
#' @return Numeric vector of residuals on `dat_eval`.
getResRF <- function(dat_train, dat_eval, formula) {
  rsp <- as.character(formula)[2]
  rsp_train <- dat_train[, rsp]
  rsp_eval <- dat_eval[, rsp]
  mtry <- max(floor(length(dim(stats::model.matrix(formula, dat_train))[2] - 1) / 3), 1)
  ntree <- 500
  maxnodes <- NULL

  res_rf <- randomForest::randomForest(
    formula,
    data = dat_train,
    ntree = ntree,
    maxnodes = maxnodes,
    mtry = mtry,
    importance = FALSE
  )
  pred_eval <- as.numeric(stats::predict(res_rf, newdata = dat_eval))
  rsp_eval - pred_eval
}
