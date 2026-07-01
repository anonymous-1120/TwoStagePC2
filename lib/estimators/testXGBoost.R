testXGBoost <- function(formula, params = list(), nrounds = 25){
  # return a function of train data and test data
  testModel <- function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE){
    # obtain the response name
    Rsp <- as.character(formula)[2]
    # regressor data
    XmatT <- stats::model.matrix(formula,  Train.data)[,-1]
    XmatE <- stats::model.matrix(formula,  Validation.data)[,-1]
    # fit xgboost
    xgModT <- xgboost::xgboost(data = XmatT, label = Train.data[, Rsp], params = params, nrounds = nrounds, verbose = 0)
    
    #predict on the test set
    predE <- stats:: predict(xgModT, XmatE)
    
    #predict on the training set
    predT <- stats:: predict(xgModT, XmatT)
    
    # calculate the residual
    res <-   Train.data[, Rsp] -  predT
    
    if(calCov){
      testn <- calCcov(formula, predT, predE, Train.data, Validation.data, selFun=selFun)
      return(list(predT = predT, predE = predE, res = res,
                  Rsp = Rsp, testn = testn))
    }else{
      return(list(predT = predT, predE = predE, res = res,
                  Rsp = Rsp))
    }
  }
  return(testModel)
}
