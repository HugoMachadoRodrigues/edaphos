skip_if_no_dagitty <- function() {
  skip_if_not_installed("dagitty")
}

test_that("causal_clorpt_dag and causal_cerrado_dag return dagitty objects", {
  skip_if_no_dagitty()
  g1 <- causal_clorpt_dag()
  g2 <- causal_cerrado_dag()
  expect_s3_class(g1, "dagitty")
  expect_s3_class(g2, "dagitty")
})

test_that("causal_adjustment_set finds a valid backdoor adjustment on Cerrado DAG", {
  skip_if_no_dagitty()
  g <- causal_cerrado_dag()
  adj <- causal_adjustment_set(g, exposure = "ndvi", outcome = "soc")
  expect_true(is.character(adj))
  # TWI, slope, map_mm are confounders of NDVI -> SOC; minimal set
  # should include at least one correct confounder.
  expect_true(length(adj) >= 1L)
})

test_that("causal_estimate_effect produces adjusted and naive coefficients", {
  skip_if_no_dagitty()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  res <- causal_estimate_effect(br_cerrado, g,
                                 exposure = "ndvi", outcome = "soc")
  expect_s3_class(res, "edaphos_causal_effect")
  expect_true(is.numeric(res$effect))
  expect_true(is.numeric(res$effect_naive))
  # For this synthetic DGP the naive effect is confounded upward via the
  # direct soil-wetness/erosion pathway; adjustment should change the
  # coefficient materially.
  expect_gt(abs(res$effect_naive - res$effect), 1e-3)
})

test_that("causal_estimate_effect honours an explicit adjustment vector", {
  skip_if_no_dagitty()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  res <- causal_estimate_effect(br_cerrado, g,
                                 exposure = "ndvi", outcome = "soc",
                                 adjustment = c("twi", "slope"))
  expect_equal(sort(res$adjustment), sort(c("twi", "slope")))
})

test_that("print.edaphos_causal_effect does not error", {
  skip_if_no_dagitty()
  data(br_cerrado, package = "edaphos")
  g <- causal_cerrado_dag()
  res <- causal_estimate_effect(br_cerrado, g,
                                 exposure = "ndvi", outcome = "soc")
  expect_output(print(res), "causal_effect")
})
