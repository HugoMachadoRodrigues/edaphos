test_that("piml_profile_predict returns one value per requested depth", {
  params <- list(lambda0 = 0.05, mu = 0.01, y_inf = 5, y0 = 25)
  pr <- piml_profile_predict(params, depths = c(5, 20, 50, 100))
  expect_length(pr, 4L)
  expect_true(all(is.finite(pr)))
  # Exponential decay when mu = 0 => monotone toward y_inf
  expect_true(all(diff(pr) <= 0))   # decreasing
  expect_gte(min(pr), params$y_inf - 1e-6)
})

test_that("piml_profile_fit recovers a monotone decay profile", {
  depths <- c(5, 15, 30, 60, 100)
  values <- c(25, 18, 12, 8, 6.5)
  fit <- piml_profile_fit(depths, values)
  expect_s3_class(fit, "edaphos_piml_profile")
  expect_true(fit$converged)
  expect_lt(fit$rmse, 0.5)                # tight fit expected
  # y_inf must fall below the deepest observation
  expect_lt(fit$params$y_inf, min(values) + 2)
  # Round-trip predictions at the training depths are close to obs
  pr <- predict(fit, depths)
  expect_lt(max(abs(pr - values)), 1.0)
})

test_that("piml_profile_fit handles a fixed y_surface", {
  depths <- c(10, 25, 50, 80)
  values <- c(22, 17, 10, 6)
  fit <- piml_profile_fit(depths, values, y_surface = 28)
  expect_equal(fit$params$y0, 28)
  # Shouldn't include y0 in the free parameter vector
  expect_true(!"y0" %in% names(fit$theta))
})

test_that("piml_profile_fit requires >= 2 observations", {
  expect_error(piml_profile_fit(5, 25), "length")
})

test_that("piml_profile_fit_group fits multiple pedons", {
  d <- data.frame(
    id    = rep(c("A", "B", "C"), each = 5),
    depth = rep(c(5, 15, 30, 60, 100), 3),
    val   = c(30, 22, 15, 9, 7,      # A: steep decay
              18, 16, 13, 11, 10,    # B: mild decay
              50, 30, 18, 10, 7)     # C: very steep
  )
  fits <- piml_profile_fit_group(d, id = "id", depth = "depth",
                                 value = "val")
  expect_named(fits, c("A", "B", "C"))
  expect_true(all(sapply(fits, inherits, "edaphos_piml_profile")))
  # Every pedon should be well-fit in absolute terms.
  expect_true(all(sapply(fits, function(f) f$rmse) < 1.5))
  # Pedon C starts the highest and ends near 7 -> its asymptote must
  # sit below the initial value by more than pedon B's (which is flat).
  drop_C <- fits$C$params$y0 - fits$C$params$y_inf
  drop_B <- fits$B$params$y0 - fits$B$params$y_inf
  expect_gt(drop_C, drop_B)
})

test_that("print.edaphos_piml_profile does not error", {
  fit <- piml_profile_fit(c(5, 20, 50), c(25, 14, 7))
  expect_output(print(fit), "piml_profile")
})
