# sim_estimators.R -- nuisance learner registry (OLS / SCAD / RF / DNN / ensemble)

resolve_estimator <- function(estimator) {
  switch(estimator,
         ols = list(
           testModelFun = function(formula) testLM(formula = formula),
           getResFun = getResLM,
           getRes_args = list(),
           pkgs = c("dplyr", "MASS"),
           needs_keras = FALSE
         ),
         scad = list(
           testModelFun = function(formula) testNcvreg(formula = formula, penalty = "SCAD"),
           getResFun = getResSCAD,
           getRes_args = list(),
           pkgs = c("dplyr", "ncvreg", "MASS"),
           needs_keras = FALSE
         ),
         rf = list(
           testModelFun = function(formula) testRF(formula = formula, ntree = 500),
           getResFun = getResRF,
           getRes_args = list(),
           pkgs = c("dplyr", "randomForest", "MASS"),
           needs_keras = FALSE
         ),
         dnn = list(
           testModelFun = function(formula) testNeu(formula = formula, activation = "sigmoid"),
           getResFun = getResNeu,
           getRes_args = sim_dnn_nn_args(),
           pkgs = c("dplyr", "keras3", "MASS"),
           needs_keras = TRUE
         ),
         ensemble = list(
           testModelFun = NULL,
           getResFun = NULL,
           getRes_args = list(),
           pkgs = c("dplyr", "ncvreg", "randomForest", "keras3", "MASS"),
           needs_keras = TRUE
         ),
         stop("Unknown estimator: ", estimator))
}

ols_feasible <- function(n, p) p < n
