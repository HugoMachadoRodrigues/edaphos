# Tests for the v0.8.0 Pillar 1 scale-up: corpus pagination +
# deduplication, cached / retrying LLM ingestion, and live AGROVOC
# alignment. Every network-bound test is intercepted with
# httr2::with_mocked_responses() so the suite stays CI-green.

# ---- Corpus dedup -----------------------------------------------------------

test_that("causal_corpus_deduplicate collapses rows by DOI", {
  df <- data.frame(
    source   = c("A", "B", "C"),
    title    = c("Pedogenesis", "Pedogenesis", "Erosion"),
    abstract = rep("abs", 3L),
    year     = c(2020L, 2021L, 2022L),
    doi      = c("10.1/same", "10.1/same", "10.1/other"),
    url      = c("u1", "u2", "u3"),
    stringsAsFactors = FALSE
  )
  out <- causal_corpus_deduplicate(df, by = c("doi", "title"))
  expect_equal(nrow(out), 2L)
  expect_equal(out$doi, c("10.1/same", "10.1/other"))
})

test_that("causal_corpus_deduplicate falls back to title when DOI missing", {
  df <- data.frame(
    source   = c("A", "B", "C"),
    title    = c("X", "X", "Y"),
    abstract = rep("abs", 3L),
    year     = rep(2024L, 3L),
    doi      = c(NA, NA, "10.1/y"),
    url      = c("u1", "u2", "u3"),
    stringsAsFactors = FALSE
  )
  out <- causal_corpus_deduplicate(df)
  expect_equal(nrow(out), 2L)
  expect_equal(sort(out$title), c("X", "Y"))
})

# ---- OpenAlex pagination ----------------------------------------------------

test_that("causal_corpus_openalex merges two cursor-paged responses", {
  skip_if_not_installed("httr2")
  page1 <- list(
    results = list(
      list(id = "W1", title = "P1", doi = NA,
           publication_year = 2020L,
           abstract_inverted_index = list("hello" = list(0L),
                                          "world" = list(1L))),
      list(id = "W2", title = "P2", doi = NA,
           publication_year = 2021L,
           abstract_inverted_index = list("a" = list(0L)))
    ),
    meta = list(next_cursor = "page2")
  )
  page2 <- list(
    results = list(
      list(id = "W3", title = "P3", doi = NA,
           publication_year = 2022L,
           abstract_inverted_index = list("b" = list(0L)))
    ),
    meta = list(next_cursor = NULL)
  )
  responses <- list(
    httr2::response_json(body = page1),
    httr2::response_json(body = page2)
  )
  idx <- 0L
  out <- httr2::with_mocked_responses(
    mock = function(req) {
      idx <<- idx + 1L
      responses[[idx]]
    },
    causal_corpus_openalex("anything", max_results = 10L)
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$title, c("P1", "P2", "P3"))
})

# ---- Cached LLM ingestion ---------------------------------------------------

test_that("causal_llm_ingest_corpus honours cache_dir (no LLM call on hit)", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("igraph")
  cache_dir <- tempfile("llm_cache_")
  dir.create(cache_dir, recursive = TRUE)

  src <- "MockSource1"
  abs <- "In Cerrado soils, precipitation drives SOC."
  key <- edaphos:::.cache_fallback_key(src, abs)
  cached_path <- file.path(cache_dir, paste0(key, ".json"))

  # Pre-populate the cache with a one-edge claim table.
  pre <- data.frame(
    cause      = "precipitation",
    effect     = "soc",
    evidence   = "precipitation drives SOC",
    confidence = 0.9,
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(pre, cached_path, pretty = FALSE,
                        auto_unbox = TRUE)

  corpus <- data.frame(source = src, abstract = abs,
                        stringsAsFactors = FALSE)
  # The mock must *never* be invoked thanks to the cache hit --
  # enforce it by returning a sentinel mocked response.
  calls <- 0L
  kg <- httr2::with_mocked_responses(
    mock = function(req) {
      calls <<- calls + 1L
      httr2::response_json(body = list(
        message = list(content = "{\"claims\": []}")
      ))
    },
    causal_llm_ingest_corpus(
      causal_kg_new(), corpus,
      backend = "ollama", model = "gemma4:latest",
      cache_dir = cache_dir
    )
  )
  # No LLM call happened, yet the KG has the cached edge.
  expect_equal(calls, 0L)
  e <- causal_kg_edges(kg)
  expect_equal(nrow(e), 1L)
  expect_equal(e$cause, "precipitation")
})

test_that("causal_llm_ingest_corpus retries on malformed responses", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("igraph")
  responses <- list(
    # First attempt: garbled content -> parser returns zero rows ->
    # ingest treats as failure and retries.
    httr2::response_json(body = list(
      message = list(content = "sorry I cannot JSON")
    )),
    # Second attempt: valid JSON.
    httr2::response_json(body = list(
      message = list(content =
        "{\"claims\":[{\"cause\":\"a\",\"effect\":\"b\",\"evidence\":\"t\",\"confidence\":0.9}]}")
    ))
  )
  idx <- 0L
  corpus <- data.frame(source = "S1", abstract = "txt",
                        stringsAsFactors = FALSE)
  kg <- httr2::with_mocked_responses(
    mock = function(req) {
      idx <<- idx + 1L
      responses[[idx]]
    },
    causal_llm_ingest_corpus(
      causal_kg_new(), corpus,
      backend = "ollama", model = "gemma4:latest",
      max_retries = 2L
    )
  )
  # Exactly two LLM calls for the single row, and the retry succeeded.
  expect_equal(idx, 2L)
  expect_equal(nrow(causal_kg_edges(kg)), 1L)
})

# ---- AGROVOC alignment ------------------------------------------------------

test_that("causal_ontology_agrovoc_align returns NA for no-match terms", {
  skip_if_not_installed("httr2")
  mock_empty <- httr2::response_json(body = list(
    results = list(bindings = list())
  ))
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_empty,
    causal_ontology_agrovoc_align(c("made_up_term_zzz"), verbose = FALSE)
  )
  expect_equal(nrow(out), 1L)
  expect_true(is.na(out$uri))
})

test_that("causal_ontology_agrovoc_align picks the Levenshtein-nearest label", {
  skip_if_not_installed("httr2")
  bindings <- list(
    list(uri   = list(value = "http://agrovoc/c_1"),
         label = list(value = "clay soil")),
    list(uri   = list(value = "http://agrovoc/c_2"),
         label = list(value = "clay"))
  )
  mock_resp <- httr2::response_json(body = list(
    results = list(bindings = bindings)
  ))
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    causal_ontology_agrovoc_align(c("clay"))
  )
  expect_equal(out$label, "clay")
  expect_equal(out$distance, 0)
})

test_that("causal_kg_alignment(vocab = 'agrovoc') plumbs the live path", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("igraph")
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "clay", "soc", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "erosion", "soc", confidence = 0.9)
  mock_resp <- httr2::response_json(body = list(
    results = list(bindings = list(
      list(uri   = list(value = "http://agrovoc/c_clay"),
           label = list(value = "clay")),
      list(uri   = list(value = "http://agrovoc/c_ero"),
           label = list(value = "erosion")),
      list(uri   = list(value = "http://agrovoc/c_soc"),
           label = list(value = "soil organic carbon"))
    ))
  ))
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    causal_kg_alignment(kg, vocab = "agrovoc")
  )
  expect_true("uri" %in% names(out))
  expect_true(all(out$method %in% c("agrovoc", "none")))
})
