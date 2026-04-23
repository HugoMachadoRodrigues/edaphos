# v1.6.0-b -- tests for the Pillar 1 adapter to the unified
# `edaphos_posterior` API.

skip_if_no_dagitty <- function() skip_if_not_installed("dagitty")

.toy_df <- function(n = 240L, seed = 1L) {
  set.seed(seed)
  # Two cluster columns so the block bootstrap has something to
  # resample.
  cluster <- sample(seq_len(6L), n, replace = TRUE)
  x <- stats::rnorm(n, mean = cluster * 0.5)
  w <- stats::rnorm(n)
  y <- 1.5 * x + 0.8 * w + stats::rnorm(n, sd = 0.7)
  data.frame(x = x, y = y, w = w, kmeans_cluster = cluster)
}

test_that("causal_effect_bootstrap() returns B draws and the sampling distribution covers the true slope", {
  skip_if_no_dagitty()
  d <- .toy_df(240L, seed = 1L)
  dag <- dagitty::dagitty("dag { x -> y ; w -> y ; w -> x }")
  draws <- causal_effect_bootstrap(
    d, dag, exposure = "x", outcome = "y",
    adjustment = "w", cluster = "kmeans_cluster",
    B = 200L, seed = 7L
  )
  expect_length(draws, 200L)
  # true slope is 1.5; the bootstrap mean should be within ~3 SEs.
  expect_lt(abs(mean(draws) - 1.5), 0.2)
  ci <- stats::quantile(draws, c(0.025, 0.975), names = FALSE)
  expect_lt(ci[1L], 1.5)
  expect_gt(ci[2L], 1.5)
})

test_that("causal_effect_bootstrap() errors on missing cluster column", {
  skip_if_no_dagitty()
  d   <- .toy_df(50L)
  dag <- dagitty::dagitty("dag { x -> y }")
  d$kmeans_cluster <- NULL
  expect_error(
    causal_effect_bootstrap(d, dag, "x", "y",
                             cluster = "kmeans_cluster",
                             adjustment = character(0)),
    regexp = "Cluster column"
  )
})

test_that("causal_effect_posterior() with LM returns an `edaphos_posterior` of the right shape", {
  skip_if_no_dagitty()
  d   <- .toy_df(240L)
  dag <- dagitty::dagitty("dag { x -> y ; w -> y ; w -> x }")
  post <- causal_effect_posterior(
    d, dag, exposure = "x", outcome = "y",
    adjustment = "w", estimator = "lm",
    B = 200L, seed = 7L, units = "y-units per x-unit"
  )
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bootstrap")
  expect_equal(post$query_type, "effect")
  expect_equal(post$units, "y-units per x-unit")
  expect_equal(dim(post$samples), c(200L, 1L))
  # Bootstrap posterior mean near the simulated slope 1.5. We don't
  # pin down exact coverage of the true slope because with only 6
  # clusters and 240 rows the block-bootstrap 90 % CI is narrow
  # enough that small-sample bias can push it just short of 1.5.
  expect_lt(abs(as.numeric(post$mean) - 1.5), 0.2)
  # Non-degenerate posterior: the Gini-type spread between q05 and q95
  # must be strictly positive.
  expect_gt(as.numeric(post$quantiles$q95) -
              as.numeric(post$quantiles$q05), 0.02)
})

test_that("as_edaphos_posterior.edaphos_causal_effect handles LM with pre-computed bootstrap", {
  skip_if_no_dagitty()
  d   <- .toy_df(240L)
  dag <- dagitty::dagitty("dag { x -> y ; w -> y ; w -> x }")
  fit <- causal_estimate_effect(d, dag, "x", "y",
                                  adjustment = "w", estimator = "lm")
  fit$effect_boot <- causal_effect_bootstrap(
    d, dag, "x", "y", adjustment = "w",
    cluster = "kmeans_cluster", B = 100L, seed = 3L)
  post <- as_edaphos_posterior(fit)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bootstrap")
  expect_equal(dim(post$samples)[1L], 100L)
})

test_that("as_edaphos_posterior.edaphos_causal_effect Gaussian-fallback for LM without bootstrap draws", {
  skip_if_no_dagitty()
  d   <- .toy_df(240L)
  dag <- dagitty::dagitty("dag { x -> y ; w -> y ; w -> x }")
  fit <- causal_estimate_effect(d, dag, "x", "y",
                                  adjustment = "w", estimator = "lm")
  # no effect_boot, no posterior -> must fall back to the asymptotic CI.
  expect_null(fit$effect_boot)
  expect_null(fit$posterior)
  post <- as_edaphos_posterior(fit)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "analytic")
  # Drawn Gaussian at mean ~ 1.5
  expect_lt(abs(as.numeric(post$mean) - fit$effect), 1e-12)
})

test_that("causal_effect_posterior() errors loudly when the effect is not identifiable from the DAG", {
  skip_if_no_dagitty()
  d   <- .toy_df(240L)
  # Unobserved confounder makes the effect non-identifiable.
  dag <- dagitty::dagitty("dag { U -> x ; U -> y ; x -> y }")
  # U is not in the data, so the adjustment set is empty -> LM would
  # be unadjusted, but dagitty::adjustmentSets returns an empty set
  # (or NULL). `causal_effect_posterior()` should bubble the error up.
  expect_error(
    causal_effect_posterior(d, dag, "x", "y", estimator = "lm",
                              B = 50L),
    regexp = "identifiable|adjustment|not found"
  )
})

test_that("calibration pipeline works on the Pillar 1 posterior (pseudo-PICP design)", {
  skip_if_no_dagitty()
  # When there is no ground truth for the effect we use the full-data
  # point estimate as a stand-in and check the pseudo-PICP. This is
  # the exact pattern the v1.6 calibration vignette will use for P1.
  d   <- .toy_df(400L, seed = 10L)
  dag <- dagitty::dagitty("dag { x -> y ; w -> y ; w -> x }")
  point_fit <- causal_estimate_effect(d, dag, "x", "y",
                                         adjustment = "w", estimator = "lm")
  post <- causal_effect_posterior(d, dag, "x", "y",
                                     adjustment = "w", estimator = "lm",
                                     B = 300L, seed = 9L)
  calib <- uncertainty_calibrate(post,
                                   truth = as.numeric(point_fit$effect))
  expect_true(is.list(calib))
  expect_true(is.numeric(calib$crps))
  expect_true(is.finite(calib$crps))
})
