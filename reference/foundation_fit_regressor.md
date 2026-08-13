# Fine-tune or linearly probe a Pillar 4 encoder for regression

Regression counterpart of
[`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md).
Attaches a scalar-output head (linear or MLP) on top of a
self-supervised encoder and trains it against a numeric target `y`.
Supports the same two regimes — linear probing with a frozen backbone or
full fine-tuning with a two-group learning rate — and the same `device`
dispatch over `"cpu"`, `"mps"` and `"cuda"`.

## Usage

``` r
foundation_fit_regressor(
  encoder,
  x,
  y,
  freeze_backbone = TRUE,
  head = c("linear", "mlp"),
  hidden = c(64L, 32L),
  dropout = 0,
  epochs = 30L,
  batch_size = 32L,
  lr = 0.001,
  weight_decay = 0,
  backbone_lr_mult = 0.1,
  loss = c("mse", "huber"),
  val_split = 0.2,
  device = c("cpu", "mps", "cuda"),
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- encoder:

  See
  [`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md).

- x:

  A 4-D array `(N, C, H, W)` of patches.

- y:

  Numeric vector of length `N` with the target values.

- freeze_backbone, head, hidden, dropout, epochs, batch_size, lr,
  weight_decay, backbone_lr_mult, val_split, device, seed, verbose:

  See
  [`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md).

- loss:

  One of `"mse"` (default) or `"huber"`. Huber is more robust to outlier
  pedons with extreme SOC / clay contents.

## Value

An `edaphos_foundation_regressor` list with the same slots as the
classifier counterpart plus `y_mean`, `y_sd` (target normalisation
constants) and `val_rmse_history`.

## Details

Target normalisation is handled internally: `y` is centred and scaled
before training and un-scaled at
[`predict()`](https://rdrr.io/r/stats/predict.html) time so the user
never has to think about the numerical range of the head.

## See also

[`predict.edaphos_foundation_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_foundation_regressor.md).

## Examples

``` r
if (FALSE) { # \dontrun{
  moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
  n_ch <- moco$n_channels

  # SYNTHETIC PATCHES, NOT A SOIL SURVEY -- as in
  # foundation_fit_classifier(), the signal is planted by hand.
  # Each patch gets its own offset in channel 1 and `soc` is a
  # linear function of that offset plus noise, so the target really
  # does depend on the patch it is paired with.
  set.seed(2)
  level   <- rnorm(300)
  patches <- array(rnorm(300 * n_ch * 16 * 16),
                   dim = c(300, n_ch, 16, 16))
  patches[, 1, , ] <- patches[, 1, , ] + level
  soc <- 15 + 6 * level + rnorm(300, sd = 2)   # stands in for g/kg

  fit <- foundation_fit_regressor(
    moco, patches, soc,
    freeze_backbone = TRUE, head = "linear",
    epochs = 40L, device = "mps", seed = 1L
  )

  # An RMSE means nothing on its own: compare it with the RMSE of
  # predicting mean(soc) for every patch, which is sd(soc). A local
  # encoder of the same architecture cuts it to about two fifths of
  # that -- and that ratio is a property of the planted signal, not
  # evidence that the encoder knows anything about carbon.
  print(c(best_val_rmse       = min(fit$val_rmse_history, na.rm = TRUE),
          intercept_only_rmse = stats::sd(soc)))

  pred <- predict(fit, patches)
  print(c(cor_pred_soc = stats::cor(pred, soc)))
  print(round(utils::head(pred, 10), 2))

  # Delete the line that adds `level` into `patches` -- i.e. make
  # `soc` independent of the input, as an earlier version of this
  # example did -- and the only attainable model is the intercept:
  # `cor_pred_soc` goes to ~0, the ten printed predictions bunch up
  # near mean(soc) instead of tracking it, and the held-out RMSE
  # stops beating sd(soc) (it lands slightly worse, since the head
  # still fits the training noise). Printing predictions from that
  # fit, as the earlier example did, shows an intercept dressed up
  # as a soil map.

  # Nothing here maps SOC. That needs patches cut from real
  # covariate rasters (foundation_tile_align() ->
  # foundation_tile_dataset()), standardised over your own area of
  # interest, and measured SOC at those same locations.
} # }
```
