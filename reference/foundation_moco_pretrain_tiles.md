# Dataset-backed MoCo v2 pre-training for planetary-scale corpora

Drop-in streaming variant of
[`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md)
that reads patches on the fly from an `edaphos_tile_dataset` (see
[`foundation_tile_dataset()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_dataset.md)).
The point is to train on real multi-source raster mosaics – SoilGrids,
WorldClim, SRTM, MODIS, ERA5 – that do not fit in RAM as a single
`(N, C, H, W)` array.

## Usage

``` r
foundation_moco_pretrain_tiles(
  dataset,
  feature_dim = 64L,
  proj_dim = 32L,
  queue_size = 1024L,
  momentum = 0.999,
  temperature = 0.07,
  batch_size = 16L,
  epochs = 100L,
  lr = 0.03,
  crop_ratio = c(0.6, 1),
  flip_prob = 0.5,
  rot90_prob = 0.75,
  channel_drop_prob = 0.2,
  cutout_prob = 0.3,
  cutout_size_ratio = 0.2,
  brightness_jitter = 0.2,
  noise_sd = 0.1,
  device = c("cpu", "mps", "cuda"),
  seed = NULL,
  verbose = FALSE,
  checkpoint_dir = NULL,
  checkpoint_every = 10L,
  resume = NULL
)
```

## Arguments

- dataset:

  An `edaphos_tile_dataset`.

- feature_dim, proj_dim, queue_size, momentum, temperature, batch_size,
  epochs, lr, crop_ratio, flip_prob, rot90_prob, channel_drop_prob,
  cutout_prob, cutout_size_ratio, brightness_jitter, noise_sd, seed,
  verbose:

  As in
  [`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md).

- device:

  Backend for the training loop. One of `"cpu"` (default), `"mps"`
  (Apple Silicon GPU via Metal) or `"cuda"` (NVIDIA).
  Requested-but-unavailable backends fall back to `"cpu"` with a
  message. Added in v1.2.0.

- checkpoint_dir:

  Optional directory for periodic checkpoints.

- checkpoint_every:

  Integer – save a checkpoint every `k` epochs.

- resume:

  Optional path to a checkpoint directory to restart from.

## Value

An `edaphos_foundation_moco` (identical structure to
[`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md)).

## Details

Checkpointing is optional but recommended for long runs: every
`checkpoint_every` epochs the encoder state dicts, the dictionary queue,
the loss history and the configuration are written to `checkpoint_dir`.
Pass `resume = path` to restart from that checkpoint.
