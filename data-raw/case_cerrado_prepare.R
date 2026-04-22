# edaphos case study: real-data Cerrado SOC benchmark --- data preparation
#
# Pulls every piece of real, open-licensed data the end-to-end
# vignette needs, with explicit attribution tracked on every source.
# Writes a single reproducible RDS bundle under
# tools/case_cerrado/ that the runner script
# (case_cerrado_run.R) consumes.
#
# Data sources
# ------------
#
#   * Cerrado biome polygon
#     IBGE (Instituto Brasileiro de Geografia e Estatistica), Biomes
#     and Coastal-Marine Systems of Brazil (1:250000), accessed via
#     the `geobr` R package (Pereira and Goncalves, 2019).
#     License: open -- IBGE public data.
#
#   * WoSIS soil profile database
#     Batjes, N. H., Ribeiro, E. and van Oostrum, A. (2020).
#     Standardised soil profile data to support global mapping and
#     modelling (WoSIS snapshot 2019). Earth System Science Data,
#     12(1), 299-320. DOI: 10.5194/essd-12-299-2020.
#     License: Creative Commons Attribution 4.0 International
#     (CC-BY-4.0), on every profile.
#     Accessed via the public WFS endpoint of ISRIC World Data
#     Centre for Soils: https://maps.isric.org/mapserv.
#
#   * SoilGrids 250 m gridded soil attributes
#     Hengl, T. et al. (2017). SoilGrids250m: global gridded soil
#     information based on machine learning. PLOS ONE 12(2),
#     e0169748. DOI: 10.1371/journal.pone.0169748.
#     License: Open Database License (ODbL) / CC-BY-4.0 as per
#     ISRIC terms.
#     Accessed via the `geodata` R package.
#
#   * WorldClim 2.1 climate surfaces
#     Fick, S. E. and Hijmans, R. J. (2017). WorldClim 2: new 1-km
#     spatial resolution climate surfaces for global land areas.
#     International Journal of Climatology, 37(12), 4302-4315. DOI:
#     10.1002/joc.5086.
#     License: open for non-commercial / research use.
#     Accessed via the `geodata` R package.
#
#   * SRTM 30-arc-second elevation
#     Jarvis, A., Reuter, H. I., Nelson, A. and Guevara, E. (2008).
#     Hole-filled SRTM for the globe (Version 4). CGIAR-CSI SRTM
#     90 m Database. Originally produced by the National
#     Aeronautics and Space Administration (NASA).
#     License: public domain / CGIAR-CSI terms.
#     Accessed via the `geodata` R package.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(sf)
  library(terra)
  library(geobr)
  library(geodata)
  library(dplyr)
})

out_dir <- "tools/case_cerrado"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- 1. Cerrado biome polygon (IBGE via geobr) ------------------------------

message("[case] 1/5  Cerrado biome polygon (IBGE via geobr)...")
biomes  <- geobr::read_biomes(showProgress = FALSE)
cerrado <- biomes[biomes$name_biome == "Cerrado", ]
cerrado <- sf::st_make_valid(cerrado)
# geobr ships SIRGAS 2000 (EPSG:4674); every other dataset here uses
# WGS 84 (EPSG:4326). Reproject the AoI once up-front so downstream
# spatial filters don't trip on the CRS mismatch.
cerrado <- sf::st_transform(cerrado, 4326)
cerrado_bbox <- sf::st_bbox(cerrado)
message(sprintf("  [ok] area = %.0f km^2   bbox = [%.2f, %.2f, %.2f, %.2f]",
                 as.numeric(sum(sf::st_area(cerrado))) / 1e6,
                 cerrado_bbox["xmin"], cerrado_bbox["ymin"],
                 cerrado_bbox["xmax"], cerrado_bbox["ymax"]))

# ---- 2. WoSIS SOC (organic carbon) profiles ---------------------------------
#
# WFS endpoint returns GML3 per-horizon observations of the "orgc"
# attribute. Each feature carries the profile id, the depth range,
# the measurement value (g/kg), the dataset of origin (RADAM / EMBRAPA
# / Cooper etc.) and the CC-BY-4.0 licence string.
#
# We pull everything in the Cerrado biome bounding box in one WFS
# GetFeature, then clip with the biome polygon itself.

message("[case] 2/5  WoSIS organic-carbon measurements via ISRIC WFS...")

