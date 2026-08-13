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

## Examples

``` r
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed()) &&
    requireNamespace("terra", quietly = TRUE)) {

  # A 2 deg x 2 deg Cerrado tile at 0.05 deg (40 x 40 cells) with
  # three covariate channels, standing in for the 31-channel stack
  # that foundation_build_cerrado_stack() downloads.
  cerrado <- terra::rast(nrows = 40, ncols = 40,
                         xmin = -50, xmax = -48,
                         ymin = -16, ymax = -14,
                         crs = "EPSG:4326", nlyrs = 3)
  xy <- terra::xyFromCell(cerrado, seq_len(terra::ncell(cerrado)))
  terra::values(cerrado) <- cbind(
    900 + 260 * sin((xy[, 1] + 50) * 2.4) - 140 * (xy[, 2] + 16),
    1500 - 90 * (xy[, 1] + 50) + 40 * cos((xy[, 2] + 16) * 3),
    0.45 + 0.18 * sin((xy[, 1] + 50) * 1.7 + (xy[, 2] + 16)))
  names(cerrado) <- c("elev", "map_mm", "ndvi")

  # Touch torch once before relying on `seed`: the call that loads
  # the backend does not keep it.
  invisible(torch::torch_manual_seed(11L))
  set.seed(42)
  tiles <- foundation_tile_dataset(cerrado, patch_size = 8L,
                                   n_patches = 24L, seed = 1)
  moco  <- foundation_moco_pretrain(tiles$sample(12),
                                    feature_dim = 8L, proj_dim = 4L,
                                    epochs = 2L, batch_size = 6L,
                                    seed = 11L)

  # Five profiles: three interior, one outside the tile, and one
  # inside it but in the very first column of cells.
  sites <- data.frame(
    site = c("BR-01", "BR-02", "BR-03", "BR-04", "BR-05"),
    lon  = c(-49.50, -48.70, -49.10, -46.20, -49.96),
    lat  = c(-15.40, -14.60, -15.50, -15.00, -15.40))

  # Put the encoder in eval mode before extracting anything.
  # foundation_moco_pretrain() hands it back in TRAINING mode and
  # the backbone is full of BatchNorm, which in training mode
  # standardises with the statistics of the batch in front of it:
  # a site's embedding then depends on which other sites share its
  # batch, and `batch_size` stops being only a memory knob.
  b32 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
                                    batch_size = 32L)
  b01 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
                                    batch_size = 1L)
  invisible(moco$encoder_q$eval())
  e32 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
                                    batch_size = 32L)
  e01 <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
                                    batch_size = 1L)
  # First entry is the size of the leak; the second is zero to
  # numerical precision.
  print(c(train_mode = max(abs(b32 - b01), na.rm = TRUE),
          eval_mode  = max(abs(e32 - e01), na.rm = TRUE)))

  # One row per site, in the order supplied, `feature_dim` columns
  # named emb_001 ... emb_008.
  print(dim(e32))
  print(colnames(e32))

  # Rows 4 and 5 come back all NA for two different reasons that
  # look identical in the output: BR-04 is outside the raster,
  # while BR-05 is inside it but a patch centred there would run
  # off the western edge.  Carry the site identifiers alongside --
  # the matrix has no row names to tell you which is which.
  print(cbind(sites["site"], usable = stats::complete.cases(e32)))

  # The margin required is exactly `patch_size %/% 2` = 4 cells.
  # Marching east from the western edge, the first four columns of
  # the raster are refused and the fifth is the first that returns
  # an embedding.
  transect <- data.frame(lon = -49.975 + 0.05 * (0:5), lat = -15.4)
  print(is.na(foundation_embed_at_coords(moco, transect, cerrado,
                                         tiles)[, 1]))

  # NA is only ever a geometric verdict.  Missing covariate values
  # inside the window are imputed at the channel mean, so a site
  # sitting on a NoData hole still gets a full embedding row --
  # only terra::extract() will tell you it is uninformed.
  holed <- cerrado
  hole  <- terra::cellFromXY(holed, as.matrix(expand.grid(
    lon = -49.10 + c(-0.05, 0, 0.05),
    lat = -15.50 + c(-0.05, 0, 0.05))))
  vals <- terra::values(holed)
  vals[hole, ] <- NA
  terra::values(holed) <- vals
  emb_holed <- foundation_embed_at_coords(moco, sites, holed, tiles)
  # All three covariates are NA at BR-03 (column 1 is terra's ID),
  # yet the embedding row is finite.
  print(terra::extract(holed, sites[3, c("lon", "lat")]))
  print(all(is.finite(emb_holed[3, ])))

  # `projection = TRUE` returns the L2-normalised projection head
  # instead of the backbone features: `proj_dim` columns, and every
  # extracted row has unit length.
  proj <- foundation_embed_at_coords(moco, sites, cerrado, tiles,
                                     projection = TRUE)
  ok <- stats::complete.cases(proj)
  print(c(ncol = ncol(proj),
          norm = unique(round(sqrt(rowSums(proj[ok, ]^2)), 6))))
}
```
