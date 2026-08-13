# Apply a fitted MoCo v2 encoder over a full raster mosaic

Slides a `patch_size x patch_size` window over the input raster at
stride `stride`, extracts each patch, encodes it with the backbone of
`moco$encoder_q`, and writes the resulting embedding vector back as a
multi-layer
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
whose layer count equals `moco$feature_dim`. Patches whose centre cell
is NA in the input produce an NA row in the output.

## Usage

``` r
foundation_moco_embed_raster(
  moco,
  stack,
  dataset,
  patch_size = NULL,
  stride = NULL,
  projection = FALSE
)
```

## Arguments

- moco:

  An `edaphos_foundation_moco` returned by
  [`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md).

- stack:

  A
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  with the **same channel order** as the one used at training time.

- dataset:

  The `edaphos_tile_dataset` used at training time (provides the
  per-channel normalisation statistics).

- patch_size:

  Integer – must equal `dataset$patch_size`.

- stride:

  Integer step size of the sliding window (default half of
  `patch_size`).

- projection:

  Logical – if `TRUE` return the L2-normalised projection-head outputs
  instead of the backbone features.

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with `feature_dim` (or `proj_dim`) layers.

## Details

Normalisation uses the global per-layer mean and sd stored in `dataset`,
so the embedding pipeline is consistent between pretraining and
inference.

## Examples

``` r
# Guard on the libtorch binaries as well as on the R package --
# requireNamespace() alone is TRUE on machines that cannot run a
# single tensor operation.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed()) &&
    requireNamespace("terra", quietly = TRUE)) {

covs <- terra::rast(br_cerrado[, c("x", "y", "elev", "slope", "twi",
                                   "map_mm", "ndvi")], type = "xyz")
ds <- foundation_tile_dataset(covs, patch_size = 8L, n_patches = 64L,
                              seed = 7L)
set.seed(11)
moco <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
                                       proj_dim = 4L, queue_size = 32L,
                                       batch_size = 8L, epochs = 6L,
                                       seed = 11L)

# One output layer per backbone feature, on a grid coarsened by
# `stride`. Pass the same `dataset` you trained on: its per-channel
# means and sds are the normalisation, and a different dataset would
# feed the encoder a differently-scaled raster.
emb <- foundation_moco_embed_raster(moco, covs, ds, stride = 8L)
print(c(layers = terra::nlyr(emb), feature_dim = moco$feature_dim))
print(terra::res(emb) / terra::res(covs))

# TRAP: the output is not co-registered with the input. The grid is
# anchored at the input's top-left corner and is ncol(emb) * stride
# input columns wide, so with 45 columns and stride 8 the last five
# columns -- and the last five rows -- of `covs` are not covered.
print(terra::ncol(covs) - 8L * terra::ncol(emb))
print(rbind(covs = as.vector(terra::ext(covs)),
            emb  = as.vector(terra::ext(emb))))

# It overshoots just as happily in the other direction: stride 24
# gives two columns of 24 cells, i.e. 48 > 45, and the embedding
# raster sticks out past the input. Always crop or resample to a
# reference grid before overlaying anything on it.
emb24 <- foundation_moco_embed_raster(moco, covs, ds, stride = 24L)
print(c(covered = 24L * terra::ncol(emb24),
        input = terra::ncol(covs),
        overshoots = terra::xmax(emb24) > terra::xmax(covs)))

# TRAP: missing data is imputed, not propagated. NA cells are set to
# the channel mean before encoding, so a patch that is entirely
# no-data -- all five channels blank, below -- still gets a finite
# embedding. The output cannot be used to find gaps: carry a separate
# mask.
blank <- terra::cellFromRowCol(covs, rep(1:8, each = 8), rep(1:8, 8))
gap <- terra::deepcopy(covs)
for (k in 1:5) gap[[k]][blank] <- NA
emb_gap <- foundation_moco_embed_raster(moco, gap, ds, stride = 24L)
print(colSums(is.na(terra::values(gap))))
print(c(na_in_output = sum(is.na(terra::values(emb_gap)))))

# Rows 1:8 / columns 1:8 are exactly the window of the first stride-24
# patch, so row 1 of the gapped output is the all-NA patch. Finite it
# is; "close to an average patch" it is not, and nothing in the
# encoder pulls it there. The line below prints its distance to the
# mean of the four real embeddings, then how far the real patches
# themselves sit from that same mean, on average and at worst. The
# blank patch comes out FARTHER from the average than the average
# real patch is -- the opposite of reassuring. Read the printed
# values, do not quote a number from this comment: they move with the
# fit, and this one is 6 optimiser steps on 64 patches. Nor is the
# gap recoverable this way in general; the load-bearing number is the
# NA count above -- zero NA reaches the output, so carry a mask.
real <- terra::values(emb24)
ctr  <- colMeans(real)
print(round(c(blank_to_mean = sqrt(sum((terra::values(emb_gap)[1, ] -
                                          ctr)^2)),
              real_to_mean_mean = mean(sqrt(rowSums(sweep(real, 2,
                                                          ctr)^2))),
              real_to_mean_max  = max(sqrt(rowSums(sweep(real, 2,
                                                         ctr)^2)))), 3))

# `projection = TRUE` swaps in the L2-normalised head, so each cell
# of the output has unit length across layers: a ready-made cosine
# similarity space, and a useless magnitude map.
embp <- foundation_moco_embed_raster(moco, covs, ds, stride = 24L,
                                     projection = TRUE)
print(c(layers = terra::nlyr(embp), proj_dim = moco$proj_dim))
print(range(round(sqrt(rowSums(terra::values(embp)^2)), 6)))
}
```
