## Tests for the RcppArmadillo Gibbs backend.  The contract:
##
##   1. backend = "rcpp" produces a valid `edaphos_bhs` object whose
##      posterior mean recovers a known true beta within 5 sigma.
##   2. Under one seed it reproduces backend = "gibbs" draw for draw, and
##      `predict()` and `as_edaphos_posterior()` work the same way.
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

test_that("backend = 'rcpp' reproduces backend = 'gibbs' draw for draw", {
  # Both backends draw from R's RNG in the same order and apply the same
  # linear algebra, so under one seed they produce the SAME chain, not merely
  # the same posterior. Measured: every draw agrees to ~1e-15. This test used
  # to compare one posterior mean at a tolerance of 0.2, under a comment
  # saying bit-equivalence could not be expected; a C++ port that drew from
  # the wrong conditional by a few per cent would have passed it.
  # Three designs: a slope, intercept only, and three columns.
  designs <- list(list(f = y ~ x,            n = 60L, seed = 2L),
                  list(f = y ~ 1,            n = 40L, seed = 7L),
                  list(f = y ~ x + I(x^2),   n = 50L, seed = 9L))
  for (d in designs) {
    dat <- .mk_spatial_data(n = d$n, true_beta = 1.5, seed = d$seed)
    args <- list(dat, d$f, c("lon", "lat"), nmcmc = 300L, burn = 100L,
                 seed = d$seed, phi_range = c(0.1, 20))
    fit_r   <- do.call(bhs_fit, c(args, backend = "gibbs"))
    fit_cpp <- do.call(bhs_fit, c(args, backend = "rcpp"))
    expect_identical(fit_cpp$phi_hat, fit_r$phi_hat)
    expect_equal(fit_cpp$beta_draws,   fit_r$beta_draws,   tolerance = 1e-8)
    expect_equal(fit_cpp$sigma2_draws, fit_r$sigma2_draws, tolerance = 1e-8)
    expect_equal(fit_cpp$tau2_draws,   fit_r$tau2_draws,   tolerance = 1e-8)
    expect_equal(fit_cpp$w_post_mean,  fit_r$w_post_mean,  tolerance = 1e-8)
  }
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
  # Wall-clock assertion: skipped on CRAN, whose builders are shared, some
  # single-core, some under valgrind, so an absolute ceiling or an A < B
  # timing comparison flips for reasons unrelated to the code. It still runs
  # on every CI leg and in local test runs.
  skip_on_cran()
  # And skipped under covr, which instruments R code line by line but not
  # the C++ backend: the times it reports belong to the instrumentation, not
  # to either backend. That is where this test failed, once in ten coverage
  # runs, with rcpp at 0.286 s against 0.277 s -- a 9 ms coin flip.
  skip_on_covr()
  dat <- .mk_spatial_data(n = 200L, seed = 5L)
  fit_time <- function(backend) system.time(
    bhs_fit(dat, y ~ x, c("lon", "lat"),
              backend = backend,
              nmcmc = 300L, burn = 150L, seed = 5L,
              phi_range = c(0.1, 5))
  )[["elapsed"]]
  # The minimum of three alternating runs, not one run each: the minimum is
  # the standard estimator for a timing with additive noise, and alternating
  # keeps a background spike from landing on one backend only.
  t_r <- t_c <- Inf
  for (i in 1:3) {
    t_r <- min(t_r, fit_time("gibbs"))
    t_c <- min(t_c, fit_time("rcpp"))
  }
  # Measured on an M-series Mac, eight alternating runs each: rcpp takes
  # 0.50 of the R time at n = 200 and 0.37 at n = 500, faster in 8 of 8 at
  # both sizes. The contract asserted is only that rcpp is not slower.
  expect_lt(t_c, t_r)
})
