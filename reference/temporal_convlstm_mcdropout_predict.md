# MC-dropout predictive draws from a ConvLSTM fit

Runs `n_draws` forward passes through a fitted
`edaphos_temporal_convlstm` with dropout active in train mode, producing
a Monte-Carlo sample of the predictive posterior (Gal and Ghahramani
2016). The fit must have been trained with `dropout_p > 0` for this to
give a non-degenerate sample; when the fit has no dropout layers the
draws collapse to the deterministic forward pass.

## Usage

``` r
temporal_convlstm_mcdropout_predict(
  object,
  sequence,
  n_draws = 50L,
  return_sequence = NULL,
  seed = NULL
)
```

## Arguments

- object:

  An `edaphos_temporal_convlstm` whose underlying `nn_module` contains
  `nn_dropout2d` layers. Fits produced by
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
  with the default `dropout_p = 0` work but produce a degenerate
  constant draw.

- sequence:

  5-D input tensor `(batch, T, C, H, W)` or equivalent R array.

- n_draws:

  Integer; number of MC forward passes.

- return_sequence:

  Logical override; defaults to the value used at training time.

- seed:

  Optional integer seed.

## Value

A numeric array; first axis is the draw axis. Shape:
`(n_draws, batch, T, H, W)` when `return_sequence = TRUE`, else
`(n_draws, batch, H, W)`.

## References

Gal, Y. and Ghahramani, Z. (2016). Dropout as a Bayesian approximation:
representing model uncertainty in deep learning. *ICML 33*, 1050-1059.
