# MODIS source stub (needs NASA EarthData credentials)

Returns a documented error pointing the user to `MODIStsp`, `rgee` or a
manual pre-processing step. Provided so that downstream code can
reference a canonical MODIS entry point; the implementation will be
filled in once the package takes a harder dependency on a MODIS client.

## Usage

``` r
foundation_tile_source_modis(...)
```

## Arguments

- ...:

  Ignored.

## Value

Nothing; always stops with an install-hint message.

## Details

Users who already have a MODIS mosaic on disk can skip this function
entirely and pass their raster straight to
[`foundation_tile_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_align.md).
