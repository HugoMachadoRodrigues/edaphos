# Benchmark wrapper: Pilar 6 – bootstrap-ensembled quantum KRR

PCA-reduces the covariate matrix to `n_pcs` components rescaled to
`[-pi, pi]`, then trains `n_boot` quantum-kernel ridge regressors on
bootstrap resamples and aggregates their predictions into a predictive
posterior.

## Usage

``` r
benchmark_fit_p6_quantum(
  train,
  test,
  cov_cols,
  n_pcs = 6L,
  reps = 2L,
  lambda = 0.5,
  n_boot = 20L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with `soc` + `cov_cols`.

- cov_cols:

  Character vector of covariate column names.

- n_pcs:

  Integer; number of PCs (= qubits). Default `6L`.

- reps:

  Integer; ZZFeatureMap repetitions. Default `2L`.

- lambda:

  Ridge regulariser. Default `0.5`.

- n_boot:

  Integer; number of bootstrap KRR fits. Default `20L`.

- seed:

  Optional RNG seed.

- calibrate:

  Logical (default `TRUE`). When `TRUE`, residual noise from a full-data
  quantum-KRR fit is injected into every posterior sample (see Pilar-1
  wrapper for the rationale).

## Value

An `edaphos_posterior` with `method = "ensemble"`, `query_type = "map"`.
