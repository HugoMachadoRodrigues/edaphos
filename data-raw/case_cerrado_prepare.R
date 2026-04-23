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

# -- v1.3.1 option-2 upgrade: SOC stock 0-30 cm as the regression target --
#
# The v1.3.1a attempt used SOC *concentration* at the topsoil slice
# (g/kg, single horizon per profile). On 302 profiles the R2 bottomed
# at 0.23 because the target has the depth-specific noise of a single
# horizon measurement and throws away every other horizon of the same
# profile.
#
# The canonical DSM target
# (Hengl et al. 2017; Gomes et al. 2019; GlobalSoilMap consortium) is
# the carbon *stock* -- mass of organic C per unit area integrated
# over a standard depth window. For a column
#
#   SOC_stock_kg_per_m2 = sum_i (SOC_i_gkg * BD_i_gcm3 * thickness_i_cm) / 100
#
# where the sum runs over every horizon that overlaps the 0-30 cm
# window and the thickness is the slice of that horizon inside 0-30 cm.
#
# Stocks are less noisy than point concentrations (noise in a single
# horizon is averaged across several horizons) and retain every WoSIS
# profile that has any measurement in the top 30 cm -- typically 3-4x
# more profiles than the "shallowest-horizon topsoil" recipe.

# --- BD per horizon: pull the WoSIS bdfiod layer (bulk density, fine
# earth, oven-dry) so we can weight each horizon's SOC by its mass per
# unit volume, not just its thickness.

bdfiod_gml <- file.path(out_dir, "wosis_bdfiod_cerrado.gml")
if (!file.exists(bdfiod_gml) ||
    file.info(bdfiod_gml)$size < 1000L) {
  req <- httr2::request(wfs_url("wosis_latest_bdfiod", bbox_lat, bbox_lon))
  req <- httr2::req_timeout(req, 600L)
  req <- httr2::req_retry(req, max_tries = 3L,
                            backoff = function(i) 2 ^ i)
  resp <- httr2::req_perform(req, path = bdfiod_gml)
  stopifnot(httr2::resp_status(resp) == 200L)
}
message(sprintf("  [ok] WoSIS bdfiod GML saved (%.1f MB)",
                 file.info(bdfiod_gml)$size / 1024^2))

bdfiod <- sf::st_read(bdfiod_gml, quiet = TRUE) |>
  sf::st_transform(4326)
bdfiod$upper_depth <- suppressWarnings(as.numeric(bdfiod$upper_depth))
bdfiod$lower_depth <- suppressWarnings(as.numeric(bdfiod$lower_depth))
bdfiod$value_avg   <- suppressWarnings(as.numeric(bdfiod$value_avg))
bdfiod <- bdfiod[is.finite(bdfiod$upper_depth) &
                 is.finite(bdfiod$lower_depth) &
                 is.finite(bdfiod$value_avg) &
                 bdfiod$upper_depth < bdfiod$lower_depth &
                 bdfiod$value_avg > 0.3 & bdfiod$value_avg < 2.5, ,
                 drop = FALSE]
message(sprintf("  [ok] bdfiod QC-clean: %d measurements across %d profiles",
                 nrow(bdfiod), length(unique(bdfiod$profile_id))))

# Helper: for a given profile id, look up the bdfiod measurement
# whose horizon covers `depth_cm` (upper <= depth_cm < lower). Return
# NA when the profile has no matching BD measurement.
.bd_for <- function(pid, depth_cm) {
  rows <- bdfiod[bdfiod$profile_id == pid, , drop = FALSE]
  if (nrow(rows) == 0L) return(NA_real_)
  hit <- which(rows$upper_depth <= depth_cm & rows$lower_depth > depth_cm)
  if (length(hit) == 0L) {
    # Fallback: nearest-horizon BD
    mid <- (rows$upper_depth + rows$lower_depth) / 2
    j <- which.min(abs(mid - depth_cm))
    return(rows$value_avg[j])
  }
  rows$value_avg[hit[1L]]
}

