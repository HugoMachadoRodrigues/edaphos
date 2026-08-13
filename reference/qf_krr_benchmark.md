# Benchmark quantum-foundation KRR against classical baselines

Runs four regressors on the same train/test split:

1.  `ranger` (QRF) over the RAW covariates (our established plain-ML
    baseline from the v1.3 `case-cerrado-end-to-end`).

2.  RBF Kernel Ridge Regression over the foundation-embedding PCs.

3.  Quantum Kernel Ridge Regression over the RAW covariates (Pillar 6
    original).

4.  Quantum Kernel Ridge Regression over the foundation-embedding PCs
    (the v2.0.0 contribution).

## Usage

``` r
qf_krr_benchmark(
  embeddings,
  covariates,
  y,
  train_ix = NULL,
  test_ix = NULL,
  n_pcs = 8L,
  reps = 2L,
  lambda = 0.1
)
```

## Arguments

- embeddings:

  Foundation-model embedding matrix (n_obs x D).

- covariates:

  Raw-covariate matrix or data frame (n_obs x C).

- y:

  Numeric response.

- train_ix, test_ix:

  Integer index vectors selecting rows for train/test. If `NULL`, a
  70/30 random split is drawn.

- n_pcs, reps, lambda:

  Passed to
  [`qf_krr_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/qf_krr_fit.md).

## Value

A data frame with columns `method`, `rmse`, `mae`, `r2`, `n_train`,
`n_test`.

## Details

Returns the test-set RMSE, MAE and R^2 for each setup so the question
"does the quantum lift on foundation embeddings beat either its
quantum-only or foundation-only ancestor?" gets an empirical answer.

## Examples

``` r
# Stand-in MoCo encoder output plus the five raw covariates it was
# built from, over 200 Cerrado pixels, predicting SOC (g/kg).
set.seed(42)
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
sub  <- br_cerrado[sample(nrow(br_cerrado), 200L), ]
Z    <- scale(as.matrix(sub[, covs]))
W    <- matrix(rnorm(5L * 64L), 5L, 64L)
emb  <- tanh(Z %*% W) + matrix(rnorm(200L * 64L, 0, 0.1), 200L, 64L)
y    <- sub$soc
tr   <- 1:140; te <- 141:200

# set.seed() even with a fixed split: arm 1 draws 500 ranger trees
# from the ambient RNG stream, so its RMSE moves without one.
set.seed(7)
bm <- qf_krr_benchmark(emb, as.matrix(sub[, covs]), y,
                       train_ix = tr, test_ix = te,
                       n_pcs = 5L, reps = 2L, lambda = 0.1)
bm[, c("method", "rmse", "r2")]
#>                             method     rmse          r2
#> rf         ranger (raw covariates) 5.051015  0.50603423
#> rbf      RBF-KRR on foundation PCs 4.981030  0.51962777
#> qraw Quantum KRR on raw covariates 6.798584  0.10509592
#> qf   Quantum KRR on foundation PCs 7.387175 -0.05656509
#   ranger (raw covariates)         5.02   0.513
#   RBF-KRR on foundation PCs       4.98   0.520
#   Quantum KRR on raw covariates   6.80   0.105
#   Quantum KRR on foundation PCs   7.39  -0.057

# The bridge's own arm comes last, and it loses to the null the
# whole table has to clear first:
edaphos_rmse(y[te], rep(mean(y[tr]), length(te)))   # 7.21
#> [1] 7.208675
# Only the two classical arms beat it.  The quantum lift over the
# foundation PCs is worse than predicting the training mean here,
# which is what a Gram matrix collapsed onto the identity looks
# like downstream -- see qf_kernel_compare().

# Three things that make this table less of a head-to-head than
# it reads:
#  * arms 2 and 3 fit their preprocessing (the PCA, and
#    quantum_scale()'s column min/max) on ALL rows, test included;
#    arms 1 and 4 only ever see the training rows.
#  * arm 3 quantum-encodes the FIRST n_pcs covariate columns, in
#    whatever order the matrix happens to have -- not a selection.
colnames(as.matrix(sub[, covs]))[1:5]
#> [1] "elev"   "slope"  "twi"    "map_mm" "ndvi"  
#  * if ncol(covariates) < n_pcs, arm 3 is dropped in silence and
#    you get a three-row table with no warning:
set.seed(7)
nrow(qf_krr_benchmark(emb, as.matrix(sub[, covs[1:3]]), y,
                      train_ix = tr, test_ix = te,
                      n_pcs = 5L, reps = 2L, lambda = 0.1))   # 3
#> [1] 3
```
