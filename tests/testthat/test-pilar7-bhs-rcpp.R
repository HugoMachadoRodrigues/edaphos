## Tests for the v3.5.0 RcppArmadillo Gibbs backend.  The contract:
##
##   1. backend = "rcpp" produces a valid `edaphos_bhs` object whose
##      posterior mean recovers a known true beta within 5 sigma.
##   2. `predict()` and `as_edaphos_posterior()` work the same way as
##      with backend = "gibbs".
##   3. The Rcpp sweep is materially faster than the R fast path
##      (we contract a perf-regression ceiling, not a raw speedup).
##   4. Posterior variance components remain positive.

.mk_spatial_data <- function(n = 100L, true_beta = 2, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  x   <- stats::rnorm(n)
  D <- as.matrix(stats::dist(cbind(lon, lat)))
  R <- exp(-2 * D);  diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  y <- true_beta * x + w + stats::rnorm(n, 0, 0.3)
  data.frame(y = y, x = x, lon = lon, lat = lat)
}

test_that("backend = 'rcpp': recovers the true beta", {
  dat <- .mk_spatial_data(n = 80L, true_beta = 2, seed = 1L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   backend = "rcpp",
                   nmcmc = 500L, burn = 200L, thin = 1L,
                   phi_range = c(0.1, 10), seed = 1L)
  expect_s3_class(fit, "edaphos_bhs")
  expect_equal(fit$backend, "rcpp")
  beta_x_mean <- mean(fit$beta_draws[, "x"])
  beta_x_sd   <- stats::sd(fit$beta_draws[, "x"])
  expect_lt(abs(beta_x_mean - 2), 5 * beta_x_sd)
  expect_true(all(fit$sigma2_draws > 0))
  expect_true(all(fit$tau2_draws  > 0))
})

test_that("backend = 'rcpp' vs 'gibbs': same posterior MEANS within 0.2", {
  # Gibbs is stochastic, so we contract that the long-run posterior
  # means agree (large nmcmc reduces MCMC error).  We don't expect
  # bit-equivalence -- the C++ RNG ordering differs.
  dat <- .mk_spatial_data(n = 60L, true_beta = 1.5, seed = 2L)
  fit_r    <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                        backend = "gibbs",
                        nmcmc = 800L, burn = 400L, seed = 2L,
                        phi_range = c(0.1, 5))
  fit_cpp  <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                        backend = "rcpp",
                        nmcmc = 800L, burn = 400L, seed = 2L,
                        phi_range = c(0.1, 5))
  m_r   <- mean(fit_r$beta_draws[,   "x"])
  m_cpp <- mean(fit_cpp$beta_draws[, "x"])
  expect_lt(abs(m_r - m_cpp), 0.2)
})

test_that("backend = 'rcpp': predict() returns a well-shaped posterior summary", {
  dat <- .mk_spatial_data(n = 60L, seed = 3L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   backend = "rcpp",
                   nmcmc = 300L, burn = 150L, seed = 3L)
  newd <- data.frame(
    x   = stats::rnorm(8),
    lon = stats::runif(8, -49.9, -48.1),
    lat = stats::runif(8, -15.9, -14.1)
  )
  pr <- predict(fit, newd, n_draws = 100L)
  expect_s3_class(pr, "data.frame")
  expect_equal(nrow(pr), 8L)
  expect_true(all(c("mean", "sd") %in% names(pr)))
})

test_that("backend = 'rcpp': as_edaphos_posterior wraps cleanly", {
  dat <- .mk_spatial_data(n = 50L, seed = 4L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   backend = "rcpp",
                   nmcmc = 200L, burn = 100L, seed = 4L)
  post <- as_edaphos_posterior(fit)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bayesian")
  expect_equal(post$query_type, "map")
})

test_that("backend = 'rcpp': performance ceiling -- under R fast path on n = 200", {
  dat <- .mk_spatial_data(n = 200L, seed = 5L)
  t_r <- system.time(
    bhs_fit(dat, y ~ x, c("lon", "lat"),
              backend = "gibbs",
              nmcmc = 300L, burn = 150L, seed = 5L,
              phi_range = c(0.1, 5))
  )["elapsed"]
  t_c <- system.time(
    bhs_fit(dat, y ~ x, c("lon", "lat"),
              backend = "rcpp",
              nmcmc = 300L, burn = 150L, seed = 5L,
              phi_range = c(0.1, 5))
  )["elapsed"]
  # Just contract that Rcpp is not strictly slower; on most systems
  # this ratio is well below 0.5 (i.e. >= 2x speedup).
  expect_lt(as.numeric(t_c), as.numeric(t_r))
})
