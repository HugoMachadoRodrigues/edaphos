## Tests for the gold-standard annotation toolkit (v1.8.1, v1.8.2).

test_that("llm_annotation_vocabulary: returns a non-trivial character vector", {
  v <- llm_annotation_vocabulary()
  expect_type(v, "character")
  expect_gt(length(v), 15L)
  # Key canonical terms must be present
  expect_true(all(c("soc", "precipitation", "clay", "slope", "vegetation")
                    %in% v))
})

test_that("llm_preannotate: simulator backend builds a valid JSONL", {
  skip_if_not_installed("jsonlite")
  corpus <- list(
    list(abstract_id = "T1", title = "Synthetic", year = 2026,
         abstract_text = paste("Rainfall drives soil organic carbon through",
                                "litter inputs in the Cerrado biome.")),
    list(abstract_id = "T2", title = "Synthetic 2", year = 2026,
         abstract_text = paste("Slope gradient correlates with erosion rates",
                                "and reduces topsoil."))
  )
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  drafts <- llm_preannotate(
    corpus       = corpus,
    backend      = "simulator",
    output_path  = tmp,
    verbose      = FALSE
  )
  expect_true(file.exists(tmp))
  expect_length(drafts, 2L)
  # Every record must carry claims with status="draft"
  for (d in drafts) {
    expect_true(is.data.frame(d$claims))
    if (nrow(d$claims) > 0L) {
      expect_true(all(d$claims$status == "draft"))
    }
  }
})

test_that("llm_annotation_validate: flags invalid polarity and confidence", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)
  # Write a single record with a claim that violates polarity + confidence
  bad <- list(
    abstract_id = "T", title = "x", abstract_text = "y",
    claims = data.frame(
      cause = "precipitation", effect = "soc",
      polarity = "?",           # invalid
      confidence = 1.5,         # out of [0,1]
      stringsAsFactors = FALSE
    )
  )
  con <- file(tmp, "w")
  writeLines(jsonlite::toJSON(bad, dataframe = "rows", auto_unbox = TRUE), con)
  close(con)
  v <- llm_annotation_validate(tmp, strict_vocab = FALSE)
  expect_false(v$ok)
  expect_gt(length(v$errors), 0L)
})

test_that("llm_annotation_export: drops rejected and draft claims, preserves legacy", {
  skip_if_not_installed("jsonlite")
  tmp_in  <- tempfile(fileext = ".jsonl")
  tmp_out <- tempfile(fileext = ".jsonl")
  on.exit(unlink(c(tmp_in, tmp_out)), add = TRUE)

  rec <- list(
    abstract_id = "T", title = "x", abstract_text = "y",
    claims = data.frame(
      cause      = c("precipitation", "slope", "temperature"),
      effect     = c("soc",           "erosion", "soc"),
      polarity   = c("+", "+", "-"),
      confidence = c(0.9, 0.8, 0.7),
      rationale  = c("r1", "r2", "r3"),
      status     = c("accepted", "rejected", "draft"),
      stringsAsFactors = FALSE
    )
  )
  con <- file(tmp_in, "w")
  writeLines(jsonlite::toJSON(rec, dataframe = "rows", auto_unbox = TRUE), con)
  close(con)
  out <- llm_annotation_export(tmp_in, tmp_out, include_rationale = TRUE)
  expect_length(out, 1L)
  # Only "accepted" claim survives
  expect_equal(nrow(out[[1]]$claims), 1L)
  expect_equal(out[[1]]$claims$cause[1], "precipitation")
  # Legacy v1 records without a `status` column should be preserved whole
  rec_legacy <- list(
    abstract_id = "T2", title = "z", abstract_text = "w",
    claims = data.frame(
      cause = c("clay", "sand"), effect = c("soc", "soc"),
      polarity = c("+", "-"), confidence = c(0.92, 0.82),
      stringsAsFactors = FALSE
    )
  )
  tmp_in2 <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp_in2), add = TRUE)
  con <- file(tmp_in2, "w")
  writeLines(jsonlite::toJSON(rec_legacy, dataframe = "rows", auto_unbox = TRUE), con)
  close(con)
  out2 <- llm_annotation_export(tmp_in2, tempfile(fileext = ".jsonl"))
  expect_equal(nrow(out2[[1]]$claims), 2L)
})

test_that("llm_annotation_to_zenodo: bundle contains expected files", {
  skip_if_not_installed("jsonlite")
  # Use the shipped v1 gold-standard for the round-trip test
  gs <- system.file("extdata", "cerrado_gold_standard_v1.jsonl",
                     package = "edaphos")
  skip_if(!nzchar(gs) || !file.exists(gs),
           "v1 gold-standard not available in installed package")
  out_dir <- tempfile()
  on.exit({
    unlink(out_dir, recursive = TRUE)
    unlink(paste0(out_dir, ".zip"))
  }, add = TRUE)

  res <- llm_annotation_to_zenodo(
    reviewed_path = gs, output_dir = out_dir,
    title = "test", zip = FALSE
  )
  files <- list.files(out_dir)
  expect_true(all(c("gold_standard.jsonl", "kg.ttl",
                      "metadata.json", "README.md") %in% files))
  # Turtle should start with RDF prefixes
  ttl <- readLines(file.path(out_dir, "kg.ttl"), n = 5L)
  expect_true(any(grepl("^@prefix", ttl)))
})
