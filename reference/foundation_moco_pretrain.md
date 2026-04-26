# Pillar 4 – MoCo v2 pre-training on raster covariate patches

Self-supervised momentum-contrastive pre-training (He et al. 2020; Chen
et al. 2020) with a raster-specific augmentation stack. Compared to the
SimCLR scaffold in
[`foundation_simclr_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_simclr_pretrain.md),
MoCo v2 introduces three architectural upgrades:

## Usage

``` r
foundation_moco_pretrain(
  patches,
  feature_dim = 64L,
  proj_dim = 32L,
  queue_size = 1024L,
  momentum = 0.999,
  temperature = 0.07,
  batch_size = 16L,
  epochs = 30L,
  lr = 0.03,
  crop_ratio = c(0.6, 1),
  flip_prob = 0.5,
  rot90_prob = 0.75,
  channel_drop_prob = 0.2,
  cutout_prob = 0.3,
  cutout_size_ratio = 0.2,
  brightness_jitter = 0.2,
  noise_sd = 0.1,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- patches:

  A 4-D array shaped `(N, C, H, W)` – `N` patches, `C` covariate
  channels, spatial `H x W`.

- feature_dim, proj_dim:

  Integer widths of the backbone output and the contrastive projection
  head.

- queue_size:

  Integer `K` – number of negatives stored in the FIFO dictionary queue.

- momentum:

  Numeric in `(0, 1)` – EMA coefficient for the key encoder (MoCo paper
  default is 0.999).

- temperature:

  Numeric `> 0` – InfoNCE temperature (MoCo v2 default is 0.07).

- batch_size, epochs, lr:

  Integer / numeric – Adam optimiser hyperparameters.

- crop_ratio:

  Numeric length-2 vector – random-resized-crop ratio range.

- flip_prob, rot90_prob:

  Probabilities of horizontal / vertical flip and 90-deg rotation.

- channel_drop_prob:

  Probability of zeroing any given channel independently.

- cutout_prob, cutout_size_ratio:

  Probability of spatial cutout and its size ratio.

- brightness_jitter:

  Numeric `[0, 1)` – per-channel multiplicative brightness range.

- noise_sd:

  Numeric `>= 0` – additive-noise standard deviation.

- seed, verbose:

  As elsewhere in the package.

## Value

An `edaphos_foundation_moco` S3 object containing the fitted query
encoder (use
[`foundation_moco_embed()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed.md)
to extract embeddings), the key encoder, the training loss history and
the configuration.

## Details

- A **momentum key encoder** updated by exponential moving average:
  \\\theta_k \leftarrow m\\\theta_k + (1-m)\\\theta_q\\.

- A **dictionary queue** of past keys, so every mini-batch sees `K`
  negatives rather than `2B - 2`.

- A wider residual CNN backbone (~feature_dim = 64 by default) followed
  by a 2-layer projection head with BatchNorm, matching the MoCo v2
  recipe.

The augmentation stack is tuned for multi-channel raster patches rather
than natural photographs: spatial random resized crop, horizontal /
vertical flip, 90-degree rotations, per-channel Bernoulli dropout
(missing-band simulation), spatial cutout (cloud-mask simulation),
per-channel multiplicative brightness jitter, and additive Gaussian
sensor noise.
