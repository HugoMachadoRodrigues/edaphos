## Smoke tests for the v3.7.0 regional synthetic datasets.
## Contract:
##   1. `br_amazon` and `br_pantanal` load with the same column schema as
##      `br_cerrado`, so any pillar / vignette runs unchanged.
##   2. Each dataset has 2025 rows (45 x 45 grid) and 8 columns.
##   3. SOC distributions match the documented regional contrasts:
##      Cerrado < Pantanal < Amazon (median).
##   4. Numeric columns are finite; coords are in their declared boxes.

test_that("br_amazon: schema matches br_cerrado", {
  expect_setequal(names(br_amazon), names(br_cerrado))
  expect_equal(nrow(br_amazon), 2025L)
  expect_equal(ncol(br_amazon), 8L)
})

test_that("br_pantanal: schema matches br_cerrado", {
  expect_setequal(names(br_pantanal), names(br_cerrado))
  expect_equal(nrow(br_pantanal), 2025L)
  expect_equal(ncol(br_pantanal), 8L)
})

test_that("regional SOC ordering: Cerrado < Pantanal < Amazon (median)", {
  expect_lt(stats::median(br_cerrado$soc),  stats::median(br_pantanal$soc))
  expect_lt(stats::median(br_pantanal$soc), stats::median(br_amazon$soc))
})

test_that("br_amazon: every numeric column is finite and in plausible ranges", {
  for (cc in c("x", "y", "elev", "slope", "twi", "map_mm", "ndvi", "soc")) {
    expect_true(all(is.finite(br_amazon[[cc]])),
                  info = sprintf("non-finite in %s", cc))
  }
  expect_true(all(br_amazon$x >= -60.50 & br_amazon$x <= -60.10))
  expect_true(all(br_amazon$y >=  -3.30 & br_amazon$y <=  -2.90))
  expect_true(all(br_amazon$ndvi >= 0.75 & br_amazon$ndvi <= 0.95))
  expect_true(all(br_amazon$slope <= 8))
})

test_that("br_pantanal: every numeric column is finite and in plausible ranges", {
  for (cc in c("x", "y", "elev", "slope", "twi", "map_mm", "ndvi", "soc")) {
    expect_true(all(is.finite(br_pantanal[[cc]])),
                  info = sprintf("non-finite in %s", cc))
  }
  expect_true(all(br_pantanal$x >= -57.40 & br_pantanal$x <= -57.00))
  expect_true(all(br_pantanal$y >= -19.50 & br_pantanal$y <= -19.10))
  expect_true(all(br_pantanal$slope <= 3))
})

test_that("br_amazon end-to-end: al_fit() runs on a sub-sample", {
  set.seed(1L)
  pool <- br_amazon[sample.int(nrow(br_amazon), 60L), ]
  pool$lon <- pool$x; pool$lat <- pool$y
  fit <- al_fit(labeled    = pool,
                  target     = "soc",
                  covariates = c("elev", "slope", "twi",
                                  "map_mm", "ndvi"),
                  coords     = c("lon", "lat"),
                  num.trees  = 100L)
  expect_s3_class(fit, "edaphos_al_model")
})

test_that("br_pantanal end-to-end: al_fit() runs on a sub-sample", {
  set.seed(1L)
  pool <- br_pantanal[sample.int(nrow(br_pantanal), 60L), ]
  pool$lon <- pool$x; pool$lat <- pool$y
  fit <- al_fit(labeled    = pool,
                  target     = "soc",
                  covariates = c("elev", "slope", "twi",
                                  "map_mm", "ndvi"),
                  coords     = c("lon", "lat"),
                  num.trees  = 100L)
  expect_s3_class(fit, "edaphos_al_model")
})
