# Posterior distribution of a backdoor-adjusted direct effect

Unified v1.6.0 entry point for Pillar 1. Returns an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
with posterior draws over the identified direct effect, ready for
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html).
For the LM estimator the draws are a cluster-block bootstrap; for BART
the draws are the native Markov- chain posterior.

## Usage

``` r
causal_effect_posterior(
  data,
  dag,
  exposure,
  outcome,
  adjustment = NULL,
  estimator = c("lm", "bart"),
  cluster = "kmeans_cluster",
  B = 500L,
  seed = NULL,
  bart_kwargs = list(),
  delta = NULL,
  units = NULL
)
```

## Arguments

- data:

  A data frame.

- dag:

  A `dagitty` DAG (required when `adjustment = NULL`).

- exposure, outcome:

  Character; column names.

- adjustment:

  Optional character vector of adjustment-set columns; derived from the
  DAG if `NULL`.

- estimator:

  `"lm"` or `"bart"`.

- cluster, B, seed:

  See
  [`causal_effect_bootstrap()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_effect_bootstrap.md);
  only used for the LM estimator.

- bart_kwargs:

  Named list of extra arguments forwarded to
  [`dbarts::bart()`](https://rdrr.io/pkg/dbarts/man/bart.html) when
  `estimator = "bart"`.

- delta:

  Numeric; counterfactual increment for the BART estimator (defaults to
  `IQR(exposure) / 2`).

- units:

  Optional character; free-text tag passed through to the
  `edaphos_posterior`.

## Value

An `edaphos_posterior` with `query_type = "effect"` and `method` set to
`"bootstrap"` (LM) or `"bayesian"` (BART).

## Examples

``` r
if (requireNamespace("dagitty", quietly = TRUE)) {
  dag <- causal_cerrado_dag()
  d   <- br_cerrado
  set.seed(42)
  d$kmeans_cluster <- stats::kmeans(d[, c("x", "y")], centers = 9L)$cluster

  # LM path: the draws are the cluster block bootstrap. B = 50 keeps
  # the example fast; use several hundred for anything you report.
  post <- causal_effect_posterior(d, dag, "twi", "soc", B = 50L,
                                  seed = 1L, units = "g/kg per TWI unit")
  post

  # `post$quantiles` holds q05/q50/q95 -- a 90% interval, not the
  # 95% one most papers quote. Take that from the draws directly.
  quantile(post$samples[, 1], c(0.025, 0.975))

  # When the adjustment set is derived from the DAG rather than
  # passed in, the LM path records `metadata$adjustment` as NULL.
  # Recover the set from the graph for your provenance record.
  post$metadata$adjustment
  causal_adjustment_set(dag, "twi", "soc", effect = "direct")

  # The posterior is conditional on the DAG *and* on the estimator.
  # BART on the same graph and the same rows returns about 1.20,
  # outside the LM bootstrap interval of roughly [1.36, 1.69]. No
  # number of resamples exposes that -- it is a functional-form
  # disagreement, not sampling noise.
  if (requireNamespace("dbarts", quietly = TRUE)) {
    pb <- causal_effect_posterior(
      d, dag, "twi", "soc", estimator = "bart",
      bart_kwargs = list(ntree = 50L, ndpost = 200L, nskip = 100L,
                         seed = 1L)
    )
    c(lm = post$mean, bart = pb$mean)
  }
}
#>       lm     bart 
#> 1.512274 1.197336 
```
