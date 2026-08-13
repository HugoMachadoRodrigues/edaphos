# Predict with a fitted stacked ConvLSTM

Predict with a fitted stacked ConvLSTM

## Usage

``` r
temporal_convlstm_predict(object, sequence, return_sequence = NULL, ...)
```

## Arguments

- object:

  A `edaphos_temporal_convlstm`.

- sequence:

  Array / `torch_tensor` of shape `(batch, T, C, H, W)`.

- return_sequence:

  Logical override; defaults to the value used at training time.

- ...:

  Unused.

## Value

An R array. Shape is `(batch, T, H, W)` when `return_sequence = TRUE`,
otherwise `(batch, H, W)`.

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {
  cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
  tt   <- temporal_cube_to_tensor(cube)
  y6   <- array(tt$target[1, 6, , ], dim = c(1, 8, 8))
  fit  <- temporal_convlstm_fit(tt$sequence, y6, hidden_dims = 4L,
                                epochs = 150L, lr = 0.05, seed = 1L)

  p1 <- temporal_convlstm_predict(fit, tt$sequence)
  print(dim(p1))                          # 1 8 8

  # return_sequence is an override, not a retrain: the same 1x1 head
  # is simply read at every step instead of only the last one. So
  # the last slice of the sequence output is bit-identical to the
  # sequence-to-one output -- no second model is involved.
  ps <- temporal_convlstm_predict(fit, tt$sequence,
                                  return_sequence = TRUE)
  print(dim(ps))                          # 1 6 8 8
  print(max(abs(ps[1, 6, , ] - p1[1, , ])))   # 0

  # The five earlier maps are not free predictions. This model was
  # only ever scored on month 6, and the per-step RMSE (z units)
  # says so: month 1 is off by nearly two standard deviations.
  print(round(vapply(1:6, function(t)
    sqrt(mean((ps[1, t, , ] - tt$target[1, t, , ])^2)), 0), 3))
  # 1.883 1.727 1.463 1.153 0.703 0.095

  # Output is in the z units of tt$scaling, never g/kg. Rescale
  # before reporting, and read the error next to the spread of the
  # month it is scoring.
  sc <- tt$scaling
  y6z <- tt$target[1, 6, , ]
  print(round(c(
    rmse_gkg  = sc$soc_sd * sqrt(mean((p1[1, , ] - y6z)^2)),
    sd_month6 = sd(as.vector(cube$soc[6, , ]))), 3))
  #  rmse_gkg sd_month6
  #     0.410     3.189
}
```
