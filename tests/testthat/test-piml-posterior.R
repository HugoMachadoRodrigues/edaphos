# v1.6.0-c -- Pillar 2 adapter tests.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  has_torch <- isTRUE(tryCatch(torch::torch_is_installed(),
                                 error = function(e) FALSE))
  if (!has_torch) skip("libtorch backend unavailable")
}

.small_profile <- function() {
  list(
    depths = c(5, 15, 30, 60, 100),
    values = c(25, 18, 12, 8, 6.5)
  )
}

test_that("piml_neural_ode_posterior() returns an edaphos_posterior with the right shape", {
  skip_if_no_torch()
  d <- .small_profile()
  ens <- piml_neural_ode_fit_ensemble(
    depths = d$depths, values = d$values,
    K = 3L, hidden = c(8L, 8L), n_steps = 2L,
    epochs = 50L, seed = 1L, verbose = FALSE
  )
  post <- piml_neural_ode_posterior(ens,
                                       newdepths = c(10, 20, 40, 80),
                                       units = "g/kg")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "ensemble")
  expect_equal(post$query_type, "sample")
  # samples: (K, n_depths) = (3, 4)
  expect_equal(dim(post$samples), c(3L, 4L))
  expect_equal(length(post$mean), 4L)
  expect_equal(length(post$sd),   4L)
  expect_equal(post$units, "g/kg")
})

test_that("single-depth query yields a scalar (feature) posterior", {
  skip_if_no_torch()
  d <- .small_profile()
  ens <- piml_neural_ode_fit_ensemble(
    depths = d$depths, values = d$values,
    K = 3L, hidden = c(8L, 8L), n_steps = 2L,
    epochs = 50L, seed = 1L, verbose = FALSE
  )
  post <- piml_neural_ode_posterior(ens, newdepths = 15)
  expect_equal(post$query_type, "feature")
  expect_equal(dim(post$samples), c(3L, 1L))
})

test_that("as_edaphos_posterior.edaphos_piml_neural_ode_ensemble requires newdepths", {
  skip_if_no_torch()
  d <- .small_profile()
  ens <- piml_neural_ode_fit_ensemble(
    depths = d$depths, values = d$values,
    K = 3L, hidden = c(8L, 8L), n_steps = 2L,
    epochs = 20L, seed = 1L, verbose = FALSE
  )
  expect_error(as_edaphos_posterior(ens),
               regexp = "newdepths")
})

test_that("piml_bayes_posterior() wraps a Laplace posterior", {
  # Laplace posterior has no torch / external dependency.
  d <- .small_profile()
  fit <- piml_profile_fit_bayesian(depths = d$depths, values = d$values,
                                      method = "laplace")
  post <- piml_bayes_posterior(fit, newdepths = c(10, 20, 40, 80),
                                 n_draws = 200L, seed = 1L,
                                 units = "g/kg")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bayesian")
  expect_equal(dim(post$samples), c(200L, 4L))
  expect_equal(post$metadata$bayesian_method, "laplace")
})

test_that("as_edaphos_posterior.edaphos_piml_bayes works too", {
  d <- .small_profile()
  fit <- piml_profile_fit_bayesian(depths = d$depths, values = d$values,
                                      method = "laplace")
  post <- as_edaphos_posterior(fit, newdepths = c(10, 20, 40, 80),
                                 n_draws = 100L)
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "bayesian")
})

test_that("calibrate pipeline works on a Pillar 2 posterior", {
  d <- .small_profile()
  fit <- piml_profile_fit_bayesian(depths = d$depths, values = d$values,
                                      method = "laplace")
  # Pseudo-calibration: the Laplace posterior mean at the training
  # depths acts as the truth stand-in (it interpolates the observed
  # values well for a 4-parameter model).
  post <- piml_bayes_posterior(fit, newdepths = d$depths,
                                 n_draws = 400L, seed = 3L)
  calib <- uncertainty_calibrate(post, truth = d$values)
  expect_true(is.finite(calib$crps))
  expect_true(is.finite(calib$point_rmse))
  # Reasonable in-sample fit: point RMSE should be < 1 g/kg.
  expect_lt(calib$point_rmse, 1.0)
})
