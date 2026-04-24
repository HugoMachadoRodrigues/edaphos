## Tests for the v2.7.0 torch backend of Pilar 8.

test_that("no_fno_fit(backend='torch'): fits and predicts with autograd", {
  skip_if_not_installed("torch")
  set.seed(1L)
  n_obs <- 12L; n_depths <- 8L
  depths <- seq(5, 120, length.out = n_depths)
  cov_static <- matrix(stats::rnorm(n_obs * 2), n_obs, 2L)
  make_prof <- function(ci, z) (10 + 5 * ci[1L]) * exp(-(0.02 + 0.005 * ci[2L]) * z)
  targets <- t(apply(cov_static, 1L, make_prof, z = depths))
  cov_dep <- array(0, dim = c(n_obs, n_depths, 2L))
  for (i in 1:n_obs) for (c in 1:2) cov_dep[i, , c] <- cov_static[i, c]
  fit <- no_fno_fit(depths, targets, cov_dep,
                      n_modes = 3L, width = 4L, n_blocks = 1L,
                      epochs = 20L, lr = 0.01, seed = 1L,
                      backend = "torch", device = "cpu")
  expect_s3_class(fit, "edaphos_no_fno")
  expect_equal(fit$backend, "torch")
  expect_true(length(fit$history) > 0L)
  expect_true(all(is.finite(fit$history)))
  pr <- predict(fit, cov_dep)
  expect_equal(dim(pr), dim(targets))
  expect_true(all(is.finite(pr)))
})

test_that("no_deeponet_fit(backend='torch'): training loss decreases", {
  skip_if_not_installed("torch")
  set.seed(1L)
  n_obs <- 20L; n_depths <- 10L
  depths <- seq(5, 120, length.out = n_depths)
  cov_static <- matrix(stats::rnorm(n_obs * 3), n_obs, 3L)
  make_prof <- function(ci, z) (10 + 5 * ci[1L]) *
    exp(-(0.02 + 0.005 * ci[2L]) * z) + ci[3L]
  targets <- t(apply(cov_static, 1L, make_prof, z = depths))
  fit <- no_deeponet_fit(depths, targets, cov_static,
                            branch_hidden = 16L, trunk_hidden = 16L,
                            output_dim = 8L,
                            epochs = 200L, lr = 0.01, seed = 1L,
                            backend = "torch", device = "cpu")
  expect_s3_class(fit, "edaphos_no_deeponet")
  expect_equal(fit$backend, "torch")
  # Torch autograd should achieve notable loss reduction
  expect_lt(fit$history[length(fit$history)], fit$history[1L] * 0.5)
  # Predict on new depths
  pr <- predict(fit, cov_static, newdepths = c(10, 50, 100))
  expect_equal(dim(pr), c(20L, 3L))
})

test_that("backend='r' and backend='torch' both produce valid output", {
  skip_if_not_installed("torch")
  set.seed(1L)
  n <- 12L; d <- 8L
  depths <- seq(5, 100, length.out = d)
  cov_static <- matrix(stats::rnorm(n * 2), n, 2L)
  y <- matrix(stats::rnorm(n * d), n, d)
  fit_r <- no_deeponet_fit(depths, y, cov_static,
                             branch_hidden = 6L, trunk_hidden = 6L,
                             output_dim = 4L,
                             epochs = 30L, backend = "r", seed = 1L)
  fit_t <- no_deeponet_fit(depths, y, cov_static,
                             branch_hidden = 6L, trunk_hidden = 6L,
                             output_dim = 4L,
                             epochs = 30L, backend = "torch", seed = 1L)
  expect_equal(fit_r$backend, "r")
  expect_equal(fit_t$backend, "torch")
  pr_r <- predict(fit_r, cov_static)
  pr_t <- predict(fit_t, cov_static)
  expect_equal(dim(pr_r), dim(pr_t))
  expect_true(all(is.finite(pr_r)) && all(is.finite(pr_t)))
})
