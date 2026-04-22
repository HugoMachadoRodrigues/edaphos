# Pillar 2 v1.1.0 tests: Neural ODE deep ensemble.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  if (!torch::torch_is_installed()) {
    skip("torch backend is not installed")
  }
}

test_that("piml_neural_ode_fit_ensemble trains K independent members", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  ens <- piml_neural_ode_fit_ensemble(depths, values,
                                        K = 3L, epochs = 80L,
                                        seed = 1L)
  expect_s3_class(ens, "edaphos_piml_neural_ode_ensemble")
  expect_equal(ens$K, 3L)
  expect_length(ens$members, 3L)
  expect_true(all(vapply(ens$members,
                          inherits, logical(1L),
                          "edaphos_piml_neural_ode")))
  expect_equal(nrow(ens$fitted), 3L)
  expect_equal(ncol(ens$fitted), length(depths))
  expect_true(is.finite(ens$rmse))
})

test_that("predict.edaphos_piml_neural_ode_ensemble returns draws + CI", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  ens <- piml_neural_ode_fit_ensemble(depths, values,
                                        K = 3L, epochs = 60L,
                                        seed = 1L)
  draws <- predict(ens, newdepths = c(10, 40))
  expect_true(is.matrix(draws))
  expect_equal(nrow(draws), 3L)
  expect_equal(ncol(draws), 2L)

  tidy <- predict(ens, newdepths = c(10, 40), interval = 0.9)
  expect_s3_class(tidy, "data.frame")
  expect_setequal(names(tidy), c("depth", "mean", "sd", "lower", "upper"))
  expect_equal(nrow(tidy), 2L)
  expect_true(all(tidy$lower <= tidy$mean))
  expect_true(all(tidy$mean  <= tidy$upper))
})

test_that("include_obs_noise widens the predictive interval on average", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  # Need K large enough for a stable quantile-based CI. With K < 5
  # the 90% quantile interval is extremely coarse and the
  # observation-noise draw can shrink it on an unlucky seed.
  ens <- piml_neural_ode_fit_ensemble(depths, values, K = 6L,
                                        epochs = 50L, seed = 1L)
  pp_mean <- predict(ens, newdepths = c(10, 40), interval = 0.9,
                      include_obs_noise = FALSE)
  pp_obs <- predict(ens, newdepths = c(10, 40), interval = 0.9,
                     include_obs_noise = TRUE, seed = 1L)
  expect_gt(mean(pp_obs$upper  - pp_obs$lower),
             mean(pp_mean$upper - pp_mean$lower))
})

test_that("piml_neural_ode_fit_ensemble rejects K < 2", {
  expect_error(
    piml_neural_ode_fit_ensemble(c(5, 10), c(20, 10), K = 1L),
    regexp = "K >= 2L"
  )
})
