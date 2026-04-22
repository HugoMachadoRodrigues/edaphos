# Pillar 1 v1.1.0 tests: structure learning via bnlearn.

skip_if_no_bnlearn <- function() {
  skip_if_not_installed("bnlearn")
  skip_if_not_installed("igraph")
}

.structure_fixture <- function(n = 300L, seed = 1L) {
  set.seed(seed)
  data(br_cerrado, package = "edaphos", envir = environment())
  br_cerrado[sample(nrow(br_cerrado), n), ]
}

test_that("causal_structure_learn(hc) returns a KG with DAG edges", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  kg <- causal_structure_learn(
    d,
    variables = c("elev", "slope", "twi", "map_mm", "ndvi", "soc"),
    method    = "hc"
  )
  expect_s3_class(kg, "edaphos_causal_kg")
  expect_gte(igraph::ecount(kg$graph), 3L)
  expect_true(igraph::is_dag(kg$graph))
  e <- causal_kg_edges(kg)
  expect_true(all(grepl("structure_learn\\(method=hc\\)", e$source)))
})

test_that("whitelist and blacklist are honoured", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  wl <- data.frame(from = c("elev", "map_mm"),
                    to   = c("twi",  "soc"))
  bl <- data.frame(from = c("soc"), to = c("elev"))
  kg <- causal_structure_learn(
    d,
    variables = c("elev", "slope", "twi", "map_mm", "soc"),
    method    = "hc",
    whitelist = wl,
    blacklist = bl
  )
  e <- causal_kg_edges(kg)
  # whitelist edges must appear
  expect_true(any(e$cause == "elev"   & e$effect == "twi"))
  expect_true(any(e$cause == "map_mm" & e$effect == "soc"))
  # blacklisted edge must NOT appear
  expect_false(any(e$cause == "soc" & e$effect == "elev"))
})

test_that("bootstrap variant attaches strength-based confidence", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  kg <- causal_structure_learn(
    d,
    variables = c("elev", "slope", "twi", "map_mm"),
    method    = "hc",
    bootstrap = TRUE,
    R_boot    = 30L,
    seed      = 1L
  )
  e <- causal_kg_edges(kg)
  expect_true(all(e$confidence >= 0.5))
  expect_true(all(e$confidence <= 1.0))
  # The source tag should announce the bootstrap.
  expect_true(all(grepl("boot=30", e$source)))
})

test_that("causal_structure_learn rejects <2 variables", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  expect_error(
    causal_structure_learn(d, variables = "elev", method = "hc"),
    regexp = "At least two"
  )
})

test_that("learned KG round-trips through save/load", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  kg <- causal_structure_learn(
    d,
    variables = c("elev", "slope", "twi", "map_mm"),
    method    = "hc"
  )
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  causal_kg_save(kg, f)
  kg2 <- causal_kg_load(f)
  expect_identical(causal_kg_edges(kg), causal_kg_edges(kg2))
})

test_that("causal_structure_learn + causal_augment_dag unions with an LLM KG", {
  skip_if_no_bnlearn()
  d <- .structure_fixture()
  kg_struct <- causal_structure_learn(
    d,
    variables = c("elev", "slope", "twi", "map_mm"),
    method    = "hc"
  )
  kg_llm <- causal_kg_new()
  kg_llm <- causal_kg_add_edge(kg_llm, "ndvi", "soc",
                                 source = "LLM mock", confidence = 0.9)
  # Confirm that the two KGs can be combined by adding edges of one to
  # the other via causal_kg_add_edge (which is what augment_dag does
  # internally for the KG side).
  for (i in seq_len(igraph::ecount(kg_llm$graph))) {
    e <- causal_kg_edges(kg_llm)
    kg_struct <- causal_kg_add_edge(
      kg_struct, e$cause[i], e$effect[i],
      source = e$source[i], evidence = e$evidence[i],
      confidence = e$confidence[i]
    )
  }
  expect_true(any(causal_kg_edges(kg_struct)$source == "LLM mock"))
})
