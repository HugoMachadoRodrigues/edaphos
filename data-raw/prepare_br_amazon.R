# data-raw/prepare_br_amazon.R  (edaphos v3.7.0)
#
# Builds `br_amazon`, a 45 x 45 synthetic Amazon-rainforest soil
# dataset with the same column schema as `br_cerrado` so any pillar /
# vignette that runs on `br_cerrado` runs on `br_amazon` with no code
# changes.
#
# Bounding box (NW Brazilian Amazon, near Manaus):
#   x (longitude) in [-60.50, -60.10]
#   y (latitude)  in [ -3.30,  -2.90]
#
# The Amazon contrast vs Cerrado:
#   * Lower elevation       (50-300 m vs 800-1200 m)
#   * Much higher rainfall  (2200-3000 mm vs 1300-1700 mm)
#   * Higher NDVI           (0.75-0.95 vs 0.20-0.90)
#   * Higher SOC            (35-90 g/kg vs 5-75 g/kg)
#   * Lower slopes          (0-8 deg vs 0-20 deg)
#
# These distinct distributions exercise different parts of every
# pillar's parameter space (longer GP correlation lengths, more
# right-skewed SOC, etc.), making them useful as a second smoke test
# for any pipeline.

set.seed(202604L)

nx <- 45L; ny <- 45L
xs <- seq(-60.50, -60.10, length.out = nx)
ys <- seq( -3.30,  -2.90, length.out = ny)
grid <- expand.grid(x = xs, y = ys, KEEP.OUT.ATTRS = FALSE)

# Elevation (50-300 m): low-relief floodplain with a few terra firme
# uplifts.
elev_trend <- 150 +
  60 * sin((grid$x + 60.30) * 30) +
  40 * cos((grid$y +  3.10) * 25) +
  60 * ((grid$x + 60.30) / 0.40)
grid$elev <- as.numeric(elev_trend + stats::rnorm(nrow(grid), 0, 12))

# Slope (deg): derived from local elev gradient.  Amazon terra firme
# is mostly flat (< 8 deg).
elev_mat <- matrix(grid$elev, nrow = nx, ncol = ny)
dx <- rbind(0, diff(elev_mat))
dy <- cbind(0, t(diff(t(elev_mat))))
slope_mat <- sqrt(dx^2 + dy^2)
slope <- pmin(8, pmax(0, as.vector(slope_mat) * 0.3 +
                           abs(stats::rnorm(nrow(grid), 0, 0.6))))
grid$slope <- slope

# Topographic Wetness Index (4-18): higher overall than Cerrado
# (extensive flood plains).
grid$twi <- pmax(4, pmin(18, 12 -
                          (grid$elev - mean(grid$elev)) / 25 +
                          stats::rnorm(nrow(grid), 0, 1.0)))

# Mean annual precipitation (mm/y): 2200-3000.
grid$map_mm <- 2600 + 250 * scale(grid$x)[, 1] +
               stats::rnorm(nrow(grid), 0, 50)

# NDVI (0.75-0.95): closed-canopy forest is greener and less variable
# than Cerrado savanna.
ndvi <- 0.85 + 0.005 * grid$twi - 0.008 * grid$slope +
        0.00003 * (grid$map_mm - 2600) +
        stats::rnorm(nrow(grid), 0, 0.025)
grid$ndvi <- pmax(0.75, pmin(0.95, ndvi))

# SOC (g/kg, 0-5 cm topsoil) -- Amazon Oxisols/Spodosols carry more
# carbon at the surface than Cerrado Latossolos.
lin <- 50 +
       0.04  * (grid$elev - 150) +
       2.0   * grid$twi -
       0.5   * grid$slope +
       0.012 * (grid$map_mm - 2400) +
      35.0   * (grid$ndvi - 0.85)
interaction <- 0.04 * grid$twi * (grid$elev - 150) / 50
noise <- stats::rnorm(nrow(grid), 0, 4 + 0.1 * slope)
grid$soc <- pmax(35, pmin(90, lin + interaction + noise))

br_amazon <- grid[, c("x", "y", "elev", "slope", "twi",
                       "map_mm", "ndvi", "soc")]
br_amazon <- br_amazon[order(br_amazon$y, br_amazon$x), ]
rownames(br_amazon) <- NULL

br_amazon$elev   <- round(br_amazon$elev,   1)
br_amazon$slope  <- round(br_amazon$slope,  2)
br_amazon$twi    <- round(br_amazon$twi,    3)
br_amazon$map_mm <- round(br_amazon$map_mm, 1)
br_amazon$ndvi   <- round(br_amazon$ndvi,   3)
br_amazon$soc    <- round(br_amazon$soc,    2)

usethis::use_data(br_amazon, overwrite = TRUE, compress = "xz")
