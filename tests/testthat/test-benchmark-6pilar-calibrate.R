## v3.4.0 calibration tests for the v3.1.0 P1/P6/P10 benchmark
## wrappers.  The contract is:
##
##   1. With `calibrate = TRUE` (default), an aleatoric residual-noise
##      term is injected on every (sample, test-row) entry of the
##      posterior, raising per-row SD by sqrt(eps_sd^2 + sigma_resid^2)
##      and lifting PICP_90 toward nominal coverage.
##   2. With `calibrate = FALSE`, behaviour is identical to v3.1.0
##      (epistemic-only spread).
##   3. The estimated `sigma_resid` is exposed in the posterior
##      metadata for downstream introspection.

.mk_mini_wosis <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  dat <- data.frame(
    lon    = stats::runif(n, -50, -48),
    lat    = stats::runif(n, -16, -14),
    map    = stats::runif(n, 800, 1500),
    mat    = stats::runif(n, 20, 28),
    slope  = stats::runif(n, 0, 10),
    elev   = stats::runif(n, 400, 900),
    clay   = stats::runif(n, 10, 50),
    sand   = stats::runif(n, 20, 70),
    bd     = stats::runif(n, 0.8, 1.5),
    trees  = stats::runif(n, 0, 60),
    cropland = stats::runif(n, 0, 50),
    grass  = stats::runif(n, 0, 60)
  )
  dat$soc <- 8 + 0.2 * dat$trees - 0.15 * dat$cropland +
             0.1 * dat$clay + stats::rnorm(n, 0, 2)
  dat
}

.cov_cols <- c("map", "mat", "slope", "elev", "clay", "sand", "bd",
                "trees", "cropland", "grass")

# ---------------------------------------------------------------------------
# P1
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p1_causal: calibrated posterior covers more variance", {
  dat <- .mk_mini_wosis(n = 90L, seed = 1L)
  tr  <- dat[1:60, ]; te <- dat[61:90, ]
  cal <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                     n_boot = 80L, seed = 1L,
                                     calibrate = TRUE)
  raw <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                     n_boot = 80L, seed = 1L,
                                     calibrate = FALSE)
  sd_cal <- mean(apply(cal$samples, 2L, stats::sd))
  sd_raw <- mean(apply(raw$samples, 2L, stats::sd))
  expect_gt(sd_cal, sd_raw)
  expect_true(cal$metadata$calibrate)
  expect_false(raw$metadata$calibrate)
  expect_gt(cal$metadata$sigma_resid, 0)
  expect_equal(raw$metadata$sigma_resid, 0)
})

test_that("benchmark_fit_p1_causal: PICP_90 of calibrated posterior is closer to 0.9", {
  dat <- .mk_mini_wosis(n = 120L, seed = 2L)
  tr  <- dat[1:80, ]; te <- dat[81:120, ]
  cal <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                     n_boot = 100L, seed = 2L)
  raw <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                     n_boot = 100L, seed = 2L,
                                     calibrate = FALSE)
  picp_cal <- uncertainty_calibrate(cal, truth = te$soc)$picp[["0.90"]]
  picp_raw <- uncertainty_calibrate(raw, truth = te$soc)$picp[["0.90"]]
  expect_gt(picp_cal, picp_raw)
  # Calibrated PICP should be in the right ballpark of nominal 0.9
  expect_gt(picp_cal, 0.7)
})

# ---------------------------------------------------------------------------
# P6
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p6_quantum: calibrated SD strictly larger than raw", {
  dat <- .mk_mini_wosis(n = 60L, seed = 3L)
  tr  <- dat[1:45, ]; te <- dat[46:60, ]
  cal <- benchmark_fit_p6_quantum(tr, te, .cov_cols,
                                       n_pcs = 4L, reps = 1L,
                                       n_boot = 5L, seed = 3L,
                                       calibrate = TRUE)
  raw <- benchmark_fit_p6_quantum(tr, te, .cov_cols,
                                       n_pcs = 4L, reps = 1L,
                                       n_boot = 5L, seed = 3L,
                                       calibrate = FALSE)
  sd_cal <- mean(apply(cal$samples, 2L, stats::sd))
  sd_raw <- mean(apply(raw$samples, 2L, stats::sd))
  expect_gt(sd_cal, sd_raw)
  expect_gt(cal$metadata$sigma_resid, 0)
})

