# Corpus clients never actually hit the network in tests — every live
# call is intercepted with `httr2::with_mocked_responses()`.

test_that("OpenAlex abstract reconstruction inverts the index correctly", {
  inv <- list("Higher" = list(0L),
              "rainfall" = list(1L),
              "increases" = list(2L),
              "SOC." = list(3L))
  txt <- edaphos:::.openalex_abstract_from_inverted_index(inv)
  expect_equal(txt, "Higher rainfall increases SOC.")
})

test_that("OpenAlex abstract reconstruction handles gaps safely", {
  inv <- list("A" = list(0L), "B" = list(2L), "C" = list(4L))
  txt <- edaphos:::.openalex_abstract_from_inverted_index(inv)
  expect_equal(txt, "A B C")   # missing positions dropped, words kept in order
})

test_that("causal_corpus_openalex mocks end-to-end into a tidy frame", {
  skip_if_not_installed("httr2")
  mock_body <- list(
    results = list(
      list(
        id    = "https://openalex.org/W1",
        title = "Cerrado SOC and rainfall",
        doi   = "https://doi.org/10.1000/x.y",
        publication_year = 2023L,
        abstract_inverted_index = list(
          "Higher" = list(0L), "rainfall" = list(1L),
          "drives" = list(2L), "SOC." = list(3L)
        )
      ),
      list(
        id    = "https://openalex.org/W2",
        title = "No-abstract paper",
        doi   = "https://doi.org/10.1000/none",
        publication_year = 2024L,
        abstract_inverted_index = NULL
      )
    )
  )
  mock_resp <- httr2::response_json(body = mock_body)
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    causal_corpus_openalex("cerrado soc", max_results = 5L)
  )
  expect_s3_class(out, "data.frame")
  # Empty abstracts are filtered out.
  expect_equal(nrow(out), 1L)
  expect_equal(out$title, "Cerrado SOC and rainfall")
  expect_equal(out$year, 2023L)
  expect_equal(out$abstract, "Higher rainfall drives SOC.")
  expect_true(grepl("10.1000", out$doi))
})

test_that("causal_corpus_scielo mocks end-to-end into a tidy frame", {
  skip_if_not_installed("httr2")
  mock_body <- list(
    objects = list(
      list(
        code  = "S1234-5678",
        title = "Cerrado pedogenesis",
        doi   = "10.1000/cerrado1",
        publication_year = "2022",
        abstract = "Precipitation drives soil organic carbon accumulation.",
        url   = "https://scielo.br/fake"
      )
    )
  )
  mock_resp <- httr2::response_json(body = mock_body)
  out <- httr2::with_mocked_responses(
    mock = function(req) mock_resp,
    causal_corpus_scielo("cerrado pedogenesis", max_results = 5L)
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$year, 2022L)
  expect_true(grepl("Precipitation", out$abstract))
})
