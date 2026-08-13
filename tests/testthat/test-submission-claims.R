# ---------------------------------------------------------------------------
# The self-report written for external reviewers, bound to the measurements.
#
# inst/rosc/submission.md is what a reviewer reads first, and every number in
# it was typed by hand and wrong: 1 345 expectations against 2 151, 14
# vignettes against 19, and a ticked "[x] builds with 0 errors / 0 notes"
# against a log recording two NOTEs. The 1 345 figure is the one NEWS.md had
# already withdrawn as unreproducible; this file was the last place asserting
# it. It also declared "Version: 3.10.0" -- a release the package itself
# repudiated -- while conceding 0.9.0 eighty lines further down.
#
# Worse, it INSTALLED. Without .Rinstignore everything under inst/ lands in
# the user's library, so those claims travelled with the package.
#
# The block is generated now (tools/status/render-submission-qa.R). These
# tests check the generated output against the same facts the generator reads,
# so a stale regeneration fails rather than ships.
# ---------------------------------------------------------------------------

pkg_root_sub <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        file.exists(file.path(d, "inst", "rosc", "submission.md")))
      return(d)
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  NA_character_
}

test_that("the submission self-report agrees with the measured facts", {
  root <- pkg_root_sub()
  skip_if(is.na(root), "not running from a source checkout")
  skip_if_not_installed("jsonlite")
  fp <- file.path(root, "tools", "status", "facts.json")
  skip_if_not(file.exists(fp), "facts.json not built")

  f  <- jsonlite::fromJSON(fp, simplifyVector = TRUE)
  md <- readLines(file.path(root, "inst", "rosc", "submission.md"), warn = FALSE)

  # The generated region must exist. Its absence means someone replaced the
  # block by hand, which is the failure this file is here to catch.
  expect_length(grep("^<!-- BEGIN GENERATED QA", md), 1L)
  expect_length(grep("^<!-- END GENERATED QA", md), 1L)

  qa <- paste(md[seq(grep("^<!-- BEGIN GENERATED QA", md),
                     grep("^<!-- END GENERATED QA", md))], collapse = " ")

  # Every figure the block states, against the facts the generator read.
  spaced <- function(n) formatC(n, big.mark = " ", format = "d")
  expect_true(grepl(spaced(f$tests_run$passed), qa, fixed = TRUE))
  expect_true(grepl(spaced(f$tests_static$test_file_count), qa, fixed = TRUE))
  expect_true(grepl(spaced(f$docs$vignette_count), qa, fixed = TRUE))
  expect_true(grepl(f$check$status_line, qa, fixed = TRUE))

  # The withdrawn figures must not be ASSERTED again. Disclosing them is a
  # different act and is allowed: the generated block and the corrected
  # checklist item both name the old numbers to say they were false, and a
  # test that forbade the string outright would delete the explanation along
  # with the defect. So the check runs on the document MINUS the generated
  # region and minus lines that are visibly retractions.
  outside <- md[-seq(grep("^<!-- BEGIN GENERATED QA", md),
                     grep("^<!-- END GENERATED QA", md))]
  outside <- grep("used to|previously|was never true|withdrawn|which was",
                  outside, value = TRUE, invert = TRUE)
  whole <- paste(outside, collapse = " ")
  expect_false(grepl("1 345", whole, fixed = TRUE))
  expect_false(grepl("0 errors / 0 notes", whole, fixed = TRUE))
})

test_that("the submission document states the package's actual version", {
  root <- pkg_root_sub()
  skip_if(is.na(root), "not running from a source checkout")
  md  <- readLines(file.path(root, "inst", "rosc", "submission.md"), warn = FALSE)
  ver <- read.dcf(file.path(root, "DESCRIPTION"), "Version")[1, 1]

  hdr <- grep("^# rOpenSci pre-submission inquiry", md, value = TRUE)
  expect_length(hdr, 1L)
  expect_true(grepl(ver, hdr, fixed = TRUE))

  vln <- grep("^- \\*\\*Version\\*\\*:", md, value = TRUE)
  expect_length(vln, 1L)
  expect_true(grepl(ver, vln, fixed = TRUE))
})

test_that("maintainer documentation does not install into the user library", {
  # .Rinstignore patterns are matched against paths relative to the SOURCE
  # ROOT, not to inst/. The first version of this file said `^rosc$`, which
  # matches nothing and silently kept shipping the document. Asserting the
  # pattern text is the only cheap check; the authoritative one is installing
  # to a temporary library, which is too slow for the suite and was done by
  # hand when the file was written.
  root <- pkg_root_sub()
  skip_if(is.na(root), "not running from a source checkout")
  ri <- file.path(root, ".Rinstignore")
  expect_true(file.exists(ri))

  pats <- grep("^\\s*(#|$)", readLines(ri, warn = FALSE), value = TRUE,
               invert = TRUE)
  expect_true(any(grepl("^\\^inst/", pats)),
              info = paste("no pattern is anchored at inst/; .Rinstignore",
                           "matches source-root-relative paths, so a bare",
                           "`^rosc$` never fires"))
  # The specific file this was written for.
  expect_true(any(vapply(pats,
                         function(p) grepl(p, "inst/rosc/submission.md", perl = TRUE),
                         TRUE)))
})
