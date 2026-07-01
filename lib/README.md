# lib/ — core method implementation

The statistical method itself (goodness-of-fit test, nuisance estimators, inference),
independent of any particular simulation or dataset. Loaded by `R/utils.R`.

| File | Contents |
|------|----------|
| `ccov/ccov.R` | Cauchy combine (clip 0.005–0.995), random/K-fold splits, `ccovTest` |
| `estimators/*.R` | `test*.R` (first-stage) and `getRes*.R` (residual fitters) |
| `inference/inference.R` | `calCcov`, `Tnp`/`Snp`, `dcPre` |
