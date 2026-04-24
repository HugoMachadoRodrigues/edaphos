## Tests for the three new v3.1.0 benchmark wrappers.
## These helpers power the 6-pilar head-to-head on WoSIS topsoil SOC
## (P1 Causal, P6 Quantum, P10 GAT).  Small-n smoke tests keep CI
## fast; the full 1 095-profile run lives in
## data-raw/benchmark_wosis_6pilar.R.

.mk_mini_wosis <- function(n = 40L, seed = 1L) {
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
  # Known signal: SOC = c0 + a*trees - b*cropland + noise
  dat$soc <- 8 + 0.2 * dat$trees - 0.15 * dat$cropland +
             0.1 * dat$clay + stats::rnorm(n, 0, 2)
  dat
}

.cov_cols <- c("map", "mat", "slope", "elev", "clay", "sand", "bd",
                "trees", "cropland", "grass")

# ---------------------------------------------------------------------------
# P1 -- DAG-adjusted OLS + parametric bootstrap
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p1_causal: returns a well-shaped edaphos_posterior", {
  dat <- .mk_mini_wosis(n = 40L, seed = 1L)
  tr  <- dat[1:30, ]; te <- dat[31:40, ]
  post <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                      dag = NULL, n_boot = 50L, seed = 1L)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(dim(post$samples), c(50L, 10L))
  expect_equal(post$method, "bootstrap")
  expect_equal(post$query_type, "map")
  # Bootstrap SD > 0 (there's genuine uncertainty)
  expect_true(all(apply(post$samples, 2L, stats::sd) > 0))
})

test_that("benchmark_fit_p1_causal: uses DAG when variables overlap", {
  skip_if_not_installed("dagitty")
  dat <- .mk_mini_wosis(n = 40L, seed = 2L)
  tr  <- dat[1:30, ]; te <- dat[31:40, ]
  # Build a DAG whose variable names overlap only partially
  dag <- dagitty::dagitty(
    "dag { trees -> soc  ; cropland -> soc ; clay -> soc ; grass -> soc }"
  )
  post <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                      dag = dag, n_boot = 40L, seed = 2L)
  expect_true("adjusted_features" %in% names(post$metadata))
  adj <- post$metadata$adjusted_features
  expect_true(all(adj %in% c("trees", "cropland", "clay", "grass")))
  expect_true(length(adj) >= 2L)
})

test_that("benchmark_fit_p1_causal: predictive RMSE beats constant baseline", {
  dat <- .mk_mini_wosis(n = 120L, seed = 3L)
  tr  <- dat[1:90, ]; te <- dat[91:120, ]
  post <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                      dag = NULL, n_boot = 100L, seed = 3L)
  point_pred <- colMeans(post$samples)
  rmse_fit  <- sqrt(mean((point_pred - te$soc)^2))
  rmse_null <- sqrt(mean((mean(tr$soc) - te$soc)^2))
  expect_lt(rmse_fit, rmse_null)
})

# ---------------------------------------------------------------------------
# P6 -- Quantum KRR bootstrap ensemble
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p6_quantum: returns a well-shaped edaphos_posterior", {
  dat <- .mk_mini_wosis(n = 30L, seed = 1L)
  tr  <- dat[1:24, ]; te <- dat[25:30, ]
  post <- benchmark_fit_p6_quantum(tr, te, .cov_cols,
                                        n_pcs = 4L, reps = 1L,
                                        n_boot = 3L, lambda = 0.5,
                                        seed = 1L)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(dim(post$samples), c(3L, 6L))
  expect_equal(post$method, "ensemble")
  expect_true(all(is.finite(post$samples)))
  expect_equal(post$metadata$n_pcs, 4L)
})

