# Posterior distribution of a backdoor-adjusted direct effect

Unified v1.6.0 entry point for Pillar 1. Returns an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
with posterior draws over the identified direct effect, ready for
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`ggplot2::autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html).
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
