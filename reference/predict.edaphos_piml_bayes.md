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

  Optional integer seed for the sub-sampling of draws.

- ...:

  Unused; present for S3 `predict` generic compatibility.

## Value

Either a matrix (when `interval` is NULL) or a data frame with columns
`depth`, `mean`, `sd`, `lower`, `upper`.

## Examples

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)
fit <- piml_profile_fit_bayesian(depths, values)
predict(fit, newdepths = c(10, 20, 40, 80), interval = 0.95)
#>   depth      mean        sd     lower     upper
#> 1    10 21.012520 0.1387745 20.742415 21.278981
#> 2    20 15.504483 0.1367901 15.214314 15.755396
#> 3    40 10.069634 0.1481595  9.800381 10.377096
#> 4    80  7.029437 0.1405769  6.787625  7.327181
```
