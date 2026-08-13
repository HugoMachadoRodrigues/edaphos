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

## Examples

``` r
# torch_is_installed() is the half of the guard that matters on a
# fresh machine: the R package installs in seconds, the libtorch /
# lantern binaries behind it are a separate download.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed()) &&
    requireNamespace("terra", quietly = TRUE)) {

# A tile dataset streams patches out of a raster instead of holding
# an (N, C, H, W) array in RAM. The mosaic here is small enough to
# build in memory from `br_cerrado`, but the call sequence is the
# one you use for a SoilGrids + WorldClim + SRTM stack that is not.
covs <- terra::rast(br_cerrado[, c("x", "y", "elev", "slope", "twi",
                                   "map_mm", "ndvi")], type = "xyz")
ds <- foundation_tile_dataset(covs, patch_size = 8L, n_patches = 64L,
                              seed = 7L)

set.seed(11)
mt <- foundation_moco_pretrain_tiles(ds, feature_dim = 16L,
                                     proj_dim = 8L, queue_size = 32L,
                                     batch_size = 8L, epochs = 6L,
                                     seed = 11L, device = "cpu")
print(mt)

# Unlike foundation_moco_pretrain(), `queue_size` is honoured here
# rather than clamped to the corpus size. The FIFO still only
# retains queue_size - batch_size old keys per step, so this is the
# knob that decides how much of a dictionary you actually have.
print(c(queue = mt$queue_size, batch = mt$batch_size,
        retained = mt$queue_size - mt$batch_size))

# The queue is warmed by drawing min(queue_size, 4 * batch_size)
# patches in a single call, and foundation_tile_dataset() refuses a
# draw larger than `n_patches`. So the dataset must satisfy
# n_patches >= min(queue_size, 4 * batch_size); below, min(256, 32)
# is 32 and the dataset only holds 20.
small <- foundation_tile_dataset(covs, patch_size = 8L,
                                 n_patches = 20L, seed = 3L)
try(foundation_moco_pretrain_tiles(small, feature_dim = 8L,
                                   proj_dim = 4L, queue_size = 256L,
                                   batch_size = 8L, epochs = 2L,
                                   seed = 3L))

# `device` is resolved, not obeyed: an unavailable backend prints a
# note and the run silently continues on CPU. Read the resolved
# value back rather than trusting the argument you passed -- a
# "GPU run" that took CPU wall-clock is usually this.
set.seed(11)
gpu <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
                                      proj_dim = 4L, queue_size = 32L,
                                      batch_size = 8L, epochs = 2L,
                                      seed = 11L, device = "cuda")
print(identical(gpu$device,
                if (torch::cuda_is_available()) "cuda" else "cpu"))

# Checkpointing is what makes a multi-day run restartable. Four
# epochs at checkpoint_every = 2 leave both encoders, the dictionary
# queue and the loss history on disk; `resume=` restores them and
# carries on at the stored next_epoch, so run2 holds run1's four
# losses verbatim plus the two new ones.
ck <- file.path(tempdir(), "moco_ck")
set.seed(21)
run1 <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
                                       proj_dim = 4L, queue_size = 32L,
                                       batch_size = 8L, epochs = 4L,
                                       seed = 21L, checkpoint_dir = ck,
                                       checkpoint_every = 2L)
print(list.files(ck))
set.seed(22)
run2 <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
                                       proj_dim = 4L, queue_size = 32L,
                                       batch_size = 8L, epochs = 6L,
                                       seed = 22L, resume = ck)
print(length(run2$loss_history))
print(identical(run2$loss_history[1:4], run1$loss_history))
unlink(ck, recursive = TRUE)
}

if (FALSE) { # \dontrun{
# The real target: a multi-source mosaic that does not fit in RAM.
# Every source below downloads, so this block is never run by
# examples -- but it is the working pipeline.
aoi  <- c(-48.5, -47.0, -16.5, -15.0)   # xmin, xmax, ymin, ymax
srtm <- foundation_tile_source_srtm(aoi, derive = c("slope", "TPI"),
                                    country = "BRA")
clim <- foundation_tile_source_worldclim(c("prec", "tavg"),
                                         country = "BRA", aoi = aoi)
soil <- foundation_tile_source_soilgrids(c("soc", "clay"),
                                         depth = "0-5cm", aoi = aoi)
mosaic <- foundation_tile_align(
  list(srtm = srtm, clim = clim, soil = soil),
  target_res = 0.005, aoi = aoi)
ds_big <- foundation_tile_dataset(mosaic, patch_size = 32L,
                                  n_patches = 20000L, seed = 1L)
moco <- foundation_moco_pretrain_tiles(
  ds_big, queue_size = 4096L, batch_size = 64L, epochs = 20000L,
  device = "mps", checkpoint_dir = "moco_ck", checkpoint_every = 500L,
  verbose = TRUE)
} # }
```
