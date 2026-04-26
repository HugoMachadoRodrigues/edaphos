# Unified posterior object for the edaphos pillars

Constructs an `edaphos_posterior` — the single S3 class that edaphos
uses to represent predictive uncertainty regardless of which pillar
produced it. The constructor accepts either a sample-based posterior
(`samples`) or a Gaussian summary (`mean` + `sd`), and derives the
missing fields automatically.

## Usage

``` r
edaphos_posterior(
  samples = NULL,
  mean = NULL,
  sd = NULL,
  epistemic_sd = NULL,
  aleatoric_sd = NULL,
  probs = c(0.05, 0.5, 0.95),
  method = c("ensemble", "bootstrap", "mcdropout", "bayesian", "loo_cv", "shots",
    "analytic", "gaussian"),
  query_type = c("effect", "param", "map", "feature", "sample", "energy", "other"),
  units = NULL,
  metadata = list(),
  n_samples_if_gaussian = 500L
)
```

## Arguments

- samples:

  Optional numeric array or matrix. The first axis is the posterior-draw
  axis of length `n_samples`; the remaining axes are the query shape. A
  1-D vector is treated as `n_samples` scalar draws.

- mean:

  Optional numeric array with the query shape. If `samples` is `NULL`,
  required together with `sd`.

- sd:

  Optional numeric array with the query shape.

- epistemic_sd, aleatoric_sd:

  Optional numeric arrays with the query shape; the variance
  decomposition `epistemic_sd^2 + aleatoric_sd^2 ~ sd^2` is expected to
  hold approximately (exact for Gaussian posteriors).

- probs:

  Numeric vector of quantile probabilities to pre- compute from
  `samples`. Defaults to `c(0.05, 0.5, 0.95)`.

- method:

  Character tag describing how the posterior was produced, for
  diagnostics and plotting. One of `"ensemble"`, `"bootstrap"`,
  `"mcdropout"`, `"bayesian"`, `"loo_cv"`, `"shots"`, `"analytic"`,
  `"gaussian"`.

- query_type:

  Character tag describing what the posterior is over. One of
  `"effect"`, `"param"`, `"map"`, `"feature"`, `"sample"`, `"energy"`,
  `"other"`.

- units:

  Optional free-text tag (e.g. "g/kg", "NDVI z-units").

- metadata:

  Optional list of extra provenance fields.

- n_samples_if_gaussian:

  If only `mean` and `sd` are provided, the constructor synthesises this
  many Gaussian draws so that downstream helpers
  (`uncertainty_calibrate`, `autoplot`) always have a sample to work
  with. Defaults to `500L`.

## Value

An `edaphos_posterior` object. See `?edaphos_posterior` for the list of
invariants the class satisfies.

## Examples

``` r
# From a posterior sample
post <- edaphos_posterior(
  samples    = matrix(stats::rnorm(200), nrow = 100, ncol = 2),
  method     = "bootstrap",
  query_type = "effect",
  units      = "g/kg per mm"
)
post
#> <edaphos_posterior>
#>   method      : bootstrap
#>   query_type  : effect
#>   units       : g/kg per mm
#>   n_samples   : 100
#>   query shape : 2
#>   mean range  : [-0.0136, +0.0313]  mean = +0.0088
#>   sd   range  : [+0.9701, +1.0418]  mean = +1.0060

# From a Gaussian summary
post2 <- edaphos_posterior(
  mean       = c(0.5, 0.7),
  sd         = c(0.1, 0.2),
  method     = "gaussian",
  query_type = "param"
)
post2
#> <edaphos_posterior>
#>   method      : gaussian
#>   query_type  : param
#>   n_samples   : 500
#>   query shape : 2
#>   mean range  : [+0.5000, +0.7000]  mean = +0.6000
#>   sd   range  : [+0.1000, +0.2000]  mean = +0.1500
```
