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

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- c(-50, -48, -16, -14)

topo <- foundation_tile_source_srtm(
  aoi = aoi, derive = c("slope", "TPI"), country = "BRA",
  path = tools::R_user_dir("edaphos", "cache")
)
names(topo)   # "elev" "slope" "TPI"

# `country` picks which national tile geodata fetches and the crop to
# `aoi` happens afterwards, so the default "BRA" is wrong the moment
# the AoI leaves Brazil. The failure comes from terra, not from a
# helpful check: "[crop] extents do not overlap".
foundation_tile_source_srtm(aoi = c(30, 32, -2, 0), country = "KEN")

# geodata::elevation_30s() masks to the country border by default and
# this wrapper does not expose that argument, so an AoI straddling a
# border comes back NA on the foreign side.
terra::global(topo, "isNA")

# Every entry of `derive` goes through terra::terrain(), which needs a
# full 3 x 3 neighbourhood, so each derived layer is NA on the outer
# ring of the tile even where `elev` is present.
# foundation_tile_dataset() imputes those NAs to the layer mean
# without warning -- crop with a margin if that matters to you.

# `unit = "degrees"` is passed for every derived layer but only
# affects "slope" and "aspect"; TPI, TRI and roughness stay in the
# units of `elev`.

# elevation_30s() is the 30 arc-SECOND (roughly 1 km) aggregation of
# the 90 m CGIAR-SRTM, not a 30 m product -- the cell size says so:
terra::res(topo)   # ~0.008333 degrees = 30 arc-seconds, roughly 1 km
# Slope computed from that is a kilometre-scale gradient and will not
# match a slope map derived from a fine LiDAR DEM over the same field.
} # }
```
