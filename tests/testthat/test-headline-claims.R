## Headline claims must match the artefacts the package ships.
##
## Every empirical figure quoted in README.md comes from a bundle under
## inst/extdata.  Before this file existed, no test read any of those bundles,
## so the two drifted: README published Sargan p = 0.343 / 0.283 / 0.424 while
## the shipped bundle contained 3.2e-08 / 7.5e-04 / 8.9e-02.  These tests are
## the mechanism that makes that impossible to repeat.
##
## When a benchmark is legitimately re-run, update BOTH the expected values
## here and the README table in the same commit.  That is the point.

bundle <- function(f) {
  p <- system.file("extdata", f, package = "edaphos")
  if (!nzchar(p) || !file.exists(p)) testthat::skip(paste("missing bundle:", f))
  readRDS(p)
}

# README.md is not installed with the package; when the tests run from a
# source checkout we can additionally assert the prose, otherwise we assert
# only the artefacts.
readme_lines <- function() {
  for (p in c("../../README.md", "../../../README.md", "README.md")) {
    if (file.exists(p)) return(readLines(p, warn = FALSE, encoding = "UTF-8"))
  }
  testthat::skip("README.md not reachable from the test working directory")
}

# ---------------------------------------------------------------------------
# Pillar 1 x Pillar 4: instrumental variables from foundation embeddings
# ---------------------------------------------------------------------------

test_that("the IV bundle records honest provenance", {
  b <- bundle("causal_iv_cerrado_real.rds")

  # stack_source must say what happened, not what was requested.  The old
  # field recorded the environment variable, so a run that fell back to a
  # synthetic stack still reported used_real_stack = TRUE.
  expect_true("stack_source" %in% names(b))
  expect_true(b$stack_source %in% c("real", "synthetic-fallback"))
  expect_identical(b$used_real_stack, identical(b$stack_source, "real"))

  # the normalisation actually used must be declared
  expect_true("normalisation_source" %in% names(b))
  expect_true(b$normalisation_source %in% c("aoi", "training"))
  if (identical(b$normalisation_source, "aoi"))
    expect_match(b$normalisation_note, "never persisted|cannot be recovered")

  # channel contract and encoder grid
  expect_equal(b$stack_nlyr, 31L)
  expect_equal(b$stack_res_deg, 0.01, tolerance = 1e-9)

  # the encoder was trained on a smaller region than this AoI
  expect_true(b$aoi_exceeds_training)
})

test_that("the IV figures in README match the shipped bundle", {
  b  <- bundle("causal_iv_cerrado_real.rds")
  bt <- b$benchmark_table
  iv <- bt[grepl("2SLS", bt$estimator), ]
  expect_equal(nrow(iv), 3L)

  # Values as published in the README table.  Update both together.
  expected <- data.frame(
    exposure = c("MAP (mm/a)", "Tree cover (%)", "Clay (%)"),
    stage1_F = c(862, 8.4, 11.0),
    sargan_p = c(0.250, 0.042, 0.0030),
    stringsAsFactors = FALSE
  )
  expect_equal(iv$exposure, expected$exposure)
  expect_equal(round(iv$stage1_F, 1), expected$stage1_F, tolerance = 0.05)
  expect_equal(signif(iv$sargan_p, 2), signif(expected$sargan_p, 2),
               tolerance = 0.02)

  # The qualitative claim the README makes: exactly one exposure survives
  # over-identification at the 5 % level.
  expect_equal(sum(iv$sargan_p > 0.05), 1L)
  expect_true(iv$sargan_p[iv$exposure == "MAP (mm/a)"] > 0.05)

  # and only that one has strong instruments
  expect_gt(iv$stage1_F[iv$exposure == "MAP (mm/a)"], 10)
  expect_lt(iv$stage1_F[iv$exposure == "Tree cover (%)"], 10)
})

test_that("README does not re-publish the withdrawn Sargan figures", {
  skip_on_cran()
  ln <- readme_lines()
  i  <- grep("Sargan", ln)
  skip_if(length(i) == 0L, "no Sargan section in README")
  txt <- paste(ln, collapse = "\n")
  # The withdrawn table claimed all three exposures passed.
  expect_false(grepl("\\*\\*0\\.343\\*\\*\\s*✅", txt))
  expect_false(grepl("The decisive test passes", txt, fixed = TRUE))
  # and the limitations must still be stated
  expect_match(txt, "normalisation.*never persisted|never persisted")
})

# ---------------------------------------------------------------------------
# Pillar 1: the multi-backend LLM extraction benchmark
# ---------------------------------------------------------------------------

test_that("the LLM benchmark bundle declares whether it is simulated", {
  b <- bundle("llm_benchmark_results.rds")
  expect_true("mode" %in% names(b))
  expect_true(b$mode %in% c("simulated", "real"))
})

test_that("README does not attribute simulated numbers to named vendors", {
  skip_on_cran()
  b  <- bundle("llm_benchmark_results.rds")
  skip_if(identical(b$mode, "real"), "bundle carries a real run")
  ln <- readme_lines()
  # With mode == "simulated" no vendor-attributed metric TABLE may appear:
  # those figures are the simulator's own inputs.  Naming a vendor in prose
  # -- for instance to say the table was withdrawn -- is fine; what is not
  # fine is a markdown table row that pairs a vendor with scores.
  vendors <- "Gemma|GPT-4|Claude|Sonnet|Llama|Mistral"
  rows <- grep("^\\s*\\|", ln, value = TRUE)          # markdown table rows
  rows <- grep(vendors, rows, value = TRUE)          # naming a vendor
  offending <- rows[vapply(rows, function(r) {
    nums <- unlist(regmatches(r, gregexpr("[0-9]+\\.[0-9]+", r)))
    length(nums) >= 3L                               # at least 3 metric cells
  }, logical(1))]
  expect_equal(
    offending, character(0),
    info = paste("llm_benchmark_results.rds has mode =", b$mode,
                 "-- the README must not present its values as a measured",
                 "vendor comparison.")
  )
})

# ---------------------------------------------------------------------------
# Metrics must not be censored
# ---------------------------------------------------------------------------

test_that("R2 is never clamped at zero anywhere in the package", {
  # A predictor worse than the mean must produce a negative R2.
  set.seed(42L)
  truth <- stats::rnorm(50L)
  expect_lt(edaphos_r2(truth, rep(mean(truth) + 5, 50L)), 0)

  # and no source file may reintroduce the clamp
  skip_on_cran()
  rdir <- system.file("R", package = "edaphos")
  src  <- if (dir.exists("../../R")) Sys.glob("../../R/*.R") else character()
  skip_if(length(src) == 0L, "R/ sources not reachable")
  hits <- unlist(lapply(src, function(f) {
    ln <- readLines(f, warn = FALSE)
    i  <- grep("max\\(\\s*0\\s*,\\s*1\\s*-", ln)
    if (length(i)) sprintf("%s:%d", basename(f), i) else character()
  }))
  expect_equal(hits, character(0))
})