wfs_url <- function(typeName, bbox_lat, bbox_lon) {
  sprintf(paste0(
    "https://maps.isric.org/mapserv?",
    "map=/map/wosis_latest.map&",
    "service=WFS&version=2.0.0&request=GetFeature&",
    "typeName=wosis_latest:%s&",
    "srsName=EPSG:4326&",
    "bbox=%f,%f,%f,%f,EPSG:4326&",
    "outputFormat=GML3"),
    typeName,
    bbox_lat[1L], bbox_lon[1L], bbox_lat[2L], bbox_lon[2L])
}

# WFS 2.0 with EPSG:4326 -- lat/lon axis order.
bbox_lat <- c(cerrado_bbox[["ymin"]], cerrado_bbox[["ymax"]])
bbox_lon <- c(cerrado_bbox[["xmin"]], cerrado_bbox[["xmax"]])
orgc_gml <- file.path(out_dir, "wosis_orgc_cerrado.gml")

if (!file.exists(orgc_gml) ||
    file.info(orgc_gml)$size < 10000L) {
  req <- httr2::request(wfs_url("wosis_latest_orgc", bbox_lat, bbox_lon))
  req <- httr2::req_timeout(req, 600L)
  req <- httr2::req_retry(req, max_tries = 3L,
                            backoff = function(i) 2 ^ i)
  resp <- httr2::req_perform(req, path = orgc_gml)
  stopifnot(httr2::resp_status(resp) == 200L)
}
message(sprintf("  [ok] WoSIS orgc GML saved (%.1f MB)",
                 file.info(orgc_gml)$size / 1024^2))

# Parse GML3 into an sf data frame.
orgc <- sf::st_read(orgc_gml, quiet = TRUE)
orgc <- sf::st_transform(orgc, 4326)
message(sprintf("  [ok] parsed %d orgc measurements across %d profiles",
                 nrow(orgc), length(unique(orgc$profile_id))))

# Clip to the actual Cerrado biome (not just bbox).
orgc <- sf::st_filter(orgc, cerrado, .predicate = sf::st_within)
message(sprintf("  [ok] inside Cerrado biome: %d measurements, %d profiles",
                 nrow(orgc), length(unique(orgc$profile_id))))

# Quality filters.
orgc$upper_depth <- suppressWarnings(as.numeric(orgc$upper_depth))
orgc$lower_depth <- suppressWarnings(as.numeric(orgc$lower_depth))
orgc$value_avg   <- suppressWarnings(as.numeric(orgc$value_avg))
valid <- !is.na(orgc$value_avg) & !is.na(orgc$upper_depth) &
         !is.na(orgc$lower_depth) & orgc$upper_depth < orgc$lower_depth &
         orgc$value_avg >= 0 & orgc$value_avg < 500
orgc <- orgc[valid, , drop = FALSE]
message(sprintf("  [ok] QC-clean (finite depth + 0 <= SOC < 500 g/kg): %d rows",
                 nrow(orgc)))

# Topsoil layer per profile: the layer whose upper_depth is shallowest
# AND whose lower_depth is <= 30 cm (canonical DSM topsoil convention).
# When several layers qualify we keep the one closest to the 0-5 cm
# slice (shallowest upper_depth).
topsoil <- orgc |>
  dplyr::filter(lower_depth <= 30) |>
  dplyr::group_by(profile_id) |>
  dplyr::arrange(upper_depth, lower_depth, .by_group = TRUE) |>
  dplyr::slice(1L) |>
  dplyr::ungroup()

topsoil <- sf::st_as_sf(topsoil)
message(sprintf("  [ok] one topsoil row per profile: %d profiles retained",
                 nrow(topsoil)))

# ---- 3. Covariate stack (SoilGrids + WorldClim + SRTM) ---------------------

message("[case] 3/5  covariate stack (SoilGrids + WorldClim + SRTM)...")
aoi_ext <- c(xmin = cerrado_bbox[["xmin"]],
              xmax = cerrado_bbox[["xmax"]],
              ymin = cerrado_bbox[["ymin"]],
              ymax = cerrado_bbox[["ymax"]])
cache_dir <- file.path(out_dir, "geodata_cache")
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

sg <- foundation_tile_source_soilgrids(
  variables = c("soc", "clay", "sand", "phh2o", "bdod"),
  depth = "0-5cm", stat = "mean",
  aoi = aoi_ext, path = cache_dir
)
wc <- foundation_tile_source_worldclim(
  variables = c("prec", "tavg"),
  country = "BRA", aoi = aoi_ext, path = cache_dir
)
sr <- foundation_tile_source_srtm(
  # Channel set chosen to match `edaphos-cerrado-moco-v1`'s 31-layer
  # input (elev + slope), so the pretrained encoder can be applied
  # directly to patches sampled from this stack. See Zenodo deposit
  # 10.5281/zenodo.19701276 for the full training spec.
  aoi = aoi_ext, derive = c("slope"),
  country = "BRA", path = cache_dir
)
aligned <- foundation_tile_align(
  sources = list(soilgrids = sg, worldclim = wc, srtm = sr),
  target_res = 0.01, method = "bilinear"
)
message(sprintf("  [ok] aligned stack: %d layers, %d rows x %d cols",
                 terra::nlyr(aligned),
                 terra::nrow(aligned), terra::ncol(aligned)))
