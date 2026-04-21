skip_if_no_igraph <- function() {
  skip_if_not_installed("igraph")
}
skip_if_no_dagitty <- function() {
  skip_if_not_installed("dagitty")
}

test_that("causal_kg_new() returns an empty KG", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  expect_s3_class(kg, "edaphos_causal_kg")
  expect_equal(nrow(causal_kg_edges(kg)), 0L)
})

test_that("causal_kg_add_edge normalises node names and stores metadata", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(
    kg, "Mean Annual Precipitation", "organic-matter accumulation",
    source     = "Ferreira 2021",
    evidence   = "MAP drives SOC accumulation.",
    confidence = 0.9
  )
  e <- causal_kg_edges(kg)
  expect_equal(e$cause,  "mean_annual_precipitation")
  expect_equal(e$effect, "organic_matter_accumulation")
  expect_equal(e$confidence, 0.9)
  expect_true(!is.na(e$timestamp))
})

test_that("duplicate edges merge (max confidence, concat evidence)", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precip", "soc",
                           source = "A", evidence = "text-A",
                           confidence = 0.7)
  kg <- causal_kg_add_edge(kg, "precip", "soc",
                           source = "B", evidence = "text-B",
                           confidence = 0.9)
  e <- causal_kg_edges(kg)
  expect_equal(nrow(e), 1L)
  expect_equal(e$confidence, 0.9)
  expect_true(grepl("text-A", e$evidence, fixed = TRUE))
  expect_true(grepl("text-B", e$evidence, fixed = TRUE))
})

test_that("self-loops are rejected", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  expect_error(
    causal_kg_add_edge(kg, "soc", "soc", confidence = 0.8),
    "Self-loops"
  )
})

test_that("introducing a cycle warns and keeps the edge (cycle check)", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "a", "b", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "b", "c", confidence = 0.9)
  expect_warning(
    causal_kg_add_edge(kg, "c", "a", confidence = 0.9),
    "cycle"
  )
})

test_that("causal_kg_to_dagitty honours min_confidence", {
  skip_if_no_igraph(); skip_if_no_dagitty()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "x", "y", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "w", "y", confidence = 0.4)
  dag_all <- causal_kg_to_dagitty(kg, min_confidence = 0.1)
  dag_hi  <- causal_kg_to_dagitty(kg, min_confidence = 0.7)
  expect_s3_class(dag_all, "dagitty")
  expect_s3_class(dag_hi,  "dagitty")
  expect_equal(nrow(dagitty::edges(dag_all)), 2L)
  expect_equal(nrow(dagitty::edges(dag_hi)),  1L)
})

test_that("print.edaphos_causal_kg produces output", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "x", "y", confidence = 0.9)
  expect_output(print(kg), "edaphos_causal_kg")
})

test_that("causal_augment_dag merges KG into base DAG, preserves acyclicity", {
  skip_if_no_igraph(); skip_if_no_dagitty()
  base <- causal_cerrado_dag()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "mean_annual_precipitation", "soc",
                           confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "slope", "erosion", confidence = 0.85)
  kg <- causal_kg_add_edge(kg, "erosion", "soc", confidence = 0.8)
  aug <- causal_augment_dag(base, kg, min_confidence = 0.7)
  diff <- causal_augment_diff(base, aug)
  expect_true("kg" %in% diff$origin)
  expect_true("base" %in% diff$origin)
  expect_true(dagitty::isAcyclic(aug))
})

test_that("causal_augment_dag rejects KG edges that would create a cycle", {
  skip_if_no_igraph(); skip_if_no_dagitty()
  base <- dagitty::dagitty("dag { a -> b -> c }")
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "c", "a", confidence = 0.9)  # cycle
  expect_warning(
    aug <- causal_augment_dag(base, kg, min_confidence = 0.5),
    "cycle"
  )
  expect_true(dagitty::isAcyclic(aug))
})
