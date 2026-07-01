testLM <- function (formula) 
{
  testModel <- function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE) {
    modT <- stats::lm(formula, Train.data)
    predT <- stats::predict(modT, newdata = Train.data, 
                            type = "response", se.fit = TRUE)$fit
    predE <- stats::predict(modT, newdata = Validation.data, 
                            type = "response", se.fit = TRUE)$fit
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
