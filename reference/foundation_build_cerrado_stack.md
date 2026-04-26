# Build a minimal Cerrado raster stack for the v1.9.1 IV benchmark

Downloads / assembles the covariate raster stack that the
`edaphos-cerrado-moco-v1` encoder was pretrained on. The stack has 10
channels: 5 SoilGrids 250 m layers (soc, clay, sand, ph, bdod), 2
WorldClim 2.1 bioclim layers (bio1 = MAT, bio12 = MAP), 1 SRTM
30-arc-second elevation, 1 derived slope, and 1 placeholder NDVI. All
layers are resampled to a common 0.01-deg grid and clipped to the
bounding box `bbox`.

## Usage

``` r
foundation_build_cerrado_stack(
  bbox = c(-50, -16, -48, -14),
  cache_dir = tools::R_user_dir("edaphos", which = "cache"),
  target_res = 0.01,
  force = FALSE
)
```

## Arguments

- bbox:

  Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` in decimal
  degrees. Defaults to a central Cerrado quadrant around Brasília:
  `c(-50, -16, -48, -14)`.

- cache_dir:

  Directory to write the assembled stack(s) to. Defaults to the user R
  cache under `tools::R_user_dir("edaphos")`.

- target_res:

  Numeric; target resolution in degrees. Defaults to `0.01` (~ 1 km at
  the equator, matching the encoder training resolution).

- force:

  Logical; re-download even if a cached stack exists.

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with 10 aligned layers named
`c("soc", "clay", "sand", "ph", "bdod", "bio1", "bio12", "elev", "slope", "ndvi")`.

## Details

**Heavy download.** A 2-deg x 2-deg Cerrado AoI produces roughly 200 MB
of raster data after alignment. The first call populates `cache_dir`;
subsequent calls read from disk instantly.
