# ERA5 source stub (needs Copernicus CDS key)

Returns a documented error pointing users to `ecmwfr`. As with MODIS,
once a CDS key is configured the downloaded NetCDF can be converted to a
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
and fed directly into
[`foundation_tile_align()`](https://hugomachadorodrigues.github.io/edaphos/reference/foundation_tile_align.md).

## Usage

``` r
foundation_tile_source_era5(...)
```

## Arguments

- ...:

  Ignored.
