## Regressions for two Pilar 7 defects found while writing the v4.1.0
## vignette.  They concealed each other, so both are pinned here.
##
##  (a) predict.edaphos_bhs() added only the nugget tau^2 and dropped
##      the kriging variance sigma^2 (1 - r' R^-1 r) entirely.  Every
##      interval was too narrow by exactly the spatially structured
##      share of the residual variance.
##  (b) bhs_fit() profiled phi over `phi_range` and reported whatever
##      optimise() returned, including a value pinned to an endpoint.
##      A railed phi collapses sigma^2, which made (a) invisible.

.mk_spatial <- function(n = 120L, seed = 7L) {
  set.seed(seed)
  lon <- stats::runif(n, 0, 1)
  lat <- stats::runif(n, 0, 1)
  x   <- stats::rnorm(n)
  D <- as.matrix(stats::dist(cbind(lon, lat)))
  R <- exp(-3 * D); diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n, 0, 2))
  data.frame(y = 2 * x + w + stats::rnorm(n, 0, 0.4),
             x = x, lon = lon, lat = lat)
}

.fit <- function(dat, phi_range = c(0.05, 200)) {
  suppressWarnings(bhs_fit(
    data = dat, formula = y ~ x, coords = c("lon", "lat"),
    backend = "gibbs", nmcmc = 1200L, burn = 400L, thin = 2L,
    phi_range = phi_range, seed = 1L, verbose = FALSE))
}

test_that("predictive variance relaxes to sigma^2 + tau^2 far from data", {
  dat <- .mk_spatial()
  fit <- .fit(dat)

  s2 <- mean(fit$sigma2_draws)
  t2 <- mean(fit$tau2_draws)

  # Sites translated far outside any correlation range: the kriging
  # term must vanish, leaving the full marginal variance.
  far <- dat[1:30, ]
  far$lon <- far$lon + 1e4
  p_far <- predict(fit, newdata = far, n_draws = 2000L)

  expect_equal(mean(p_far$sd), sqrt(s2 + t2), tolerance = 0.05)

  # The bug returned sqrt(tau2) here.  Guard against its return: with a
  # genuinely spatial field the two targets are far apart.
  expect_gt(sqrt(s2 + t2), 1.5 * sqrt(t2))
  expect_gt(mean(p_far$sd), 1.4 * sqrt(t2))
})

test_that("predictive variance shrinks towards the nugget at observed sites", {
  dat <- .mk_spatial()
  fit <- .fit(dat)

  s2 <- mean(fit$sigma2_draws)
  t2 <- mean(fit$tau2_draws)

  p_tr <- predict(fit, newdata = dat, n_draws = 2000L)

  # At the training sites the kriging variance is ~0, so the spread is
  # the nugget plus the (small) contribution of beta uncertainty --
  # well below the marginal sigma^2 + tau^2.
  expect_lt(mean(p_tr$sd), 0.6 * sqrt(s2 + t2))

  # And strictly tighter than predictions made far away.
  far <- dat; far$lon <- far$lon + 1e4
  expect_lt(mean(p_tr$sd), mean(predict(fit, newdata = far,
                                        n_draws = 2000L)$sd))
})

test_that("95% intervals are approximately calibrated on held-out sites", {
  set.seed(11)
  dat <- .mk_spatial(n = 200L, seed = 3L)
  ho  <- sample(nrow(dat), 60)

  fit <- .fit(dat[-ho, ])
  p   <- predict(fit, newdata = dat[ho, ], n_draws = 2000L)

  picp <- mean(dat$y[ho] >= p$q025 & dat$y[ho] <= p$q975)

  # The pre-fix implementation scored ~0.4 here.  Nominal is 0.95;
  # allow honest Monte-Carlo slack on 60 held-out sites.
  expect_gt(picp, 0.85)
  expect_lte(picp, 1)
})

test_that("bhs_fit warns when the profile-MLE of phi hits the bracket", {
  dat <- .mk_spatial()

  # Absurdly narrow upper bound: the likelihood is still climbing.
  expect_warning(
    bhs_fit(data = dat, formula = y ~ x, coords = c("lon", "lat"),
            backend = "gibbs", nmcmc = 300L, burn = 100L, thin = 1L,
            phi_range = c(0.05, 0.06), seed = 1L, verbose = FALSE),
    "profile-MLE of phi"
  )

  # A bracket wide enough to contain the optimum must stay silent.
  expect_no_warning(
    bhs_fit(data = dat, formula = y ~ x, coords = c("lon", "lat"),
            backend = "gibbs", nmcmc = 300L, burn = 100L, thin = 1L,
            phi_range = c(0.05, 200), seed = 1L, verbose = FALSE)
  )
})

test_that("a railed phi understates the spatial variance fraction", {
  dat <- .mk_spatial()

  railed   <- .fit(dat, phi_range = c(0.05, 0.06))
  interior <- .fit(dat, phi_range = c(0.05, 200))

  frac <- function(f) {
    s2 <- mean(f$sigma2_draws); s2 / (s2 + mean(f$tau2_draws))
  }

  # This is the mechanism that hid the predict() bug: pinning phi to a
  # tiny value drives sigma^2 away from its supported value, so the
  # missing kriging term had little left to omit.
  expect_true(is.finite(frac(railed)))
  expect_true(is.finite(frac(interior)))
  expect_false(isTRUE(all.equal(frac(railed), frac(interior),
                                tolerance = 0.05)))
})