# ---------------------------------------------------------------------------
# P10
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p10_gat: calibration targets a total, and never narrows", {
  # The contract changed when the residual scale stopped double-counting the
  # ensemble. The interval is (member spread) + (injected noise), and the
  # injected part is only what the spread does not already carry. So
  # `calibrate = TRUE` widens toward an estimated TOTAL rather than widening
  # unconditionally -- and on a fixture where the members already disagree by
  # more than that total, the honest amount to inject is zero.
  #
  # This fixture is exactly that case: 30 training rows, three members, 20
  # epochs. Measured here, the members disagree by SD 2.28 while the estimated
  # total predictive SD is 1.06. Asserting that calibration widens it would be
  # asserting that the interval should be inflated past what the data support.
  dat <- .mk_mini_wosis(n = 40L, seed = 4L)
  tr  <- dat[1:30, ]; te <- dat[31:40, ]
  args <- list(tr, te, .cov_cols, k = 4L, hidden = 6L, n_heads = 1L,
               n_layers = 1L, epochs = 20L, lr = 0.05, n_ensemble = 3L,
               seed = 4L)
  cal <- suppressWarnings(
    do.call(benchmark_fit_p10_gat, c(args, calibrate = TRUE)))
  raw <- do.call(benchmark_fit_p10_gat, c(args, calibrate = FALSE))

  sd_cal <- mean(apply(cal$samples, 2L, stats::sd))
  sd_raw <- mean(apply(raw$samples, 2L, stats::sd))

  # never NARROWER, whatever the regime
  expect_gte(sd_cal, sd_raw * 0.999)
  # a non-negative injection, and one that respects the variance budget
  expect_gte(cal$metadata$sigma_resid, 0)
  v_ens <- mean(apply(raw$samples, 2L, stats::var))
  expect_equal(cal$metadata$sigma_resid,
               sqrt(max(0, cal$metadata$sigma_total^2 - v_ens)),
               tolerance = 1e-6)

  # 30 rows cannot carry an inner blocked CV, and the fallback must SAY so
  # rather than quietly reverting to training residuals
  expect_match(cal$metadata$sigma_source, "training residuals")
  expect_warning(
    do.call(benchmark_fit_p10_gat, c(args, calibrate = TRUE)),
    "inner blocked CV could not run")
})

test_that("benchmark_fit_p10_gat: the injection widens when the ensemble is narrow", {
  # The complementary regime, so the widening path is covered too: more
  # members and more epochs bring them into agreement, and the injected term
  # then carries most of the interval.
  skip_on_cran()
  dat <- .mk_mini_wosis(n = 90L, seed = 7L)
  tr  <- dat[1:70, ]; te <- dat[71:90, ]
  args <- list(tr, te, .cov_cols, k = 5L, hidden = 8L, n_heads = 2L,
               n_layers = 2L, epochs = 120L, lr = 0.03, n_ensemble = 6L,
               seed = 7L)
  cal <- suppressWarnings(
    do.call(benchmark_fit_p10_gat, c(args, calibrate = TRUE)))
  raw <- do.call(benchmark_fit_p10_gat, c(args, calibrate = FALSE))
  v_ens <- mean(apply(raw$samples, 2L, stats::var))

  skip_if(v_ens >= cal$metadata$sigma_total^2,
          "members still disagree by more than the estimated total")
  expect_gt(cal$metadata$sigma_resid, 0)
  expect_gt(mean(apply(cal$samples, 2L, stats::sd)),
            mean(apply(raw$samples, 2L, stats::sd)))
})

