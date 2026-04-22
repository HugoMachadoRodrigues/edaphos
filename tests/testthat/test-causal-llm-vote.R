# Pillar 1 v1.1.0 tests: multi-extractor LLM voting.
#
# Every test mocks `causal_llm_extract` via testthat::local_mocked_
# bindings so the suite runs offline and deterministically.

.mock_claims <- function(triples, backend = "mock", model = "mock-1") {
  if (nrow(triples) == 0L) {
    df <- data.frame(cause = character(0), effect = character(0),
                      evidence = character(0), confidence = numeric(0),
                      stringsAsFactors = FALSE)
  } else {
    df <- data.frame(
      cause      = tolower(triples$cause),
      effect     = tolower(triples$effect),
      evidence   = triples$evidence %||% rep(NA_character_, nrow(triples)),
      confidence = triples$confidence %||% rep(0.9, nrow(triples)),
      stringsAsFactors = FALSE
    )
  }
  attr(df, "backend") <- backend
  attr(df, "model")   <- model
  df
}

.make_backends <- function() {
  list(
    list(backend = "ollama",    model = "gemma4:latest", id = "ollama_g4"),
    list(backend = "openai",    model = "gpt-4o-mini",    id = "openai_mini"),
    list(backend = "anthropic", model = "claude-sonnet-4-6", id = "ant_s46")
  )
}

.three_way_answers <- list(
  ollama_g4 = data.frame(
    cause  = c("precipitation", "slope"),
    effect = c("soc",            "soc"),
    evidence = c("MAP drives SOC", "slope drives erosion"),
    confidence = c(0.9, 0.8),
    stringsAsFactors = FALSE
  ),
  openai_mini = data.frame(
    cause  = c("precipitation", "ndvi"),
    effect = c("soc",            "soc"),
    evidence = c("MAP->SOC",       "NDVI->SOC"),
    confidence = c(0.85, 0.7),
    stringsAsFactors = FALSE
  ),
  ant_s46 = data.frame(
    cause  = c("precipitation"),
    effect = c("soc"),
    evidence = c("claude MAP->SOC"),
    confidence = c(0.95),
    stringsAsFactors = FALSE
  )
)

# Inject per-backend responses through a local mock of
# causal_llm_extract.
.mock_extract_factory <- function(answers) {
  function(text, backend, model = NULL, ...) {
    id <- paste0(
      switch(backend,
              ollama    = "ollama_g4",
              openai    = "openai_mini",
              anthropic = "ant_s46")
    )
    .mock_claims(answers[[id]], backend = backend,
                  model = model %||% "mock")
  }
}

test_that("voting='majority' keeps edges asserted by >= ceil(N/2)", {
  testthat::local_mocked_bindings(
    causal_llm_extract = .mock_extract_factory(.three_way_answers)
  )
  cons <- causal_llm_vote(
    abstract = "foo",
    backends = .make_backends(),
    voting   = "majority"
  )
  expect_s3_class(cons, "data.frame")
  # precipitation -> soc is asserted by all three, slope->soc only by 1,
  # ndvi->soc only by 1. With N=3, min_support defaults to 2, so only
  # precipitation->soc survives.
  expect_equal(nrow(cons), 1L)
  expect_equal(cons$cause[1L],  "precipitation")
  expect_equal(cons$effect[1L], "soc")
  expect_equal(cons$n_backends[1L], 3L)
  expect_gt(cons$mean_confidence[1L], 0.8)
})

test_that("voting='intersection' keeps only edges asserted by EVERY backend", {
  testthat::local_mocked_bindings(
    causal_llm_extract = .mock_extract_factory(.three_way_answers)
  )
  cons <- causal_llm_vote(
    abstract = "foo",
    backends = .make_backends(),
    voting   = "intersection"
  )
  expect_equal(nrow(cons), 1L)   # only precipitation->soc is universal
  expect_equal(cons$n_backends[1L], 3L)
})

test_that("voting='weighted' honours the weights vector", {
  testthat::local_mocked_bindings(
    causal_llm_extract = .mock_extract_factory(.three_way_answers)
  )
  # Make the openai extractor heavily favoured so that ndvi->soc
  # (asserted only by openai) squeaks past a tuned threshold that
  # slope->soc (asserted only by ollama, weight 0.1) would fail.
  cons <- causal_llm_vote(
    abstract = "foo",
    backends = .make_backends(),
    voting   = "weighted",
    weights  = c(0.1, 10, 1),
    threshold = 5
  )
  expect_true(any(cons$cause == "precipitation" & cons$effect == "soc"))
  expect_true(any(cons$cause == "ndvi"          & cons$effect == "soc"))
  expect_false(any(cons$cause == "slope"        & cons$effect == "soc"))
})

test_that("majority with min_support=1 keeps every unique edge", {
  testthat::local_mocked_bindings(
    causal_llm_extract = .mock_extract_factory(.three_way_answers)
  )
  cons <- causal_llm_vote(
    abstract = "foo",
    backends = .make_backends(),
    voting   = "majority",
    min_support = 1L
  )
  expect_equal(sort(paste(cons$cause, cons$effect)),
                sort(c("precipitation soc", "slope soc", "ndvi soc")))
})

test_that("causal_llm_ingest_abstract_voted inserts consensus edges with voted source tag", {
  testthat::local_mocked_bindings(
    causal_llm_extract = .mock_extract_factory(.three_way_answers)
  )
  kg <- causal_kg_new()
  kg <- causal_llm_ingest_abstract_voted(
    kg,
    abstract = "foo",
    source   = "Ferreira 2021",
    backends = .make_backends(),
    voting   = "majority",
    min_confidence = 0.5
  )
  e <- causal_kg_edges(kg)
  expect_equal(nrow(e), 1L)
  expect_equal(e$cause[1L],  "precipitation")
  expect_equal(e$effect[1L], "soc")
  # Source tag records the vote metadata.
  expect_true(grepl("vote\\(majority,n=3\\)", e$source[1L]))
  expect_true(grepl("Ferreira 2021", e$source[1L]))
})

test_that("a crashing backend emits a warning but the vote survives", {
  # Only two backends answer; one raises.
  testthat::local_mocked_bindings(
    causal_llm_extract = function(text, backend, model = NULL, ...) {
      if (backend == "openai") {
        stop("simulated API failure")
      }
      id <- switch(backend, ollama = "ollama_g4", anthropic = "ant_s46")
      .mock_claims(.three_way_answers[[id]], backend = backend)
    }
  )
  expect_warning(
    cons <- causal_llm_vote(
      abstract = "foo", backends = .make_backends(),
      voting   = "majority"
    ),
    regexp = "backend 'openai"
  )
  # precipitation -> soc still asserted by 2 of 3 => survives majority.
  expect_true(any(cons$cause == "precipitation" & cons$effect == "soc"))
})

test_that("causal_llm_vote rejects fewer than 2 backends", {
  expect_error(
    causal_llm_vote("foo", backends = list(list(backend = "ollama"))),
    regexp = "length\\(backends\\) >= 2L"
  )
})
