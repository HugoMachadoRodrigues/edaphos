# Fetch a WorldClim 2.1 climate stack over an AoI

Keyless download of WorldClim 2.1 variables for a given country or
bounding box via
[`geodata::worldclim_country()`](https://rspatial.github.io/geodata/reference/worldclim.html)
(country-scope) or
[`geodata::worldclim_global()`](https://rspatial.github.io/geodata/reference/worldclim.html)
(global scope, needs resolution). Cropped to `aoi` and returned as a
multi-layer
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html).

## Usage

``` r
foundation_tile_source_worldclim(
  variables = c("prec", "tavg"),
  country = NULL,
  res = 2.5,
  aoi,
  path = tempdir()
)
```

## Arguments

- variables:

  Character vector. Any of
  `c("tavg","tmin","tmax","prec","wind","vapr","bio","elev","srad")`.

- country:

  Optional ISO3 code (e.g. `"BRA"`). If `NULL`, `res` is used instead.

- res:

  Spatial resolution in arc-minutes (`2.5`, `5`, `10`) for global
  downloads.

- aoi:

  See
  [`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md).

- path:

  Cache directory.

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html).
