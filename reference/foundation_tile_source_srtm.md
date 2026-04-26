# Fetch an SRTM elevation raster over an AoI

Wraps
[`geodata::elevation_30s()`](https://rspatial.github.io/geodata/reference/elevation.html)
(global, 30 arc-second SRTM) and crops it to the AoI. Optionally derives
`slope` and `aspect` via
[`terra::terrain()`](https://rspatial.github.io/terra/reference/terrain.html).

## Usage

``` r
foundation_tile_source_srtm(
  aoi,
  derive = c("slope"),
  country = "BRA",
  path = tempdir()
)
```

## Arguments

- aoi:

  See
  [`foundation_tile_source_soilgrids()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_source_soilgrids.md).

- derive:

  Character vector of additional topographic layers to compute. Any
  subset of `c("slope","aspect","TPI","TRI","roughness")`.

- country:

  Optional ISO3 code for country-scope download.

- path:

  Cache directory.

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with layer `elev` plus any derived layers.
