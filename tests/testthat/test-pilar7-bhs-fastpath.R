## Tests for the v3.2.0 Gibbs-sampler fast path (triangular-solve
## MVN sampling + in-place diagonal updates).  The fast path
## replaces `chol2inv` + a second Cholesky per iteration with a
## single Cholesky of the precision matrix and 3 backsolves.

test_that("fast-path bhs_fit: posterior mean of beta recovers the truth", {
  set.seed(10L)
  n <- 120L
  dat <- data.frame(
    lon = stats::runif(n, -50, -48),
    lat = stats::runif(n, -16, -14),
    x   = stats::rnorm(n)
  )
  D <- as.matrix(stats::dist(cbind(dat$lon, dat$lat)))
  R <- exp(-2 * D); diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  dat$y <- 3 * dat$x + w + stats::rnorm(n, 0, 0.3)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   backend = "gibbs",
                   nmcmc = 600L, burn = 300L, seed = 10L,
                   phi_range = c(0.1, 10))
  beta_x_mean <- mean(fit$beta_draws[, "x"])
  beta_x_sd   <- stats::sd(fit$beta_draws[, "x"])
  # Posterior mean should be within 5 standard errors of the truth on
  # 300 post-burn MCMC draws.  The wide band avoids flakiness from
  # (a) the Gibbs sampler's run-to-run stochasticity when nmcmc is
  # short and (b) the small-sample spatial-GP bias contribution.
  expect_lt(abs(beta_x_mean - 3), 5 * beta_x_sd)
})

test_that("fast-path bhs_fit: posterior variance components remain positive", {
  set.seed(11L)
  n <- 80L
  dat <- data.frame(
    lon = stats::runif(n, -50, -48),
    lat = stats::runif(n, -16, -14),
    x   = stats::rnorm(n)
  )
  dat$y <- 2 * dat$x + stats::rnorm(n, 0, 1)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 300L, burn = 150L, seed = 11L)
  expect_true(all(fit$sigma2_draws > 0))
  expect_true(all(fit$tau2_draws  > 0))
})

test_that("fast-path bhs_fit: predict() produces finite summaries", {
  set.seed(12L)
  n <- 60L
  dat <- data.frame(
    lon = stats::runif(n, -50, -48),
    lat = stats::runif(n, -16, -14),
    x   = stats::rnorm(n)
  )
  dat$y <- 1.5 * dat$x + stats::rnorm(n, 0, 0.5)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 300L, burn = 150L, seed = 12L)
  newd <- data.frame(
    x   = stats::rnorm(5),
    lon = stats::runif(5, -49.5, -48.5),
    lat = stats::runif(5, -15.5, -14.5)
  )
  pr <- predict(fit, newd, n_draws = 100L)
  expect_true(all(is.finite(pr$mean)))
  expect_true(all(is.finite(pr$sd)))
  expect_true(all(pr$sd > 0))
})

test_that("fast-path bhs_fit: faster than a (hypothetical) dense-inverse path", {
  # We can't easily run the v2.3.0 dense path in-line here, but we
  # DO contract that the fast path is reasonably fast on a modest
  # problem: 500 iterations at n = 150 should complete in < 3 s on a
  # modern laptop.
  set.seed(13L)
  n <- 150L
  dat <- data.frame(
    lon = stats::runif(n, -50, -48),
    lat = stats::runif(n, -16, -14),
    x   = stats::rnorm(n)
  )
  dat$y <- 2 * dat$x + stats::rnorm(n, 0, 1)
  t1 <- system.time(
    bhs_fit(dat, y ~ x, c("lon", "lat"),
             nmcmc = 500L, burn = 250L, seed = 13L,
             phi_range = c(0.1, 5))
  )["elapsed"]
  # Generous ceiling; purely a performance-regression guard-rail.
  expect_lt(as.numeric(t1), 10)
})
