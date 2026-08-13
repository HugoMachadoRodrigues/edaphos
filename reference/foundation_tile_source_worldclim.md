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

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- c(-50, -48, -16, -14)

# Country scope: geodata downloads the whole of Brazil at 30
# arc-seconds and the crop to `aoi` only happens afterwards, so a
# small AoI does not buy a small download.
clim <- foundation_tile_source_worldclim(
  variables = c("prec", "tavg"), country = "BRA", aoi = aoi,
  path = tools::R_user_dir("edaphos", "cache")
)

# Every monthly WorldClim variable is a 12-layer raster, so the two
# variables above give 24 channels, not 2. Check this before the
# stack reaches foundation_tile_dataset(): the channel count is what
# the encoder's first convolution must match.
terra::nlyr(clim)   # 24
names(clim)   # wc_prec_01 ... wc_prec_12, wc_tavg_01 ... wc_tavg_12
terra::res(clim)    # country scope is always 30 arc-seconds,
                    # i.e. ~0.008333 degrees; `res` never enters it

# `res` is ignored while `country` is non-NULL. Pass country = NULL
# for the global product, which is the right choice when the AoI
# crosses a border -- worldclim_country() returns one country only.
bio <- foundation_tile_source_worldclim(
  variables = "bio", country = NULL, res = 2.5, aoi = aoi
)

# `bio` is not monthly, so it does not follow the 12-layer rule --
# print its channel count instead of assuming one:
terra::nlyr(bio)    # 19 bioclimatic variables, named wc_bio_01..19

# geodata documents its own `var` argument as one of tmin, tmax,
# tavg, prec, wind, vapr, bio. The "elev" and "srad" entries listed
# among `variables` above are outside that documented set, although
# geodata's stopifnot() does accept them. "elev" in particular is a
# single-band product, so it breaks the layer arithmetic above --
# again, count, do not assume:
el <- foundation_tile_source_worldclim(variables = "elev",
                                       country = "BRA", aoi = aoi)
terra::nlyr(el)

# WorldClim 2.1 is a 1970-2000 climate normal, not a time series.
# Stacking it beside a 2020 vegetation composite gives channels that
# describe different decades: acceptable for self-supervised
# pretraining, wrong for any statement about a particular year.
} # }
```
