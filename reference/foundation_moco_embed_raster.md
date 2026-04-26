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
