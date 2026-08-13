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

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
  # ONE call, so the train and forecast windows share a scaling and
  # the two error numbers below are comparable at all.
  tt <- temporal_cube_to_tensor(cube)
  past   <- tt$sequence[, 1:4, , , , drop = FALSE]
  past_y <- tt$target[,   1:4, , , drop = FALSE]
  fut    <- tt$sequence[, 5:6, , , , drop = FALSE]
  fut_y  <- tt$target[,   5:6, , , drop = FALSE]

  fit <- temporal_convlstm_fit(past, past_y, hidden_dims = 8L,
                               return_sequence = TRUE,
                               epochs = 150L, lr = 0.05, seed = 1L)
  fc <- temporal_convlstm_rollout(fit, past, fut)
  print(dim(fc))                       # 1 2 8 8

  # This rollout is NOT autoregressive. The two input channels are
  # elevation and precipitation -- SOC is never one of them -- so
  # the model cannot see its own predictions and nothing is fed
  # back. It is exactly predict() on the concatenated window, then
  # sliced to the future part.
  print(dim(tt$sequence)[3])           # 2
  both <- temporal_convlstm_predict(fit, tt$sequence)
  print(max(abs(fc[1, , , ] - both[1, 5:6, , ])))   # 0

  # The scoring that matters. A forecast has to beat carrying the
  # last observed SOC map forward, so report that baseline beside
  # the model, in g/kg, at every horizon.
  rmse <- function(a, b) sqrt(mean((a - b)^2))
  sd_  <- tt$scaling$soc_sd
  print(round(rbind(
    convlstm    = sd_ * c(h1 = rmse(fc[1, 1, , ], fut_y[1, 1, , ]),
                          h2 = rmse(fc[1, 2, , ], fut_y[1, 2, , ])),
    persistence = c(h1 = rmse(cube$soc[4, , ], cube$soc[5, , ]),
                    h2 = rmse(cube$soc[4, , ], cube$soc[6, , ]))), 3))
  #                h1    h2
  # convlstm    1.875 4.635
  # persistence 3.094 6.822

  # It does beat persistence at both horizons -- and the in-sample
  # error still oversells it by a factor of six at h = 1. A fitted
  # window and a forecast are two different claims; print them
  # together or the first will be mistaken for the second.
  ins <- temporal_convlstm_predict(fit, past)
  print(round(sd_ * rmse(ins, past_y), 3))          # 0.288

  # Training longer widens that gap rather than closing it: the fit
  # keeps improving while the forecast decays.
  more <- temporal_convlstm_fit(past, past_y, hidden_dims = 8L,
                                return_sequence = TRUE,
                                epochs = 300L, lr = 0.05, seed = 1L)
  fc2 <- temporal_convlstm_rollout(more, past, fut)
  print(round(c(
    in_sample = sd_ * rmse(temporal_convlstm_predict(more, past), past_y),
    h1 = sd_ * rmse(fc2[1, 1, , ], fut_y[1, 1, , ]),
    h2 = sd_ * rmse(fc2[1, 2, , ], fut_y[1, 2, , ])), 3))
  # in_sample        h1        h2
  #     0.176     2.451     5.685

  # The cause is not compounding feedback -- there is none -- it is
  # extrapolation. A third of the forecast window is wetter than
  # any month the model trained on, and most of its SOC sits above
  # the training range, so the head is asked for values it was
  # never shown. Check this BEFORE trusting a rollout.
  print(round(c(
    drivers_above_train = mean(fut[1, , 2, , ] > max(past[1, , 2, , ])),
    target_above_train  = mean(fut_y > max(past_y))), 3))
  # drivers_above_train  target_above_train
  #               0.328               0.578

  # A sequence-to-one model has no per-step head to roll forward,
  # and is refused rather than silently reinterpreted.
  s2o <- temporal_convlstm_fit(
    past, array(past_y[1, 4, , ], dim = c(1, 8, 8)),
    epochs = 1L, seed = 1L)
  print(tryCatch(temporal_convlstm_rollout(s2o, past, fut),
                 error = function(e) conditionMessage(e)))
  # "isTRUE(object$return_sequence) is not TRUE"
}
```
