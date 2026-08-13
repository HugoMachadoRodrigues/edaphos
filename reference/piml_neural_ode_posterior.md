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

## Examples

``` r
# torch is a Suggests dependency AND its libtorch binaries are a
# separate download, so both halves of the guard are needed.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  depths <- c(5, 30, 60, 100)
  soc    <- c(24, 15, 9.5, 7)      # g/kg, a decaying Latossolo

  # 30 epochs over 4 horizons is a runtime stub, not a trained model.
  # Say so with numbers before reading anything into the spread: the
  # ensemble clears the mean-only baseline but is two orders of
  # magnitude worse than the 4-parameter ODE on the same points.
  ens <- piml_neural_ode_fit_ensemble(depths, soc, K = 3L,
                                      hidden = c(8L, 8L), n_steps = 2L,
                                      epochs = 30L, seed = 1L)
  print(round(c(ensemble   = ens$rmse,
                parametric = piml_profile_fit(depths, soc)$rmse,
                mean_only  = sqrt(mean((soc - mean(soc))^2))), 4))
  #   ensemble 2.1506   parametric 0.0209   mean_only 6.5228

  post <- piml_neural_ode_posterior(ens, newdepths = c(10, 40, 70),
                                    units = "g/kg")
  print(post)

  # The sample axis IS the ensemble members, so n_samples = K = 3.
  # The stored q05 / q95 are therefore interpolations between the
  # smallest and the largest of three numbers, not tail quantiles.
  # K = 5 (the default) does not fix that, it makes them a 5-number
  # range.
  print(dim(post$samples))
  print(round(rbind(q05 = post$quantiles$q05,
                    min = apply(post$samples, 2L, min),
                    q95 = post$quantiles$q95,
                    max = apply(post$samples, 2L, max)), 4))

  # include_obs_noise adds N(0, sigma^2) to each of those K draws,
  # sigma being the pooled member training RMSE:
  print(round(sqrt(mean(vapply(ens$members,
                               function(m) m$rmse^2, 0))), 4))   # 2.5407

  # With K = 3 the resulting sd is itself computed from 3 numbers, so
  # it need not even increase: at 40 and 70 cm it FALLS, because the
  # three noise draws happened to push the members together. An
  # aleatoric term that shrinks the reported sd is the diagnostic
  # that K is far too small, not a property of the soil.
  pn <- piml_neural_ode_posterior(ens, newdepths = c(10, 40, 70),
                                  include_obs_noise = TRUE, seed = 7)
  print(round(rbind(mean_fn = post$sd, plus_noise = pn$sd), 4))

  # A single depth is tagged "feature", several are "sample" --- the
  # downstream calibration helpers branch on that. as_edaphos_posterior()
  # routes here but refuses to guess the depths.
  print(piml_neural_ode_posterior(ens, newdepths = 40)$query_type)
  print(tryCatch(as_edaphos_posterior(ens),
                 error = function(e) conditionMessage(e)))
}
```
