# Prepare the multi-source tile dataset for the Cerrado MoCo v2
# pretraining run. Reproducible by design: fixed AoI, fixed variables,
# fixed resolution, fixed seed. Output is written to
# tools/pretrain/cerrado_dataset.rds.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(terra)
  library(geodata)
})

# Core Cerrado AoI (Brazil's core cerrado corridor: GO, TO, MT, BA, MG).
# WGS84 degrees; ~1.1 M km^2.
aoi <- c(xmin = -53, xmax = -43, ymin = -23, ymax = -10)

message("[prep] 1/4  SoilGrids 250m tiles (soc, clay, sand, phh2o, bdod)")
sg <- foundation_tile_source_soilgrids(
  variables = c("soc", "clay", "sand", "phh2o", "bdod"),
  depth     = "0-5cm",
  stat      = "mean",
  aoi       = aoi,
  path      = "tools/pretrain/geodata_cache"
)
message(sprintf("  [ok] SoilGrids stack: %d layers, extent: %s",
                 nlyr(sg), paste(as.vector(ext(sg)), collapse = " ")))

message("[prep] 2/4  WorldClim 2.1 (BRA country pack: prec, tavg, bio)")
wc <- foundation_tile_source_worldclim(
  variables = c("prec", "tavg"),
  country   = "BRA",
  aoi       = aoi,
  path      = "tools/pretrain/geodata_cache"
)
message(sprintf("  [ok] WorldClim stack: %d layers (monthly prec + tavg)",
                 nlyr(wc)))

message("[prep] 3/4  SRTM elev + slope")
sr <- foundation_tile_source_srtm(
  aoi     = aoi,
  derive  = c("slope"),
  country = "BRA",
  path    = "tools/pretrain/geodata_cache"
)
message(sprintf("  [ok] SRTM stack: %d layers", nlyr(sr)))

# Align everything to a 0.01 degree grid (~1 km at these latitudes).
# This is the analysis grid of the pretraining run.
message("[prep] 4/4  align all sources to common 0.01-deg grid")
aligned <- foundation_tile_align(
  sources    = list(soilgrids = sg, worldclim = wc, srtm = sr),
  target_res = 0.01,
  method     = "bilinear"
)
message(sprintf("  [ok] aligned stack: %d layers, %d rows x %d cols",
                 nlyr(aligned), nrow(aligned), ncol(aligned)))

# Persist the aligned stack so pretraining doesn't re-download.
tif <- "tools/pretrain/cerrado_stack.tif"
writeRaster(aligned, tif, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
message(sprintf("  [ok] wrote aligned stack to %s (%.1f MB)",
                 tif, file.info(tif)$size / 1024^2))

# Build a tile dataset with 50k 16x16 patches for the actual training loop.
ds <- foundation_tile_dataset(
  stack      = aligned,
  patch_size = 16L,
  n_patches  = 50000L,
  normalise  = TRUE,
  seed       = 2026L
)
message(sprintf("  [ok] tile dataset: %d patches x %d channels x %d x %d",
                 ds$n_patches, ds$n_channels, ds$patch_size, ds$patch_size))

saveRDS(ds, "tools/pretrain/cerrado_dataset.rds")
saveRDS(
  list(
    aoi          = aoi,
    variables    = list(
      soilgrids = c("soc", "clay", "sand", "phh2o", "bdod"),
      worldclim = c("prec", "tavg"),
      srtm      = c("elev", "slope")
    ),
    target_res   = 0.01,
    patch_size   = 16L,
    n_patches    = 50000L,
    n_channels   = ds$n_channels,
    layer_names  = names(aligned),
    means        = ds$means,
    sds          = ds$sds,
    created_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    r_version    = R.version.string,
    edaphos_ver  = as.character(packageVersion("edaphos"))
  ),
  "tools/pretrain/cerrado_dataset_meta.rds"
)
message("[prep] done: tools/pretrain/cerrado_dataset.rds ready for MoCo v2 training")
