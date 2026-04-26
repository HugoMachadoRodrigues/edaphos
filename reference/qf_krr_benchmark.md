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
