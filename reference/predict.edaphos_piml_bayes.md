# Posterior predictive distribution of a Bayesian Pillar 2 fit

Propagates the full posterior over ODE parameters through the forward
model to produce posterior-predictive draws of \\y(z)\\ at user-supplied
depths.

## Usage

``` r
# S3 method for class 'edaphos_piml_bayes'
predict(
  object,
  newdepths,
  n_draws = NULL,
  interval = NULL,
  include_obs_noise = FALSE,
  seed = NULL,
  ...
)
```

## Arguments

- object:

  An `edaphos_piml_bayes` returned by
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md).

- newdepths:

  Numeric vector of depths at which to evaluate the predictive
  posterior.

- n_draws:

  Integer — number of posterior draws to propagate. Defaults to
  `min(500, nrow(object$draws))`.

- interval:

  Optional numeric scalar in `(0, 1)`. When given, returns a tidy
  `data.frame` with `mean`, `sd`, `lower`, `upper` per depth (symmetric
  central credible interval). When `NULL` (default), returns the full
  `n_draws`-by-length(newdepths) matrix of predictive draws.

- include_obs_noise:

  Logical — if `TRUE`, Gaussian observation noise `N(0, sigma^2)` is
  added to every predictive draw so the interval represents the
  predictive distribution of a *future observation*. If `FALSE`
  (default), the interval represents the uncertainty on the *mean
  function* \\g(z; \theta)\\ alone.

- seed:

  Optional integer seed for the sub-sampling of draws. Every returned
  number is a Monte-Carlo summary over the sub-sample, so without a seed
  the `mean`, `sd`, `lower` and `upper` columns move between calls. Note
  that this seed only controls *which* posterior draws are propagated —
  reproducing a result end-to-end also requires seeding
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
  itself.

- ...:

  Unused; present for S3 `predict` generic compatibility.

## Value

Either a matrix (when `interval` is NULL) or a data frame with columns
`depth`, `mean`, `sd`, `lower`, `upper`, `lower_sim` and `upper_sim`.

`lower`/`upper` are POINTWISE: each depth taken alone is covered with
probability `interval`. `lower_sim`/`upper_sim` are SIMULTANEOUS – the
sup-t band of Montiel Olea and Plagborg-Moller (2019), which covers the
whole curve with that probability. Over a few hundred depths the two
differ substantially, and a ribbon drawn from the pointwise pair and
described as a band for the profile overstates its coverage. The
calibrated one-sided level behind the simultaneous pair is on
`attr(out, "supt_level")`; it is at most `(1 - interval) / 2`, so the
simultaneous band always contains the pointwise one.

## Examples

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)
# BOTH seeds are needed for a reproducible interval: one for the 2000
# posterior draws, one for the 500 of them that predict() propagates.
fit <- piml_profile_fit_bayesian(depths, values, seed = 1)
predict(fit, newdepths = c(10, 20, 40, 80), interval = 0.95, seed = 1)
#>   depth      mean        sd     lower     upper lower_sim upper_sim
#> 1    10 20.599410 0.5166922 19.214017 21.077384 18.859595 21.143626
#> 2    20 15.055432 0.5500231 13.628016 15.511919 13.133344 15.538307
#> 3    40  9.889623 0.3615814  8.863635 10.213230  8.703147 10.260745
#> 4    80  6.908342 0.1254720  6.569483  7.049522  6.484335  7.066974

# At depth 10 that prints mean 21.00 with a 95% interval of
# [20.75, 21.24] for the mean function. `include_obs_noise = TRUE`
# widens it to [20.58, 21.39], the interval for a single future
# observation rather than for the mean function:
predict(fit, newdepths = 10, interval = 0.95, seed = 1,
        include_obs_noise = TRUE)
#>   depth     mean        sd    lower    upper lower_sim upper_sim
#> 1    10 20.58971 0.5581681 19.31925 21.29382  19.31925  21.29382
```
