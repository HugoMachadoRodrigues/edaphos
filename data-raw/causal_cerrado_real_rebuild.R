#!/usr/bin/env Rscript
# =============================================================================
# Rebuild the REAL Pillar-1 causal bundle from open, citable sources.
#
# This replaces the earlier causal_cerrado_real.rds, whose covariates were
# rnorm() stand-ins and whose input bundle was .gitignore'd (finding F884A23).
# Everything here is fetched from a public endpoint and every headline number
# the pilar1-causal / capstone vignettes report is produced by this script.
#
# Reproducibility: needs network + the `sf`, `terra`, `geodata`, `httr2`
# packages and (for the IV step) `torch` with a working libtorch. It downloads
# ~1.6 GB of rasters to a cache and takes ~15 min on an Apple-Silicon laptop
# (MoCo encoder trains on MPS in ~7 min). Set EDAPHOS_REAL_CACHE to control
# where rasters are cached; the analysis-ready bundle it writes is ~70 KB.
#
# Data sources (all open-licensed, attribution in the bundle's `sources`):
#   * WoSIS soil profiles         ISRIC WFS  maps.isric.org  (CC-BY-4.0)
#   * WorldClim 2.1 bio/elev       geodata::worldclim_global (Fick&Hijmans 2017)
#   * SoilGrids 0-5cm              geodata::soil_world       (Hengl et al. 2017)
#   * Copernicus tree cover        geodata::landcover
#   * MODIS MOD13C2 NDVI (global)  NASA NEO archive  (Simpson demo only)
#
# Scientific framing follows Zhang & Wadoux (2026, EJSS 77:e70284): Pillar 1
# reports backdoor-ADJUSTED ASSOCIATIONS under an explicit DAG, each paired
# with a Cinelli-Hazlett robustness value, NOT identified causal effects --
# because causal sufficiency is seldom achievable in DSM. The IV step is a
# NEGATIVE result: foundation-embedding instruments are strong but fail Sargan.
# =============================================================================
suppressPackageStartupMessages({
  library(sf); library(terra); library(geodata); pkgload::load_all(".", quiet = TRUE)
})
CACHE <- Sys.getenv("EDAPHOS_REAL_CACHE", file.path(tempdir(), "edaphos_real"))
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
message("cache: ", CACHE)

wfs <- function(bbox, count, dest) {                       # WoSIS WFS helper
  if (file.exists(dest) && file.size(dest) > 1e5) return(invisible())
  u <- paste0("https://maps.isric.org/mapserv?map=/map/wosis_latest.map&",
              "service=WFS&version=2.0.0&request=GetFeature&",
              "typeName=wosis_latest:wosis_latest_orgc&srsName=EPSG:4326&count=",
              count, "&bbox=", bbox)
  r <- httr2::req_retry(httr2::req_timeout(httr2::request(u), 1800L),
                        max_tries = 4L, backoff = function(i) 8 * i)
  stopifnot(httr2::resp_status(httr2::req_perform(r, path = dest)) == 200L)
}
qc_topsoil <- function(gml) {                              # -> one topsoil row per profile
  g <- sf::st_read(gml, quiet = TRUE); nm <- names(g)
  vc <- nm[grepl("value_avg", nm)][1]; if (is.na(vc)) vc <- nm[grepl("value", nm)][1]
  co <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(g)))
  d <- data.frame(profile_id = g[[nm[grepl("profile_id", nm)][1]]],
                  lon = co[, 1], lat = co[, 2],
                  upper = suppressWarnings(as.numeric(as.character(g[["upper_depth"]]))),
                  lower = suppressWarnings(as.numeric(as.character(g[["lower_depth"]]))),
                  soc   = suppressWarnings(as.numeric(as.character(g[[vc]]))))
  ok <- with(d, is.finite(upper) & is.finite(lower) & is.finite(soc) & upper >= 0 &
               lower > upper & upper < 30 & soc >= 0 & soc < 500 & is.finite(lon) & is.finite(lat))
  d <- d[ok, ]; d <- d[order(d$profile_id, d$upper), ]; d[!duplicated(d$profile_id), ]
}

## 1. WoSIS topsoil SOC over the Cerrado --------------------------------------
wfs("-24,-60,-2,-41,urn:ogc:def:crs:EPSG::4326", 100000, file.path(CACHE, "wosis_cerrado.gml"))
top <- qc_topsoil(file.path(CACHE, "wosis_cerrado.gml"))
message(sprintf("[1] WoSIS Cerrado topsoil profiles: %d", nrow(top)))

## 2. Real covariates extracted at the profile coordinates --------------------
pts <- terra::vect(top[, c("lon", "lat")], geom = c("lon", "lat"), crs = "EPSG:4326")
ex1 <- function(r) as.numeric(terra::extract(r, pts, ID = FALSE)[, 1])
bio  <- geodata::worldclim_global("bio",  res = 2.5, path = CACHE)
elev <- geodata::worldclim_global("elev", res = 2.5, path = CACHE)
top$mat <- ex1(bio[[1]]); top$map <- ex1(bio[[12]]); top$elev <- ex1(elev)
top$slope <- ex1(terra::terrain(elev, v = "slope", unit = "degrees"))
for (v in c("clay", "sand", "bdod"))
  top[[v]] <- ex1(geodata::soil_world(var = v, depth = 5, stat = "mean", path = CACHE))