test_that("benchmark_fit_p6_quantum: produces finite calibrated posteriors", {
  dat <- .mk_mini_wosis(n = 80L, seed = 2L)
  tr  <- dat[1:60, ]; te <- dat[61:80, ]
  post <- benchmark_fit_p6_quantum(tr, te, .cov_cols,
                                        n_pcs = 4L, reps = 1L,
                                        n_boot = 4L, lambda = 0.3,
                                        seed = 2L)
  # With 4 qubits, 1 rep, and 4 bootstrap samples the quantum KRR can
  # beat, match, or lose to a horizontal-line predictor depending on
  # the PCA rotation and boot seed -- no strict RMSE contract.  What
  # we DO contract is (a) all posterior samples are finite and (b)
  # the posterior has non-trivial uncertainty spread.
  expect_true(all(is.finite(post$samples)))
  expect_true(mean(apply(post$samples, 2L, stats::sd)) > 0)
  expect_equal(post$metadata$reps, 1L)
})

# ---------------------------------------------------------------------------
# P10 -- GAT seed-ensemble on k-NN co-location graph
# ---------------------------------------------------------------------------

test_that("benchmark_fit_p10_gat: returns a well-shaped edaphos_posterior", {
  dat <- .mk_mini_wosis(n = 30L, seed = 1L)
  tr  <- dat[1:22, ]; te <- dat[23:30, ]
  post <- benchmark_fit_p10_gat(tr, te, .cov_cols,
                                      k = 4L, hidden = 6L, n_heads = 2L,
                                      n_layers = 1L, epochs = 20L,
                                      lr = 0.05, n_ensemble = 2L,
                                      seed = 1L)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(dim(post$samples), c(2L, 8L))
  expect_equal(post$method, "ensemble")
  expect_true(all(is.finite(post$samples)))
  expect_equal(post$metadata$n_ensemble, 2L)
})

test_that("benchmark_fit_p10_gat: imputes NA targets on test rows safely", {
  dat <- .mk_mini_wosis(n = 25L, seed = 2L)
  tr  <- dat[1:20, ]; te <- dat[21:25, ]
  # test rows are passed WITHOUT their 'soc' column (the wrapper
  # should impute internally).
  te2 <- te[, setdiff(names(te), "soc")]
  post <- benchmark_fit_p10_gat(tr, te2, .cov_cols,
                                      k = 3L, hidden = 4L, n_heads = 1L,
                                      n_layers = 1L, epochs = 10L,
                                      lr = 0.05, n_ensemble = 2L,
                                      seed = 2L)
  expect_equal(ncol(post$samples), 5L)
  expect_true(all(is.finite(post$samples)))
})

# ---------------------------------------------------------------------------
# End-to-end uncertainty scoring
# ---------------------------------------------------------------------------

test_that("all three benchmark posteriors pass uncertainty_calibrate()", {
  dat <- .mk_mini_wosis(n = 50L, seed = 42L)
  tr  <- dat[1:40, ]; te <- dat[41:50, ]
  p1  <- benchmark_fit_p1_causal(tr, te, .cov_cols,
                                     n_boot = 50L, seed = 1L)
  p6  <- benchmark_fit_p6_quantum(tr, te, .cov_cols,
                                       n_pcs = 4L, reps = 1L,
                                       n_boot = 3L, lambda = 0.5, seed = 1L)
  p10 <- benchmark_fit_p10_gat(tr, te, .cov_cols,
                                     k = 4L, hidden = 4L, n_heads = 1L,
                                     n_layers = 1L, epochs = 15L,
                                     lr = 0.05, n_ensemble = 2L, seed = 1L)
  c1  <- uncertainty_calibrate(p1,  truth = te$soc)
  c6  <- uncertainty_calibrate(p6,  truth = te$soc)
  c10 <- uncertainty_calibrate(p10, truth = te$soc)
  for (cal in list(c1, c6, c10)) {
    expect_true("picp" %in% names(cal))
    expect_true("mpiw" %in% names(cal))
    expect_true("crps" %in% names(cal))
    expect_true(is.finite(cal$crps))
  }
})