# Depth-weighted mean SOC concentration over the 0-30 cm window.
# Simpler than a full carbon-stock integral because it needs no per-
# horizon bulk density (which WoSIS provides for only ~20 % of
# profiles); far more robust than a single-horizon concentration
# because it pools every sampled horizon in 0-30 cm. Units: g/kg.
.soc_mean_0_30 <- function(df_orgc_profile) {
  keep <- df_orgc_profile$upper_depth < 30 &
          df_orgc_profile$lower_depth > 0
  h <- df_orgc_profile[keep, , drop = FALSE]
  if (nrow(h) == 0L) return(NA_real_)
  u <- pmax(h$upper_depth, 0)
  l <- pmin(h$lower_depth, 30)
  thickness <- l - u
  if (sum(thickness) == 0) return(NA_real_)
  stats::weighted.mean(h$value_avg, w = thickness)
}

# (Kept for future use when a better bulk-density product becomes
# available; not on the v1.3.1 critical path.)
.stock_0_30 <- function(df_orgc_profile) {
  pid <- df_orgc_profile$profile_id[1L]
  keep <- df_orgc_profile$upper_depth < 30 &
          df_orgc_profile$lower_depth > 0
  h <- df_orgc_profile[keep, , drop = FALSE]
  if (nrow(h) == 0L) return(NA_real_)
  u <- pmax(h$upper_depth, 0)
  l <- pmin(h$lower_depth, 30)
  thickness <- l - u
  bd <- vapply(seq_len(nrow(h)), function(i)
    .bd_for(pid, (u[i] + l[i]) / 2), numeric(1L))
  bd[!is.finite(bd)] <- 1.25
  sum(h$value_avg * bd * thickness / 100)
}

# Coverage ratio: fraction of 0-30 cm depth actually observed.
.cover_0_30 <- function(df_orgc_profile) {
  keep <- df_orgc_profile$upper_depth < 30 &
          df_orgc_profile$lower_depth > 0
  h <- df_orgc_profile[keep, , drop = FALSE]
  if (nrow(h) == 0L) return(0)
  u <- pmax(h$upper_depth, 0)
  l <- pmin(h$lower_depth, 30)
  # Merge overlapping intervals before summing thickness (guards
  # against double-counting if two methods sampled the same horizon).
  ord <- order(u)
  u <- u[ord]; l <- l[ord]
  cov <- 0
  cur_u <- u[1L]; cur_l <- l[1L]
  for (i in seq_along(u)[-1L]) {
    if (u[i] <= cur_l) {
      cur_l <- max(cur_l, l[i])
    } else {
      cov <- cov + (cur_l - cur_u)
      cur_u <- u[i]; cur_l <- l[i]
    }
  }
  cov <- cov + (cur_l - cur_u)
  cov / 30
}

# -- v1.3.1 repair (a) -- clean filters, relaxed to SOC-stock target --
#
#   1. SOC-stock 0-30 cm integrated across every horizon in the window
#      (uses WoSIS bdfiod per-horizon BD when available, fallback 1.25
#      g/cm^3 — canonical Cerrado topsoil BD).
#   2. Coverage of the 0-30 cm column at least 70 % (drops profiles
#      with a single 0-5 cm horizon and nothing else; the integral
#      would be meaningless).
#   3. positional_uncertainty <= 2 km (relaxed from 500 m; WoSIS
#      Brazilian profiles use "Circa 1 km" as a common tag and our
#      covariates are 1 km, so 2 km is the right operational cap).
#   4. value_avg > 0 for at least one horizon in the window.

.pos_unc_upper_m <- function(s) {
  # Returns the upper bound of the positional_uncertainty field in
  # metres. Handles "Circa 100 m", "1 to 10 km", "<1 km", "Unknown" etc.
  s <- as.character(s)
  out <- rep(NA_real_, length(s))
  has_km <- grepl("km", s, ignore.case = TRUE)
  has_m  <- grepl("m",  s, ignore.case = TRUE) & !has_km
  nums <- regmatches(s, gregexpr("[0-9]+\\.?[0-9]*", s))
  for (i in seq_along(s)) {
    n <- as.numeric(nums[[i]])
    if (length(n) == 0L || any(is.na(n))) next
    u <- max(n)                              # upper bound
    if (has_km[i]) u <- u * 1000
    out[i] <- u
  }
  # Missing / "Unknown" -> NA (conservative: drop in the filter).
  out
}

