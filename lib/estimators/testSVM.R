testSVM <- function (formula, kernel="radial", cost=10, gamma=0.1) 
{
  testModel <- function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE) {
    modT <- e1071::svm(formula, Train.data, kernel=kernel, cost=cost, gamma=gamma)
    predT <- stats::predict(modT, newdata = Train.data)
    predE <- stats::predict(modT, newdata = Validation.data)
    res <- stats::resid(modT)
    Rsp <- as.character(formula)[2]
    
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
