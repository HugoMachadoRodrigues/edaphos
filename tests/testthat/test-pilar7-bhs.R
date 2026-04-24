## Tests for Pilar 7 -- Bayesian Hierarchical Spatial (v2.3.0).

.mk_spatial_data <- function(n = 100L, true_beta = 2, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  x   <- stats::rnorm(n)
  # Latent GP with exponential covariance
  D <- as.matrix(stats::dist(cbind(lon, lat)))
  R <- exp(-2 * D);  diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  y <- true_beta * x + w + stats::rnorm(n, 0, 0.3)
  data.frame(y = y, x = x, lon = lon, lat = lat)
}

test_that("bhs_fit: recovers the true beta on a spatial dataset", {
  dat <- .mk_spatial_data(n = 80L, true_beta = 2, seed = 1L)
  fit <- bhs_fit(
    data = dat, formula = y ~ x, coords = c("lon", "lat"),
    backend = "gibbs",
    nmcmc = 500L, burn = 200L, thin = 1L,
    phi_range = c(0.1, 10),
    seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_bhs")
  # Mean of posterior draws on the x coefficient should cover 2
  beta_x_mean <- mean(fit$beta_draws[, "x"])
  beta_x_sd   <- stats::sd(fit$beta_draws[, "x"])
  expect_lt(abs(beta_x_mean - 2), 3 * beta_x_sd)
  # Posterior variance components are positive
  expect_true(all(fit$sigma2_draws > 0))
  expect_true(all(fit$tau2_draws  > 0))
})

test_that("bhs_fit: phi profile-MLE sits inside the user bracket", {
  dat <- .mk_spatial_data(n = 60L, seed = 2L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 200L, burn = 100L, seed = 2L,
                   phi_range = c(0.01, 10))
  expect_gte(fit$phi_hat, 0.01)
  expect_lte(fit$phi_hat, 10)
})

test_that("predict.edaphos_bhs: returns a well-shaped frame", {
  dat <- .mk_spatial_data(n = 60L, seed = 3L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 300L, burn = 150L, seed = 3L)
  newd <- data.frame(
    x = stats::rnorm(8),
    lon = stats::runif(8, -49.9, -48.1),
    lat = stats::runif(8, -15.9, -14.1)
  )
  pr <- predict(fit, newd, n_draws = 100L)
  expect_s3_class(pr, "data.frame")
  expect_equal(nrow(pr), 8L)
  expect_true(all(c("mean", "sd") %in% names(pr)))
  # Quantile columns
  expect_true(any(grepl("^q\\d+", names(pr))))
})

test_that("as_edaphos_posterior.edaphos_bhs: produces a valid posterior", {
  dat <- .mk_spatial_data(n = 50L, seed = 4L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 300L, burn = 150L, seed = 4L)
  post <- as_edaphos_posterior(fit)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bayesian")
  expect_equal(post$query_type, "map")
})

test_that("bhs_fit: print method emits a readable header", {
  dat <- .mk_spatial_data(n = 40L, seed = 5L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 200L, burn = 100L, seed = 5L)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("edaphos_bhs", out)))
  expect_true(any(grepl("Pilar 7", out)))
})
