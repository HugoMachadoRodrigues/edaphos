# Extract foundation-model embeddings at a set of query coordinates

For each row of `coords` (longitude, latitude) crops a
`patch_size x patch_size` window out of the raster `stack`, normalises
every channel with the training means / sds stored in `dataset`, and
runs the MoCo v2 encoder forward to get one embedding vector per query
point. Returns the resulting `(n_coords, D)` matrix where `D` is either
the backbone feature dimension (when `projection = FALSE`, the default)
or the projection-head output dimension.

## Usage

``` r
foundation_embed_at_coords(
  moco,
  coords,
  stack,
  dataset,
  patch_size = NULL,
  projection = FALSE,
  batch_size = 32L
)
```

## Arguments

- moco:

  An `edaphos_foundation_moco` (as returned by
  [`foundation_weights_load()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_weights_load.md)
  or
  [`foundation_moco_pretrain()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_pretrain.md)).

- coords:

  A data frame or matrix with two columns `"lon"` and `"lat"` in the
  same CRS as `stack`. Order of rows is preserved.

- stack:

  A
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  with one layer per channel. The number of layers must equal
  `dataset$n_channels`.

- dataset:

  An `edaphos_tile_dataset` (or any list carrying `patch_size`,
  `n_channels`, `means`, `sds` fields).

- patch_size:

  Integer; side length of the square patch. Defaults to
  `dataset$patch_size`.

- projection:

  Logical; if `TRUE` return the L2-normalised projection-head outputs
  instead of the backbone features.

- batch_size:

  Integer; number of patches to forward through the encoder in a single
  call (trades memory for speed). Defaults to `32L`.

## Value

A numeric matrix with `nrow(coords)` rows and `D` columns, where `D` is
`moco$feature_dim` or `moco$proj_dim`. Rows that could not be extracted
contain `NA`.

## Details

Compared with
[`foundation_moco_embed_raster()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_moco_embed_raster.md)
(which runs the encoder over a regular stride-based grid), this
function:

- reads only `n_coords` patches, not the full grid, so extraction at 1
  095 WoSIS profiles is O(minutes) rather than O(hour) even on a 2 deg x
  2 deg Cerrado cube;

- returns a tidy `matrix` (rows aligned with `coords`) ready to hand
  directly to
  [`causal_iv_from_embeddings()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_from_embeddings.md)
  as the instrument matrix.

Coordinates that fall outside the raster extent, or whose patch would
cross the raster edge, are returned as a row of `NA`.