covariate_tif <- file.path(out_dir, "cerrado_covariates.tif")
terra::writeRaster(aligned, covariate_tif, overwrite = TRUE,
                    gdal = "COMPRESS=DEFLATE")

# ---- 4. Extract covariates at profile locations -----------------------------

message("[case] 4/5  extracting covariates at profile locations...")
pts <- sf::st_coordinates(topsoil)
pts <- terra::vect(pts, crs = "EPSG:4326")
vals <- terra::extract(aligned, pts, ID = FALSE)
stopifnot(nrow(vals) == nrow(topsoil))
message(sprintf("  [ok] %d profiles x %d covariates extracted",
                 nrow(vals), ncol(vals)))

# Keep only profiles whose covariates are fully observed.
keep <- stats::complete.cases(vals)
message(sprintf("  [ok] fully-observed rows: %d / %d",
                 sum(keep), length(keep)))
topsoil <- topsoil[keep, , drop = FALSE]
vals    <- vals[keep, , drop = FALSE]

profiles <- data.frame(
  profile_id   = as.integer(topsoil$profile_id),
  profile_code = as.character(topsoil$profile_code),
  dataset_id   = as.character(topsoil$dataset_id),
  year         = suppressWarnings(as.integer(substr(topsoil$date, 1, 4))),
  upper_depth  = topsoil$upper_depth,
  lower_depth  = topsoil$lower_depth,
  soc_gkg      = topsoil$value_avg,
  licence      = as.character(topsoil$licence),
  stringsAsFactors = FALSE
)
coords <- sf::st_coordinates(topsoil)
profiles$lon <- coords[, 1L]
profiles$lat <- coords[, 2L]
profiles <- cbind(profiles, vals)

# ---- 5. Deterministic 80/20 spatial split -----------------------------------
# Reproducible, spatially stratified by longitude/latitude quadrants so
# the test set contains points from every sub-region of the biome.

set.seed(2026L)
q_lon <- cut(profiles$lon,
              breaks = stats::quantile(profiles$lon,
                                         probs = c(0, 0.5, 1)),
              include.lowest = TRUE, labels = FALSE)
q_lat <- cut(profiles$lat,
              breaks = stats::quantile(profiles$lat,
                                         probs = c(0, 0.5, 1)),
              include.lowest = TRUE, labels = FALSE)
profiles$quadrant <- factor(paste(q_lon, q_lat, sep = "_"))
split_mask <- logical(nrow(profiles))
for (q in levels(profiles$quadrant)) {
  ix <- which(profiles$quadrant == q)
  n_test <- max(1L, round(0.2 * length(ix)))
  split_mask[sample(ix, n_test)] <- TRUE
}
profiles$split <- ifelse(split_mask, "test", "train")
message(sprintf(
  "[case] 5/5  split: %d train / %d test (stratified by 2x2 lon/lat quadrants)",
  sum(profiles$split == "train"), sum(profiles$split == "test")
))

# ---- Persist ----------------------------------------------------------------

bundle_path <- file.path(out_dir, "case_cerrado_bundle.rds")
saveRDS(
  list(
    aoi         = cerrado,
    profiles    = profiles,
    covariates  = covariate_tif,       # path; caller reopens via terra::rast()
    covariate_names = names(aligned),
    created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    edaphos_ver = as.character(packageVersion("edaphos")),
    sources = list(
      aoi        = "IBGE Biomes via geobr (Pereira & Goncalves 2019)",
      soc        = "WoSIS snapshot 2019 (Batjes et al. 2020), CC-BY-4.0, ISRIC",
      soilgrids  = "SoilGrids 250m (Hengl et al. 2017), CC-BY-4.0, ISRIC",
      worldclim  = "WorldClim 2.1 (Fick & Hijmans 2017)",
      srtm       = "SRTM 30-arcsec (Jarvis et al. 2008; NASA public domain)"
    )
  ),
  bundle_path
)
message(sprintf("[case] bundle written: %s  (%.1f KB)",
                 bundle_path, file.info(bundle_path)$size / 1024))
message("[case] done.")
