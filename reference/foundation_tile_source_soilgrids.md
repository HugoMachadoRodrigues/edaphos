# Fetch a SoilGrids soil-property stack over an AoI

Thin convenience wrapper around
[`geodata::soil_world()`](https://rspatial.github.io/geodata/reference/soil_grids.html)
that pulls the listed variables, crops them to the area of interest, and
returns them as a single
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with one layer per variable. SoilGrids is **public and keyless** so no
authentication is required.

## Usage

``` r
foundation_tile_source_soilgrids(
  variables = c("soc", "clay"),
  depth = "0-5cm",
  stat = "mean",
  aoi,
  path = tempdir()
)
```

## Arguments

- variables:

  Character vector of SoilGrids variable codes. Common choices: `"soc"`
  (organic carbon), `"clay"`, `"sand"`, `"phh2o"` (pH in water),
  `"cec"`, `"bdod"` (bulk density), `"nitrogen"`, `"cfvo"` (coarse
  fragments).

- depth:

  Character, one of `"0-5cm"`, `"5-15cm"`, `"15-30cm"`, `"30-60cm"`,
  `"60-100cm"`, `"100-200cm"`.

- stat:

  Character, one of `"mean"`, `"Q0.05"`, `"Q0.5"`, `"Q0.95"`.

- aoi:

  A
  [`terra::SpatExtent`](https://rspatial.github.io/terra/reference/SpatExtent-class.html),
  `sf` bounding box, or a length-4 numeric vector
  `c(xmin, xmax, ymin, ymax)` in WGS84 degrees.

- path:

  Directory where `geodata` caches raw downloads (defaults to
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html)).

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with one layer per requested variable, cropped to the AoI.

## Details

The layers arrive at the resolution `geodata` serves, which is the 30
arc-second (roughly 1 km) aggregation of SoilGrids, not the native 250 m
grid; the example prints
[`terra::res()`](https://rspatial.github.io/terra/reference/dimensions.html)
to show it.

## Examples

``` r
if (FALSE) { # \dontrun{
# A 2 x 2 degree window over the Brazilian Cerrado. The AoI is
# c(xmin, xmax, ymin, ymax) in WGS84 degrees -- not the
# c(north, west, south, east) that Copernicus and NASA services use.
aoi <- c(-50, -48, -16, -14)

soil <- foundation_tile_source_soilgrids(
  variables = c("soc", "clay", "phh2o"),
  depth = "0-5cm", stat = "mean", aoi = aoi,
  path = tools::R_user_dir("edaphos", "cache")
)
names(soil)   # one layer per variable, prefixed "soilgrids_"

# `depth` is normalised internally, so the documented string form and
# geodata's own integer upper bound in centimetres are one request:
by_string  <- foundation_tile_source_soilgrids("soc", depth = "0-5cm",
                                                 aoi = aoi)
by_integer <- foundation_tile_source_soilgrids("soc", depth = 5,
                                                 aoi = aoi)

# Anything outside the six standard intervals is rejected before a
# single byte is downloaded, and the message names all six:
foundation_tile_source_soilgrids("soc", depth = "0-10cm", aoi = aoi)
## Error: Unknown depth string '0-10cm'. Use one of: 0-5cm, 5-15cm,
##   15-30cm, 30-60cm, 60-100cm, 100-200cm (or an integer in
##   c(5, 15, 30, 60, 100, 200)).

# Two limits this wrapper cannot check for you, because they belong
# to geodata::soil_world(): `variables` must be one of bdod, cfvo,
# clay, nitrogen, ocd, ocs, phh2o, sand, silt, soc, wrb; and geodata's
# own help notes that only stat = "mean" down to 60 cm is currently
# served, so the quantile statistics and the two deepest intervals
# fail at download time rather than at argument checking.

# geodata serves the 30 arc-second aggregation of SoilGrids, not the
# native 250 m grid, so read the realised cell size off the result
# rather than trusting the "250 m" in the product's name. Aligning
# these layers onto a 250 m grid resamples; it does not restore
# detail that was never downloaded.
terra::res(soil)   # ~0.008333 degrees = 30 arc-seconds, roughly 1 km

# `path` is geodata's download cache, not scratch space. The default
# tempdir() dies with the session, so every new R process re-fetches
# the whole global mosaic before cropping to `aoi`.
} # }
```
