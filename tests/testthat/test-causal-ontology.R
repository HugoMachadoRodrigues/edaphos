skip_if_no_igraph <- function() skip_if_not_installed("igraph")

test_that("causal_ontology_cerrado() returns a typed frame", {
  v <- causal_ontology_cerrado()
  expect_s3_class(v, "data.frame")
  expect_true(all(c("term", "category") %in% names(v)))
  expect_true("soc" %in% v$term)
  expect_true("slope" %in% v$term)
})

test_that("exact matcher recognises already-canonical labels", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "slope", "soc", confidence = 0.9)
  m <- causal_kg_alignment(kg)
  expect_true(all(m$method[m$original %in% c("slope", "soc")] == "exact"))
  expect_equal(m$canonical[m$original == "slope"], "slope")
  expect_equal(m$canonical[m$original == "soc"],   "soc")
})

test_that("substring matcher collapses near-canonical labels", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "topsoil_nitrogen", "productivity",
                           confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "native_vegetation", "ndvi",
                           confidence = 0.9)
  m <- causal_kg_alignment(kg)
  expect_equal(m$canonical[m$original == "topsoil_nitrogen"], "nitrogen")
  expect_equal(m$method[m$original == "topsoil_nitrogen"], "substring")
  expect_equal(m$canonical[m$original == "native_vegetation"], "vegetation")
})

test_that("fuzzy matcher picks the Levenshtein-nearest term", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipetation", "soc", confidence = 0.9)
  m <- causal_kg_alignment(kg, method = c("exact", "fuzzy"),
                            max_distance = 3L)
  expect_equal(m$canonical[m$original == "precipetation"], "precipitation")
  expect_equal(m$method[m$original == "precipetation"], "fuzzy")
})

test_that("causal_kg_rename collapses synonymous nodes and merges edges", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "native_vegetation", "nitrogen",
                           confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "vegetation", "nitrogen",
                           confidence = 0.7)  # duplicate once renamed
  m  <- causal_kg_alignment(kg)
  kg2 <- causal_kg_rename(kg, m)
  edges <- causal_kg_edges(kg2)
  # After rename both incoming edges collapse to vegetation -> nitrogen
  expect_equal(nrow(edges), 1L)
  expect_equal(edges$cause,  "vegetation")
  expect_equal(edges$effect, "nitrogen")
  expect_equal(edges$confidence, 0.9)
})
