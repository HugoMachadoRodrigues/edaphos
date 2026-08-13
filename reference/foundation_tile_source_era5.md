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

## Examples

``` r
if (FALSE) { # \dontrun{
# The stub always errors; it is a signpost, not an implementation.
foundation_tile_source_era5()

# Supported route: register at the Copernicus Climate Data Store,
# store the key once, request the NetCDF, then convert.
ecmwfr::wf_set_key(key = "your-cds-personal-access-token")
req <- list(
  dataset_short_name = "reanalysis-era5-land-monthly-means",
  product_type       = "monthly_averaged_reanalysis",
  variable = c("2m_temperature", "total_evaporation"),
  year = "2020", month = sprintf("%02d", 1:12), time = "00:00",
  # The CDS bounding box is north, west, south, east -- the reverse
  # convention to the c(xmin, xmax, ymin, ymax) that every
  # foundation_tile_* function in this package expects.
  area = c(-14, -50, -16, -48),
  format = "netcdf",
  target = "era5_land_cerrado_2020.nc"
)
ecmwfr::wf_request(req, path = tempdir())
era5 <- terra::rast(file.path(tempdir(), "era5_land_cerrado_2020.nc"))

aoi  <- c(-50, -48, -16, -14)
soil <- foundation_tile_source_soilgrids(variables = "soc", aoi = aoi)
stack <- foundation_tile_align(list(soil = soil, era5 = era5),
                                 target_res = 0.0025, aoi = aoi)

# ERA5-Land is a 0.1 degree (roughly 9 km) reanalysis -- confirm on
# the object you actually downloaded rather than taking it on trust:
terra::res(era5)
# Projected onto a 250 m grid with the default bilinear method it
# becomes a smooth channel carrying no information below 9 km. That
# is harmless for a contrastive encoder and misleading in a
# covariate-importance table.
} # }
```
