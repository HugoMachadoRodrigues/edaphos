# Fine-tune or linearly probe a Pillar 4 encoder for classification

Attaches a classification head on top of a self-supervised encoder
produced by
[`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md),
[`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md)
or
[`foundation_simclr_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_pretrain.md)
and trains it against a labelled patch set. Two standard regimes from
the transfer-learning literature are supported:

## Usage

``` r
foundation_fit_classifier(
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
  val_split = 0.2,
  device = c("cpu", "mps", "cuda"),
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- encoder:

  An `edaphos_foundation_moco` or `edaphos_foundation_simclr` fit, or a
  bare `nn_module` that accepts `(batch, C, H, W)` input and returns
  either an embedding tensor or a list with a `feature` field.

- x:

  A 4-dimensional R array `(N, C, H, W)` of labelled patches, of the
  same shape that was used to pretrain the encoder.

- y:

  A factor (or coercible character / integer) of length `N` with the
  patch-level class labels.

- freeze_backbone:

  Logical — `TRUE` for linear probing (default), `FALSE` for full
  fine-tuning. When `FALSE`, the encoder is put into training mode and
  its gradients flow back through the classification loss.

- head:

  `"linear"` (default) or `"mlp"`.

- hidden:

  Integer vector with MLP hidden-layer widths when `head = "mlp"`.
  Default `c(64L, 32L)`.

- dropout:

  Dropout probability in the MLP head (0 = disabled).

- epochs, batch_size, lr:

  Training hyperparameters.

- weight_decay:

  Adam weight decay (L2 regularisation).

- backbone_lr_mult:

  Multiplicative factor applied to `lr` for the encoder parameters when
  `freeze_backbone = FALSE`. Default `0.1`; set to `1.0` to train the
  backbone at full speed.

- val_split:

  Fraction of `x` held out for validation. `0` disables validation.

- device:

  `"cpu"` (default), `"mps"` or `"cuda"`. When the requested backend is
  unavailable the function falls back to `"cpu"` with a message.

- seed:

  Optional integer — seeds torch, NumPy and the train/val split.

- verbose:

  Logical — print loss / accuracy every 10 epochs.

## Value

An `edaphos_foundation_classifier` list with:

- encoder, head:

  The trained torch modules.

- classes:

  The character factor levels used for prediction.

- loss_history, val_accuracy_history:

  Per-epoch training loss and validation accuracy (NA when
  `val_split = 0`).

- config:

  List of the inputs to `foundation_fit_classifier()` for
  reproducibility.

## Details

- Linear probe (`freeze_backbone = TRUE`, `head = "linear"`):

  The encoder weights are frozen; only a single
  `nn_linear(feature_dim, n_classes)` head is trained. This is the
  canonical benchmark for evaluating self-supervised representations as
  fixed feature extractors (He, Girshick and Dollar 2019).

- Full fine-tuning (`freeze_backbone = FALSE`):

  The encoder and the head are trained jointly, with a two-group
  learning rate (`lr * backbone_lr_mult` for the backbone, `lr` for the
  head). Usually the better option when the downstream dataset is large
  enough (≥ ~500 patches per class).

## References

He, K., Girshick, R. and Dollar, P. (2019). Rethinking ImageNet
pre-training. *ICCV 2019*.

Kornblith, S., Shlens, J. and Le, Q. V. (2019). Do better ImageNet
models transfer better? *CVPR 2019*.

## See also

[`predict.edaphos_foundation_classifier()`](https://hugomachadorodrigues.github.io/edaphos/reference/predict.edaphos_foundation_classifier.md),
[`foundation_fit_regressor()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_fit_regressor.md),
[`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md).

## Examples

``` r
if (FALSE) { # \dontrun{
  ds <- readRDS("tools/pretrain/cerrado_dataset.rds")
  moco <- foundation_weights_load("edaphos-cerrado-moco-v1")

  # Label a subset of patches by soil order (synthetic example).
  patches <- array(rnorm(200 * ds$n_channels * 16 * 16),
                   dim = c(200, ds$n_channels, 16, 16))
  soil_order <- factor(sample(c("Oxisol", "Ultisol", "Inceptisol"),
                               200, replace = TRUE))

  fit <- foundation_fit_classifier(
    moco, patches, soil_order,
    freeze_backbone = TRUE, head = "linear",
    epochs = 40L, device = "mps", seed = 1L
  )
  pred <- predict(fit, patches, type = "class")
} # }
```
