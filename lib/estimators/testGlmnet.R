testGlmnet <- function(formula, alpha = 1){
  # return a function of train data and test data
  return(function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE){
    # obtain the response name
    Rsp <- as.character(formula)[2]
    # regressor data 
    XmatT <- model.matrix(formula,  Train.data)[,setdiff(colnames(Train.data),Rsp)] 
    XmatE <- model.matrix(formula,  Validation.data)[,setdiff(colnames(Train.data),Rsp)] 
    # fit lasso regression
    lasso_cvlamT <- glmnet::cv.glmnet(XmatT, Train.data[, Rsp], alpha = alpha)$lambda.min
    lassoModT <- glmnet::glmnet(XmatT, Train.data[, Rsp], alpha = alpha, lambda = lasso_cvlamT)
    
    #predict on the test set
    predE <- stats:: predict(lassoModT, XmatE)
    
    #predict on the training set
    predT <- stats:: predict(lassoModT, XmatT)
    
    # calculate the residual
    res <-   (Train.data[, Rsp] -  predT)
    
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
