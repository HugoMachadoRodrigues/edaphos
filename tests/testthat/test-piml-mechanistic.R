## piml_profile_fit_mechanistic() -- the steady-state advection-reaction
## profile model of Pillar 2 -- had no test at all. These check the closed
## forms it is built on and that the fit returns what it documents.

p_true <- list(A = 4, B = 20, lambda = 0.04, z_r = 30, y0 = 28)
p_true$beta <- 1 / p_true$z_r

test_that("the layer mean is the depth-average of the point solution", {
  # .pmech_layer_mean() integrates .pmech_solution() analytically. Check it
  # against numerical quadrature, on both branches of the solution: the
  # general one and the confluent one where lambda equals 1 / z_r.
  for (p in list(p_true,
                 modifyList(p_true, list(lambda = 1 / 30)))) {
    for (lim in list(c(0, 10), c(10, 35), c(60, 140))) {
      num <- stats::integrate(function(z) edaphos:::.pmech_solution(z, p),
                              lim[1], lim[2], rel.tol = 1e-10)$value /
        diff(lim)
      expect_equal(edaphos:::.pmech_layer_mean(lim[1], lim[2], p), num,
                   tolerance = 1e-8)
    }
  }
})

test_that("a noise-free profile is reproduced, at its depths and between them", {
  z  <- c(2.5, 7.5, 15, 25, 40, 60, 85, 115, 150)
  y  <- edaphos:::.pmech_solution(z, p_true)
  fit <- piml_profile_fit_mechanistic(z, y)
  expect_s3_class(fit, "edaphos_piml_mech")
  expect_true(fit$converged)
  expect_lt(fit$rmse, 0.02 * mean(y))

  # Point mode: $fitted is the solution at the data depths, and predict()
  # gives the same numbers.
  expect_equal(fit$fitted, predict(fit, z), tolerance = 1e-12)
  # Between the data depths it should follow the curve that generated them.
  znew <- c(10, 32, 70, 130)
  truth <- edaphos:::.pmech_solution(znew, p_true)
  expect_lt(max(abs(predict(fit, znew) - truth)), 0.05 * mean(y))
  # Every parameter is positive by construction (log-scale parameters).
  expect_true(all(unlist(fit$params[c("A", "B", "lambda", "z_r", "y0")]) > 0))
})

test_that("a fixed surface value is used as given, not re-estimated", {
  z <- c(5, 15, 30, 50, 80, 120)
  y <- edaphos:::.pmech_solution(z, p_true)
  fit <- piml_profile_fit_mechanistic(z, y, y_surface = 31)
  expect_identical(fit$params$y0, 31)
  expect_equal(predict(fit, 0), 31)
})

test_that("with horizon bounds, $fitted is the layer mean, not the midpoint", {
  top <- c(0, 10, 20, 40, 60, 100); bottom <- c(10, 20, 40, 60, 100, 150)
  mid <- (top + bottom) / 2
  y   <- edaphos:::.pmech_layer_mean(top, bottom, p_true)
  fit <- piml_profile_fit_mechanistic(mid, y, top = top, bottom = bottom)
  expect_equal(fit$fitted,
               edaphos:::.pmech_layer_mean(top, bottom, fit$params),
               tolerance = 1e-12)
  # The exponential curve is convex, so the layer mean and the midpoint value
  # differ; if the fit silently used points, these would coincide.
  expect_gt(max(abs(fit$fitted - predict(fit, mid))), 1e-3)
})

test_that("inputs it cannot model are refused", {
  z <- c(5, 15, 30, 50); y <- c(20, 12, 8, 5)
  expect_error(piml_profile_fit_mechanistic(z, c(20, 12, 0, 5)),
               "positive concentration")
  expect_error(piml_profile_fit_mechanistic(z, y[1:3]))
  expect_error(piml_profile_fit_mechanistic(z, y, top = c(0, 10, 20, 40)))
  expect_error(piml_profile_fit_mechanistic(z[1:2], y[1:2]))
})
