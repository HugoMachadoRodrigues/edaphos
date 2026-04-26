# Fetch a SoilGrids 250 m stack over an AoI

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
