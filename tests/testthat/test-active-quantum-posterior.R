# v1.6.0-f -- Pillar 5 + Pillar 6 adapters to edaphos_posterior.

# ---- Pillar 5 --------------------------------------------------------------

test_that("active_learning_posterior() returns a sample posterior with QRF quantile grid", {
  skip_if_not_installed("ranger")
  set.seed(1L)
  n <- 60L
  df <- data.frame(
    x1 = stats::rnorm(n),
    x2 = stats::rnorm(n),
    y  = NA_real_
  )
  df$y <- 1.2 * df$x1 - 0.8 * df$x2 + stats::rnorm(n, sd = 0.3)
  fit <- al_fit(labeled = df, target = "y",
                  covariates = c("x1", "x2"), num.trees = 100L)
  newdata <- data.frame(
    x1 = stats::rnorm(20L),
    x2 = stats::rnorm(20L)
  )
  post <- active_learning_posterior(fit, newdata, n_quantiles = 49L,
                                       units = "y-units")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "ensemble")
  expect_equal(post$query_type, "sample")
  expect_equal(dim(post$samples)[1L], 49L)
  expect_equal(dim(post$samples)[2L], 20L)
})

test_that("as_edaphos_posterior.edaphos_al_model requires newdata", {
  skip_if_not_installed("ranger")
  df <- data.frame(x = stats::rnorm(40L),
                     y = stats::rnorm(40L))
  fit <- al_fit(df, target = "y", covariates = "x", num.trees = 50L)
  expect_error(as_edaphos_posterior(fit), regexp = "newdata")
})

test_that("calibrate works on the AL posterior", {
  skip_if_not_installed("ranger")
  set.seed(2L)
  n <- 80L
  df <- data.frame(
    x1 = stats::rnorm(n),
    x2 = stats::rnorm(n),
    y  = NA_real_
  )
  df$y <- 1.2 * df$x1 - 0.8 * df$x2 + stats::rnorm(n, sd = 0.3)
  split <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.8, 0.2))
  fit <- al_fit(df[split, ], target = "y",
                  covariates = c("x1", "x2"), num.trees = 150L)
  test_df <- df[!split, ]
  post <- active_learning_posterior(fit, test_df)
  calib <- uncertainty_calibrate(post, truth = test_df$y)
  expect_true(is.finite(calib$crps))
  # QRF is usually well-calibrated; PICP @ 90 % should be 0.65..1.0
  expect_gt(calib$picp["0.90"], 0.5)
  expect_lte(calib$picp["0.90"], 1.0)
})

# ---- Pillar 6 --------------------------------------------------------------

test_that("quantum_krr_posterior() returns mean + epistemic + aleatoric sd of the right shape", {
  set.seed(3L)
  # Tiny scalable regression with n_qubits = 3 to keep the quantum-
  # kernel Gram matrix small.
  n <- 20L; d <- 3L
  X <- matrix(stats::runif(n * d, 0, pi), ncol = d)
  y <- sin(X[, 1L]) + 0.5 * cos(X[, 2L]) + stats::rnorm(n, sd = 0.1)
  fit <- quantum_krr_fit(X = X, y = y, reps = 1L, lambda = 0.2)
  Xnew <- matrix(stats::runif(6L * d, 0, pi), ncol = d)
  post <- quantum_krr_posterior(fit, newdata = Xnew,
                                  n_samples = 300L,
                                  units = "target-units")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "analytic")
  expect_equal(length(post$mean), 6L)
  expect_equal(length(post$sd),   6L)
  expect_equal(length(post$epistemic_sd), 6L)
  expect_equal(length(post$aleatoric_sd), 6L)
  # Total variance = epistemic + aleatoric (analytic).
  expect_lt(max(abs(post$sd^2 - post$epistemic_sd^2 -
                       post$aleatoric_sd^2)), 1e-10)
  expect_equal(post$units, "target-units")
})

test_that("as_edaphos_posterior.edaphos_quantum_krr requires newdata", {
  set.seed(4L)
  X <- matrix(stats::runif(15L * 2L), ncol = 2L)
  y <- stats::rnorm(15L)
  fit <- quantum_krr_fit(X, y)
  expect_error(as_edaphos_posterior(fit), regexp = "newdata")
})

test_that("the Quantum-KRR GP posterior is at least as good as the point estimate in RMSE", {
  set.seed(5L)
  n <- 30L
  X <- matrix(stats::runif(n * 3L, 0, pi), ncol = 3L)
  y <- sin(X[, 1L]) + 0.5 * cos(X[, 2L]) + stats::rnorm(n, sd = 0.1)
  fit <- quantum_krr_fit(X, y, reps = 1L, lambda = 0.2)
  # Hold out 8 test rows with the same DGP.
  Xt <- matrix(stats::runif(8L * 3L, 0, pi), ncol = 3L)
  yt <- sin(Xt[, 1L]) + 0.5 * cos(Xt[, 2L]) + stats::rnorm(8L, sd = 0.1)
  post <- quantum_krr_posterior(fit, Xt, n_samples = 300L)
  calib <- uncertainty_calibrate(post, truth = yt)
  # point RMSE equals abs(post$mean - yt) which should be < 1
  expect_lt(calib$point_rmse, 1.5)
})
