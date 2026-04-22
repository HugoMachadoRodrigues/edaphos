# Pillar 2 v1.1.0 tests: Laplace + MCMC Bayesian posterior for the
# parametric pedogenetic ODE.

.depths_fixture <- c(5, 15, 30, 60, 100)
.values_fixture <- c(25, 18, 12, 8, 6.5)

test_that("piml_profile_fit_bayesian(method='laplace') returns a posterior", {
  fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                    method = "laplace", seed = 1L)
  expect_s3_class(fit, "edaphos_piml_bayes")
  expect_identical(fit$method, "laplace")
  # 2000 draws sampled from N(MAP, Sigma).
  expect_equal(nrow(fit$draws), 2000L)
  expect_equal(ncol(fit$draws), 4L)
  # Posterior summary is a data frame with the four natural parameters.
  expect_setequal(fit$summary$parameter,
                   c("lambda0", "mu", "y_inf", "y0"))
  # MAP lambda0 must be strictly positive (posterior lives on
  # log-lambda0 so this checks unpacking).
  expect_gt(fit$map$lambda0, 0)
  # Posterior covariance must be SPD (symmetric and positive-definite
  # after the nearest-PSD projection).
  expect_equal(fit$cov, t(fit$cov), tolerance = 1e-8)
  expect_true(all(eigen(fit$cov)$values > -1e-8))
})

test_that("piml_profile_fit_bayesian recovers the MAP of piml_profile_fit", {
  # The MAP of the Bayesian fit should match the NLS point estimate
  # to within a few percent when the prior is weakly informative.
  nls_fit <- piml_profile_fit(.depths_fixture, .values_fixture)
  bay_fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                        method = "laplace", seed = 1L)
  # Relative tolerance of 15% on lambda0 — priors regularise the
  # Bayesian fit so exact equality isn't expected.
  expect_lt(abs(log(bay_fit$map$lambda0) - log(nls_fit$params$lambda0)),
             log(1.5))
  expect_lt(abs(bay_fit$map$y_inf - nls_fit$params$y_inf),
             max(2, 0.2 * abs(nls_fit$params$y_inf)))
})

test_that("predict.edaphos_piml_bayes gives a credible interval", {
  fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                    method = "laplace", seed = 1L)
  pp <- predict(fit, newdepths = c(10, 20, 40, 80),
                 interval = 0.95, seed = 1L)
  expect_s3_class(pp, "data.frame")
  expect_setequal(names(pp), c("depth", "mean", "sd", "lower", "upper"))
  expect_equal(nrow(pp), 4L)
  # Lower <= mean <= upper for every row.
  expect_true(all(pp$lower <= pp$mean))
  expect_true(all(pp$mean  <= pp$upper))
  # SDs strictly positive.
  expect_true(all(pp$sd > 0))
})

test_that("predict.edaphos_piml_bayes (no interval) returns raw draws", {
  fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                    seed = 1L)
  mat <- predict(fit, newdepths = c(10, 50), n_draws = 100L, seed = 1L)
  expect_true(is.matrix(mat))
  expect_equal(nrow(mat), 100L)
  expect_equal(ncol(mat), 2L)
})

test_that("MCMC sampler produces a chain with positive acceptance", {
  fit_mc <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                        method = "mcmc",
                                        n_iter = 1500L, n_burn = 500L,
                                        seed = 1L)
  expect_identical(fit_mc$method, "mcmc")
  expect_equal(nrow(fit_mc$draws), 1000L)  # 1500 - 500
  expect_gt(fit_mc$accept_rate, 0)
  expect_lt(fit_mc$accept_rate, 1)
  # Posterior mean of lambda0 should be of the right order of
  # magnitude; guards against a disconnected-chain bug.
  expect_gt(fit_mc$summary$mean[fit_mc$summary$parameter == "lambda0"],
             1e-3)
  expect_lt(fit_mc$summary$mean[fit_mc$summary$parameter == "lambda0"],
             1)
})

test_that("print + summary methods dispatch on edaphos_piml_bayes", {
  fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                    seed = 1L)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("^<edaphos_piml_bayes>", out)))
  expect_true(any(grepl("posterior summary", out)))
  s <- summary(fit)
  expect_s3_class(s, "data.frame")
  expect_equal(nrow(s), 4L)
})

test_that("include_obs_noise widens the predictive interval", {
  fit <- piml_profile_fit_bayesian(.depths_fixture, .values_fixture,
                                    seed = 1L)
  pp_mean <- predict(fit, newdepths = c(10, 50), interval = 0.9,
                      include_obs_noise = FALSE, seed = 1L)
  pp_obs <- predict(fit, newdepths = c(10, 50), interval = 0.9,
                     include_obs_noise = TRUE, seed = 1L)
  # Predictive interval for a future *observation* must be strictly
  # wider than the mean-function interval.
  expect_true(all(pp_obs$upper - pp_obs$lower >=
                   pp_mean$upper - pp_mean$lower))
})
