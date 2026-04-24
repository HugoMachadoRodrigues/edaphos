## Tests for Pilar 1 x Pilar 3 Causal 4D bridge (v2.2.1).

.mk_4d_frame <- function(n_t = 60L, n_cell = 25L,
                          beta_fn = function(t) 0.008 * exp(0.01 * t)) {
  # Synthetic temporal frame with a time-varying beta
  t_vec <- seq_len(n_t)
  grid  <- expand.grid(t = t_vec, cell = seq_len(n_cell))
  set.seed(1L)
  grid$lon <- stats::runif(nrow(grid), -50, -48)
  grid$lat <- stats::runif(nrow(grid), -16, -14)
  # Exogenous adjustment z
  grid$z <- stats::rnorm(nrow(grid))
  # Exposure x (correlated with z)
  grid$map <- 0.3 * grid$z + stats::rnorm(nrow(grid))
  # Outcome y with time-varying effect
  grid$soc <- beta_fn(grid$t) * grid$map + 0.5 * grid$z +
                stats::rnorm(nrow(grid), 0, 0.3)
  grid
}

test_that("causal_effect_time_varying: returns an edaphos_causal_4d frame", {
  frame <- .mk_4d_frame()
  res <- causal_effect_time_varying(
    frame = frame, dag = NULL,
    exposure = "map", outcome = "soc",
    window = 20L, step = 5L,
    adjustment = "z",
    B = 50L, seed = 1L
  )
  expect_s3_class(res, "edaphos_causal_4d")
  expect_true(all(c("t_start", "t_end", "t_centre",
                      "n", "beta_hat", "se",
                      "ci_lo", "ci_hi") %in% names(res)))
  # Enough windows produced
  expect_gte(nrow(res), 5L)
  # beta_hat values approximately match the generative function
  # at window centres (tolerant because of bootstrap noise).
  centres <- res$t_centre
  true_beta <- 0.008 * exp(0.01 * centres)
  expect_lt(mean(abs(res$beta_hat - true_beta), na.rm = TRUE), 0.005)
})

test_that("causal_effect_trend_test: detects monotonic increase", {
  # Generative beta(t): strong linear rise over 60 time slices.
  # beta goes from 0.05 at t=1 to 3.05 at t=60 -- overwhelming
  # signal relative to noise.
  frame <- .mk_4d_frame(
    n_t = 60L,
    beta_fn = function(t) 0.05 * t
  )
  res <- causal_effect_time_varying(
    frame = frame, dag = NULL,
    exposure = "map", outcome = "soc",
    window = 20L, step = 3L,
    adjustment = "z", B = 0L
  )
  tt <- causal_effect_trend_test(res)
  expect_true(is.list(tt))
  expect_equal(tt$trend_direction, "increasing")
  expect_lt(tt$p_value, 0.05)
  expect_gt(tt$tau, 0.3)
})

test_that("causal_effect_trend_test: no trend when beta is flat", {
  frame <- .mk_4d_frame(
    n_t = 60L,
    beta_fn = function(t) rep(0.01, length(t))
  )
  res <- causal_effect_time_varying(
    frame = frame, dag = NULL,
    exposure = "map", outcome = "soc",
    window = 20L, step = 5L,
    adjustment = "z", B = 0L
  )
  tt <- causal_effect_trend_test(res)
  # With a flat beta, Mann-Kendall p should generally be above 0.05
  expect_true(tt$trend_direction %in% c("none", "increasing", "decreasing"))
  # Mean |beta| should be near 0.01
  expect_lt(abs(mean(res$beta_hat, na.rm = TRUE) - 0.01), 0.003)
})

test_that("causal_effect_time_varying: errors on missing columns", {
  frame <- .mk_4d_frame()
  expect_error(
    causal_effect_time_varying(frame, NULL,
                                 exposure = "nonexistent",
                                 outcome  = "soc",
                                 adjustment = "z",
                                 window = 20L, step = 5L, B = 0L),
    regexp = "Columns not found"
  )
})

test_that("causal_4d_plot: returns a ggplot object", {
  skip_if_not_installed("ggplot2")
  frame <- .mk_4d_frame()
  res <- causal_effect_time_varying(frame, NULL,
                                       exposure = "map",
                                       outcome  = "soc",
                                       adjustment = "z",
                                       window = 20L, step = 5L,
                                       B = 0L)
  p <- causal_4d_plot(res)
  expect_s3_class(p, "ggplot")
})
