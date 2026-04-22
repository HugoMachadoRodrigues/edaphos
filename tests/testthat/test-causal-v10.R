# Pillar 1 v1.0.0 tests: KG persistence, Turtle export, edge
# ranking, and parallel AGROVOC alignment plumbing.
#
# Every network-dependent path is either mocked via
# `httr2::with_mocked_responses()` or gated on internet availability
# so the suite stays green on a headless CI runner.

skip_if_no_igraph <- function() {
  skip_if_not_installed("igraph")
}

make_toy_kg <- function() {
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                             source = "Jenny 1941", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                             source = "Minasny 2017", confidence = 0.85)
  kg <- causal_kg_add_edge(kg, "precipitation", "soc",
                             source = "Ferreira 2021", confidence = 0.80)
  kg <- causal_kg_add_edge(kg, "slope", "soc",
                             source = "Jenny 1941", confidence = 0.7)
  kg <- causal_kg_add_edge(kg, "clay", "cec",
                             source = "Random 2020", confidence = 0.95,
                             evidence = "High clay content raises CEC.")
  kg
}

# --- (i) persistence: save / load -------------------------------------------

test_that("causal_kg_save + causal_kg_load round-trip the edge list", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  causal_kg_save(kg, f)
  expect_true(file.exists(f))

  kg2 <- causal_kg_load(f)
  expect_s3_class(kg2, "edaphos_causal_kg")
  # Edge lists must be identical up to the merge-driven canonical
  # ordering.
  expect_identical(causal_kg_edges(kg), causal_kg_edges(kg2))
})

test_that("causal_kg_save writes a self-describing payload", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  causal_kg_save(kg, f)
  payload <- readRDS(f)
  expect_identical(payload$format_version, "edaphos_causal_kg/1")
  expect_true(grepl("\\d{4}-\\d{2}-\\d{2}", payload$saved_at))
  expect_true(is.data.frame(payload$edges))
  expect_true(nrow(payload$edges) == 3L)  # duplicate precipitation->soc merges
})

test_that("causal_kg_load rejects a non-edaphos RDS", {
  skip_if_no_igraph()
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  saveRDS(list(format_version = "some/other"), f)
  expect_error(causal_kg_load(f), "does not look like a saved edaphos KG")
})

test_that("causal_kg_load on an empty KG returns a valid empty KG", {
  skip_if_no_igraph()
  kg_empty <- causal_kg_new()
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  causal_kg_save(kg_empty, f)
  kg2 <- causal_kg_load(f)
  expect_s3_class(kg2, "edaphos_causal_kg")
  expect_equal(nrow(causal_kg_edges(kg2)), 0L)
})

# --- (ii) Turtle export -----------------------------------------------------

test_that("causal_kg_to_turtle returns a parseable-looking document", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  ttl <- causal_kg_to_turtle(kg)
  expect_type(ttl, "character")
  expect_length(ttl, 1L)
  # Required prefix declarations
  expect_true(grepl("@prefix ed: <https://edaphos.io/kg/node/>", ttl))
  expect_true(grepl("@prefix eds: <https://edaphos.io/schema#>", ttl))
  expect_true(grepl("@prefix rdf: ",  ttl))
  expect_true(grepl("@prefix prov:",  ttl))
  # Schema
  expect_true(grepl("eds:Causes a rdf:Property", ttl))
  # Reified edge: precipitation -> soc with 3 eds:source lines
  expect_true(grepl("edge:precipitation__soc", ttl))
  expect_true(grepl("rdf:predicate eds:Causes", ttl))
  # "Jenny 1941" is cited on two edges in the toy KG (precipitation
  # -> soc and slope -> soc), so it appears as an eds:source twice.
  # "Minasny 2017" is a unique source on the merged 3-source edge
  # so it must appear exactly once.
  ncount <- length(gregexpr('eds:source "Minasny 2017"', ttl,
                              fixed = TRUE)[[1L]])
  expect_equal(ncount, 1L)
})

test_that("causal_kg_to_turtle writes to a path when given one", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  f <- tempfile(fileext = ".ttl")
  on.exit(unlink(f), add = TRUE)
  out <- causal_kg_to_turtle(kg, path = f)
  expect_identical(out, f)
  expect_true(file.exists(f))
  # File must start with a prefix declaration.
  first <- readLines(f, n = 1L)
  expect_true(grepl("^@prefix ", first))
})

