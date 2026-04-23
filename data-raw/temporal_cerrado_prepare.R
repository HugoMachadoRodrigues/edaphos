# Pillar 3 real-data prep: build a 4D (H x W x T x C) Cerrado
# spatiotemporal cube from MODIS MOD13Q1 NDVI and NASA POWER monthly
# precipitation.
#
# The AoI is a 2 deg x 2 deg core-Cerrado cut (lat -16 to -14,
# lon -48 to -46) -- ~45000 km^2 around Goias / Minas Gerais triple
# junction. Large enough to exercise the ConvLSTM but small enough
# that the MODISTools point-by-point API is tractable (monthly
# composites over 14 years of a 10x10 grid = 100 point queries).
#
# Channels (C = 3):
#   NDVI        from MOD13Q1 250m 16-day, aggregated to monthly means
#   precip_mm   from NASA POWER (MERRA-2 bias-corrected), monthly mean
#                daily precip (mm/day) scaled to monthly sums.  We
#                originally targeted CHIRPS but the CHG data server
#                was returning HTTP 403 for v2.0 monthly tifs at the
#                time of the v1.5.0 freeze; POWER is a fully-open
#                NASA alternative with comparable accuracy for
#                monthly aggregates over the Cerrado.
#   tavg_C      from NASA POWER T2M (2-m air temperature, MERRA-2
#                bias-corrected), monthly mean.  Year-specific (not a
#                static climatology), fetched from the same POWER
#                point call as the precipitation.  (We originally
#                targeted WorldClim 2.1 BRA country-pack but the
#                geodata.ucdavis.edu server was in maintenance at
#                the v1.5.0 freeze.)
#
# Time dimension: 2010-01 through 2023-12 = 168 monthly timesteps.
# AoI grid: 10 x 10 cells at 0.2 deg resolution.
#
# Output: tools/temporal_cerrado/temporal_cerrado_cube.rds -- a
# data structure the vignette + runner consume directly.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(sf)
  library(terra)
  library(MODISTools)
  library(dplyr)
  library(curl)
  library(httr2)
  library(jsonlite)
})

out_dir <- "tools/temporal_cerrado"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- AoI + grid -----------------------------------------------------------

bbox <- c(lon_min = -48, lon_max = -46, lat_min = -16, lat_max = -14)
grid_res <- 0.2
H <- W <- as.integer(diff(bbox[1:2]) / grid_res)          # 10 cells
lons <- seq(bbox["lon_min"] + grid_res/2,
             bbox["lon_max"] - grid_res/2, by = grid_res)
lats <- seq(bbox["lat_max"] - grid_res/2,
             bbox["lat_min"] + grid_res/2, by = -grid_res)
grid_pts <- expand.grid(lon = lons, lat = lats, KEEP.OUT.ATTRS = FALSE)
grid_pts$cell_id <- seq_len(nrow(grid_pts))
message(sprintf("[temporal] AoI = 2 deg x 2 deg, grid = %d x %d (%d cells)",
                 H, W, nrow(grid_pts)))

# --- Time axis ------------------------------------------------------------

months <- seq(as.Date("2010-01-01"), as.Date("2023-12-01"), by = "month")
T_steps <- length(months)
stopifnot(T_steps == 168L)
message(sprintf("[temporal] T = %d monthly timesteps (%s .. %s)",
                 T_steps, min(months), max(months)))

# --- NASA POWER monthly precipitation at each grid cell -------------------
#
# POWER exposes a REST endpoint that returns all months in a single
# HTTP call per point:
#   https://power.larc.nasa.gov/api/temporal/monthly/point?
#     parameters=PRECTOTCORR&community=AG&longitude=...&latitude=...
#     &start=YYYY&end=YYYY&format=JSON
# The units are mm/day (monthly mean), so we scale by the number of
# days in the month to recover monthly totals. The open CDN tolerates
# 400 concurrent-ish point queries; ~2s / call -> ~13 min total.
#
# We cache the raw POWER JSONs under tools/temporal_cerrado/power_json/
# so a re-run only hits the API for cells that are missing.

