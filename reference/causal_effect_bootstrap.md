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

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- causal_cerrado_dag()
  d   <- br_cerrado

  # The bootstrap resamples CLUSTERS, not rows, so `data` must carry
  # a cluster column -- `br_cerrado` does not ship one. Nine spatial
  # blocks from k-means on the coordinates, as in the Cerrado
  # pipeline.
  set.seed(42)
  d$kmeans_cluster <- stats::kmeans(d[, c("x", "y")], centers = 9L)$cluster

  # B = 50 keeps this example fast; a real analysis wants several
  # hundred. At B = 50 the tail quantiles are themselves noisy: the
  # 95% width wandered between 0.23 and 0.37 across five seeds here,
  # against 0.35 at B = 500.
  boot <- causal_effect_bootstrap(d, dag, "twi", "soc", B = 50L, seed = 1L)
  quantile(boot, c(0.025, 0.5, 0.975))

  # Block resampling does not automatically widen the interval: here
  # it lands on the asymptotic confint(lm) width, which says these
  # (synthetic) residuals carry little block-level dependence. Check
  # that before calling the clustered interval the conservative one.
  fit <- causal_estimate_effect(d, dag, "twi", "soc")
  c(block_boot = unname(diff(quantile(boot, c(0.025, 0.975)))),
    asymptotic = unname(diff(fit$effect_ci)))

  # What resampling cannot check is the graph. Same rows, same seed,
  # one edge-level decision -- "direct" blocks the twi -> ndvi -> soc
  # mediator, "total" leaves it open -- and the target moves from
  # 1.51 to 1.80, with the two 95% intervals overlapping by 0.02.
  tot <- causal_effect_bootstrap(d, dag, "twi", "soc", B = 50L,
                                 seed = 1L, effect = "total")
  c(direct = mean(boot), total = mean(tot))
}
#>   direct    total 
#> 1.512274 1.800608 
```
