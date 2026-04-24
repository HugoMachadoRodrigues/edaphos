## Tests for Pilar 8 -- Neural operators (v2.4.0).

.mk_operator_dataset <- function(n_obs = 20L, n_depths = 12L,
                                    p_in = 3L, seed = 1L) {
  set.seed(seed)
  depths <- seq(5, 120, length.out = n_depths)
  cov_static <- matrix(stats::rnorm(n_obs * p_in), n_obs, p_in)
  # Target: decaying profile modulated by covariates
  make_profile <- function(cov_i, z) {
    amp  <- 10 + 5 * cov_i[1L]
    rate <- 0.02 + 0.005 * cov_i[2L]
    amp * exp(-rate * z) + cov_i[3L]
  }
  targets <- t(apply(cov_static, 1L, make_profile, z = depths))
  list(depths = depths, covariates = cov_static, targets = targets)
}

test_that("no_fno_fit + predict: output shape matches input grid", {
  d <- .mk_operator_dataset(n_obs = 12L, n_depths = 8L, p_in = 1L)
  # Build depth-dependent cov cube from static covariates (replicate
  # along the depth axis).
  cov_dep <- array(d$covariates, dim = c(12L, 8L, 1L))
  for (i in 1:12) cov_dep[i, , 1L] <- d$covariates[i, 1L]
  fit <- no_fno_fit(d$depths, d$targets, cov_dep,
                      n_modes = 3L, width = 4L, n_blocks = 1L,
                      epochs = 30L, lr = 0.01, seed = 1L)
  expect_s3_class(fit, "edaphos_no_fno")
  expect_true(length(fit$history) > 0L)
  pr <- predict(fit, cov_dep)
  expect_equal(dim(pr), dim(d$targets))
})

test_that("no_deeponet_fit + predict: output shape matches", {
  d <- .mk_operator_dataset(n_obs = 20L, n_depths = 10L, p_in = 3L)
  fit <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                            branch_hidden = 8L, trunk_hidden = 8L,
                            output_dim = 4L,
                            epochs = 50L, lr = 0.03, seed = 1L)
  expect_s3_class(fit, "edaphos_no_deeponet")
  pr <- predict(fit, d$covariates)
  expect_equal(dim(pr), c(20L, 10L))
})

test_that("no_deeponet_fit: training loss decreases", {
  d <- .mk_operator_dataset(n_obs = 20L, n_depths = 10L, p_in = 3L,
                               seed = 2L)
  fit <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                            branch_hidden = 16L, trunk_hidden = 16L,
                            output_dim = 8L,
                            epochs = 200L, lr = 0.03, seed = 2L)
  # After training, final MSE should be notably smaller than initial
  expect_lt(fit$history[length(fit$history)], fit$history[1L] * 0.8)
})

test_that("no_deeponet predict: handles new depths", {
  d <- .mk_operator_dataset(n_obs = 10L, n_depths = 8L, p_in = 2L)
  fit <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                            branch_hidden = 6L, trunk_hidden = 6L,
                            output_dim = 4L,
                            epochs = 50L, lr = 0.02, seed = 1L)
  new_z <- c(10, 50, 100)
  pr <- predict(fit, d$covariates, newdepths = new_z)
  expect_equal(dim(pr), c(10L, 3L))
})

test_that("print methods emit the expected headers", {
  d <- .mk_operator_dataset(n_obs = 8L, n_depths = 6L, p_in = 2L)
  cov_dep <- array(d$covariates, dim = c(8L, 6L, 2L))
  for (i in 1:8) for (c in 1:2) cov_dep[i, , c] <- d$covariates[i, c]
  f1 <- no_fno_fit(d$depths, d$targets, cov_dep,
                     n_modes = 2L, width = 3L, n_blocks = 1L,
                     epochs = 10L, lr = 0.01, seed = 1L)
  f2 <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                           branch_hidden = 4L, trunk_hidden = 4L,
                           output_dim = 3L, epochs = 10L, seed = 1L)
  o1 <- utils::capture.output(print(f1))
  o2 <- utils::capture.output(print(f2))
  expect_true(any(grepl("Fourier Neural Operator", o1)))
  expect_true(any(grepl("Deep Operator Network", o2)))
})
