# ---------------------------------------------------------------------------
# Every @citation in a vignette must exist in references.bib.
#
# An unresolved key does not fail the build. Pandoc emits
# "[WARNING] Citeproc: citation X not found", the vignette renders, and the
# reader gets a bare "[?]" where a reference should be. Two had been sitting
# there: @SchuldKilloran2019, which was the WRONG KEY for an entry already in
# the file under Schuld2019qml, and @Chipman2010bart, which was genuinely
# absent. The first is the more instructive: adding a second entry for the
# same paper would have "fixed" the warning and left the bibliography with a
# duplicate.
#
# Checked here rather than by reading build logs, because a warning nobody
# fails on is a warning nobody reads.
# ---------------------------------------------------------------------------

test_that("every vignette citation key resolves against references.bib", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (dir.exists(file.path(d, "vignettes")) &&
        file.exists(file.path(d, "DESCRIPTION"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "not running from a source checkout")

  bibf <- file.path(root, "vignettes", "references.bib")
  skip_if_not(file.exists(bibf), "references.bib not present")
  bib  <- readLines(bibf, warn = FALSE)
  keys <- trimws(gsub("^@[a-zA-Z]+\\{([^,]+),.*$", "\\1", grep("^@", bib, value = TRUE)))
  expect_gt(length(keys), 50L)

  rmds <- list.files(file.path(root, "vignettes"), "[.]Rmd$",
                     full.names = TRUE, recursive = TRUE)
  skip_if(!length(rmds), "no vignettes")

  unresolved <- character(0)
  for (f in rmds) {
    x <- readLines(f, warn = FALSE)
    # Drop lines carrying an e-mail or URL: "user@host.com" is not a citation
    # and matching it was the first thing that made this check cry wolf.
    x <- x[!grepl("@[A-Za-z0-9._-]+\\.(com|org|net|br|edu|gov)", x)]
    one <- paste(x, collapse = " ")
    # A key follows "[", ";" or whitespace and ends on an alphanumeric, so
    # trailing punctuation ("@Key." at the end of a sentence) is not captured.
    used <- regmatches(one, gregexpr("(?<=\\[|\\s|;)@[A-Za-z][A-Za-z0-9_-]*[A-Za-z0-9]",
                                     one, perl = TRUE))[[1]]
    used <- unique(sub("^@", "", used))
    miss <- setdiff(used, keys)
    if (length(miss))
      unresolved <- c(unresolved,
                      sprintf("%s: %s", basename(f), paste(miss, collapse = ", ")))
  }

  expect_equal(unresolved, character(0),
               info = paste("citation keys with no bib entry —",
                            "the vignette still renders and the reader gets [?]:",
                            paste(unresolved, collapse = "; ")))
})
