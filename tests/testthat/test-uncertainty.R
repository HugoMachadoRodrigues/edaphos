# v1.6.0 -- unit tests for the unified uncertainty API.

test_that("edaphos_posterior() builds from a scalar sample vector", {
  set.seed(1L)
  draws <- stats::rnorm(400, mean = 1.2, sd = 0.3)
  post <- edaphos_posterior(samples    = draws,
                              method     = "bootstrap",
                              query_type = "effect",
                              units      = "g/kg")
  expect_s3_class(post, "edaphos_posterior")
  # Mean / sd accurate to within MC error.
  expect_equal(as.numeric(post$mean), 1.2, tolerance = 0.05)
  expect_equal(as.numeric(post$sd),   0.3, tolerance = 0.05)
  # Quantiles have the three default levels.
  expect_setequal(names(post$quantiles), c("q05", "q50", "q95"))
  expect_lt(post$quantiles$q05, post$quantiles$q95)
})

test_that("edaphos_posterior() accepts a (n_samples, n_query) matrix", {
  set.seed(2L)
  mat <- matrix(stats::rnorm(200 * 3), nrow = 200, ncol = 3)
  post <- edaphos_posterior(samples    = mat,
                              method     = "ensemble",
                              query_type = "sample",
                              probs      = c(0.1, 0.9))
  expect_equal(length(post$mean), 3L)
  expect_equal(length(post$sd),   3L)
  expect_setequal(names(post$quantiles), c("q10", "q90"))
  # Sanity: empirical sd per column ~ 1
  expect_lt(max(abs(post$sd - 1)), 0.25)
})

test_that("edaphos_posterior() accepts a 3-D (n_samples, H, W) array for map queries", {
  set.seed(3L)
  arr <- array(stats::rnorm(50 * 4 * 4), dim = c(50, 4, 4))
  post <- edaphos_posterior(samples    = arr,
                              method     = "ensemble",
                              query_type = "map")
  expect_equal(dim(post$mean), c(4L, 4L))
  expect_equal(dim(post$sd),   c(4L, 4L))
  expect_equal(dim(post$quantiles$q05), c(4L, 4L))
})

test_that("Gaussian shortcut (mean + sd, no samples) synthesises draws", {
  post <- edaphos_posterior(mean       = c(0.1, 0.2, 0.3),
                              sd         = c(0.05, 0.05, 0.05),
                              method     = "gaussian",
                              query_type = "param",
                              n_samples_if_gaussian = 1000L)
  expect_equal(dim(post$samples)[1L], 1000L)
  expect_equal(as.numeric(post$mean), c(0.1, 0.2, 0.3))
})

test_that("as_edaphos_posterior() coerces a numeric vector", {
  draws <- stats::rnorm(100, mean = 0, sd = 1)
  post <- as_edaphos_posterior(draws,
                                 method     = "bootstrap",
                                 query_type = "effect")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(length(post$mean), 1L)
})

test_that("as_edaphos_posterior() is idempotent on already-wrapped objects", {
  x <- edaphos_posterior(samples = stats::rnorm(50),
                           method = "bootstrap",
                           query_type = "effect")
  y <- as_edaphos_posterior(x)
  expect_identical(x, y)
})

test_that("uncertainty_calibrate() computes coherent CRPS, PICP, MPIW", {
  set.seed(4L)
  # Ground truth follows a known data-generating process; posterior
  # is a deep-ensemble Gaussian centred on truth with sigma = 0.2.
  n_q <- 60L
  truth <- stats::rnorm(n_q, 0, 1)
  # Draw 500 posterior samples centred at truth + small bias, sd 0.2
  post <- edaphos_posterior(
    samples = t(sapply(truth, function(mu)
      stats::rnorm(500, mean = mu + 0.05, sd = 0.2))) |> t(),
    method = "ensemble", query_type = "sample")
  # Oops: that transposes wrong; construct directly.
  S <- matrix(0, nrow = 500, ncol = n_q)
  for (j in seq_len(n_q)) S[, j] <- stats::rnorm(500, mean = truth[j] + 0.05,
                                                    sd = 0.2)
  post <- edaphos_posterior(samples = S,
                             method = "ensemble",
                             query_type = "sample")
  calib <- uncertainty_calibrate(post, truth)
  expect_true(all(c("crps", "picp", "mpiw", "reliability_df",
                     "point_rmse") %in% names(calib)))
  # An *over*-spread Gaussian posterior (sd = 0.2, but truth residuals
  # are only a deterministic 0.05 bias) should cover the truth at
  # every cell -- i.e. PICP saturates at 1.0. This is the easy
  # direction; the follow-up test checks detection of the hard
  # direction (over-confident posteriors below).
  expect_gte(calib$picp["0.95"], 0.90)
  # CRPS of a proper Gaussian with sigma = 0.2 centred near truth
  # should be O(0.1).
  expect_lt(calib$crps, 0.25)
  expect_gt(calib$crps, 0.0)
  # PICP monotone in nominal level
  expect_true(all(diff(calib$picp) >= -0.02))
  # Point RMSE close to the 0.2 signal noise + 0.05 bias
  expect_lt(calib$point_rmse, 0.5)
})

test_that("uncertainty_calibrate() detects an over-confident posterior", {
  set.seed(5L)
  truth <- stats::rnorm(60)
  # Posterior sd ridiculously small -> PICP @ 95% should crash
  S <- matrix(0, nrow = 300, ncol = 60)
  for (j in seq_len(60)) S[, j] <- stats::rnorm(300, mean = 0, sd = 0.001)
  post <- edaphos_posterior(samples = S,
                             method = "ensemble",
                             query_type = "sample")
  calib <- uncertainty_calibrate(post, truth)
  expect_lt(calib$picp["0.95"], 0.2)   # very low coverage
  expect_gt(calib$crps, 0.5)           # bad CRPS
})

test_that("autoplot() works for effect / map / sample query types", {
  skip_if_not_installed("ggplot2")
  # Effect
  p1 <- ggplot2::autoplot(edaphos_posterior(
    samples = stats::rnorm(300), method = "bootstrap",
    query_type = "effect", units = "g/kg"))
  expect_s3_class(p1, "ggplot")
  # Map
  arr <- array(stats::rnorm(100 * 5 * 5), dim = c(100, 5, 5))
  p2 <- ggplot2::autoplot(edaphos_posterior(
    samples = arr, method = "ensemble", query_type = "map"))
  expect_s3_class(p2, "ggplot")
  # Sample ribbon
  p3 <- ggplot2::autoplot(edaphos_posterior(
    samples = matrix(stats::rnorm(300 * 10), nrow = 300),
    method = "ensemble", query_type = "sample"))
  expect_s3_class(p3, "ggplot")
})

test_that("uncertainty_plot_reliability() returns a ggplot", {
  skip_if_not_installed("ggplot2")
  set.seed(6L)
  truth <- stats::rnorm(30)
  S <- matrix(0, nrow = 200, ncol = 30)
  for (j in seq_len(30)) S[, j] <- stats::rnorm(200, mean = truth[j], sd = 0.2)
  post <- edaphos_posterior(samples = S, method = "ensemble",
                             query_type = "sample")
  calib <- uncertainty_calibrate(post, truth)
  expect_s3_class(uncertainty_plot_reliability(calib), "ggplot")
})

test_that("validation rejects mismatched mean / truth lengths", {
  post <- edaphos_posterior(samples = stats::rnorm(50),
                             method = "ensemble",
                             query_type = "effect")
  expect_error(uncertainty_calibrate(post, truth = c(0.1, 0.2)),
               regexp = "length.*posterior mean")
})
