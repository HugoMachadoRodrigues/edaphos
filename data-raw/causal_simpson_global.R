#!/usr/bin/env Rscript
# =============================================================================
# Global confounding demonstration for the Pillar-1 vignette, motivated by
# Zhang & Wadoux (2026) Figure 1.
#
# HONEST RESULT, reported as measured: on a genuinely global WoSIS topsoil
# sample (~49k profiles, MAT -20..31 C) with real WorldClim MAT and MODIS
# MOD13C2 NDVI, the T -> SOC relationship is robustly NEGATIVE at every
# vegetation level and pooled, and conditioning on vegetation ATTENUATES but
# does NOT reverse it. The striking sign-flip of the paper's Figure 1d does not
# reproduce with SOC concentration + NDVI -- it depends on the paper's specific
# EVI + SOC-stock construction. We therefore present confounding as attenuation
# (and, regionally, as the tree-cover effect collapsing once climate is
# adjusted for -- see the main bundle's `effects`), not as a forced reversal.
#
# Needs sf, terra, httr2. Downloads global WoSIS (~2x135 MB) + one global NDVI
# GeoTIFF (~6 MB). Writes $EDAPHOS_REAL_CACHE/simpson_global.rds.
# =============================================================================
suppressPackageStartupMessages({ library(sf); library(terra) })
CACHE <- Sys.getenv("EDAPHOS_REAL_CACHE", file.path(tempdir(), "edaphos_real"))

wfs <- function(bbox, count, dest) {
  if (file.exists(dest) && file.size(dest) > 1e5) return(invisible())
  u <- paste0("https://maps.isric.org/mapserv?map=/map/wosis_latest.map&service=WFS",
              "&version=2.0.0&request=GetFeature&typeName=wosis_latest:wosis_latest_orgc",
              "&srsName=EPSG:4326&count=", count, "&bbox=", bbox)
  r <- httr2::req_retry(httr2::req_timeout(httr2::request(u), 1800L), max_tries = 4L,
                        backoff = function(i) 8 * i)
  stopifnot(httr2::resp_status(httr2::req_perform(r, path = dest)) == 200L)
}
qc <- function(gml) {
  g <- sf::st_read(gml, quiet = TRUE); nm <- names(g)
  vc <- nm[grepl("value_avg", nm)][1]; if (is.na(vc)) vc <- nm[grepl("value", nm)][1]
  co <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(g)))
  d <- data.frame(lon = co[, 1], lat = co[, 2],
                  upper = suppressWarnings(as.numeric(as.character(g[["upper_depth"]]))),
                  lower = suppressWarnings(as.numeric(as.character(g[["lower_depth"]]))),
                  soc   = suppressWarnings(as.numeric(as.character(g[[vc]]))))
  ok <- with(d, is.finite(upper) & is.finite(soc) & upper >= 0 & lower > upper &
               upper < 30 & soc >= 0 & soc < 500)
  d[ok, ]
}
# Two bands so the sample truly spans the globe (a single capped call truncates).
wfs("-56,-180,17.5,180,urn:ogc:def:crs:EPSG::4326", 80000, file.path(CACHE, "wosis_south.gml"))
wfs("17.5,-180,84,180,urn:ogc:def:crs:EPSG::4326",  90000, file.path(CACHE, "wosis_north.gml"))
g <- unique(rbind(qc(file.path(CACHE, "wosis_south.gml")), qc(file.path(CACHE, "wosis_north.gml"))))

# Global NDVI: MODIS MOD13C2 from NASA NEO (georef must be forced -- NEO grid).
ndir <- file.path(CACHE, "ndvi"); dir.create(ndir, showWarnings = FALSE, recursive = TRUE)
ndest <- file.path(ndir, "ndvi_global.tif")
if (!file.exists(ndest) || file.size(ndest) < 1e5) {
  base <- "https://neo.gsfc.nasa.gov/archive/geotiff.float/MOD_NDVI_M/"
  fl <- unique(regmatches(paste(readLines(url(base), warn = FALSE), collapse = "\n"),
               gregexpr("MOD13C2[.]A[0-9]+[.]061[.][0-9]+[.]tif",
                        paste(readLines(url(base), warn = FALSE), collapse = "\n")))[[1]])
  f <- fl[length(fl) %/% 2]
  httr2::req_perform(httr2::req_timeout(httr2::request(paste0(base, f)), 240L), path = ndest)
}
ndvi <- terra::rast(ndest); terra::ext(ndvi) <- c(-180, 180, -90, 90)
terra::crs(ndvi) <- "EPSG:4326"; ndvi <- terra::clamp(ndvi, -1, 1, values = FALSE)
mat <- terra::rast(file.path(CACHE, "climate/wc2.1_2.5m/wc2.1_2.5m_bio_1.tif"))
pts <- terra::vect(g[, c("lon", "lat")], geom = c("lon", "lat"), crs = "EPSG:4326")
g$mat  <- as.numeric(terra::extract(mat,  pts, ID = FALSE)[, 1])
g$ndvi <- as.numeric(terra::extract(ndvi, pts, ID = FALSE)[, 1])
g <- g[stats::complete.cases(g[, c("soc", "mat", "ndvi")]) & g$ndvi > 0, ]

g$vlev <- cut(g$ndvi, quantile(g$ndvi, seq(0, 1, length.out = 7)), include.lowest = TRUE)
cen <- do.call(rbind, lapply(split(g, g$vlev), function(s) data.frame(
  level = s$vlev[1], mT = mean(s$mat), mS = mean(s$soc), n = nrow(s),
  within = coef(lm(soc ~ mat, s))["mat"])))
out <- list(centroids = cen, pooled = unname(coef(lm(soc ~ mat, g))["mat"]),
            between = unname(coef(lm(mS ~ mT, cen))["mT"]), within = median(cen$within),
            cor_ndvi_mat = cor(g$ndvi, g$mat), cor_soc_ndvi = cor(g$soc, g$ndvi), n = nrow(g))
saveRDS(out, file.path(CACHE, "simpson_global.rds"))
message(sprintf("[simpson] n=%d MAT %.0f..%.0f | pooled %+.2f within %+.2f between %+.2f | reversal=%s",
                out$n, min(g$mat), max(g$mat), out$pooled, out$within, out$between,
                sign(out$between) != sign(out$within)))
