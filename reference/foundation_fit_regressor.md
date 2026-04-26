# Fine-tune or linearly probe a Pillar 4 encoder for regression

Regression counterpart of
[`foundation_fit_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_classifier.md).
Attaches a scalar-output head (linear or MLP) on top of a
self-supervised encoder and trains it against a numeric target `y`.
Supports the same two regimes — linear probing with a frozen backbone or
full fine-tuning with a two-group learning rate — and the same
`device ∈ {"cpu", "mps", "cuda"}` dispatch.

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
  ds   <- readRDS("tools/pretrain/cerrado_dataset.rds")
  patches <- array(rnorm(300 * ds$n_channels * 16 * 16),
                   dim = c(300, ds$n_channels, 16, 16))
  soc <- rnorm(300, mean = 15, sd = 6)
  fit <- foundation_fit_regressor(
    moco, patches, soc,
    freeze_backbone = TRUE, head = "linear",
    epochs = 40L, device = "mps", seed = 1L
  )
  predict(fit, patches[1:10, , , , drop = FALSE])
} # }
```