precip_path <- file.path(out_dir, "power_precip_monthly.rds")
tavg_path   <- file.path(out_dir, "power_tavg_monthly.rds")
if (file.exists(precip_path) && file.exists(tavg_path)) {
  precip_mm <- readRDS(precip_path)
  tavg_mm   <- readRDS(tavg_path)
  message("[temporal] POWER precip + tavg cache hit")
} else {
  message(sprintf(
    "[temporal] Pulling NASA POWER monthly precip + tavg for %d cells...",
    nrow(grid_pts)
  ))
  power_cache <- file.path(out_dir, "power_json")
  dir.create(power_cache, recursive = TRUE, showWarnings = FALSE)

  .fetch_power_cell <- function(lon, lat, start_year, end_year,
                                 cache_path) {
    if (file.exists(cache_path)) {
      return(jsonlite::fromJSON(cache_path, simplifyVector = FALSE))
    }
    url <- sprintf(
      "https://power.larc.nasa.gov/api/temporal/monthly/point?parameters=PRECTOTCORR,T2M&community=AG&longitude=%.4f&latitude=%.4f&start=%d&end=%d&format=JSON",
      lon, lat, start_year, end_year
    )
    req <- httr2::request(url) |> httr2::req_retry(max_tries = 3L)
    resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
    if (is.null(resp) || httr2::resp_status(resp) != 200L) return(NULL)
    raw <- httr2::resp_body_string(resp)
    writeLines(raw, cache_path)
    jsonlite::fromJSON(raw, simplifyVector = FALSE)
  }

  precip_rows <- vector("list", nrow(grid_pts))
  tavg_rows   <- vector("list", nrow(grid_pts))
  dpm <- vapply(months, function(d) {
    as.integer(format(seq(d, by = "month", length.out = 2L)[2L] - 1L, "%d"))
  }, integer(1L))          # days per month, aligned with months[]
  ym_keys_num <- as.integer(format(months, "%Y%m"))

  for (i in seq_len(nrow(grid_pts))) {
    cell_id <- grid_pts$cell_id[i]
    cache_path <- file.path(power_cache,
                              sprintf("cell_%04d.json", cell_id))
    obj <- .fetch_power_cell(grid_pts$lon[i], grid_pts$lat[i],
                               2010L, 2023L, cache_path)
    if (is.null(obj)) {
      message(sprintf("  POWER cell %d failed", cell_id)); next
    }
    pr_par <- obj$properties$parameter$PRECTOTCORR
    t_par  <- obj$properties$parameter$T2M
    if (is.null(pr_par) || is.null(t_par)) next
    # Drop annual-mean key (YYYY13) from both series.
    pr_keys <- as.integer(names(pr_par))
    t_keys  <- as.integer(names(t_par))
    pr_ok <- pr_keys %% 100L != 13L
    t_ok  <- t_keys  %% 100L != 13L
    pr_keys <- pr_keys[pr_ok]; pr_vals <- unlist(pr_par)[pr_ok]
    t_keys  <- t_keys[t_ok];   t_vals  <- unlist(t_par)[t_ok]
    mm_per_day <- pr_vals[match(ym_keys_num, pr_keys)]
    tavg       <- t_vals[match(ym_keys_num, t_keys)]
    precip_rows[[i]] <- data.frame(
      cell_id   = rep(cell_id, length(months)),
      ym        = format(months, "%Y-%m"),
      precip_mm = as.numeric(mm_per_day) * dpm,
      stringsAsFactors = FALSE
    )
    tavg_rows[[i]] <- data.frame(
      cell_id = rep(cell_id, length(months)),
      ym      = format(months, "%Y-%m"),
      tavg_C  = as.numeric(tavg),
      stringsAsFactors = FALSE
    )
    if (i %% 25L == 0L)
      message(sprintf("  [POWER] %d / %d cells",
                       i, nrow(grid_pts)))
  }
  precip_mm <- do.call(rbind, precip_rows)
  tavg_mm   <- do.call(rbind, tavg_rows)
  # Keep the `id` column name for compatibility with the cube builder.
  precip_mm$id <- precip_mm$cell_id
  tavg_mm$id   <- tavg_mm$cell_id
  saveRDS(precip_mm, precip_path)
  saveRDS(tavg_mm,   tavg_path)
  message(sprintf("[temporal] POWER precip + tavg cached to %s, %s",
                   precip_path, tavg_path))
}
# Alias retained so downstream code stays readable.
chirps_mm <- precip_mm

# --- MODIS MOD13Q1 NDVI at each grid cell -------------------------------
#
# The ORNL MODIS REST service is the bottleneck of this prep: each
# point-subset query against MOD13Q1 takes 1-2 minutes for a 14-year
# pull. We cache each cell's raw response under
# `tools/temporal_cerrado/modis_ndvi_cells/cell_NNNN.rds` so the loop
# is safely resumable after interrupts.

