# ---------------------------------------------------------------------------
# Every exported prefix must be explained where a user would look.
#
# The API is organised by domain prefix -- causal_, piml_, foundation_ and so
# on -- and a reader meeting `spatial_block_folds()` or
# `active_learning_posterior()` in the index had nowhere to learn what family
# those belong to. Both were absent from the README and from the package-level
# Rd; the finding that raised this claimed five such prefixes, and measuring
# found two.
#
# The check is on the PREFIX, not on each function: 178 exports across 18
# prefixes, and requiring a mention of every function would be a documentation
# ratchet nobody would maintain. A prefix is the unit a reader navigates by.
# ---------------------------------------------------------------------------

test_that("every exported prefix is documented in the package-level Rd or README", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "NAMESPACE")) &&
        file.exists(file.path(d, "DESCRIPTION"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "not running from a source checkout")

  ns  <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exp <- gsub('^export\\(|\\)$|"', "", grep("^export\\(", ns, value = TRUE))
  skip_if(!length(exp), "no exports")
  prefixes <- unique(sub("_.*$", "", exp[grepl("_", exp)]))
  expect_gt(length(prefixes), 10L)

  where <- c(file.path(root, "man", "edaphos-package.Rd"),
             file.path(root, "README.md"))
  where <- where[file.exists(where)]
  skip_if(!length(where), "neither the package Rd nor the README is present")
  text <- paste(unlist(lapply(where, readLines, warn = FALSE)), collapse = " ")

  undocumented <- prefixes[!vapply(prefixes,
                                   function(p) grepl(paste0(p, "_"), text, fixed = TRUE),
                                   TRUE)]
  expect_equal(undocumented, character(0),
               info = paste("exported prefixes a reader cannot look up:",
                            paste(paste0(undocumented, "_"), collapse = ", ")))
})
