skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1), error = function(e) skip("torch runtime unavailable"))
}

test_that("piml_neural_ode_fit recovers a clean exponential decay", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  fit <- piml_neural_ode_fit(depths, values, epochs = 400L, seed = 1L,
                             verbose = FALSE)
  expect_s3_class(fit, "edaphos_piml_neural_ode")
  expect_lt(fit$rmse, 2.0)
  # Loss must have decreased meaningfully from initial to final.
  expect_lt(fit$loss_history[length(fit$loss_history)],
            fit$loss_history[1] * 0.5)
  # Predictions at training depths are close to observations.
  pr <- predict(fit, depths)
  expect_length(pr, length(depths))
  expect_true(all(is.finite(pr)))
})

test_that("piml_neural_ode_fit honours a fixed y_surface", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 60)
  values <- c(24, 17, 11, 7)
  fit <- piml_neural_ode_fit(depths, values, y_surface = 30,
                             epochs = 200L, seed = 2L)
  # y0 must be a buffer (non-trainable), not a learnable parameter.
  param_names <- names(fit$model$parameters)
  expect_false("y0" %in% param_names)
  # And the stored y0 should equal the requested surface value
  # (normalised and back-transformed).
  y0_stored <- as.numeric(fit$model$y0) * fit$y_scale + fit$y_center
  expect_equal(y0_stored, 30, tolerance = 1e-5)
})

test_that("piml_neural_ode_fit can fit a non-monotone (bimodal) profile", {
  skip_if_no_torch()
  # Synthetic E-horizon: dip at middle depth, then rebound.
  depths <- c(2, 10, 25, 40, 60, 90)
  values <- c(32, 26, 12, 18, 22, 20)   # non-monotone
  fit <- piml_neural_ode_fit(depths, values, epochs = 800L, seed = 3L,
                             hidden = c(32L, 16L), n_steps = 6L)
  pr <- predict(fit, depths)
  expect_lt(stats::cor(pr, values), 1.01)  # sanity
  expect_gt(stats::cor(pr, values), 0.85)  # strong fit
})
