# Build the Cerrado raster stack for IV / quantum-foundation benchmarks

Downloads / assembles the covariate raster stack that the
`edaphos-cerrado-moco-v1` encoder was pretrained on. As of v3.11.0 the
stack matches the v1 encoder's 31-channel input schema:

## Usage

``` r
foundation_build_cerrado_stack(
  bbox = c(-50, -16, -48, -14),
  cache_dir = tools::R_user_dir("edaphos", which = "cache"),
  target_res = 0.01,
  force = FALSE,
  schema = c("v1_encoder", "minimal")
)
```

## Arguments

- bbox:

  Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` in decimal
  degrees. Defaults to a central Cerrado quadrant around Brasilia:
  `c(-50, -16, -48, -14)`.

- cache_dir:

  Directory to write the assembled stack(s) to. Defaults to the user R
  cache under `tools::R_user_dir("edaphos")`.

- target_res:

  Numeric; target resolution in degrees. Defaults to `0.01` (~ 1 km at
  the equator, matching the encoder training resolution).

- force:

  Logical; re-download even if a cached stack exists.

- schema:

  One of `"v1_encoder"` (default; 31-channel encoder- compatible stack)
  or `"minimal"` (10-channel legacy stack used pre-v3.11.0). Pass
  `"minimal"` to reproduce the older bundles.

## Value

A
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html)
with the requested number of aligned layers.

## Details

- 5 SoilGrids 250 m layers (`soc`, `clay`, `sand`, `phh2o`, `bdod`)

- 12 monthly WorldClim 2.1 precipitation layers (`wc_prec_01` ...
  `wc_prec_12`)

- 12 monthly WorldClim 2.1 mean-temperature layers (`wc_tavg_01` ...
  `wc_tavg_12`)

- 2 SRTM 30-arc-second topography layers (`elev`, `slope`)

All 31 layers are resampled to a common `target_res`-degree grid and
clipped to `bbox`. Earlier versions assembled only a 10-channel subset,
which forced the IV benchmark (`data-raw/causal_iv_benchmark_real.R`) to
fall back to a synthetic 31-channel stack – the v3.11.0 rewrite closes
that gap.

**Heavy download.** A 2-deg x 2-deg Cerrado AoI lands in \\80-110 MB
after alignment (cache_dir hit on subsequent calls).
