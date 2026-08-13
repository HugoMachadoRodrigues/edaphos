# MC-dropout predictive draws from a ConvLSTM fit

Runs `n_draws` forward passes through a fitted
`edaphos_temporal_convlstm` with dropout active in train mode, producing
a Monte-Carlo sample of the predictive posterior (Gal and Ghahramani
2016).

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
  `nn_dropout2d` layers. A fit taken straight from
  [`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
  is accepted, but returns `n_draws` identical copies of the
  deterministic forward pass.

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

## Details

The module has to contain dropout layers for the sample to be
non-degenerate.
[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md)
takes no dropout argument and the stack it builds – ConvLSTM cells plus
a 1x1 convolutional head – contains none, so on an unmodified fit every
draw is bit-identical and the posterior sd is exactly zero, not merely
small. Splicing an `nn_dropout2d` in front of the head, as the example
does, is the shortest route to a real MC-dropout posterior; it samples
the head's weights only and stays blind to the frozen ConvLSTM backbone
beneath it.

## References

Gal, Y. and Ghahramani, Z. (2016). Dropout as a Bayesian approximation:
representing model uncertainty in deep learning. *ICML 33*, 1050-1059.

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {

  cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L,
                                  seed = 42L)
  tt   <- temporal_cube_to_tensor(cube)
  past_seq <- tt$sequence[, 1:9, , , , drop = FALSE]
  past_tgt <- tt$target[,   1:9, , , drop = FALSE]
  fit <- temporal_convlstm_fit(past_seq, past_tgt, hidden_dims = 4L,
                               return_sequence = TRUE, epochs = 20L,
                               lr = 0.05, seed = 7L)

  # First trap: this fit contains no dropout layer, so MC-dropout on
  # it is a no-op. The 20 draws are bit-identical -- the posterior sd
  # is 0, not 1e-6. A silent zero-width posterior is exactly the
  # failure mode you must check for before trusting any spread.
  draws <- temporal_convlstm_mcdropout_predict(
    fit, sequence = tt$sequence, n_draws = 20L, seed = 11L,
    return_sequence = TRUE)
  print(dim(draws))                       # (n_draws, batch, T, H, W)
  print(max(apply(draws, 2:5, stats::sd)))          # 0
  print(grep("dropout", names(fit$model$modules), value = TRUE,
             ignore.case = TRUE))                   # character(0)

  # Put a dropout layer in front of the 1x1 head to get a real
  # posterior. Second trap: torch modules are references, so `fit2`
  # and `fit` share one module and this edits both.
  fit2 <- fit
  fit2$model$head <- torch::nn_sequential(torch::nn_dropout2d(p = 0.2),
                                          fit2$model$head)
  print(any(names(fit$model$modules) == "head.1"))  # TRUE: fit too

  draws <- temporal_convlstm_mcdropout_predict(
    fit2, sequence = tt$sequence, n_draws = 40L, seed = 11L,
    return_sequence = TRUE)
  mu_z <- apply(draws, 2:5, mean)
  sd_z <- apply(draws, 2:5, stats::sd)

  # Score that one posterior on the last training month and on month
  # 12, three months past the end of the training window.
  score <- function(m) {
    mu <- as.numeric(mu_z[1L, m, , ]) * tt$scaling$soc_sd +
          tt$scaling$soc_mu
    s  <- as.numeric(sd_z[1L, m, , ]) * tt$scaling$soc_sd
    y  <- as.numeric(cube$soc[m, , ])
    c(spread = mean(s),
      rmse   = edaphos_rmse(y, mu),
      bias   = edaphos_bias(y, mu),
      picp90 = edaphos_picp(y, mu - 1.645 * s, mu + 1.645 * s),
      IS     = edaphos_interval_score(y, mu - 1.645 * s,
                                      mu + 1.645 * s, alpha = 0.10))
  }
  print(round(rbind(month_09_in_sample = score(9L),
                    month_12_forecast  = score(12L)), 3))

  # The spread hardly moves between the two rows (4.72 -> 4.43 g/kg)
  # while RMSE nearly quadruples (2.17 -> 8.46) and the bias goes
  # from 0.09 to 8.01 g/kg, dropping coverage 1.000 -> 0.438.
  # MC-dropout samples the head's weights, not the lead time: it
  # cannot see the frozen backbone's extrapolation error, the same
  # blind spot a deep ensemble has -- see
  # ?temporal_convlstm_ensemble_rollout.

  # And read the in-sample row sceptically too: PICP 1.000 comes
  # from a band 2 * 1.645 * 4.72 = 15.5 g/kg wide on a variable
  # whose whole-cube sd is 9.58 g/kg. The interval score charges for
  # that width -- 15.52 there is all width and no miss penalty.
  print(round(stats::sd(cube$soc), 2))
}
```
