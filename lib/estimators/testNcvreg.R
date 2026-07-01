testNcvreg <- function(formula, alpha = 1, penalty = "SCAD"){
  # return a function of train data and test data
  return(function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE){
    # obtain the response name
    Rsp <- as.character(formula)[2]
    # regressor data 
    XmatT <- model.matrix(formula,  Train.data)[,-1] 
    XmatE <- model.matrix(formula,  Validation.data)[,-1] 
    
    lasso_cvlamT <- ncvreg::cv.ncvreg(XmatT, Train.data[, Rsp], alpha = alpha, penalty=penalty)$lambda.min
    
    lassoModT <- ncvreg::ncvreg(XmatT, Train.data[, Rsp], alpha = alpha, penalty = penalty, lambda =lasso_cvlamT)
    
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
