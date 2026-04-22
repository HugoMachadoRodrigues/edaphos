# Unit tests for the supervised-learning metric helpers introduced
# in v1.3.0. Every metric is checked on a tiny hand-computed fixture
# so the numbers are auditable from the test file alone.

test_that("edaphos_rmse matches the textbook sqrt of mean squared error", {
  y  <- c(1, 2, 3, 4)
  yh <- c(1, 3, 2, 4)   # errors: 0, -1, 1, 0
  # sqrt(mean(c(0, 1, 1, 0))) = sqrt(0.5) ~ 0.7071068
  expect_equal(edaphos_rmse(y, yh), sqrt(0.5), tolerance = 1e-10)
})

test_that("edaphos_mae matches the textbook mean absolute error", {
  y  <- c(1, 2, 3, 4)
  yh <- c(1, 3, 2, 4)
  expect_equal(edaphos_mae(y, yh), 0.5, tolerance = 1e-10)
})

test_that("edaphos_r2 is 1 for perfect prediction and 0 for mean predictor", {
  y  <- c(1, 2, 3, 4, 5)
  expect_equal(edaphos_r2(y, y), 1, tolerance = 1e-10)
  expect_equal(edaphos_r2(y, rep(mean(y), length(y))), 0, tolerance = 1e-10)
})

test_that("edaphos_r2 can go negative when the predictor is worse than the mean", {
  y  <- c(1, 2, 3)
  yh <- c(5, 5, 5)
  expect_lt(edaphos_r2(y, yh), 0)
})

test_that("edaphos_bias has the right sign", {
  y  <- c(10, 20, 30)
  # Systematic under-prediction by 5 units.
  yh <- y - 5
  expect_equal(edaphos_bias(y, yh), 5, tolerance = 1e-10)
})

test_that("edaphos_picp computes the empirical coverage", {
  y     <- c(1, 2, 3, 4, 5)
  lower <- c(0, 1, 5, 3, 4)  # third interval [5, 6] misses y=3
  upper <- c(2, 3, 6, 5, 6)
  # 4 of 5 observations inside the interval
  expect_equal(edaphos_picp(y, lower, upper), 0.8, tolerance = 1e-10)
})

test_that("edaphos_interval_score penalises misses proportionally to alpha", {
  # Two equal-width intervals; one covers, one misses by the same
  # amount. The miss should score strictly worse than the hit by
  # 2 * miss_magnitude / alpha.
  alpha <- 0.1
  y     <- c(1, 5)
  lower <- c(0, 0)
  upper <- c(2, 2)           # second interval misses y=5 by 3
  mean_score <- edaphos_interval_score(y, lower, upper, alpha = alpha)
  # per-point: width=2 for both; miss penalty = (2/alpha) * 3 = 60
  # total: (2 + 0) + (2 + 60) / 2 = mean(2, 62) = 32
  expect_equal(mean_score, 32, tolerance = 1e-10)
})

test_that("edaphos_ece is 0 for perfectly calibrated quantiles", {
  set.seed(1)
  y <- stats::rnorm(400L)
  # For a standard Normal sample, the theoretical 10/25/50/75/90
  # quantile predictions ARE the calibrated predictions.
  levels <- c(0.1, 0.25, 0.5, 0.75, 0.9)
  qmat <- matrix(stats::qnorm(levels), nrow = length(y), ncol = length(levels),
                  byrow = TRUE)
  ece <- edaphos_ece(y, qmat, levels)
  # 400 samples is small so ECE > 0 but tiny; sanity-check upper
  # bound at 0.1.
  expect_lt(ece, 0.1)
})

test_that("edaphos_ece is large for mis-calibrated quantiles", {
  set.seed(1)
  y <- stats::rnorm(200L)
  # Claim every quantile is exactly 0: empirical miscoverage peaks
  # at the tails.
  levels <- c(0.1, 0.25, 0.5, 0.75, 0.9)
  qmat <- matrix(0, nrow = length(y), ncol = length(levels))
  ece_bad <- edaphos_ece(y, qmat, levels)
  expect_gt(ece_bad, 0.2)
})

test_that("edaphos_metrics_summary returns a one-row data frame with all fields", {
  y  <- c(10, 20, 30, 40)
  yh <- c(12, 18, 33, 39)
  lo <- c( 8, 15, 28, 35)
  up <- c(16, 25, 36, 45)
  row <- edaphos_metrics_summary(y, yh, lo, up, interval = 0.95,
                                   method = "test")
  expect_s3_class(row, "data.frame")
  expect_equal(nrow(row), 1L)
  expect_setequal(names(row),
                   c("method", "n", "rmse", "mae", "r2", "bias",
                     "picp", "interval_score"))
  expect_equal(row$method, "test")
  expect_equal(row$n,      4L)
  expect_equal(row$picp,   1.0, tolerance = 1e-10) # all 4 covered
})

test_that("NA values are dropped pairwise", {
  y  <- c(1, 2, NA, 4)
  yh <- c(1, NA, 3, 4)
  # Only (1,1) and (4,4) are fully observed.
  expect_equal(edaphos_rmse(y, yh), 0, tolerance = 1e-10)
  expect_equal(edaphos_mae(y, yh),  0, tolerance = 1e-10)
})

test_that("edaphos_metrics_summary returns NA for interval fields when none given", {
  row <- edaphos_metrics_summary(c(1, 2, 3), c(1, 2, 3),
                                   method = "no-intervals")
  expect_true(is.na(row$picp))
  expect_true(is.na(row$interval_score))
  expect_equal(row$n, 3L)
})
