# K-seed deep ensemble of stacked ConvLSTMs

Trains `K_ens` independent
[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
models with different random seeds and collects them in a single object.
This formalises the hand-rolled ensemble loop from the v1.5.0 Pillar 3
Cerrado runner (`data-raw/temporal_cerrado_run.R`) and produces the
natural forecast-ensemble input for
[`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
or for
[`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md).

## Usage

``` r
temporal_convlstm_ensemble_fit(
  sequence,
  target,
  hidden_dims = c(8L, 4L),
  kernel_size = 3L,
  return_sequence = FALSE,
  epochs = 80L,
  lr = 0.02,
  K_ens = 10L,
  base_seed = 101L,
  physics_lambda = 0,
  physics_k_in = 0.03,
  physics_k_out = 0.015,
  physics_driver_channel = 2L,
  verbose = FALSE
)
```

## Arguments

- sequence, target, hidden_dims, kernel_size, return_sequence, epochs,
  lr, physics_lambda, physics_k_in, physics_k_out,
  physics_driver_channel, verbose:

  Passed through unchanged to
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md).

- K_ens:

  Integer; number of ensemble members. Defaults to `10L`.

- base_seed:

  Integer; each member uses `base_seed + k - 1L`.

## Value

A list with class `edaphos_temporal_convlstm_ensemble` containing

- members:

  List of K `edaphos_temporal_convlstm` fits.

- K_ens:

  Integer, the ensemble size.

- final_losses:

  Numeric vector of per-member final training losses.

- loss_histories:

  List of K numeric vectors (one per member).

## See also

[`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
to roll each member forward,
[`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
to assimilate observations into the forecast ensemble,
[`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md)
for the unified uncertainty wrapper.
