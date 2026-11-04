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

test_that("print.edaphos_causal_effect states the naive-adjusted difference, not a verdict", {
  # Adjustment that barely moves the estimate: the old print still called
  # the naive effect "likely confounded".
  x <- structure(list(estimator = "lm", adjustment = "slope",
                      effect = -0.07328, effect_ci = c(-0.217, 0.07044),
                      effect_naive = -0.07384, effect_type = "total",
                      exposure = "clay", outcome = "soc"),
                 class = "edaphos_causal_effect")
  out <- paste(utils::capture.output(print(x)), collapse = "\n")
  expect_false(grepl("confounded", out, fixed = TRUE))
  expect_match(out, sprintf("adjusted - naive = %.4g", -0.07328 - -0.07384),
               fixed = TRUE)
})

.mk_dag_test <- function(p) {
  structure(list(pooled = data.frame(estimate = rep(0.1, length(p)),
                                     p.value = p),
                 spatial = NULL, n = 120L, n_tests = length(p),
                 n_rejected = sum(p < 0.05), n_rejected_spatial = NA_integer_,
                 max_abs_r = 0.1, alpha = 0.05,
                 nodes_tested = c("a", "b", "c"), nodes_without_data = character(0)),
            class = "edaphos_dag_test")
}

test_that("print.edaphos_dag_test rests its verdict on a Holm adjustment", {
  # 66 tests, 6 unadjusted rejections between p = 0.01 and 0.04, nothing
  # that survives Holm: about what a TRUE graph produces (3.3 expected).
  # The old rule ("any p < alpha") declared this graph incompatible.
  p <- c(seq(0.01, 0.04, length.out = 6), seq(0.1, 1, length.out = 60))
  out <- paste(utils::capture.output(print(.mk_dag_test(p))), collapse = "\n")
  expect_match(out, "6 (3.3 expected if all hold)", fixed = TRUE)
  expect_match(out, "Holm FWER 5%     : 0", fixed = TRUE)
  expect_false(grepl("not compatible", out, fixed = TRUE))
  expect_match(out, "No implied independence is rejected after a Holm", fixed = TRUE)

  # One test far beyond any multiplicity correction does reject the graph.
  p2 <- replace(p, 1L, 1e-10)
  stopifnot(sum(stats::p.adjust(p2, "holm") < 0.05) == 1L)
  out2 <- paste(utils::capture.output(print(.mk_dag_test(p2))), collapse = "\n")
  expect_match(out2, "rejects 1 implied independency after a Holm", fixed = TRUE)
  expect_match(out2, "not compatible", fixed = TRUE)
})

test_that("causal_dag_test records the Holm count it prints", {
  skip_if_not_installed("dagitty")
  prof <- suppressWarnings(suppressMessages(edaphos_example_profiles()))
  tst <- causal_dag_test(causal_cerrado_real_dag(), prof)
  expect_identical(tst$n_rejected_holm,
                   as.integer(sum(stats::p.adjust(tst$pooled$p.value, "holm") <
                                    tst$alpha)))
  expect_lte(tst$n_rejected_holm, tst$n_rejected)
  expect_true(is.na(tst$n_rejected_spatial_holm))
})
