# Roll every ensemble member forward and stack the forecasts

Produces the `(K_ens, T_future, H, W)` array that
[`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
and
[`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md)
consume.

## Usage

``` r
temporal_convlstm_ensemble_rollout(object, past_sequence, future_drivers)
```

## Arguments

- object:

  An `edaphos_temporal_convlstm_ensemble`.

- past_sequence, future_drivers:

  Passed through to
  [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
  for each member.

## Value

A 4-D numeric array `(K_ens, T_future, H, W)`.
