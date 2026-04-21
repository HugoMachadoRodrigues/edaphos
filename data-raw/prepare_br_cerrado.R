# data-raw/prepare_br_cerrado.R
#
# Builds `br_cerrado`, a small Cerrado-like synthetic soil dataset bundled
# with edaphos so that the vignettes run offline and reproducibly.
#
# The bounding box mimics a ~30 km square near Brasília (Distrito Federal):
#   x (longitude) in [-47.95, -47.60]
#   y (latitude)  in [-16.00, -15.70]
# at roughly 600 m resolution (45 x 45 grid).
#
# Covariates and Soil Organic Carbon (SOC) are generated with plausible
# Cerrado-like ranges and a deliberately non-trivial response surface so
# the Active Learning loop in Pillar 5 has something real to learn.
#
# ---- Live-data variant (optional, requires Internet + geodata + terra)
# The block below fetches the real SoilGrids 250 m SOC + WorldClim MAP +
# SRTM elevation for the same bbox and returns a data frame with the same
# column names, so you can rerun the vignettes on true observations:
#
# if (FALSE) {
#   if (!requireNamespace("geodata", quietly = TRUE) ||
#       !requireNamespace("terra",   quietly = TRUE)) {
#     stop("Install `geodata` and `terra` to fetch real data.")
#   }
#   tmp <- tempdir()
#   bbox <- terra::ext(-47.95, -47.60, -16.00, -15.70)
#
#   elev <- geodata::elevation_30s(country = "BRA", path = tmp)
#   elev <- terra::crop(elev, bbox)
#
#   soc  <- geodata::soil_world(var = "soc", depth = 5, stat = "mean",
#                               path = tmp)
#   soc  <- terra::crop(soc, bbox)
#
#   map_mm <- geodata::worldclim_country("BRA", var = "prec", path = tmp)
#   map_mm <- sum(terra::crop(map_mm, bbox))
#
#   # Resample to a common ~600 m grid
#   tpl <- terra::rast(bbox, res = 0.006, crs = "EPSG:4326")
#   stk <- c(
#     terra::resample(elev,   tpl, method = "bilinear"),
#     terra::resample(soc,    tpl, method = "bilinear"),
#     terra::resample(map_mm, tpl, method = "bilinear")
#   )
#   names(stk) <- c("elev", "soc", "map_mm")
#   df <- as.data.frame(stk, xy = TRUE, na.rm = TRUE)
#   df$slope <- terra::terrain(stk$elev, "slope", unit = "degrees") |>
#                 terra::values() |> as.vector() |> head(nrow(df))
#   # ... (downstream derivations of TWI / NDVI left as an exercise)
# }

set.seed(202604)

nx <- 45L
ny <- 45L
xs <- seq(-47.95, -47.60, length.out = nx)
ys <- seq(-16.00, -15.70, length.out = ny)
grid <- expand.grid(x = xs, y = ys, KEEP.OUT.ATTRS = FALSE)

# --- Synthetic environmental covariates (Cerrado-like ranges) -----------

# Elevation: low-frequency sinusoidal trend + localised noise (800-1200 m).
elev_trend <- 950 +
  120 * sin((grid$x + 47.77) * 30) +
   80 * cos((grid$y + 15.85) * 25) +
  200 * ((grid$x + 47.77) / 0.35)
grid$elev <- as.numeric(elev_trend + rnorm(nrow(grid), 0, 25))

# Slope (deg): derived from local elev gradient + noise (0-20).
elev_mat <- matrix(grid$elev, nrow = nx, ncol = ny)
dx <- rbind(0, diff(elev_mat))             # nx x ny
dy <- cbind(0, t(diff(t(elev_mat))))       # nx x ny
slope_mat <- sqrt(dx^2 + dy^2)
slope <- pmin(20, pmax(0, as.vector(slope_mat) * 0.4 +
                           abs(rnorm(nrow(grid), 0, 1.5))))
grid$slope <- slope

# Topographic Wetness Index (0-15): higher in concave/low areas.
grid$twi <- pmax(0, pmin(15, 10 -
                          (grid$elev - mean(grid$elev)) / 40 +
                          rnorm(nrow(grid), 0, 1.2)))

# Mean annual precipitation (mm/y): mild west-east gradient (1300-1700).
grid$map_mm <- 1500 + 200 * scale(grid$x)[, 1] +
               rnorm(nrow(grid), 0, 35)

# NDVI (0.2-0.9): increases with wetness, decreases with slope.
ndvi <- 0.55 + 0.015 * grid$twi - 0.01 * grid$slope +
        0.00005 * (grid$map_mm - 1500) +
        rnorm(nrow(grid), 0, 0.05)
grid$ndvi <- pmax(0.20, pmin(0.90, ndvi))

# --- Target: Soil Organic Carbon (g/kg), 0-5 cm topsoil -----------------
#
# Response surface chosen to be non-linear and multivariate, so that cLHS
# seeding alone cannot pinpoint the high-uncertainty zones -- this is
# where Active Learning pays off.
lin <-  8 +
        0.012 * (grid$elev - 900) +
        1.5   * grid$twi -
        0.35  * grid$slope +
        0.009 * (grid$map_mm - 1400) +
       20.0   * (grid$ndvi - 0.5)
interaction <- 0.03 * grid$twi * (grid$elev - 900) / 100
noise <- rnorm(nrow(grid), 0, 3 + 0.08 * slope)  # heteroscedastic
grid$soc <- pmax(5, pmin(75, lin + interaction + noise))

br_cerrado <- grid[, c("x", "y", "elev", "slope", "twi",
                       "map_mm", "ndvi", "soc")]
br_cerrado <- br_cerrado[order(br_cerrado$y, br_cerrado$x), ]
rownames(br_cerrado) <- NULL

# Round to sane precision
br_cerrado$elev   <- round(br_cerrado$elev,   1)
br_cerrado$slope  <- round(br_cerrado$slope,  2)
br_cerrado$twi    <- round(br_cerrado$twi,    3)
br_cerrado$map_mm <- round(br_cerrado$map_mm, 1)
br_cerrado$ndvi   <- round(br_cerrado$ndvi,   3)
br_cerrado$soc    <- round(br_cerrado$soc,    2)

usethis::use_data(br_cerrado, overwrite = TRUE, compress = "xz")