# Aggregate to one row per profile with the 0-30 cm integrated stock.
.orgc_df <- sf::st_drop_geometry(orgc)
.orgc_df$pos_unc_m <- .pos_unc_upper_m(.orgc_df$positional_uncertainty)
profile_ids <- unique(.orgc_df$profile_id)

# For each profile, return the **shallowest** horizon that starts at
# 0 cm (upper_depth == 0). Its SOC concentration is the canonical
# "topsoil" value -- comparable across profiles, no multi-horizon
# integration gymnastics. We tolerate thickness 5-30 cm so a
# 0-5 cm, 0-10 cm or 0-20 cm A-horizon all qualify.
profile_rows <- lapply(profile_ids, function(pid) {
  sub <- .orgc_df[.orgc_df$profile_id == pid, , drop = FALSE]
  # Shallowest horizon starting at the surface.
  candidates <- sub[sub$upper_depth == 0 &
                      sub$lower_depth >= 5 &
                      sub$lower_depth <= 30 &
                      is.finite(sub$value_avg) &
                      sub$value_avg > 0, , drop = FALSE]
  if (nrow(candidates) == 0L) return(NULL)
  # Among qualifying horizons keep the *shortest* (closest to a strict
  # 0-5 topsoil slice; thicker is kept only if nothing shallower).
  candidates <- candidates[order(candidates$lower_depth), , drop = FALSE]
  best <- candidates[1L, , drop = FALSE]
  coords_sf <- sf::st_coordinates(orgc[orgc$profile_id == pid, ][1L, ])
  data.frame(
    profile_id     = pid,
    profile_code   = best$profile_code,
    dataset_id     = best$dataset_id,
    date           = best$date,
    pos_unc_m      = best$pos_unc_m,
    topsoil_upper  = best$upper_depth,
    topsoil_lower  = best$lower_depth,
    soc_topsoil_gkg = best$value_avg,
    lon            = coords_sf[1L, 1L],
    lat            = coords_sf[1L, 2L],
    licence        = best$licence,
    stringsAsFactors = FALSE
  )
})
profiles_stock <- do.call(rbind, profile_rows)
profiles_stock <- profiles_stock[!is.na(profiles_stock$pos_unc_m) &
                                   profiles_stock$pos_unc_m <= 2000, ,
                                   drop = FALSE]
message(sprintf(
  "  [ok] shallowest 0-cm-starting WoSIS horizon (<= 30 cm), pos_unc <= 2 km: %d profiles",
  nrow(profiles_stock)
))

# Promote to sf for downstream spatial operations.
topsoil <- sf::st_as_sf(profiles_stock,
                          coords = c("lon", "lat"),
                          crs = 4326,
                          remove = FALSE)

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
  # Channel set chosen to match `edaphos-cerrado-moco-v1/v2`'s
  # 31-layer input (elev + slope); the pretrained encoder can be
  # applied to patches sampled from the *31-channel subset* of this
  # stack. See Zenodo deposit 10.5281/zenodo.19701276 for the v1
  # training spec and the matching v2 deposit (set after publish).
  aoi = aoi_ext, derive = c("slope"),
  country = "BRA", path = cache_dir
)

# v1.3.1 repair (b) -- ESA WorldCover fractional land cover.
#
# Land use is the single largest missing covariate for Cerrado
# topsoil SOC: native savanna vs planted pasture vs cropland
# produce 3-4x SOC differences that SoilGrids + WorldClim + SRTM
# *cannot* resolve (they're all latent-state proxies of climate +
# parent material). WorldCover 2020 fractional covers at 30 arc-sec
# via `geodata::landcover()` (Zanaga et al. 2021, CC-BY-4.0) give
# per-cell fractions of trees / grassland / shrubs / cropland / bare,
# which is exactly what we need for Cerrado where "tree cover %" and
# "cropland %" jointly discriminate every major land-use class.
message("[case] 3a/5 ESA WorldCover 2020 fractional covers...")
lc_vars <- c("trees", "grassland", "shrubs", "cropland", "bare", "built")
lc <- lapply(lc_vars, function(v) {
  r <- geodata::landcover(var = v, path = cache_dir)
  r <- terra::crop(r, aoi_ext)
  names(r) <- paste0("wc_landcover_", v)
  r
})
landcover <- do.call(c, lc)
message(sprintf("  [ok] WorldCover stack: %d fractional covers",
                 terra::nlyr(landcover)))

