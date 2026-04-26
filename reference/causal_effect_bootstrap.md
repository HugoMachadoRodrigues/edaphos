# Block-bootstrap the backdoor-adjusted direct effect

Resamples clusters (not rows) with replacement and refits the adjusted
OLS on each resample, returning the vector of direct-effect
coefficients. When the clustering structure is k-means on `(lon, lat)`
(as in the Cerrado pipeline from v1.4.0 onward), this produces
spatial-clustering-aware confidence intervals that the asymptotic
`confint(lm)` interval ignores.

## Usage

``` r
causal_effect_bootstrap(
  data,
  dag,
  exposure,
  outcome,
  adjustment = NULL,
  cluster = "kmeans_cluster",
  B = 500L,
  effect = c("direct", "total"),
  seed = NULL
)
```

## Arguments

- data:

  A data frame with the exposure, outcome, adjustment columns and a
  cluster-id column.

- dag:

  A `dagitty` DAG (only used when `adjustment` is `NULL`).

- exposure, outcome:

  Character; column names.

- adjustment:

  Character vector of adjustment-set column names (defaults to the
  minimal set from the DAG).

- cluster:

  Character; name of the cluster-id column in `data`.

- B:

  Integer; number of bootstrap resamples. Defaults to `500L`.

- effect:

  One of `"direct"`, `"total"` (passed to the adjustment set resolver
  when `adjustment = NULL`).

- seed:

  Optional integer for reproducibility.

## Value

Numeric vector of length `B` with one direct-effect estimate per
bootstrap resample.