modis_path <- file.path(out_dir, "modis_ndvi_monthly.rds")
if (file.exists(modis_path)) {
  ndvi_mm <- readRDS(modis_path)
  message("[temporal] MODIS cache hit")
} else {
  message(sprintf(
    "[temporal] Pulling MOD13Q1 NDVI for %d cells (point-by-point)...",
    nrow(grid_pts)
  ))
  modis_cache <- file.path(out_dir, "modis_ndvi_cells")
  dir.create(modis_cache, recursive = TRUE, showWarnings = FALSE)

  ndvi_rows <- list()
  for (i in seq_len(nrow(grid_pts))) {
    cell_rds <- file.path(modis_cache, sprintf("cell_%04d.rds", i))
    if (file.exists(cell_rds)) {
      r <- readRDS(cell_rds)
    } else {
      r <- tryCatch(
        MODISTools::mt_subset(
          product = "MOD13Q1", band = "250m_16_days_NDVI",
          lat = grid_pts$lat[i], lon = grid_pts$lon[i],
          start = "2010-01-01", end = "2023-12-31",
          km_lr = 0, km_ab = 0,
          site_name = sprintf("cell_%04d", i),
          internal = TRUE
        ),
        error = function(e) { message("  cell ", i, " failed: ",
                                        conditionMessage(e)); NULL }
      )
      if (!is.null(r) && nrow(r) > 0L) saveRDS(r, cell_rds)
    }
    if (!is.null(r) && nrow(r) > 0L) {
      r$cell_id <- grid_pts$cell_id[i]
      ndvi_rows[[i]] <- r[, c("cell_id", "calendar_date", "value",
                                "scale")]
    }
    if (i %% 10L == 0L) message(sprintf("  [%d/%d cells fetched]",
                                           i, nrow(grid_pts)))
  }
  ndvi_all <- do.call(rbind, ndvi_rows)
  ndvi_all$date <- as.Date(ndvi_all$calendar_date)
  ndvi_all$ndvi <- ndvi_all$value * as.numeric(ndvi_all$scale)
  ndvi_all$ym <- format(ndvi_all$date, "%Y-%m")
  ndvi_mm <- ndvi_all |>
    dplyr::group_by(cell_id, ym) |>
    dplyr::summarise(ndvi = mean(ndvi, na.rm = TRUE), .groups = "drop")
  saveRDS(ndvi_mm, modis_path)
  message(sprintf("[temporal] MODIS cached to %s", modis_path))
}

# --- tavg is already assembled from the POWER pull above ---------------

# --- Build the (H, W, T, 3) cube ---------------------------------------

cube <- array(NA_real_, dim = c(H, W, T_steps, 3),
                dimnames = list(NULL, NULL, format(months, "%Y-%m"),
                                  c("ndvi", "precip_mm", "tavg_C")))

for (i in seq_len(nrow(grid_pts))) {
  cell_id <- grid_pts$cell_id[i]
  # Column-major: lon index is column, lat index is row.
  r <- which(lats == grid_pts$lat[i])
  c <- which(lons == grid_pts$lon[i])
  if (length(r) == 0L || length(c) == 0L) next
  # NDVI
  nd <- ndvi_mm[ndvi_mm$cell_id == cell_id, , drop = FALSE]
  match_t <- match(format(months, "%Y-%m"), nd$ym)
  cube[r, c, , 1L] <- nd$ndvi[match_t]
  # POWER precipitation (year-specific)
  ch <- chirps_mm[chirps_mm$id == cell_id, , drop = FALSE]
  match_t <- match(format(months, "%Y-%m"), ch$ym)
  cube[r, c, , 2L] <- ch$precip_mm[match_t]
  # POWER tavg (year-specific, not a climatology)
  tv <- tavg_mm[tavg_mm$id == cell_id, , drop = FALSE]
  match_t <- match(format(months, "%Y-%m"), tv$ym)
  cube[r, c, , 3L] <- tv$tavg_C[match_t]
}

# --- Simple NA fill: impute missing NDVI per cell by cubic-spline
# over time; CHIRPS should have no NAs; tavg is static.
for (ch in seq_len(3L)) {
  for (r in seq_len(H)) {
    for (cc in seq_len(W)) {
      z <- cube[r, cc, , ch]
      if (any(!is.finite(z))) {
        ok <- which(is.finite(z))
        if (length(ok) >= 4L) {
          ix_all <- seq_along(z)
          ap <- stats::approx(ok, z[ok], xout = ix_all, rule = 2)
          cube[r, cc, , ch] <- ap$y
        }
      }
    }
  }
}
message(sprintf("[temporal] cube built: %s  (%.1f MB float64)",
                 paste(dim(cube), collapse = " x "),
                 as.numeric(object.size(cube)) / 1024^2))

# --- Persist ----------------------------------------------------------------

bundle <- list(
  cube        = cube,
  dim_names   = list(H = H, W = W, T = T_steps, C = 3),
  lons        = lons, lats = lats, months = months,
  bbox        = bbox,
  sources     = list(
    ndvi    = "MOD13Q1 250m 16-day NDVI (USGS / NASA LP DAAC)",
    precip  = "NASA POWER (MERRA-2 bias-corrected), monthly mean daily precipitation scaled by days-in-month -- public domain",
    tavg    = "NASA POWER T2M (MERRA-2 bias-corrected), monthly mean 2-m air temperature (year-specific) -- public domain"
  ),
  created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  edaphos_ver = as.character(packageVersion("edaphos"))
)
out_path <- file.path(out_dir, "temporal_cerrado_cube.rds")
saveRDS(bundle, out_path)
message(sprintf("[temporal] bundle written to %s (%.1f MB)",
                 out_path, file.info(out_path)$size / 1024^2))