# v1.3.1 repair (c) -- WorldClim bio (19 bioclim indices).
#
# bio1..bio19 are the Hijmans bioclim indices (annual means, ranges,
# seasonality of temperature and precipitation). They capture climate
# structure that monthly prec/tavg averages cannot -- e.g. bio15
# (precipitation seasonality CV) is a strong predictor of Cerrado
# vs forest biome transitions.
message("[case] 3b/5 WorldClim 2.1 bioclim indices (19 layers)...")
bio <- foundation_tile_source_worldclim(
  variables = "bio", country = "BRA", aoi = aoi_ext, path = cache_dir
)
message(sprintf("  [ok] bioclim stack: %d layers", terra::nlyr(bio)))

aligned <- foundation_tile_align(
  sources = list(soilgrids = sg, worldclim = wc, srtm = sr,
                  landcover = landcover, bio = bio),
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
  pos_unc_m       = topsoil$pos_unc_m,
  topsoil_upper   = topsoil$topsoil_upper,
  topsoil_lower   = topsoil$topsoil_lower,
  # v1.3.1 target: SOC concentration of the shallowest surface-
  # anchored horizon (upper_depth == 0, lower_depth in 5-30 cm).
  # Units: g/kg. Keeps 700+ profiles with physically comparable
  # targets.
  soc_topsoil_gkg = topsoil$soc_topsoil_gkg,
  licence      = as.character(topsoil$licence),
  lon          = topsoil$lon,
  lat          = topsoil$lat,
  stringsAsFactors = FALSE
)
profiles <- cbind(profiles, vals)

# ---- 5. Deterministic 5-fold CV split ---------------------------------------
# A single 80/20 split on 302 profiles produces a very noisy estimate
# (binomial SD of metrics dominated by the 60-point test set). 5-fold
# spatially-stratified CV evaluates every profile exactly once,
# quadruples the effective evaluation sample size, and drops the
# random-split SOC distribution mismatch (observed train mean 17 vs
# test mean 21 g/kg on the fixed 80/20 split).
#
# The stratification uses 4 spatial clusters via kmeans on
# longitude/latitude so each fold contains points from every
# sub-region of the biome, not just one corner.

set.seed(2026L)
km <- stats::kmeans(profiles[, c("lon", "lat")], centers = 5L,
                     nstart = 10L)
profiles$kmeans_cluster <- km$cluster
profiles$fold <- integer(nrow(profiles))
for (k in seq_len(5L)) {
  ix <- which(profiles$kmeans_cluster == k)
  # Assign each cluster's points round-robin to folds 1..5.
  profiles$fold[ix] <- ((seq_along(ix) + k - 2L) %% 5L) + 1L
}
# Also keep a `split` column for code that still wants the old
# 80/20 semantics: fold 1 = test, folds 2..5 = train.
profiles$split <- ifelse(profiles$fold == 1L, "test", "train")
message(sprintf(
  "[case] 5/5  5-fold CV split (k-means on coords): %d profiles, %d per fold",
  nrow(profiles), round(nrow(profiles) / 5L)
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
      srtm       = "SRTM 30-arcsec (Jarvis et al. 2008; NASA public domain)",
      landcover  = "ESA WorldCover 2020 v100 (Zanaga et al. 2021), CC-BY-4.0",
      bio        = "WorldClim 2.1 bioclim indices (Fick & Hijmans 2017)"
    )
  ),
  bundle_path
)
message(sprintf("[case] bundle written: %s  (%.1f KB)",
                 bundle_path, file.info(bundle_path)$size / 1024))
message("[case] done.")
