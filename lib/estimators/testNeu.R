testNeu <- function(formula, Train.data, Validation.data, verbose = 0,
                    units = 100, epochs=20, batch_size=25, activation = "relu"){
  # return a function of train data and test data
  return(function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE){
    # obtain the response name
    Rsp <- as.character(formula)[2]
    # 
    # # regressor data 
    # XmatT <- model.matrix(formula,  Train.data)[,-which(colnames(Train.data)==Rsp)] 
    # XmatE <- model.matrix(formula,  Validation.data)[,-which(colnames(Train.data)==Rsp)] 
    
    tmp <- getResNeu(dat_train = Train.data, dat_eval = Validation.data, formula=formula,
              units = units, epochs = epochs, batch_size = batch_size,
              activation = activation, validation_split = .0)
    res <- tmp$resE
    predE <- tmp$predE
    predT <- tmp$predT
    rm(tmp)

        # fit neural network with 1 hidden layer
    # network <- keras::keras_model_sequential() %>%
    #   layer_dense(units = units, activation = activation, input_shape = c(ncol(XmatT))) %>%
    #   layer_batch_normalization() %>%
    #   layer_dropout(rate = .2) %>%
    #   # layer_dense(units = units/2, activation = activation) %>%
    #   # layer_batch_normalization() %>%
    #   # layer_dropout(rate = .2) %>%
    #   # layer_dense(units = units/4, activation = activation) %>%
    #   # layer_batch_normalization() %>%
    #   # layer_dropout(rate = .2) %>%
    #   # layer_dense(units = units/8, activation = activation) %>%
    #   # layer_batch_normalization() %>%
    #   # layer_dropout(rate = .2) %>%
    #   # layer_dense(units = units/16, activation = activation) %>%
    #   # layer_batch_normalization() %>%
    #   # layer_dropout(rate = .2) %>%
    #   layer_dense(units = 1)
    # 
    # network %>% keras::compile(
    #   optimizer = "rmsprop",
    #   loss = 'mse',
    #   metrics = c("mse")
    # )
    # 
    # network %>% keras::fit(XmatT, Train.data[, Rsp],  epochs = epochs, batch_size = batch_size, verbose = verbose)
    # 
    # #predict on the test set
    # predE <- network %>% keras::predict_on_batch(XmatE)
    # 
    # #predict on the training set
    # predT <- network %>% keras::predict_on_batch(XmatT)
    # 
    # # calculate the Pearson residual
    # res <-   (Train.data[, Rsp] -  predT)
    
    if(calCov){
      testn <- calCcov(formula, predT, predE, Train.data, Validation.data, selFun=selFun)
      return(list(predT = predT, predE = predE, res = res,
                  Rsp = Rsp, testn = testn))
    }else{
      return(list(predT = predT, predE = predE, res = res,
                  Rsp = Rsp))
    }
  })
}
