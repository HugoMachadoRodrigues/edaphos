## Tests for the Cinelli & Hazlett (2020) sensitivity module (v1.9.2).

test_that("causal_sensitivity_summary: recovers Cinelli-Hazlett Theorem 4.4 example", {
  # Published worked example: beta = 1, SE = 0.5, df = 100 => |t| = 2
  #   f^2 = 4 / 100 = 0.04
  #   RV = (1/2)(sqrt(0.0016 + 0.16) - 0.04) ≈ 0.1810
  s <- causal_sensitivity_summary(effect = 1, se = 0.5, df = 100)
  expect_equal(round(s$rv, 4), 0.1810)
  expect_equal(s$t_stat, 2)
  expect_true(is.character(s$interpretation))
})

test_that("causal_sensitivity_summary: RV is monotonic in |t| at fixed df", {
  # RV = 1/2 ( sqrt(f^4 + 4 f^2) - f^2 ) with f^2 = |t|^2 / df.
  # Monotonic in |t|: larger |t| -> larger RV.
  s_small <- causal_sensitivity_summary(effect = 0.1, se = 1, df = 100)
  s_med   <- causal_sensitivity_summary(effect = 2,   se = 1, df = 100)
  s_big   <- causal_sensitivity_summary(effect = 10,  se = 1, df = 100)
  expect_lt(s_small$rv, s_med$rv)
  expect_lt(s_med$rv,   s_big$rv)
  # At t=10, df=100, f^2=1, RV = 1/2(sqrt(5)-1) ≈ 0.618
  expect_equal(round(s_big$rv, 3), 0.618, tolerance = 1e-3)
})

test_that("causal_sensitivity_summary: zero effect yields RV = 0", {
  s <- causal_sensitivity_summary(effect = 0, se = 1, df = 100)
  expect_equal(s$rv, 0)
})

test_that("causal_sensitivity_grid: returns a well-formed long frame", {
  g <- causal_sensitivity_grid(effect = 1, se = 0.5, df = 100,
                                  grid_size = 11L, r2_max = 0.3)
  expect_s3_class(g, "data.frame")
  expect_equal(nrow(g), 11L * 11L)
  expect_true(all(c("r2_xu_z", "r2_yu_xz",
                      "adjusted_estimate", "bias", "bias_factor")
                    %in% names(g)))
  # At (0,0): zero bias, adjusted = original estimate
  zero_row <- g[g$r2_xu_z == 0 & g$r2_yu_xz == 0, ]
  expect_equal(zero_row$bias, 0)
  expect_equal(zero_row$adjusted_estimate, 1)
  # Monotonic: higher r2 => larger bias
  r2_mid <- g[g$r2_xu_z == 0.15 & g$r2_yu_xz == 0.15, ]
  expect_gt(r2_mid$bias, 0)
})

test_that("causal_sensitivity_from_lm: extracts effect + SE correctly", {
  set.seed(1L)
  n  <- 200L
  x  <- stats::rnorm(n); w <- stats::rnorm(n)
  y  <- 2 * x + 0.5 * w + stats::rnorm(n, 0, 1)
  fm <- stats::lm(y ~ x + w)
  s  <- causal_sensitivity_from_lm(fm, exposure = "x")
  expect_true(is.list(s))
  expect_gt(s$rv, 0.5)  # strong truth -> robust to OMB
  # Error when exposure does not exist
  expect_error(causal_sensitivity_from_lm(fm, exposure = "nope"),
                 regexp = "not among")
})

test_that("causal_sensitivity_from_iv: works on a known IV fit", {
  set.seed(1L)
  n <- 400L
  Z1 <- stats::rnorm(n); Z2 <- stats::rnorm(n); U <- stats::rnorm(n)
  X <- 0.7*Z1 + 0.4*Z2 + 0.6*U + stats::rnorm(n, 0, 0.3)
  Y <- 1.5*X + 0.8*U + stats::rnorm(n, 0, 0.3)
  fit <- causal_iv_fit_2sls(
    data.frame(Y = Y, X = X, Z1 = Z1, Z2 = Z2),
    "X", "Y", c("Z1", "Z2")
  )
  s <- causal_sensitivity_from_iv(fit)
  expect_true(is.list(s))
  expect_true(!is.null(s$rv))
  expect_equal(s$fit_estimator, "2SLS")
})