test_that("causal_kg_to_turtle rejects a non-terminated base URI", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  expect_error(causal_kg_to_turtle(kg, base_uri = "https://bad"),
                regexp = "must end")
})

test_that("causal_kg_to_turtle escapes quotes inside evidence", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "a", "b",
                             source   = "Sneaky 2024",
                             evidence = "\"Quoted\" evidence here",
                             confidence = 0.7)
  ttl <- causal_kg_to_turtle(kg)
  # The embedded double-quote must be backslash-escaped per Turtle
  # STRING_LITERAL_QUOTE production; the bare quote would break
  # parsing.
  expect_true(grepl('eds:evidence "\\\\"Quoted\\\\"', ttl))
})

test_that("causal_kg_to_turtle handles an empty KG without crashing", {
  skip_if_no_igraph()
  kg <- causal_kg_new()
  ttl <- causal_kg_to_turtle(kg)
  expect_type(ttl, "character")
  expect_true(grepl("@prefix ed:",       ttl))
  expect_true(grepl("eds:Causes",        ttl))
  expect_false(grepl("rdf:Statement",    ttl))
})

# --- (iii) summary + rank ---------------------------------------------------

test_that("summary.edaphos_causal_kg counts nodes, edges, sources", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  s <- summary(kg)
  expect_s3_class(s, "edaphos_causal_kg_summary")
  expect_equal(s$n_nodes, 5L)     # precipitation, soc, slope, clay, cec
  expect_equal(s$n_edges, 3L)     # after precipitation->soc merge
  expect_equal(s$n_sources, 4L)   # Jenny (twice, dedup'd), Minasny, Ferreira, Random
  expect_true(s$dag)
  out <- utils::capture.output(print(s))
  expect_true(any(grepl("^<edaphos_causal_kg_summary>", out)))
})

test_that("causal_kg_rank_edges ranks by n_sources first, confidence second", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  r <- causal_kg_rank_edges(kg, by = c("n_sources", "mean_confidence"))
  expect_s3_class(r, "data.frame")
  expect_equal(nrow(r), 3L)
  expect_equal(r$cause[1L],  "precipitation")
  expect_equal(r$effect[1L], "soc")
  expect_equal(r$n_sources[1L], 3L)
  # Second place: clay->cec (1 source, conf 0.95) beats slope->soc
  # (1 source, conf 0.7) because mean_confidence breaks the tie.
  expect_equal(r$cause[2L],  "clay")
  expect_equal(r$effect[2L], "cec")
})

test_that("causal_kg_rank_edges rejects an unknown metric", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  expect_error(causal_kg_rank_edges(kg, by = "not_a_metric"),
                regexp = "must be any subset")
})

test_that("causal_kg_rank_edges handles an empty KG", {
  skip_if_no_igraph()
  r <- causal_kg_rank_edges(causal_kg_new())
  expect_s3_class(r, "data.frame")
  expect_equal(nrow(r), 0L)
})

test_that("causal_kg_rank_edges applies AGROVOC support from alignment", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  alignment <- data.frame(
    original  = c("precipitation", "soc", "slope", "clay", "cec"),
    canonical = c("precipitation", "soil_organic_carbon", NA,
                   "clay_soils", NA),
    method    = c("agrovoc", "agrovoc", "none", "agrovoc", "none"),
    distance  = c(0, 4, NA, 6, NA),
    uri       = c("http://aims.fao.org/aos/agrovoc/c_x1",
                   "http://aims.fao.org/aos/agrovoc/c_x2",
                   NA,
                   "http://aims.fao.org/aos/agrovoc/c_x3",
                   NA),
    stringsAsFactors = FALSE
  )
  r <- causal_kg_rank_edges(kg, by = c("n_sources", "agrovoc_support"),
                              alignment = alignment)
  # precipitation->soc : both resolved -> support = 1
  expect_equal(r$agrovoc_support[r$cause == "precipitation" &
                                   r$effect == "soc"], 1)
  # slope->soc : slope unresolved, soc resolved -> support = 0.5
  expect_equal(r$agrovoc_support[r$cause == "slope" &
                                   r$effect == "soc"], 0.5)
  # clay->cec : clay resolved, cec unresolved -> support = 0.5
  expect_equal(r$agrovoc_support[r$cause == "clay" &
                                   r$effect == "cec"], 0.5)
  expect_true("agrovoc_cause"  %in% names(r))
  expect_true("agrovoc_effect" %in% names(r))
})

