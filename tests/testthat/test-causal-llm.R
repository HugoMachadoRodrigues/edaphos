# CI-safe tests: live HTTP to Ollama / OpenAI / Anthropic is never
# exercised. The extraction pipeline is validated by two classes of
# assertion:
#   (i) `.causal_llm_parse_claims()` is a pure-R function and therefore
#       unit-testable on hard-coded LLM JSON strings;
#   (ii) end-to-end extraction is exercised under `httr2::with_mocked_responses`
#       so no network call leaks out of the test harness.

test_that(".causal_llm_parse_claims parses a canonical Gemma-style response", {
  raw <- paste0(
    "{\"claims\":[",
    "{\"cause\":\"precipitation\",\"effect\":\"soc\",",
    " \"evidence\":\"higher MAP drives SOC accumulation\",",
    " \"confidence\":0.9},",
    "{\"cause\":\"slope\",\"effect\":\"erosion\",",
    " \"evidence\":\"steeper slopes enhance erosional loss\",",
    " \"confidence\":0.85}",
    "]}"
  )
  out <- edaphos:::.causal_llm_parse_claims(raw)
  expect_equal(nrow(out), 2L)
  expect_equal(out$cause, c("precipitation", "slope"))
  expect_equal(out$effect, c("soc", "erosion"))
  expect_equal(out$confidence, c(0.9, 0.85))
})

test_that(".causal_llm_parse_claims handles an empty claims array", {
  out <- edaphos:::.causal_llm_parse_claims("{\"claims\": []}")
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out),
               c("cause", "effect", "evidence", "confidence"))
})

test_that(".causal_llm_parse_claims survives markdown fences and prose", {
  raw <- "Here is the JSON:\n```json\n{\"claims\":[{\"cause\":\"a\",\"effect\":\"b\",\"evidence\":\"x\",\"confidence\":0.7}]}\n```"
  out <- edaphos:::.causal_llm_parse_claims(raw)
  expect_equal(nrow(out), 1L)
  expect_equal(out$cause, "a")
})

test_that(".causal_llm_parse_claims drops self-loops and empty rows", {
  raw <- paste0(
    "{\"claims\":[",
    "{\"cause\":\"x\",\"effect\":\"x\",\"evidence\":\"\",\"confidence\":0.8},",
    "{\"cause\":\"\",\"effect\":\"y\",\"evidence\":\"\",\"confidence\":0.8},",
    "{\"cause\":\"a\",\"effect\":\"b\",\"evidence\":\"e\",\"confidence\":0.9}",
    "]}"
  )
  out <- edaphos:::.causal_llm_parse_claims(raw)
  expect_equal(nrow(out), 1L)
  expect_equal(out$cause, "a")
})

test_that("causal_llm_extract with mocked Ollama end-to-end", {
  skip_if_not_installed("httr2")
  mock_body <- list(
    message = list(
      role = "assistant",
      content = paste0(
        "{\"claims\":[",
        "{\"cause\":\"precipitation\",\"effect\":\"soc\",",
        " \"evidence\":\"MAP drives SOC\",\"confidence\":0.88}",
        "]}"
      )
    )
  )
  mock_resp <- httr2::response_json(body = mock_body)
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    {
      causal_llm_extract(
        "In Cerrado Oxisols, higher MAP drives SOC accumulation.",
        backend = "ollama", model = "gemma4:latest"
      )
    }
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$cause,  "precipitation")
  expect_equal(out$effect, "soc")
  expect_equal(out$confidence, 0.88)
})

test_that("causal_llm_ingest_abstract adds extracted claims to the KG", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("igraph")
  mock_body <- list(
    message = list(
      role = "assistant",
      content = paste0(
        "{\"claims\":[",
        "{\"cause\":\"precipitation\",\"effect\":\"soc\",",
        " \"evidence\":\"text\",\"confidence\":0.9},",
        "{\"cause\":\"slope\",\"effect\":\"erosion\",",
        " \"evidence\":\"text\",\"confidence\":0.8}",
        "]}"
      )
    )
  )
  mock_resp <- httr2::response_json(body = mock_body)
  kg <- causal_kg_new()
  kg <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    {
      causal_llm_ingest_abstract(
        kg, "abstract text", source = "Mock2026",
        backend = "ollama", model = "gemma4:latest"
      )
    }
  )
  e <- causal_kg_edges(kg)
  expect_equal(nrow(e), 2L)
  expect_true(all(e$source == "Mock2026"))
})

test_that("causal_llm_ingest_corpus iterates over a data frame", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("igraph")
  responses <- list(
    list(message = list(role = "assistant", content =
      "{\"claims\":[{\"cause\":\"a\",\"effect\":\"b\",\"evidence\":\"t\",\"confidence\":0.9}]}")),
    list(message = list(role = "assistant", content =
      "{\"claims\":[{\"cause\":\"b\",\"effect\":\"c\",\"evidence\":\"t\",\"confidence\":0.9}]}"))
  )
  idx <- 0L
  kg <- causal_kg_new()
  corpus <- data.frame(
    source   = c("S1", "S2"),
    abstract = c("text1", "text2"),
    stringsAsFactors = FALSE
  )
  kg <- httr2::with_mocked_responses(
    mock = function(req) {
      idx <<- idx + 1L
      httr2::response_json(body = responses[[idx]])
    },
    {
      causal_llm_ingest_corpus(
        kg, corpus,
        abstract_col = "abstract", source_col = "source",
        backend = "ollama", model = "gemma4:latest"
      )
    }
  )
  e <- causal_kg_edges(kg)
  expect_equal(nrow(e), 2L)
  expect_setequal(e$source, c("S1", "S2"))
})
