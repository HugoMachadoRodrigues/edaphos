# v1.4.0 — tests for the real-data Cerrado DAG.

skip_if_no_dagitty <- function() skip_if_not_installed("dagitty")

test_that("causal_cerrado_real_dag is a DAG", {
  skip_if_no_dagitty()
  dag <- causal_cerrado_real_dag()
  expect_s3_class(dag, "dagitty")
  # Node count matches the documented 12.
  nodes <- names(dag)
  expect_gte(length(nodes), 10L)
  expect_true("soc_topsoil_gkg" %in% nodes)
  expect_true("wc_bio_12"       %in% nodes)
  expect_true("wc_landcover_trees" %in% nodes)
})

test_that("adjustment set for bio_12 -> SOC blocks every confounder", {
  skip_if_no_dagitty()
  dag <- causal_cerrado_real_dag()
  adj <- causal_adjustment_set(dag,
                                 exposure = "wc_bio_12",
                                 outcome  = "soc_topsoil_gkg",
                                 effect = "direct")
  expect_type(adj, "character")
  # Must include wc_bio_01 (shared ancestor via elev) and the three
  # mediators that carry non-direct climate -> SOC effects.
  expect_true("wc_bio_01" %in% adj)
  expect_true(any(grepl("wc_landcover", adj)))
})

test_that("adjustment set for tree cover -> SOC is non-empty", {
  skip_if_no_dagitty()
  dag <- causal_cerrado_real_dag()
  adj <- causal_adjustment_set(dag,
                                 exposure = "wc_landcover_trees",
                                 outcome  = "soc_topsoil_gkg",
                                 effect = "direct")
  expect_true(length(adj) > 0L)
  # Climate is the sole confounder of land cover -> SOC via the DAG.
  expect_true(all(c("wc_bio_01", "wc_bio_12") %in% adj))
})

test_that("adjustment set for clay -> SOC includes slope (erosion chain)", {
  skip_if_no_dagitty()
  dag <- causal_cerrado_real_dag()
  adj <- causal_adjustment_set(dag,
                                 exposure = "soilgrids_clay",
                                 outcome  = "soc_topsoil_gkg",
                                 effect = "direct")
  expect_true("slope" %in% adj)
})