test_that("causal_kg_rank_edges(top_n) caps the returned rows", {
  skip_if_no_igraph()
  kg <- make_toy_kg()
  r <- causal_kg_rank_edges(kg, by = "n_sources", top_n = 1L)
  expect_equal(nrow(r), 1L)
})

# --- (iv) AGROVOC batch dispatch (mocked) -----------------------------------

.mock_agrovoc_response <- function(term) {
  body <- sprintf(
    '{"results":{"bindings":[{"uri":{"value":"http://aims.fao.org/aos/agrovoc/c_mock"},"label":{"value":"%s mock label"}}]}}',
    term
  )
  # Headers must be a named *list*, not a named character vector —
  # httr2::response() discards the latter's names on construction.
  httr2::response(status_code = 200L,
                   headers = list("Content-Type" =
                                     "application/sparql-results+json"),
                   body = charToRaw(body))
}

test_that("agrovoc_align_batch dispatches each term and merges responses", {
  skip_if_not_installed("httr2")
  # Sequence of mocked responses that `with_mocked_responses()` hands
  # back to each `req_perform()` call. The test runs at
  # `max_active = 1L` so the sequential fallback path is exercised —
  # httr2::with_mocked_responses() does not intercept
  # req_perform_parallel().
  mocks <- list(
    .mock_agrovoc_response("clay"),
    .mock_agrovoc_response("humus"),
    .mock_agrovoc_response("ndvi")
  )
  out <- httr2::with_mocked_responses(mocks, {
    causal_ontology_agrovoc_align_batch(
      c("clay", "humus", "ndvi"), max_active = 1L, max_retries = 0L
    )
  })
  expect_equal(nrow(out), 3L)
  expect_true(all(!is.na(out$uri)))
  expect_true(all(grepl("mock label$", out$label)))
})

test_that("agrovoc_align_batch short-circuits cached terms", {
  skip_if_not_installed("httr2")
  cache_path <- tempfile(fileext = ".rds")
  on.exit(unlink(cache_path), add = TRUE)
  # Prime the cache with "clay".
  saveRDS(list(clay = data.frame(term = "clay",
                                   uri = "http://mock/c_prev",
                                   label = "cached clay",
                                   distance = 0,
                                   stringsAsFactors = FALSE)),
          cache_path)
  # Only "humus" should trigger a live call.
  mocks <- list(.mock_agrovoc_response("humus"))
  out <- httr2::with_mocked_responses(mocks, {
    causal_ontology_agrovoc_align_batch(
      c("clay", "humus"), cache_path = cache_path,
      max_active = 1L, max_retries = 0L
    )
  })
  expect_equal(nrow(out), 2L)
  expect_equal(out$label[out$term == "clay"], "cached clay")
  expect_equal(out$uri[out$term == "humus"],
                "http://aims.fao.org/aos/agrovoc/c_mock")
})

test_that("agrovoc_align_batch handles empty input", {
  out <- causal_ontology_agrovoc_align_batch(character(0))
  expect_equal(nrow(out), 0L)
  expect_true(all(c("term", "uri", "label", "distance") %in% names(out)))
})

test_that("causal_kg_alignment(agrovoc_batch=TRUE) wires the batch path", {
  skip_if_no_igraph()
  skip_if_not_installed("httr2")
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "clay", "cec",
                             source = "Random 2020", confidence = 0.95)
  # Two mocked responses because the KG has two nodes (clay, cec).
  mocks <- list(.mock_agrovoc_response("clay"),
                 .mock_agrovoc_response("cec"))
  al <- httr2::with_mocked_responses(mocks, {
    causal_kg_alignment(kg, vocab = "agrovoc",
                         agrovoc_batch = TRUE,
                         agrovoc_max_active = 1L)
  })
  expect_true("uri" %in% names(al))
  expect_equal(nrow(al), 2L)
  expect_true(all(al$method == "agrovoc"))
})
