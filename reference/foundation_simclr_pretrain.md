# SimCLR pre-training on raster covariate patches (Pillar 4 scaffold)

Trains a small CNN encoder on unlabeled raster patches via the SimCLR
contrastive objective. Each forward pass draws two independent augmented
views of every patch in the mini-batch and enforces high embedding
similarity between views of the same patch and low similarity otherwise.

## Usage

``` r
foundation_simclr_pretrain(
  patches,
  feature_dim = 32L,
  proj_dim = 16L,
  batch_size = 8L,
  epochs = 30L,
  lr = 0.005,
  temperature = 0.2,
  noise_sd = 0.1,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- patches:

  A 4-D R array shaped `(N, C, H, W)`: `N` patches, `C` covariate
  channels, spatial `H x W`.

- feature_dim, proj_dim:

  Integer; backbone and projection head widths.

- batch_size:

  Integer; SimCLR mini-batch size. Each batch contributes
  `2 * batch_size - 2` negatives per anchor.

- epochs, lr:

  Training hyperparameters for Adam.

- temperature:

  Numeric; NT-Xent temperature.

- noise_sd:

  Numeric; additive-noise strength during augmentation.

- seed, verbose:

  As elsewhere.

## Value

A `edaphos_foundation_simclr` object (S3).
