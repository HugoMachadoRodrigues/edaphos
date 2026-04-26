# Train a deep ensemble of Neural ODEs for uncertainty quantification

Wraps
[`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)
in a K-member ensemble, each member trained from an independent random
initialisation. The returned object behaves like a single
`edaphos_piml_neural_ode` for the purposes of
[`predict()`](https://rdrr.io/r/stats/predict.html) — except that the
method returns the full `K × length(newdepths)` matrix of member-wise
predictions, or (optionally) a tidy `(mean, sd, lower, upper)`
credible-interval summary.

## Usage

``` r
piml_neural_ode_fit_ensemble(
  depths,
  values,
  y_surface = NULL,
  K = 5L,
  hidden = c(16L, 16L),
  n_steps = 4L,
  epochs = 500L,
  lr = 0.01,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- depths, values, y_surface, hidden, n_steps, epochs, lr, verbose:

  Forwarded to
  [`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)
  member-by-member. See there for details.

- K:

  Integer — number of ensemble members. Default 5 for a reasonable
  speed/variance trade-off; 10 is the recommended ceiling on
  laptop-scale problems.

- seed:

  Optional integer — seeds the ensemble. Member `k` is trained with
  `seed = seed + k - 1L`.

## Value

An `edaphos_piml_neural_ode_ensemble` carrying:

- members:

  A list of `K` fitted `edaphos_piml_neural_ode` objects.

- K, hidden, n_steps, y_surface:

  Configuration echo.

- fitted:

  A `K × n_obs` matrix of in-sample predictions.

- fitted_mean, fitted_sd:

  Ensemble mean / standard deviation of `fitted`.

- rmse:

  RMSE of the ensemble mean against the training observations.

## Details

The theoretical justification for the ensemble as a posterior
approximation is developed in Lakshminarayanan et al. 2017 and Wilson &
Izmailov 2020 (see the @references section). In short: for wide neural
networks, different SGD trajectories converge to different basins of the
loss surface, and the resulting member-wise spread is a well-calibrated
proxy for the Bayesian posterior predictive variance.

## References

Lakshminarayanan, B., Pritzel, A. and Blundell, C. (2017). Simple and
scalable predictive uncertainty estimation using deep ensembles.
*NeurIPS 30*, 6402–6413.

Wilson, A. G. and Izmailov, P. (2020). Bayesian deep learning and a
probabilistic perspective of generalization. *NeurIPS 33*, 4697–4708.

## See also

[`predict.edaphos_piml_neural_ode_ensemble()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_piml_neural_ode_ensemble.md),
[`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)
for the single-member variant,
[`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
for the parametric-ODE analogue.

## Examples

``` r
if (FALSE) { # \dontrun{
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  ens <- piml_neural_ode_fit_ensemble(depths, values, K = 5L,
                                        epochs = 300L, seed = 1L)
  predict(ens, newdepths = c(10, 20, 40, 80), interval = 0.95)
} # }
```
