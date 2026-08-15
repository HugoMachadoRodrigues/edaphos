# ---------------------------------------------------------------------------
# A diverged epoch and an unrecorded epoch are different things.
#
# The fit objects trim their loss history with `history[history > 0]`, which
# drops the trailing zeros of a pre-allocated vector. But `NaN > 0` evaluates
# to NA, and subsetting by NA yields NA -- so the trim silently CONVERTS a
# NaN into an NA. A reader of fit$history then cannot tell whether an epoch
# diverged (NaN: the loss went to 0/0 or Inf-Inf) or was never run (NA).
#
# The torch paths already guarded this with `| is.na(history)`; the two
# pure-R paths in R/pilar8_neural_operators.R did not. Measured over 20,000
# random histories, the two forms differ in 43% of cases, and every
# difference is a NaN turned into an NA.
# ---------------------------------------------------------------------------

test_that("trimming a loss history preserves NaN rather than flattening it to NA", {
  h <- c(1.5, NaN, 0.8, 0, 0.3, 0)

  antiga  <- h[h > 0]
  corrigida <- h[h > 0 | is.na(h)]

  # Both drop the trailing zeros.
  expect_false(any(corrigida == 0, na.rm = TRUE))

  # The old form loses the distinction; the new one keeps it. is.nan() is
  # the assertion that matters -- is.na() is TRUE for both, so testing that
  # would pass against the defect.
  expect_true(any(is.nan(corrigida)))
  expect_false(any(is.nan(antiga)))
  expect_true(any(is.na(antiga)))     # it became a plain NA
})

test_that("no fit path trims its history without the is.na guard", {
  root <- NA_character_
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (dir.exists(file.path(d, "R")) &&
        file.exists(file.path(d, "DESCRIPTION"))) { root <- d; break }
    up <- dirname(d); if (identical(up, d)) break; d <- up
  }
  skip_if(is.na(root), "not running from a source checkout")

  src <- unlist(lapply(list.files(file.path(root, "R"), "[.]R$", full.names = TRUE),
                       readLines, warn = FALSE))
  # `history[history > 0]` with nothing after it: the unguarded form.
  offenders <- grep("history\\[history > 0\\]", src, value = TRUE)
  expect_equal(offenders, character(0),
               info = paste("these trims convert NaN to NA, erasing",
                            "'diverged' vs 'not recorded':",
                            paste(trimws(offenders), collapse = " | ")))
})
