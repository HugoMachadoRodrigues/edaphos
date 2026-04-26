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

test_that("benchmark_fit_p10_gat: calibrated SD strictly larger than raw", {
  dat <- .mk_mini_wosis(n = 40L, seed = 4L)
  tr  <- dat[1:30, ]; te <- dat[31:40, ]
  cal <- benchmark_fit_p10_gat(tr, te, .cov_cols,
                                     k = 4L, hidden = 6L, n_heads = 1L,
                                     n_layers = 1L, epochs = 20L,
                                     lr = 0.05, n_ensemble = 3L,
                                     seed = 4L, calibrate = TRUE)
  raw <- benchmark_fit_p10_gat(tr, te, .cov_cols,
                                     k = 4L, hidden = 6L, n_heads = 1L,
                                     n_layers = 1L, epochs = 20L,
                                     lr = 0.05, n_ensemble = 3L,
                                     seed = 4L, calibrate = FALSE)
  sd_cal <- mean(apply(cal$samples, 2L, stats::sd))
  sd_raw <- mean(apply(raw$samples, 2L, stats::sd))
  expect_gt(sd_cal, sd_raw)
  expect_gt(cal$metadata$sigma_resid, 0)
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

test_that(".bench_residual_sd: returns SD of finite residuals", {
  obs <- c(1, 2, 3, 4, 5)
  hat <- c(1.1, 2.2, 2.9, 3.8, 5.2)
  expect_equal(edaphos:::.bench_residual_sd(obs, hat),
                stats::sd(obs - hat), tolerance = 1e-12)
  # NA-safe
  expect_equal(edaphos:::.bench_residual_sd(c(NA, 1, 2), c(NA, 1, 2)),
                0)
  # Too few finite residuals -> 0
  expect_equal(edaphos:::.bench_residual_sd(c(NA, NA), c(NA, NA)), 0)
})