# ---------------------------------------------------------------------------
# Helper unit tests
# ---------------------------------------------------------------------------

test_that(".bench_inject_aleatoric: identity when sigma_resid = 0", {
  M <- matrix(stats::rnorm(20), 4L, 5L)
  out <- edaphos:::.bench_inject_aleatoric(M, 0)
  expect_identical(out, M)
})

test_that(".bench_inject_aleatoric: adds zero-mean noise of expected SD", {
  set.seed(7L)
  M <- matrix(0, 50L, 50L)
  out <- edaphos:::.bench_inject_aleatoric(M, sigma_resid = 0.5,
                                                seed = 7L)
  expect_equal(mean(out),  0,    tolerance = 0.05)
  expect_equal(stats::sd(as.numeric(out)), 0.5, tolerance = 0.05)
})

test_that(".bench_residual_sd: returns the residual standard error, not sd()", {
  # This helper sizes the aleatoric term of a PREDICTIVE interval, so it must
  # measure the typical magnitude of the prediction error -- bias included.
  # stats::sd() measures scatter about the residual MEAN, so it ignores bias
  # entirely: for a predictor off by 0.42 with scatter 0.16, sd() returns 0.16
  # while the error an interval actually has to cover is 0.45.  Every pillar in
  # this benchmark is biased towards the mean, so the old sd()-based estimate
  # systematically under-inflated the intervals and depressed PICP.
  obs <- c(1, 2, 3, 4, 5)
  hat <- c(1.1, 2.2, 2.9, 3.8, 5.2)
  r   <- obs - hat
  expect_equal(edaphos:::.bench_residual_sd(obs, hat),
                sqrt(sum(r^2) / (length(r) - 1L)), tolerance = 1e-12)

  # With a biased predictor it must exceed sd() and track the RMSE.
  set.seed(1L)
  obs_b <- stats::rnorm(60L, 20, 5)
  hat_b <- obs_b + stats::rnorm(60L, 0.4, 0.18)     # deliberate offset
  got   <- edaphos:::.bench_residual_sd(obs_b, hat_b)
  expect_gt(got, stats::sd(obs_b - hat_b))
  expect_equal(got, sqrt(mean((obs_b - hat_b)^2)), tolerance = 0.02)

  # n_params applies the degrees-of-freedom correction and must not shrink it.
  expect_gt(edaphos:::.bench_residual_sd(obs_b, hat_b, n_params = 10L), got)

  # NA-safe
  expect_equal(edaphos:::.bench_residual_sd(c(NA, 1, 2), c(NA, 1, 2)), 0)
  # Too few finite residuals -> 0
  expect_equal(edaphos:::.bench_residual_sd(c(NA, NA), c(NA, NA)), 0)
})

test_that(".bench_inject_aleatoric preserves the point prediction exactly", {
  # The benchmark reads the point prediction as colMeans(samples).  Adding iid
  # noise leaves a residue of sigma/sqrt(n_draws) in that mean, which inflated
  # every published RMSE by ~0.44 g/kg at n_boot = 300.  Centring the noise per
  # column removes it exactly while preserving the marginal spread.
  set.seed(3L)
  pm  <- matrix(rep(stats::rnorm(80L, 25, 10), each = 300L), 300L, 80L)
  out <- edaphos:::.bench_inject_aleatoric(pm, sigma_resid = 8, seed = 5L)
  expect_equal(colMeans(out), colMeans(pm), tolerance = 1e-9)
  expect_equal(stats::sd(as.numeric(out - pm)), 8, tolerance = 0.2)
  # degenerate inputs are passed through untouched
  expect_identical(edaphos:::.bench_inject_aleatoric(pm, 0), pm)
  expect_identical(edaphos:::.bench_inject_aleatoric(pm[1, , drop = FALSE], 8),
                    pm[1, , drop = FALSE])
})
