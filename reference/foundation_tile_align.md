# Align multiple raster sources onto a common analysis grid

Projects every input `SpatRaster` onto a single template (common CRS,
common resolution, common extent), stacks them channel-wise, and returns
the unified mosaic. Designed to be robust to mixed resolutions
(SoilGrids at 250 m, WorldClim at 30 arc-sec, SRTM at 30 arc-sec, MODIS
at 250 m, ERA5 at 0.1 degree) so MoCo v2 pretraining can consume a
single multi-channel tensor.

## Usage

``` r
foundation_tile_align(
  sources,
  target_res = 0.005,
  target_crs = "EPSG:4326",
  aoi = NULL,
  method = "bilinear"
)
```

## Arguments

- sources:

  Named list of
  [`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
  objects.

- target_res:

  Numeric resolution of the output grid, in the units of `target_crs`.

- target_crs:

  Character EPSG code of the output CRS (default `"EPSG:4326"`).

- aoi:

  Optional AoI to crop after reprojection (see
  [`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md)).

- method:

  Resampling method for
  [`terra::project()`](https://rspatial.github.io/terra/reference/project.html).
  Defaults to `"bilinear"` (good for continuous covariates).

## Value

A single
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with one layer per input layer, aligned.
