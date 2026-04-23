# Pillar 3 v1.5.0 -- unit tests for temporal_kalman_update().

test_that("temporal_kalman_update pulls the posterior mean toward the observation", {
  set.seed(1L)
  # Ensemble of 50 flat-prior members (mean 0) over a 10x10 grid.
  fc <- array(stats::rnorm(50 * 10 * 10, mean = 0, sd = 1),
               dim = c(50, 10, 10))
  # Single observation at (5, 5) with value 3 and tight error sd = 0.1.
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = 3,
    obs_row   = 5L,
    obs_col   = 5L,
    obs_sd    = 0.1,
    seed      = 1L
  )
  expect_equal(dim(out$analysis_ensemble), c(50L, 10L, 10L))
  # Posterior mean at the observed cell should be near the observation
  # (tight R means the innovation dominates).
  expect_gt(out$analysis_mean[5L, 5L], 2.5)
  # Posterior SD at the observed cell should be smaller than the
  # prior SD (information gain).
  prior_sd_at_obs  <- stats::sd(fc[, 5L, 5L])
  expect_lt(out$analysis_sd[5L, 5L], prior_sd_at_obs)
  # Far-away cells should be substantially less updated than the
  # observed cell. With N_ens = 50 and no spatial localization the
  # vanilla stochastic EnKF has well-known spurious long-range
  # correlations (Houtekamer & Mitchell 2001), so we only require
  # the far-cell update to be a small fraction of the observation
  # value (3.0) -- not zero.
  expect_lt(abs(out$analysis_mean[1L, 1L]), 1.5)
})

test_that("slack observation error leaves the forecast near-unchanged", {
  set.seed(1L)
  fc <- array(stats::rnorm(50 * 10 * 10, mean = 0, sd = 1),
               dim = c(50, 10, 10))
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = 3,
    obs_row   = 5L, obs_col = 5L,
    obs_sd    = 100,   # deliberately huge R -> almost no update
    seed      = 1L
  )
  prior_mean <- mean(fc[, 5L, 5L])
  expect_lt(abs(out$analysis_mean[5L, 5L] - prior_mean), 0.5)
})

test_that("multiple observations produce a multi-cell posterior with correct shape", {
  set.seed(1L)
  fc <- array(stats::rnorm(30 * 20 * 20), dim = c(30, 20, 20))
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = c(0.5, -0.5, 1.0),
    obs_row   = c(5L, 10L, 15L),
    obs_col   = c(5L, 10L, 15L),
    obs_sd    = 0.1,
    seed      = 1L
  )
  expect_equal(out$n_obs, 3L)
  expect_equal(out$n_ens, 30L)
  expect_equal(dim(out$analysis_mean), c(20L, 20L))
  expect_length(out$gain_row_norm, 3L)
  expect_length(out$innovation, 3L)
})

test_that("4-D input with time_step updates only the chosen slice", {
  set.seed(1L)
  fc <- array(stats::rnorm(10 * 8 * 8 * 4), dim = c(10, 8, 8, 4))
  pre_t1 <- fc[, , , 1L]   # copy of slice 1 before update
  pre_t3 <- fc[, , , 3L]
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = 5,
    obs_row   = 4L, obs_col = 4L,
    obs_sd    = 0.05,
    time_step = 3L,
    seed      = 1L
  )
  # Slice 1 should be untouched.
  expect_equal(out$analysis_ensemble[, , , 1L], pre_t1)
  # Slice 3 should have been updated (analysis != forecast at obs cell).
  expect_false(isTRUE(all.equal(out$analysis_ensemble[, , , 3L],
                                  pre_t3)))
})

test_that("temporal_kalman_update validates its inputs", {
  fc <- array(0, dim = c(5, 10, 10))
  # Missing obs_col
  expect_error(
    temporal_kalman_update(fc, obs_value = 1, obs_row = 1L,
                             obs_col = integer(0), obs_sd = 0.1),
    regexp = "obs_col.*obs_value"
  )
  # Bad dims
  expect_error(
    temporal_kalman_update(matrix(0, 5, 5),
                             obs_value = 1, obs_row = 1L,
                             obs_col = 1L, obs_sd = 0.1),
    regexp = "dim.*4L|length.*3L"
  )
})

test_that("Gaspari-Cohn localization zeros the update beyond 2R cells", {
  set.seed(1L)
  fc <- array(stats::rnorm(50 * 10 * 10, mean = 0, sd = 1),
               dim = c(50, 10, 10))
  out <- temporal_kalman_update(
    forecast_ensemble   = fc,
    obs_value           = 5,
    obs_row             = 5L, obs_col = 5L,
    obs_sd              = 0.1,
    localization_radius = 2,
    seed                = 1L
  )
  # Within one cell of (5, 5) -- definitely inside the taper support.
  expect_gt(out$analysis_mean[5L, 5L], 2.5)
  # At distance > 2R = 4 cells (corner of grid) the taper is exactly
  # zero, so the analysis should match the ensemble mean at that cell
  # to within numerical noise from the perturbed-observation draw.
  expect_lt(abs(out$analysis_mean[1L, 1L] - mean(fc[, 1L, 1L])), 1e-10)
  expect_lt(abs(out$analysis_mean[10L, 10L] - mean(fc[, 10L, 10L])), 1e-10)
})

test_that("single-member ensemble works but collapses to a deterministic nudge", {
  set.seed(1L)
  fc <- array(0, dim = c(1, 5, 5))
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = 2,
    obs_row   = 3L, obs_col = 3L,
    obs_sd    = 0.1,
    seed      = 1L
  )
  # With N_ens = 1 the sample covariance is degenerate so the gain
  # must be zero and the analysis equals the forecast (modulo
  # numerical noise from the perturbed-observation draw at the
  # observed cell only).
  expect_true(all(abs(out$analysis_mean) < 1e-6))
  expect_equal(dim(out$analysis_ensemble), dim(fc))
})
