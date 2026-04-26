# Benchmark wrapper: Pilar 1 – DAG-adjusted OLS + parametric bootstrap

Restricts OLS to covariates that appear in the supplied DAG as direct
parents of the outcome (falling back to the full covariate set when the
DAG has no matching variables) and generates a parametric-bootstrap
predictive posterior. Intended for the v3.1.0 WoSIS head-to-head; the
exported API is stable enough for use on any regional subset that
follows the same schema.

## Usage

``` r
benchmark_fit_p1_causal(
  train,
  test,
  cov_cols,
  dag = NULL,
  n_boot = 300L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with a response column `soc`, coord columns `lon`/`lat`,
  and the columns listed in `cov_cols`.

- cov_cols:

  Character vector of candidate covariate names.

- dag:

  A `dagitty` DAG object (or `NULL` to use the full covariate set).

- n_boot:

  Number of bootstrap resamples. Default `300`.

- seed:

  Optional RNG seed.

- calibrate:

  Logical (default `TRUE`). When `TRUE`, an estimate of the in-sample
  residual standard deviation is added as iid Gaussian noise to every
  posterior sample so the predictive posterior carries BOTH epistemic
  (bootstrap-spread) AND aleatoric (residual) uncertainty. Set to
  `FALSE` to reproduce the v3.1.0 epistemic-only behaviour.

## Value

An `edaphos_posterior` with `method = "bootstrap"`,
`query_type = "map"`.