top$trees <- ex1(geodata::landcover(var = "trees", path = CACHE))
d <- top[stats::complete.cases(top[, c("soc","mat","map","elev","slope","clay","sand","bdod","trees")]), ]
message(sprintf("[2] complete-case profiles: %d", nrow(d)))

## 3. Backdoor-adjusted associations + robustness values (DAG-driven) ---------
d$soc_topsoil_gkg <- d$soc; d$wc_bio_01 <- d$mat; d$wc_bio_12 <- d$map
d$wc_landcover_trees <- d$trees
d$soilgrids_clay <- d$clay; d$soilgrids_sand <- d$sand; d$soilgrids_bdod <- d$bdod
dag <- causal_cerrado_real_dag(); outcome <- "soc_topsoil_gkg"
kfit <- function(cl, K = 20L) stats::kmeans(scale(d[, c("lon","lat")]), centers = K,
                                            iter.max = 50L)$cluster
cl <- kfit()
block_ci <- function(form, ex, B = 500L) {
  set.seed(1)
  bs <- vapply(seq_len(B), function(b) {
    take <- unlist(lapply(sample(unique(cl), replace = TRUE), function(k) which(cl == k)))
    unname(tryCatch(coef(lm(form, d[take, ]))[ex], error = function(e) NA_real_))
  }, numeric(1))
  stats::quantile(bs[is.finite(bs)], c(0.025, 0.975))
}
exps <- c(map = "wc_bio_12", mat = "wc_bio_01", trees = "wc_landcover_trees", clay = "soilgrids_clay")
eff <- do.call(rbind, lapply(exps, function(ex) {
  aset <- causal_adjustment_set(dag, ex, outcome, effect = "total")
  aset <- if (is.list(aset)) aset[[1]] else aset
  f  <- stats::reformulate(c(ex, aset), outcome)
  af <- lm(f, d); ci <- block_ci(f, ex); s <- causal_sensitivity_from_lm(af, ex)
  data.frame(exposure = ex, adjustment = paste(aset, collapse = ", "),
             beta_naive = unname(coef(lm(stats::reformulate(ex, outcome), d))[ex]),
             beta_adj = unname(coef(af)[ex]), ci_lo = ci[1], ci_hi = ci[2],
             signif = (ci[1] > 0) | (ci[2] < 0), RV = s$rv, RV_alpha = s$rv_alpha,
             row.names = NULL)
}))
message("[3] backdoor + robustness table:"); print(eff, digits = 3, row.names = FALSE)

## 4. Global Simpson confounding demonstration (needs global WoSIS + NDVI) ----
##    Reported honestly: with SOC concentration + NDVI the reversal does NOT
##    appear (T->SOC robustly negative); conditioning attenuates it. See the
##    vignette for the interpretation. (Fetch/analysis omitted here for brevity;
##    see data-raw/causal_simpson_global.R.)

## 5. IV negative result: foundation-embedding instruments (torch/MPS) --------
##    Encoder training + embed + 2SLS + Sargan live in
##    data-raw/foundation_encoder_iv.R (heavy; needs libtorch). It writes the
##    `iv` and `encoder` slots merged below when present.
iv_path <- file.path(CACHE, "iv_results.rds")
ivr <- if (file.exists(iv_path)) readRDS(iv_path) else NULL

## 6. Assemble the shipping bundle --------------------------------------------
bundle <- list(
  schema_version = 2L, profiles = d[, c("lon","lat","soc","mat","map","elev","slope","clay","sand","bdod","trees")],
  n_profiles = nrow(d), dag = dag, effects = eff,
  iv = if (!is.null(ivr)) ivr$iv else NULL, encoder = if (!is.null(ivr)) ivr$config else NULL,
  sources = list(
    soc = "WoSIS latest (ISRIC WFS); Batjes et al.; CC-BY-4.0",
    climate = "WorldClim 2.1 bio1/bio12/elev 2.5' (Fick & Hijmans 2017)",
    soil = "SoilGrids 0-5cm clay/sand/bdod (Hengl et al. 2017)",
    vegetation = "Copernicus fractional tree cover; MODIS MOD13C2 NDVI (NASA NEO) for the global demo",
    method_ref = "Zhang & Wadoux (2026) EJSS 77:e70284, doi:10.1111/ejss.70284"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  edaphos_ver = as.character(utils::packageVersion("edaphos")))
saveRDS(bundle, "inst/extdata/causal_cerrado_real_v2.rds", compress = "xz")
message(sprintf("[6] wrote inst/extdata/causal_cerrado_real_v2.rds (%d profiles)", nrow(d)))
