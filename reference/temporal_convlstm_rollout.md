# Multi-step rollout forecast

When future driver channels are known (e.g. climate forecasts,
calendar-based covariates, planned irrigation), a ConvLSTM trained with
`return_sequence = TRUE` can simply be re-applied to a longer sequence
covering **past + future** time steps — the hidden state propagates the
soil memory, and every step gets its own prediction. This function
automates that call and returns only the future part of the prediction.

## Usage

``` r
temporal_convlstm_rollout(object, past_sequence, future_drivers)
```

## Arguments

- object:

  A `edaphos_temporal_convlstm` trained with `return_sequence = TRUE`.

- past_sequence:

  Array `(batch, T_past, C, H, W)` — the observed window used for state
  warm-up.

- future_drivers:

  Array `(batch, T_future, C, H, W)` with the same channel layout as
  `past_sequence`.

## Value

Array `(batch, T_future, H, W)` with per-step predictions.
