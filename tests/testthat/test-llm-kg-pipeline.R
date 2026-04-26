## Tests for the v3.10.0 Pilar 1 LLM-KG pipeline orchestrator.
## We MOCK the Ollama HTTP call (no live server in CI) and test:
##
##   1. `llm_kg_ollama_check()` reports the right state when the
##      server is unreachable.
##   2. `llm_kg_pipeline_run()` errors helpfully on a missing
##      corpus.
##   3. With `causal_llm_extract` mocked to return a fixed claim,
##      the pipeline:
##      a) writes JSONL claims to `output_path`,
##      b) appends source IDs to `output_path.done`,
##      c) builds an `edaphos_causal_kg` with at least one edge,
##      d) skips already-done sources on re-run (resumability),
##      e) writes errors to `output_path.errors` on failure.

# Stand-in for `causal_llm_extract` -- no network calls.
.mock_llm_extract <- function(text, ...) {
  out <- data.frame(
    cause      = c("rainfall", "tree_cover"),
    effect     = c("soc",      "soc"),
    evidence   = c("higher rainfall increases SOC",
                    "tree cover correlates with SOC"),
    confidence = c(0.9, 0.8),
    stringsAsFactors = FALSE
  )
  attr(out, "backend") <- "mock"
  attr(out, "model")   <- "mock"
  out
}

.mock_llm_extract_fail <- function(text, ...) {
  stop("mock LLM failure")
}

.mk_corpus <- function(lines = 5L, path = tempfile(fileext = ".jsonl")) {
  recs <- vapply(seq_len(lines), function(i) {
    jsonlite::toJSON(list(
      source   = sprintf("test_%03d", i),
      abstract = sprintf("Mock abstract %d about pedology.", i)
    ), auto_unbox = TRUE)
  }, character(1L))
  writeLines(recs, path)
  path
}

# ---------------------------------------------------------------------------

test_that("llm_kg_ollama_check: unreachable server reports reachable=FALSE", {
  out <- llm_kg_ollama_check(host = "http://127.0.0.1:1",
                                timeout_sec = 0.2)
  expect_false(out$reachable)
})

test_that("llm_kg_pipeline_run: missing corpus errors helpfully", {
  e <- tryCatch(
    llm_kg_pipeline_run(corpus_path = "/no/such/path.jsonl",
                            output_path = tempfile(),
                            backend     = "ollama"),
    error = function(e) e
  )
  expect_match(conditionMessage(e),
                 "Corpus file not found|JSONL")
})

test_that("llm_kg_pipeline_run: skips Ollama check when corpus + mocked extract OK", {
  skip_if_not_installed("igraph")
  corpus <- .mk_corpus(5L)
  out_path <- tempfile(fileext = ".jsonl")
  on.exit({
    unlink(c(corpus, out_path,
              paste0(out_path, ".done"),
              paste0(out_path, ".errors")))
  }, add = TRUE)

  with_mocked_bindings(
    causal_llm_extract  = .mock_llm_extract,
    llm_kg_ollama_check = function(...) list(reachable = TRUE,
                                                 model_present = TRUE,
                                                 models_available = "mock"),
    {
      res <- llm_kg_pipeline_run(
        corpus_path    = corpus,
        output_path    = out_path,
        backend        = "ollama",
        model          = "mock",
        verbose        = FALSE,
        min_confidence = 0,
        max_retries    = 0L
      )
      expect_equal(res$n_processed, 5L)
      expect_equal(res$n_errors,    0L)
      expect_true(file.exists(out_path))
      expect_true(file.exists(paste0(out_path, ".done")))
      done <- readLines(paste0(out_path, ".done"))
      expect_length(done, 5L)
      expect_gte(length(igraph::E(res$kg$graph)), 1L)
    },
    .package = "edaphos"
  )
})

test_that("llm_kg_pipeline_run: re-run skips done sources", {
  corpus <- .mk_corpus(4L)
  out_path <- tempfile(fileext = ".jsonl")
  on.exit({
    unlink(c(corpus, out_path,
              paste0(out_path, ".done"),
              paste0(out_path, ".errors")))
  }, add = TRUE)

  with_mocked_bindings(
    causal_llm_extract  = .mock_llm_extract,
    llm_kg_ollama_check = function(...) list(reachable = TRUE,
                                                 model_present = TRUE,
                                                 models_available = "mock"),
    {
      res1 <- llm_kg_pipeline_run(
        corpus, out_path, backend = "ollama", model = "mock",
        verbose = FALSE, min_confidence = 0, max_retries = 0L
      )
      expect_equal(res1$n_processed, 4L)
      # Re-run: everything should be skipped
      res2 <- llm_kg_pipeline_run(
        corpus, out_path, backend = "ollama", model = "mock",
        verbose = FALSE, min_confidence = 0, max_retries = 0L
      )
      expect_equal(res2$n_processed, 0L)
      expect_equal(res2$n_skipped,   4L)
    },
    .package = "edaphos"
  )
})

test_that("llm_kg_pipeline_run: persistent extract failure logs to .errors", {
  corpus <- .mk_corpus(3L)
  out_path <- tempfile(fileext = ".jsonl")
  err_path <- paste0(out_path, ".errors")
  on.exit({
    unlink(c(corpus, out_path,
              paste0(out_path, ".done"),
              err_path))
  }, add = TRUE)

  with_mocked_bindings(
    causal_llm_extract  = .mock_llm_extract_fail,
    llm_kg_ollama_check = function(...) list(reachable = TRUE,
                                                 model_present = TRUE,
                                                 models_available = "mock"),
    {
      res <- llm_kg_pipeline_run(
        corpus, out_path, backend = "ollama", model = "mock",
        verbose = FALSE, min_confidence = 0, max_retries = 0L
      )
      expect_equal(res$n_processed, 0L)
      expect_equal(res$n_errors,    3L)
      expect_true(file.exists(err_path))
      err_lines <- readLines(err_path)
      expect_length(err_lines, 3L)
      expect_true(all(grepl("mock LLM failure", err_lines)))
    },
    .package = "edaphos"
  )
})

test_that("llm_kg_pipeline_run: max_abstracts caps the run", {
  corpus <- .mk_corpus(10L)
  out_path <- tempfile(fileext = ".jsonl")
  on.exit({
    unlink(c(corpus, out_path,
              paste0(out_path, ".done"),
              paste0(out_path, ".errors")))
  }, add = TRUE)

  with_mocked_bindings(
    causal_llm_extract  = .mock_llm_extract,
    llm_kg_ollama_check = function(...) list(reachable = TRUE,
                                                 model_present = TRUE,
                                                 models_available = "mock"),
    {
      res <- llm_kg_pipeline_run(
        corpus, out_path, backend = "ollama", model = "mock",
        verbose = FALSE, min_confidence = 0, max_retries = 0L,
        max_abstracts = 3L
      )
      expect_equal(res$n_processed, 3L)
    },
    .package = "edaphos"
  )
})
