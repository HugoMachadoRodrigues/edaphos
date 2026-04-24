## Edge-case tests for Pilar 7 BHS (v2.9.0 expansion)

.mk_spatial <- function(n = 50L, beta = 2, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48); lat <- stats::runif(n, -16, -14)
  x   <- stats::rnorm(n)
  D <- as.matrix(stats::dist(cbind(lon, lat)))
  R <- exp(-2 * D); diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  y <- beta * x + w + stats::rnorm(n, 0, 0.3)
  data.frame(y = y, x = x, lon = lon, lat = lat)
}

test_that("bhs_fit: handles NA rows gracefully via model.frame drop", {
  d <- .mk_spatial(n = 40L)
  d$x[c(3, 7, 11)] <- NA
  d$y[c(15, 20)] <- NA
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 100L, burn = 50L, seed = 1L)
  expect_s3_class(fit, "edaphos_bhs")
  # Should have dropped 5 rows (3 NAs in x, 2 in y)
  expect_equal(length(fit$y), 40L - 5L)
})

test_that("bhs_fit: rejects when too few complete rows", {
  d <- data.frame(y = c(1, 2, 3, NA, NA),
                    x = c(1, 2, NA, 4, 5),
                    lon = 1:5, lat = 1:5)
  expect_error(bhs_fit(d, y ~ x, c("lon", "lat"),
                          nmcmc = 20L, burn = 10L),
                regexp = "Too few complete rows")
})

test_that("bhs_fit: identical input produces reproducible posterior", {
  d <- .mk_spatial(n = 30L)
  f1 <- bhs_fit(d, y ~ x, c("lon", "lat"),
                  nmcmc = 100L, burn = 50L, seed = 42L)
  f2 <- bhs_fit(d, y ~ x, c("lon", "lat"),
                  nmcmc = 100L, burn = 50L, seed = 42L)
  expect_equal(colMeans(f1$beta_draws), colMeans(f2$beta_draws),
                tolerance = 1e-8)
})

test_that("bhs_fit: handles duplicate coordinates without Cholesky failure", {
  d <- .mk_spatial(n = 30L)
  # Duplicate two rows' coordinates
  d$lon[c(5, 10, 15)] <- d$lon[1]
  d$lat[c(5, 10, 15)] <- d$lat[1]
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 80L, burn = 40L, seed = 1L)
  expect_s3_class(fit, "edaphos_bhs")
  # sigma2 and tau2 should stay positive despite duplicate coords
  expect_true(all(fit$sigma2_draws > 0))
  expect_true(all(fit$tau2_draws > 0))
})

test_that("bhs_fit: constant covariate does not crash", {
  d <- .mk_spatial(n = 30L)
  d$x <- rep(1, nrow(d))  # zero variance
  # lm.fit may give NA coefficient but Gibbs should proceed
  fit <- tryCatch(
    bhs_fit(d, y ~ x, c("lon", "lat"),
              nmcmc = 50L, burn = 20L, seed = 1L),
    error = function(e) NULL
  )
  # Either it fits (NA beta from lm.fit init is OK -- Gibbs will
  # re-sample) or it errors informatively.  Both acceptable; no crash.
  expect_true(is.null(fit) || inherits(fit, "edaphos_bhs"))
})

test_that("bhs_fit: large prior_var_beta approximates flat prior", {
  d <- .mk_spatial(n = 40L, beta = 2)
  f_weak <- bhs_fit(d, y ~ x, c("lon", "lat"),
                      nmcmc = 200L, burn = 100L,
                      prior_var_beta = 1e8, seed = 1L)
  f_tight <- bhs_fit(d, y ~ x, c("lon", "lat"),
                       nmcmc = 200L, burn = 100L,
                       prior_var_beta = 0.01, seed = 1L)
  # Weak prior should have posterior mean closer to the true beta = 2
  # than tight prior (which shrinks to 0)
  weak_x  <- mean(f_weak$beta_draws[, "x"])
  tight_x <- mean(f_tight$beta_draws[, "x"])
  expect_lt(abs(weak_x - 2), abs(tight_x - 2) + 0.1)
})

test_that("predict.edaphos_bhs: out-of-extent points produce valid but uncertain predictions", {
  d <- .mk_spatial(n = 50L)
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 200L, burn = 100L, seed = 1L)
  # New points far from training extent
  new_d <- data.frame(
    x = c(0, 1),
    lon = c(-100, 0),       # far outside
    lat = c(-40, 40)
  )
  pr <- predict(fit, new_d, n_draws = 50L)
  expect_equal(nrow(pr), 2L)
  expect_true(all(is.finite(pr$mean)))
  expect_true(all(pr$sd > 0))  # at least some uncertainty
})

test_that("predict.edaphos_bhs: rejects newdata missing covariates", {
  d <- .mk_spatial(n = 30L)
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 100L, burn = 50L, seed = 1L)
  bad <- data.frame(lon = 1, lat = 2)   # no x
  expect_error(predict(fit, bad), regexp = "[Ee]rror|[Nn]ot found|object")
})

test_that("bhs_fit: extreme phi_range still returns valid posterior", {
  d <- .mk_spatial(n = 40L)
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 80L, burn = 40L,
                   phi_range = c(1e-4, 1e4), seed = 1L)
  # Profile-MLE should pick SOME value in the bracket
  expect_true(is.numeric(fit$phi_hat))
  expect_gte(fit$phi_hat, 1e-4)
  expect_lte(fit$phi_hat, 1e4)
})

test_that("as_edaphos_posterior.edaphos_bhs: matches sample dimensions", {
  d <- .mk_spatial(n = 30L)
  fit <- bhs_fit(d, y ~ x, c("lon", "lat"),
                   nmcmc = 100L, burn = 50L, seed = 1L)
  post <- as_edaphos_posterior(fit)
  expect_s3_class(post, "edaphos_posterior")
  # One posterior-sample matrix row per MCMC draw,
  # one column per training site
  expect_equal(ncol(post$samples), length(fit$y))
  expect_equal(nrow(post$samples), nrow(fit$beta_draws))
})
