# Predictive posterior from a Neural-ODE deep ensemble

Evaluates every ensemble member at the requested depths and returns
either the raw `K × length(newdepths)` matrix of member-wise predictions
or a tidy `(mean, sd, lower, upper)` summary corresponding to a
symmetric central credible interval computed directly from the empirical
ensemble distribution.

## Usage

``` r
# S3 method for class 'edaphos_piml_neural_ode_ensemble'
predict(
  object,
  newdepths,
  interval = NULL,
  include_obs_noise = FALSE,
  seed = NULL,
  ...
)
```

## Arguments

- object:

  An `edaphos_piml_neural_ode_ensemble`.

- newdepths:

  Numeric vector of depths.

- interval:

  Optional numeric in `(0, 1)` — when supplied, returns a summary data
  frame with a symmetric central credible interval at the requested
  level. When `NULL` (default) returns the raw `K × length(newdepths)`
  matrix.

- include_obs_noise:

  Logical — when `TRUE`, adds residual Gaussian noise (with SD equal to
  the pooled member-wise training RMSE) to every predictive draw so the
  interval represents the predictive distribution of a *future
  observation* rather than the uncertainty on the *mean function* alone.
  Default `FALSE`.

- seed:

  Optional integer — RNG seed for the observation-noise draw. Only
  consulted when `include_obs_noise = TRUE`.

- ...:

  Unused.

## Value

Either a numeric matrix (when `interval` is NULL) or a data frame with
columns `depth`, `mean`, `sd`, `lower`, `upper`.
