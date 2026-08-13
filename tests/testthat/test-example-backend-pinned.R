# ---------------------------------------------------------------------------
# An example may not let the machine choose its backend.
#
# dm_fit()'s default backend is torch where libtorch is installed and the
# reference R trainer otherwise, and the two produce different numbers under
# the same seed. Four \donttest examples called it unpinned while quoting
# figures measured under the R backend, so their printed output contradicted
# their own commentary on any machine with libtorch -- and only there.
#
# Measured on the shipped code: dm_sample's check prints sd 3.169 (5.4x the
# data's 0.590) and lag-1 -0.055 under `r`, matching its prose exactly; under
# torch the same lines print 0.663 (1.1x) and +0.613, under prose asserting
# the opposite. al_query_diffusion's "3.64 -> 1.02" is the R trace; torch
# gives 1.16 -> 0.63.
#
# CRAN has no libtorch, so this was invisible there and wrong everywhere else.
# ---------------------------------------------------------------------------

man_dir <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) && dir.exists(file.path(d, "man")))
      return(file.path(d, "man"))
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  NA_character_
}

test_that("every dm_fit() call in an example names its backend", {
  md <- man_dir()
  skip_if(is.na(md), "not running from a source checkout")
  rds <- list.files(md, pattern = "[.]Rd$", full.names = TRUE)
  skip_if(!length(rds), "no Rd files")

  offenders <- character(0)
  for (f in rds) {
    x <- paste(readLines(f, warn = FALSE), collapse = " ")
    calls <- regmatches(x, gregexpr("dm_fit\\([^)]+\\)", x))[[1]]
    # Drop the usage block (the signature) and \link cross-references.
    calls <- calls[!grepl("conditioning = NULL", calls, fixed = TRUE)]
    calls <- calls[!grepl("^dm_fit\\(\\)$", calls)]
    miss <- calls[!grepl("backend", calls, fixed = TRUE)]
    if (length(miss))
      offenders <- c(offenders, sprintf("%s: %s", basename(f),
                                        substr(miss, 1L, 70L)))
  }
  expect_equal(offenders, character(0),
               info = paste("these example calls let the machine pick the",
                            "backend, so their output depends on whether",
                            "libtorch is installed:",
                            paste(offenders, collapse = "; ")))
})

test_that("the two backends really do disagree, so the pin is load-bearing", {
  # If this ever stops being true the pin is merely cosmetic and the comments
  # explaining it should go. Guarded on libtorch, since without it there is
  # only one backend to compare.
  skip_if_not_installed("torch")
  skip_if_not(tryCatch(torch::torch_is_installed(), error = function(e) FALSE),
              "libtorch absent: only one backend available here")
  skip_on_cran()

  set.seed(1)
  stack <- array(stats::rnorm(16 * 8 * 8), dim = c(16L, 8L, 8L))
  fr <- suppressWarnings(dm_fit(stack, T = 20L, epochs = 30L, hidden = 16L,
                                lr = 0.02, seed = 1L, backend = "r"))
  ft <- suppressWarnings(dm_fit(stack, T = 20L, epochs = 30L, hidden = 16L,
                                lr = 0.02, seed = 1L, backend = "torch"))
  expect_false(isTRUE(all.equal(fr$history, ft$history)))
})
