# Causal Active Learning: query the next sample(s) that most reduce the uncertainty of a targeted causal effect

Closes the loop between Pillar 1 (causal identification via backdoor
adjustment) and Pillar 5 (autonomous active learning): instead of
choosing candidates by marginal-Y uncertainty (classical AL), we choose
by expected shrinkage of `Var(beta_hat_{X->Y})`.

## Usage

``` r
al_query_causal(
  data,
  pool,
  dag,
  exposure,
  outcome,
  adjustment = NULL,
  n_select = 5L,
  strategy = c("leverage", "bootstrap"),
  B = 200L,
  seed = NULL
)
```

## Arguments

- data:

  Data frame with the exposure, outcome and adjustment columns (the
  current labelled set).

- pool:

  Data frame with the same columns as `data`; the unlabelled candidate
  pool to query.

- dag:

  A `dagitty` DAG.

- exposure, outcome:

  Character; column names of the causal query.

- adjustment:

  Optional character vector of adjustment-set columns. Inferred from
  `dag` via
  [`causal_adjustment_set()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_adjustment_set.md)
  when `NULL`.

- n_select:

  Integer; how many candidates to return. Default `5L`.

- strategy:

  One of `"leverage"` (hat-matrix diagonal, closed-form, fast) or
  `"bootstrap"` (re-bootstrap the effect for each candidate; slow but
  exact under the linear-OLS estimator).

- B:

  Bootstrap replications when `strategy = "bootstrap"`.

- seed:

  RNG seed for bootstrap reproducibility.

## Value

A data frame with one row per candidate, columns `pool_index`,
`leverage`, `expected_var_reduction`, sorted by descending expected
reduction. The top-`n_select` rows are the recommended next samples.
