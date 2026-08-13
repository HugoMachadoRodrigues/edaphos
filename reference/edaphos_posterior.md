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
# Both posteriors below are built from synthetic random draws, so
# set.seed() is what makes the printed summaries reproducible.
# They illustrate the container only -- neither is a fitted model.
# A real `method = "bootstrap"` posterior comes from the Pillar-1
# block bootstrap, a real `method = "gaussian"` one from the
# Pillar-6 QKRR posterior variance; both are obtained by calling
# `as_edaphos_posterior()` on that pillar's fit, not by hand.
set.seed(42)

# From a posterior sample: 100 draws over a 2-cell query. The draws
# are standard normal noise, so this posterior is centred on ~0 with
# sd ~1 and would imply no detectable effect at all.
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
#>   mean range  : [-0.0875, +0.0325]  mean = -0.0275
#>   sd   range  : [+0.9042, +1.0414]  mean = +0.9728
# Under set.seed(42) the two summary lines printed above read
#   mean range  : [-0.0875, +0.0325]  mean = -0.0275
#   sd   range  : [+0.9042, +1.0414]  mean = +0.9728

# From a Gaussian summary. `mean` and `sd` are stored verbatim, but
# the constructor still draws `n_samples_if_gaussian` (500) samples
# so that uncertainty_calibrate() and autoplot() have a sample to
# work with -- that hidden draw is the other thing set.seed() fixes.
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

# Those synthesised draws only reproduce the requested sd up to
# Monte-Carlo error at n = 500: this prints 0.099 and 0.205 against
# the requested 0.1 and 0.2.
round(apply(post2$samples, 2L, stats::sd), 3L)
#> [1] 0.099 0.205

# print() shows the exact mean / sd; summary() adds quantiles, and
# those are computed from the synthesised draws, so they move with
# the seed even though the mean / sd lines do not.
summary(post2)
#> <edaphos_posterior>
#>   method      : gaussian
#>   query_type  : param
#>   n_samples   : 500
#>   query shape : 2
#>   mean range  : [+0.5000, +0.7000]  mean = +0.6000
#>   sd   range  : [+0.1000, +0.2000]  mean = +0.1500
#> 
#> Quantiles (over query shape):
#>   q05   : min=+0.3355  med=+0.3541  max=+0.3727
#>   q50   : min=+0.4963  med=+0.5995  max=+0.7027
#>   q95   : min=+0.6521  med=+0.8432  max=+1.0342
```
