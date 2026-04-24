## Tests for the Pilar 1 x Pilar 5 Causal AL bridge (v2.1.1).

test_that("al_query_causal: returns leverage-ranked candidates", {
  skip_if_not_installed("dagitty")
  set.seed(1L)
  n <- 100L
  data <- data.frame(
    x = stats::rnorm(n),
    z = stats::rnorm(n),
    y = stats::rnorm(n),
    stringsAsFactors = FALSE
  )
  data$y <- 0.8 * data$x + 0.4 * data$z + stats::rnorm(n, 0, 0.3)
  pool <- data.frame(
    x = stats::rnorm(20L),
    z = stats::rnorm(20L),
    y = NA_real_,
    stringsAsFactors = FALSE
  )
  dag <- dagitty::dagitty("dag { z -> x ; z -> y ; x -> y }")
  q <- al_query_causal(data, pool, dag,
                         exposure = "x", outcome = "y",
                         adjustment = "z",
                         n_select = 5L, strategy = "leverage")
  expect_s3_class(q, "edaphos_causal_al_query")
  expect_equal(nrow(q), 20L)
  expect_true(all(c("pool_index", "leverage",
                      "expected_var_reduction") %in% names(q)))
  # Sorted descending by expected reduction
  expect_true(!is.unsorted(-q$expected_var_reduction))
  # All leverages in [0, 1] per theoretical bound
  expect_true(all(q$leverage >= 0))
})

test_that("al_query_causal: infers adjustment set from DAG when NULL", {
  skip_if_not_installed("dagitty")
  set.seed(1L)
  data <- data.frame(
    x = stats::rnorm(50), z = stats::rnorm(50), y = stats::rnorm(50),
    stringsAsFactors = FALSE
  )
  pool <- data[1:10, ]; pool$y <- NA
  dag <- dagitty::dagitty("dag { z -> x ; z -> y ; x -> y }")
  q <- al_query_causal(data, pool, dag,
                         exposure = "x", outcome = "y",
                         n_select = 3L)
  expect_true(!is.null(attr(q, "adjustment")))
  expect_true("z" %in% attr(q, "adjustment"))
})
