skip_if_no_bart <- function() {
  skip_if_not_installed("dbarts")
  skip_if_not_installed("dagitty")
}

test_that("BART estimator returns the expected effect on br_cerrado", {
  skip_if_no_bart()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  set.seed(1)
  fit <- causal_estimate_effect(
    br_cerrado, g,
    exposure  = "ndvi", outcome = "soc",
    estimator = "bart",
    bart_kwargs = list(ndpost = 150L, nskip = 50L)
  )
  expect_s3_class(fit, "edaphos_causal_effect")
  expect_equal(fit$estimator, "bart")
  # Posterior credible interval must be a proper 2-element vector.
  expect_length(fit$effect_ci, 2L)
  expect_lt(fit$effect_ci[1], fit$effect_ci[2])
  # The BART point estimate and the LM estimate should agree to within
  # the width of the credible interval on a linear-by-design DGP.
  lm_fit <- causal_estimate_effect(br_cerrado, g,
                                    "ndvi", "soc", estimator = "lm")
  expect_lt(abs(fit$effect - lm_fit$effect),
            diff(as.numeric(fit$effect_ci)))
})

test_that("BART effect has a valid posterior draw vector", {
  skip_if_no_bart()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  set.seed(2)
  fit <- causal_estimate_effect(
    br_cerrado, g, "ndvi", "soc",
    estimator = "bart",
    bart_kwargs = list(ndpost = 120L, nskip = 50L)
  )
  expect_true(is.numeric(fit$posterior))
  expect_length(fit$posterior, 120L)
  expect_true(all(is.finite(fit$posterior)))
})

test_that("print.edaphos_causal_effect distinguishes lm and bart", {
  skip_if_no_bart()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  fit <- causal_estimate_effect(br_cerrado, g, "ndvi", "soc",
                                  estimator = "bart",
                                  bart_kwargs = list(ndpost = 50L,
                                                      nskip = 20L))
  expect_output(print(fit), "estimator: bart")
  expect_output(print(fit), "credible")
})
