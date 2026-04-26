# Posterior predictive distribution from a Pillar 2 deep ensemble

Convenience wrapper that calls
[`predict.edaphos_piml_neural_ode_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_neural_ode_ensemble.md)
on the requested depths and returns the result as an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md)
with `query_type = "sample"` (one scalar prediction per query depth) or
`"feature"` (when the caller passes a single depth and wants the
posterior over that single scalar).

## Usage

``` r
piml_neural_ode_posterior(
  object,
  newdepths,
  include_obs_noise = FALSE,
  seed = NULL,
  units = NULL
)
```

## Arguments

- object:

  An `edaphos_piml_neural_ode_ensemble`.

- newdepths:

  Numeric vector of depths at which to evaluate the posterior
  predictive.

- include_obs_noise:

  Logical — when `TRUE`, adds Gaussian observation noise to every draw
  so the posterior is the *predictive distribution of a future
  observation* (aleatoric included) rather than only the uncertainty on
  the mean function. Default `FALSE`.

- seed:

  Optional RNG seed for the observation-noise draw.

- units:

  Optional units tag.

## Value

An `edaphos_posterior` with `method = "ensemble"`.
