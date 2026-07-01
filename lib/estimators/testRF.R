testRF <- function(formula, ntree = 500, mtry = NULL, maxnodes = NULL){
  # return a function of train data and test data
  testModel <- function(Train.data, Validation.data, selFun = dcPre(), calCov=TRUE){
    if (is.null(mtry)){
      mtry <- max(floor( length( dim(stats::model.matrix(formula ,Train.data))[2]-1)/3),1)
    }
    
    # obtain the response name
    Rsp <- as.character(formula)[2]
    
    RspDat <- Train.data[,Rsp]
    
    resRf <- randomForest::randomForest(formula, data = Train.data, ntree = ntree,  maxnodes = maxnodes, mtry = mtry, importance=FALSE)
    # obtain random forest prediction on the training set
    predT <-  as.numeric(stats:: predict(resRf, newdata = Train.data))
    # obtain random forest prediction on the test set
    predE <-  as.numeric(stats:: predict(resRf, newdata = Validation.data))
    
    # calculate the Pearson residual
    # res <-   (RspDat -  predT)/sqrt(predT * (1 - predT ))
    res <-   (RspDat -  predT)
    
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
