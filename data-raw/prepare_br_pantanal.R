# data-raw/prepare_br_pantanal.R  (edaphos v3.7.0)
#
# Builds `br_pantanal`, a 45 x 45 synthetic Pantanal-wetland soil
# dataset with the same column schema as `br_cerrado` so the same
# vignettes run unchanged.
#
# Bounding box (Brazilian Pantanal, Mato Grosso do Sul):
#   x (longitude) in [-57.40, -57.00]
#   y (latitude)  in [-19.50, -19.10]
#
# Pantanal contrast vs Cerrado:
#   * Very flat               (elev 80-150 m, slopes 0-3 deg)
#   * Strongly bimodal SOC    (long dry season vs prolonged flooding)
#   * Higher TWI variance     (perennial channels + episodic floodplain)
#   * Moderate rainfall       (1100-1400 mm)
#   * Variable NDVI           (0.30-0.80; flooded grass + gallery forest)

set.seed(202604L)

nx <- 45L; ny <- 45L
xs <- seq(-57.40, -57.00, length.out = nx)
ys <- seq(-19.50, -19.10, length.out = ny)
grid <- expand.grid(x = xs, y = ys, KEEP.OUT.ATTRS = FALSE)

# Elevation: very flat plain (80-150 m).
elev_trend <- 110 +
  18 * sin((grid$x + 57.20) * 30) +
  12 * cos((grid$y + 19.30) * 25) +
  20 * ((grid$x + 57.20) / 0.40)
grid$elev <- as.numeric(elev_trend + stats::rnorm(nrow(grid), 0, 4))

# Slope (deg): essentially flat.
elev_mat <- matrix(grid$elev, nrow = nx, ncol = ny)
dx <- rbind(0, diff(elev_mat))
dy <- cbind(0, t(diff(t(elev_mat))))
slope_mat <- sqrt(dx^2 + dy^2)
slope <- pmin(3, pmax(0, as.vector(slope_mat) * 0.5 +
                           abs(stats::rnorm(nrow(grid), 0, 0.2))))
grid$slope <- slope

# TWI: bimodal (channels + floodplain).  Synthesise as a mixture of
# two Gaussians to mimic the wetland geomorphology.
twi_mode <- ifelse(stats::runif(nrow(grid)) < 0.35, 16, 9)
grid$twi <- pmax(3, pmin(20, twi_mode +
                           stats::rnorm(nrow(grid), 0, 1.5)))

# Mean annual precipitation (1100-1400 mm): seasonal monsoon climate.
grid$map_mm <- 1250 + 90 * scale(grid$x)[, 1] +
               stats::rnorm(nrow(grid), 0, 25)

# NDVI: bimodal mirror of TWI (gallery forest vs flooded grassland).
ndvi <- ifelse(grid$twi > 13,
                 0.75 + stats::rnorm(nrow(grid), 0, 0.04),
                 0.40 + stats::rnorm(nrow(grid), 0, 0.06))
grid$ndvi <- pmax(0.30, pmin(0.85, ndvi))

# SOC (g/kg): wetland soils carry HIGHLY VARIABLE carbon depending on
# flood-pulse history.
lin <- 18 +
        0.05 * (grid$elev - 110) +
        2.5  * grid$twi -
        0.2  * grid$slope +
        0.01 * (grid$map_mm - 1250) +
       18.0  * (grid$ndvi - 0.55)
interaction <- 0.06 * grid$twi * (grid$ndvi - 0.55)
noise <- stats::rnorm(nrow(grid), 0, 4 + 0.5 * grid$twi / 10)
grid$soc <- pmax(8, pmin(95, lin + interaction + noise))

br_pantanal <- grid[, c("x", "y", "elev", "slope", "twi",
                         "map_mm", "ndvi", "soc")]
br_pantanal <- br_pantanal[order(br_pantanal$y, br_pantanal$x), ]
rownames(br_pantanal) <- NULL

br_pantanal$elev   <- round(br_pantanal$elev,   1)
br_pantanal$slope  <- round(br_pantanal$slope,  2)
br_pantanal$twi    <- round(br_pantanal$twi,    3)
br_pantanal$map_mm <- round(br_pantanal$map_mm, 1)
br_pantanal$ndvi   <- round(br_pantanal$ndvi,   3)
br_pantanal$soc    <- round(br_pantanal$soc,    2)

usethis::use_data(br_pantanal, overwrite = TRUE, compress = "xz")
