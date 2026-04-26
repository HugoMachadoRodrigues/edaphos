# Build a lazy patch dataset over a `terra::SpatRaster`

Returns an `edaphos_tile_dataset` S3 object that knows how to sample
batched `(B, C, H, W)` tensors from the underlying raster on demand –
without ever loading the whole mosaic into memory. The dataset is what
[`foundation_moco_pretrain_tiles()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain_tiles.md)
consumes.

## Usage

``` r
foundation_tile_dataset(
  stack,
  patch_size = 16L,
  n_patches = 1000L,
  valid_mask = NULL,
  normalise = TRUE,
  seed = NULL
)
```

## Arguments

- stack:

  A
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  with the channels to sample.

- patch_size:

  Integer – spatial side of each patch.

- n_patches:

  Integer – total number of patches the dataset should expose. Sampling
  is with replacement when `n_patches > total valid cells`.

- valid_mask:

  Optional
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  of 0/1 defining which cells are eligible as patch centres.

- normalise:

  Logical – if `TRUE` (default) each channel is standardised to zero
  mean / unit standard deviation based on the raster's global
  statistics.

- seed:

  Optional integer for reproducibility.

## Value

A list of class `edaphos_tile_dataset` with slots `stack`, `patch_size`,
`n_patches`, `n_channels`, `means`, `sds`, `valid_cells`; and a
`sample(batch_size)` function that returns a `(batch_size, C, H, W)` R
array.

## Details

Patch centres are drawn uniformly within the AoI, optionally constrained
to a `valid_mask` (e.g. a land-sea mask or a biome polygon). Each patch
is a `patch_size x patch_size` window extracted from the raster; missing
values are replaced by the per-layer mean.
