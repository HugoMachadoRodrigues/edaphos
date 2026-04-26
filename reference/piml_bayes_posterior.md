# Posterior predictive distribution from a Bayesian Pillar 2 fit

Convenience wrapper that calls
[`predict.edaphos_piml_bayes()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_bayes.md)
on the requested depths with either the Laplace or the MCMC posterior
samples, and returns the result as an
[`edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos_posterior.md).

## Usage

``` r
piml_bayes_posterior(
  object,
  newdepths,
  n_draws = NULL,
  include_obs_noise = FALSE,
  seed = NULL,
  units = NULL
)
```

## Arguments

- object:

  An `edaphos_piml_bayes` (Laplace or MCMC).

- newdepths:

  Numeric vector of depths.

- n_draws:

  Integer — number of posterior draws to keep from the underlying chain.
  Defaults to `min(500, nrow(object$draws))`.

- include_obs_noise:

  Logical — see
  [`piml_neural_ode_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_posterior.md).

- seed:

  Optional RNG seed.

- units:

  Optional units tag.

## Value

An `edaphos_posterior` with `method = "bayesian"`.
