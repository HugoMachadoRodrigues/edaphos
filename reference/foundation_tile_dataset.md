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

## Examples

``` r
if (requireNamespace("terra", quietly = TRUE)) {
  data(br_cerrado, package = "edaphos")
  # br_cerrado is a complete 45 x 45 grid, so it converts straight to
  # a SpatRaster; x and y have to be the first two columns.
  cerr <- terra::rast(br_cerrado[, c("x", "y", "soc", "elev", "twi")],
                      type = "xyz", crs = "EPSG:4326")

  ds <- foundation_tile_dataset(cerr, patch_size = 8L,
                                  n_patches = 200L, seed = 1L)
  print(ds)
  # (B, C, H, W) -- channel-first, the layout torch conv layers want.
  print(dim(ds$sample(batch_size = 4L)))

  # Normalisation uses GLOBAL raster statistics computed once at
  # construction, never per-batch ones. They are the column statistics
  # of the source table -- to floating-point tolerance, not bit for
  # bit, because terra accumulates in a different order:
  print(c(ds$means[1], mean(br_cerrado$soc)))
  print(c(ds$sds[1], stats::sd(br_cerrado$soc)))
  print(isTRUE(all.equal(ds$means[1], mean(br_cerrado$soc))))    # TRUE
  print(identical(ds$means[1], mean(br_cerrado$soc)))            # FALSE

  # `seed` fixes WHICH patches the dataset owns, not which ones a
  # call draws. Two datasets built with the same seed agree on
  # patch_cells and still disagree on their batches, so seed the RNG
  # immediately before sample() when you need a reproducible batch.
  d2 <- foundation_tile_dataset(cerr, patch_size = 8L,
                                  n_patches = 200L, seed = 1L)
  print(identical(ds$patch_cells, d2$patch_cells))   # TRUE
  print(identical(ds$sample(4L), d2$sample(4L)))     # FALSE
  set.seed(99); b1 <- ds$sample(4L)
  set.seed(99); b2 <- d2$sample(4L)
  print(identical(b1, b2))                           # TRUE

  # normalise = FALSE returns raw units, which is what you want when
  # inspecting a patch and not what you want in a contrastive loss:
  # elevation in metres would swamp TWI.
  raw <- foundation_tile_dataset(cerr, patch_size = 8L,
                                   n_patches = 200L, normalise = FALSE,
                                   seed = 1L)
  set.seed(7); print(round(apply(raw$sample(8L), 2, mean), 2))
  set.seed(7); print(round(apply(ds$sample(8L),  2, mean), 2))

  # Patch CENTRES must sit at least patch_size %/% 2 cells from every
  # edge, so a large patch on a small grid leaves very few of them.
  # On 45 x 45 with patch_size = 40 only rows and columns 21 to 25
  # qualify -- 25 centres -- and n_patches = 200 is then drawn WITH
  # replacement. The dataset reports 200 patches and owns 25 windows.
  crowded <- foundation_tile_dataset(cerr, patch_size = 40L,
                                       n_patches = 200L, seed = 1L)
  print(crowded$n_patches)                          # 200 reported
  print(length(unique(crowded$patch_cells)))        # 25 distinct
  print(apply(terra::rowColFromCell(cerr,
                                    unique(crowded$patch_cells)),
              2, range))                            # rows/cols 21..25

  # Ask for a patch the grid cannot hold at all and it is an error,
  # not a silent shrink.
  try(foundation_tile_dataset(cerr, patch_size = 46L, n_patches = 10L))

  # A valid_mask restricts eligible centres -- here to the cells above
  # mean TWI, which is a bit over half the grid, not exactly half. It
  # is resampled onto the stack with method "near", so a coarser mask
  # is allowed.
  wet <- cerr[["twi"]] > terra::global(cerr[["twi"]], "mean")[1, 1]
  print(mean(terra::values(wet)[, 1]))   # fraction of cells kept
  dw <- foundation_tile_dataset(cerr, patch_size = 8L, n_patches = 100L,
                                  valid_mask = wet, seed = 1L)
  print(all(terra::values(wet)[dw$patch_cells, 1] > 0))

  # Only the FIRST layer decides eligibility. A gap in any other
  # channel is invisible to the sampler; those cells are imputed to
  # the channel mean instead, which after normalisation is an exact
  # zero. Put the layer with the honest coverage first.
  gappy <- cerr
  v <- terra::values(gappy[[2]]); v[1:900] <- NA   # the top 20 rows
  terra::values(gappy[[2]]) <- v
  dg <- foundation_tile_dataset(gappy, patch_size = 8L,
                                  n_patches = 200L, seed = 1L)
  print(identical(dg$patch_cells, ds$patch_cells))   # TRUE
  # Numerator and denominator, plus the gap-free control that shows
  # the zeros are imputation and not coincidence:
  set.seed(5); print(sum(dg$sample(16L)[, 2, , ] == 0))   # hundreds
  print(16L * 8L * 8L)                                    # of 1024
  set.seed(5); print(sum(ds$sample(16L)[, 2, , ] == 0))   # 0

  # batch_size is capped by n_patches, not by memory.
  try(ds$sample(batch_size = 1000L))
}
#> <edaphos_tile_dataset>
#>   stack       : 45 x 45 x 3 (rows x cols x channels)
#>   patch_size  : 8 x 8
#>   n_patches   : 200
#>   channels    : soc, elev, twi
#> [1] 4 3 8 8
#> [1] 19.50303 19.50303
#> [1] 6.510679 6.510679
#> [1] TRUE
#> [1] FALSE
#> [1] TRUE
#> [1] FALSE
#> [1] TRUE
#> [1]  18.61 994.61   8.53
#> [1] -0.14  0.52 -0.49
#> [1] 200
#> [1] 25
#>      [,1] [,2]
#> [1,]   21   21
#> [2,]   25   25
#> Error : No valid cells leave enough margin for patch_size = 46.
#> [1] 0.517037
#> [1] TRUE
#> [1] TRUE
#> [1] 448
#> [1] 1024
#> [1] 0
#> Error in ds$sample(batch_size = 1000L) : 
#>   batch_size <= n_patches is not TRUE
```
