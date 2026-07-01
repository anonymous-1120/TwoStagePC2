#' Residuals on evaluation data from a small Keras neural net with dcPre variable screening
#'
#' @inheritParams getResLM
#' @param units,epochs,batch_size,activation,validation_split,verbose Passed to [keras3::fit].
#' @return List with `resE`, `predE`, `predT` (evaluation residuals and predictions).
getResNeu <- function(
    dat_train,
    dat_eval,
    formula,
    units = 100,
    epochs = 20,
    batch_size = 25,
    activation = "relu",
    validation_split = 0.1,
    verbose = 0) {
  if (exists("sim_configure_tensorflow", mode = "function")) {
    sim_configure_tensorflow()
  }
  rsp <- as.character(formula)[2]
  x_train <- model.matrix(formula, dat_train)[, -which(colnames(dat_train) == rsp)]
  x_eval <- model.matrix(formula, dat_eval)[, -which(colnames(dat_eval) == rsp)]

  dcs <- dcPre(npreSel = 5)
  tmp <- data.frame(x_train)
  tmp$res <- dat_train[, rsp]
  res <- dcs(tmp, ".")$parVarNew
  x_train <- x_train[, res]
  x_eval <- x_eval[, res]

  network <- keras3::keras_model_sequential() %>%
    layer_dense(units = units, activation = activation, input_shape = c(ncol(x_train))) %>%
    layer_batch_normalization() %>%
    layer_dropout(rate = 0.2) %>%
    layer_dense(units = units / 2, activation = activation) %>%
    layer_batch_normalization() %>%
    layer_dropout(rate = 0.2) %>%
    layer_dense(units = units / 4, activation = activation) %>%
    layer_batch_normalization() %>%
    layer_dense(units = 1)

  compile(
    network,
    optimizer = "rmsprop",
    loss = "mse",
    metrics = c("mse")
  )

  fit(
    network,
    x_train,
    dat_train[, rsp],
    epochs = epochs,
    batch_size = batch_size,
    validation_split = validation_split,
    verbose = verbose
  )

  pred_train <- predict_on_batch(network, x_train)
  pred_eval <- predict_on_batch(network, x_eval)
  res_eval <- dat_eval[, rsp] - pred_eval
  out <- list(resE = res_eval, predE = pred_eval, predT = pred_train)
  rm(network, x_train, x_eval, pred_train, pred_eval, res_eval, dcs, tmp, res)
  if (exists("sim_keras_gc", mode = "function")) {
    sim_keras_gc()
  } else if (requireNamespace("keras3", quietly = TRUE)) {
    keras3::clear_session()
    gc(verbose = FALSE)
  }
  out
}
