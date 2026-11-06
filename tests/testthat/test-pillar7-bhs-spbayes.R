# =============================================================================
# backend = "spBayes" is a full peer of "gibbs" and "rcpp".
#
# Until 2026-11 this backend returned draws and nothing else. predict() and
# al_query_bhs() refused it, and as_edaphos_posterior() crashed inside sweep()
# on a NULL w_post_mean -- while README, NEWS and ?bhs_fit presented it as an
# equal option. These tests hold it to the same contract as the others, and
# check its predictions against the gibbs backend's on the same data, since
# "it runs" is not evidence that it predicts correctly.
# =============================================================================

.mk_spb_data <- function(n = 80L, seed = 5L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48); lat <- stats::runif(n, -16, -14)
  x   <- stats::rnorm(n)
  D   <- as.matrix(stats::dist(cbind(lon, lat)))
  R   <- exp(-2 * D); diag(R) <- diag(R) + 1e-8
  w   <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  data.frame(y = 2 * x + w + stats::rnorm(n, 0, 0.3), x = x, lon = lon, lat = lat)
}

test_that("spBayes fits carry the fields every method reads", {
  skip_if_not_installed("spBayes")
  skip_on_cran()
  d <- .mk_spb_data()
  expect_no_warning(
    s <- bhs_fit(d, y ~ x, c("lon", "lat"), backend = "spBayes",
                 nmcmc = 1500L, burn = 750L, seed = 1L, phi_range = c(0.1, 10)))
  for (k in c("w_post_mean", "phi_hat", "phi_draws", "spatial", "nmcmc", "burn"))
    expect_false(is.null(s[[k]]), info = k)
  expect_identical(s$phi_method, "posterior median")
  expect_equal(s$phi_hat, stats::median(s$phi_draws))
  expect_true(is.na(s$phi_railed))
  expect_length(s$w_post_mean, nrow(d))
  expect_identical(colnames(s$beta_draws), colnames(s$X))
  expect_output(print(s), "phi \\(posterior median\\)")
})

test_that("spBayes predictions agree with the gibbs backend's", {
  skip_if_not_installed("spBayes")
  skip_on_cran()
  d  <- .mk_spb_data(n = 120L)
  tr <- d[1:90, ]; te <- d[91:120, ]
  g <- suppressWarnings(bhs_fit(tr, y ~ x, c("lon", "lat"), backend = "gibbs",
                                nmcmc = 1500L, burn = 750L, seed = 1L,
                                phi_range = c(0.1, 10)))
  s <- bhs_fit(tr, y ~ x, c("lon", "lat"), backend = "spBayes",
               nmcmc = 3000L, burn = 1500L, seed = 1L, phi_range = c(0.1, 10))
  pg <- predict(g, te)
  ps <- predict(s, te, draws = TRUE)
  expect_identical(names(ps), names(pg))
  expect_equal(nrow(ps), nrow(te))
  expect_true(all(ps$sd > 0))
  expect_true(all(ps$q025 < ps$mean & ps$mean < ps$q975))
  # Same field, two samplers: the means must agree closely, and neither may
  # be materially worse against the truth.
  expect_gt(stats::cor(pg$mean, ps$mean), 0.98)
  rmse <- function(m) sqrt(mean((m - te$y)^2))
  expect_lt(rmse(ps$mean), 1.25 * rmse(pg$mean))
  dr <- attr(ps, "draws")
  expect_equal(ncol(dr), nrow(te))
  expect_equal(colMeans(dr), ps$mean)
})

test_that("as_edaphos_posterior and al_query_bhs serve spBayes fits", {
  skip_if_not_installed("spBayes")
  skip_on_cran()
  d <- .mk_spb_data()
  s <- bhs_fit(d, y ~ x, c("lon", "lat"), backend = "spBayes",
               nmcmc = 1500L, burn = 750L, seed = 1L, phi_range = c(0.1, 10))
  post <- as_edaphos_posterior(s)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(ncol(post$samples), nrow(d))
  pool <- data.frame(x = 0, lon = c(-49, -48.2), lat = c(-15, -14.1))
  q <- al_query_bhs(s, pool, n_draws = 50L)
  expect_equal(nrow(q), 2L)
  expect_true(all(q$posterior_var > 0))
})

test_that("a fit without a latent-field estimate fails readably, not in sweep()", {
  d <- .mk_spb_data(n = 40L)
  g <- suppressWarnings(bhs_fit(d, y ~ x, c("lon", "lat"), nmcmc = 100L,
                                burn = 50L, seed = 1L, phi_range = c(0.1, 10)))
  g$w_post_mean <- NULL
  expect_error(as_edaphos_posterior(g), "carries no latent-field estimate")
})
