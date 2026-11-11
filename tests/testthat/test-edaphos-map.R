# edaphos_map(): a fitted model and covariates in, prediction and
# uncertainty out, in the same form as the input.

grid_df <- function() {
  data("br_cerrado", package = "edaphos", envir = environment())
  br_cerrado
}
COVS <- c("elev", "slope", "twi", "map_mm", "ndvi")
lm_fit <- function(g) {
  set.seed(1)
  stats::lm(soc ~ elev + slope + twi + map_mm + ndvi,
            data = g[sample(nrow(g), 60), ])
}

test_that("data frame in, data frame out, with mean, sd and quantiles", {
  g <- grid_df(); f <- lm_fit(g)
  out <- edaphos_map(f, g)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), nrow(g))
  expect_true(all(c("mean", "sd", "q5", "q50", "q95") %in% names(out)))
  expect_equal(out$mean, unname(stats::predict(f, g)))
  expect_true(all(out$q5 < out$mean & out$mean < out$q95))
  info <- attr(out, "edaphos_map")
  expect_identical(info$uncertainty, "lm prediction interval")
  expect_equal(info$n_predicted, nrow(g))
})

test_that("lm quantiles are the exact prediction interval", {
  g <- grid_df(); f <- lm_fit(g)
  out <- edaphos_map(f, g[1:20, ], probs = c(0.025, 0.975))
  pi <- stats::predict(f, g[1:20, ], interval = "prediction", level = 0.95)
  expect_equal(out$q2.5, unname(pi[, "lwr"]))
  expect_equal(out$q97.5, unname(pi[, "upr"]))
})

test_that("missing covariates give NA, not an error and not a value", {
  g <- grid_df(); f <- lm_fit(g)
  g$ndvi[1:7] <- NA
  out <- edaphos_map(f, g)
  expect_true(all(is.na(out$mean[1:7])))
  expect_false(anyNA(out$mean[-(1:7)]))
  expect_equal(attr(out, "edaphos_map")$n_predicted, nrow(g) - 7L)
})

test_that("a missing covariate column is named in the error", {
  g <- grid_df(); f <- lm_fit(g)
  expect_error(edaphos_map(f, g[, c("x", "y", "elev")]), "slope")
})

test_that("chunking does not change the result", {
  g <- grid_df(); f <- lm_fit(g)
  expect_equal(edaphos_map(f, g, chunk_size = 97L)$q95,
               edaphos_map(f, g)$q95)
})

test_that("raster in, raster out, cell for cell", {
  skip_if_not_installed("terra")
  g <- grid_df(); f <- lm_fit(g)
  r <- terra::rast(g[, c("x", "y", COVS)], type = "xyz", crs = "EPSG:4326")
  r[3] <- NA
  m <- edaphos_map(f, r)
  expect_s4_class(m, "SpatRaster")
  expect_identical(names(m), c("mean", "sd", "q5", "q50", "q95"))
  expect_true(terra::compareGeom(m, r))
  v  <- terra::values(m)
  cv <- as.data.frame(terra::values(r))
  ok <- stats::complete.cases(cv)
  expect_true(is.na(v[3, "mean"]))
  expect_equal(v[ok, "mean"], unname(stats::predict(f, cv[ok, ])))
})

test_that("sf points in, sf points out", {
  skip_if_not_installed("sf")
  g <- grid_df(); f <- lm_fit(g)
  pts <- sf::st_as_sf(g[1:15, ], coords = c("x", "y"), crs = 4326)
  out <- edaphos_map(f, pts)
  expect_s3_class(out, "sf")
  expect_equal(out$mean, unname(stats::predict(f, g[1:15, ])))
})

test_that("Pillar 7 maps with coordinates taken from the fit", {
  g <- grid_df()
  set.seed(2)
  tr <- g[sample(nrow(g), 50), ]
  f <- bhs_fit(tr, soc ~ elev + ndvi, coords = c("x", "y"),
               nmcmc = 300L, seed = 1L)
  set.seed(3)
  out <- edaphos_map(f, g[1:30, ], n_draws = 100L)
  expect_identical(attr(out, "edaphos_map")$uncertainty,
                   "posterior predictive draws")
  expect_true(all(out$sd > 0))
  expect_true(all(out$q5 <= out$q50 & out$q50 <= out$q95))
  # coordinates are required: without them the model cannot predict
  expect_error(edaphos_map(f, g[1:5, c("elev", "ndvi")]), "x, y")
})

test_that("Pillar 5 maps with its quantile-forest uncertainty", {
  g <- grid_df()
  set.seed(4)
  tr <- g[sample(nrow(g), 60), ]
  f <- al_fit(tr, "soc", COVS, num.trees = 200L)
  out <- edaphos_map(f, g[1:25, ])
  expect_identical(attr(out, "edaphos_map")$uncertainty,
                   "quantile regression forest")
  expect_true(all(out$q5 <= out$q95))
})

test_that("a model without uncertainty gets a mean layer only", {
  g <- grid_df()
  f <- stats::glm(I(soc > 20) ~ elev + ndvi, family = stats::binomial,
                  data = g[1:200, ])
  out <- edaphos_map(f, g[1:10, ])
  expect_false(any(c("sd", "q5") %in% names(out)))
  expect_true(all(out$mean > 0 & out$mean < 1))   # response scale
  expect_identical(attr(out, "edaphos_map")$uncertainty, "none")
})

test_that("bad inputs are refused", {
  g <- grid_df(); f <- lm_fit(g)
  expect_error(edaphos_map(f, as.matrix(g)), "data frame")
  expect_error(edaphos_map(f, g, probs = 1.2))
  expect_error(edaphos_map(structure(list(), class = "nonsense"), g),
               "nonsense")
})
