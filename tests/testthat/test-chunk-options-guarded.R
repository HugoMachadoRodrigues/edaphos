# ---------------------------------------------------------------------------
# A chunk option may not call into a package it has not checked for.
#
# knitr evaluates chunk options before the chunk. If the option calls
# `pkg::fn()` and pkg is absent, the option ERRORS and the vignette build
# fails -- it does not quietly evaluate to FALSE and skip. The failure lands
# on whoever builds the package, not on whoever wrote the vignette.
#
# vignettes/pilar4-simclr-embeddings.Rmd had:
#   eval = requireNamespace("torch", ...) && reticulate::py_available() || .torch_ok
# On a machine with torch and without reticulate that raises rather than
# skips. It was also pointless twice over: `&&` binds tighter than `||`, so
# the reticulate clause could only change the answer in the case where it
# crashes, and the chunk trains a MoCo encoder -- pure torch, no Python.
#
# vignettes/pilar6-quantum.Rmd shows the correct idiom in six places:
# requireNamespace("reticulate", quietly = TRUE) && reticulate::py_module_available(...)
# -- the guard first, and && short-circuits. This test encodes that idiom.
# ---------------------------------------------------------------------------

test_that("no chunk option calls a package before checking it is installed", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (dir.exists(file.path(d, "vignettes")) &&
        file.exists(file.path(d, "DESCRIPTION"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "not running from a source checkout")

  fs <- list.files(file.path(root, "vignettes"), "[.]Rmd$",
                   full.names = TRUE, recursive = TRUE)
  skip_if(!length(fs), "no vignettes")

  offenders <- character(0)
  for (f in fs) {
    opts <- grep("^```\\{r", readLines(f, warn = FALSE), value = TRUE)
    for (h in opts[grepl("[a-zA-Z0-9.]+::", opts)]) {
      pkgs <- unique(sub("::$", "",
                regmatches(h, gregexpr("[a-zA-Z][a-zA-Z0-9.]*::", h))[[1]]))
      for (p in pkgs) {
        # Guarded only if requireNamespace("p") appears BEFORE the p:: call in
        # the same expression, so && can short-circuit past it.
        i_req <- regexpr(sprintf('requireNamespace\\("%s"', p), h)
        i_use <- regexpr(sprintf("%s::", p), h)
        if (i_req == -1L || i_req > i_use)
          offenders <- c(offenders,
                         sprintf("%s: %s", basename(f), substr(trimws(h), 1L, 90L)))
      }
    }
  }

  expect_equal(unique(offenders), character(0),
               info = paste("chunk options calling an unchecked package —",
                            "these raise rather than skip when it is absent:",
                            paste(unique(offenders), collapse = " | ")))
})
