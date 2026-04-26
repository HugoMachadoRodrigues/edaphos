# Bootstrap posterior for a 2SLS effect as an edaphos_posterior

Wraps
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
in a nonparametric bootstrap over rows (or over clusters if `cluster` is
supplied) and packages the resulting vector of effect estimates as an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
so that
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`ggplot2::autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
apply uniformly.

## Usage

``` r
causal_iv_posterior(
  data,
  exposure,
  outcome,
  instruments,
  covariates = NULL,
  B = 500L,
  cluster = NULL,
  seed = NULL,
  units = NULL
)
```

## Arguments

- data:

  A data frame.

- exposure:

  Character; name of the endogenous exposure column.

- outcome:

  Character; name of the outcome column.

- instruments:

  Character vector; names of instrument columns. More instruments than
  exposures gives an over-identified model on which the Sargan test is
  applicable.

- covariates:

  Optional character vector of exogenous-control column names included
  in both first and second stage.

- B:

  Integer; number of bootstrap resamples. Default `500L`.

- cluster:

  Optional character; column in `data` to resample by block (e.g.
  `"kmeans_cluster"` for spatial resampling).

- seed:

  Optional RNG seed.

- units:

  Optional units string.

## Value

An `edaphos_posterior` with `query_type = "effect"` and
`method = "bootstrap"`.
