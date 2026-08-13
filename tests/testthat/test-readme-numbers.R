# ---------------------------------------------------------------------------
# The README's benchmark tables, bound to the bundles that produced them.
#
# They are hand-maintained markdown, and they had drifted: after a change to
# the Pillar-7 phi bracket the README still showed the old RMSE in both
# tables, with nothing to notice. A reader's first contact with this package
# is the README, so a number there that disagrees with the shipped .rds is
# worse than the same drift inside a vignette.
#
# These tests parse the tables out of README.md and compare every cell to the
# bundle. They also pin WHICH quantity each column holds: the first table is
# the POOLED result (one number over all folds), not the mean of per-fold
# numbers, and confusing the two silently changes P1's R-squared from +0.162
# to +0.069.
# ---------------------------------------------------------------------------

# Anchored to the package root by walking up to the DESCRIPTION, not by
# relative paths: under a full test_dir() run another file can leave the
# working directory somewhere else, and a relative path then finds either
# nothing or the wrong README.
readme_path <- function() {
  d <- normalizePath(".", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "DESCRIPTION")) &&
        file.exists(file.path(d, "README.md")))
      return(file.path(d, "README.md"))
    up <- dirname(d)
    if (identical(up, d)) break
    d <- up
  }
  NA_character_
}

parse_table <- function(md, header_regex, n_rows) {
  h <- grep(header_regex, md)
  if (!length(h)) return(NULL)
  first <- h[1] + 2L
  last  <- h[1] + 1L + n_rows
  if (last > length(md)) return(NULL)
  rows <- md[first:last]
  # every row must actually be a table row, or the table moved and the
  # positional slice is reading prose
  if (!all(grepl("^\\|", rows))) return(NULL)
  cells <- lapply(strsplit(rows, "\\|"), function(x) trimws(x[-1]))
  if (!all(lengths(cells) >= 4L)) return(NULL)
  # Byte-wise, not locale-wise. The tables use U+2212 MINUS SIGN, and a full
  # test_dir() run initialises reticulate/qiskit, which changes the locale and
  # makes the multibyte character invalid input to gsub(). Matching its UTF-8
  # bytes directly sidesteps the locale entirely.
  num <- function(s) {
    s <- gsub("\xe2\x88\x92", "-", s, useBytes = TRUE)
    as.numeric(gsub("[*+ ]", "", s, useBytes = TRUE))
  }
  list(method = vapply(cells, `[`, "", 1L), cells = cells, num = num)
}

test_that("the README's pooled benchmark table matches the bundle", {
  rp <- readme_path(); skip_if(is.na(rp), "README.md not found")
  f <- system.file("extdata", "benchmark_wosis_6pilar.rds", package = "edaphos")
  if (!nzchar(f)) f <- file.path("inst", "extdata", "benchmark_wosis_6pilar.rds")
  skip_if_not(file.exists(f), "benchmark bundle not built")

  B <- readRDS(f)
  p <- B$cv_pooled
  p <- p[order(p$pooled_rmse), ]
  md <- readLines(rp, warn = FALSE, encoding = "UTF-8")
  tb <- parse_table(md, "^\\| Method \\| RMSE \\| R", nrow(p))
  skip_if(is.null(tb), "pooled table not found in README")

  # THE POOLED QUANTITY, not the mean of per-fold values. They differ: P1's
  # pooled R-squared is +0.162 and its per-fold mean is +0.069.
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 2L)),
               round(p$pooled_rmse, 3), tolerance = 5e-4)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 3L)),
               round(p$pooled_r2_vs_global_mean, 3), tolerance = 5e-4)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 4L)),
               round(p$nse_vs_training_fold_mean, 3), tolerance = 5e-4)

  # rows in RMSE order, and the bolded NSE is the best one
  expect_false(is.unsorted(p$pooled_rmse))
  bolded <- grep("\\*\\*", vapply(tb$cells, `[`, "", 4L))
  expect_equal(bolded, which.max(p$nse_vs_training_fold_mean))
})

test_that("the README's buffer table matches the bundle", {
  rp <- readme_path(); skip_if(is.na(rp), "README.md not found")
  f <- system.file("extdata", "buffer_effect.rds", package = "edaphos")
  if (!nzchar(f)) f <- file.path("inst", "extdata", "buffer_effect.rds")
  skip_if_not(file.exists(f), "buffer bundle not built")

  b <- readRDS(f)$comparison
  b <- b[order(b$rmse_mean_buf), ]
  md <- readLines(rp, warn = FALSE, encoding = "UTF-8")
  tb <- parse_table(md, "^\\| Method \\| unbuffered \\| buffered", nrow(b))
  skip_if(is.null(tb), "buffer table not found in README")

  expect_equal(tb$num(vapply(tb$cells, `[`, "", 2L)),
               round(b$rmse_mean_unbuf, 3), tolerance = 5e-4)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 3L)),
               round(b$rmse_mean_buf, 3), tolerance = 5e-4)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 4L)),
               round(b$d_rmse, 3), tolerance = 5e-4)

  # The claim the surrounding prose makes: the buffer costs every method
  # something and never reorders them.
  expect_true(all(b$d_rmse >= -5e-4))
  expect_equal(b$rank_buf, b$rank_unbuf)
})

test_that("the README's quantum-foundation table matches the rebuilt bundle", {
  # THIS TABLE IS WHY THE FILE EXISTS TWICE OVER. It published `0.00` for
  # three methods and `0.08` for ranger for four months after the clamp that
  # produced those zeros was removed, under the conclusion that the four
  # regressors were "statistically indistinguishable". The zeros were floored
  # negatives: 17 of 20 fold-by-method values were below zero. Nothing
  # compared the table to the bundle, so nothing noticed.
  rp <- readme_path(); skip_if(is.na(rp), "README.md not found")
  f <- system.file("extdata", "quantum_foundation_cerrado.rds", package = "edaphos")
  if (!nzchar(f)) f <- file.path("inst", "extdata", "quantum_foundation_cerrado.rds")
  skip_if_not(file.exists(f), "quantum bundle not built")

  B <- readRDS(f)
  s <- as.data.frame(B$cv_summary)
  s <- s[order(-s$r2_pooled), ]
  md <- readLines(rp, warn = FALSE, encoding = "UTF-8")
  tb <- parse_table(md, "^\\| Method +\\| RMSE \\| MAE \\| R. \\(pooled\\)", nrow(s))
  skip_if(is.null(tb), "quantum table not found in README")

  expect_equal(tb$method, s$method)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 2L)),
               round(s$rmse_pooled, 1), tolerance = 5e-2)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 3L)),
               round(s$mae_mean, 1), tolerance = 5e-2)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 4L)),
               round(s$r2_pooled, 3), tolerance = 5e-4)
  expect_equal(tb$num(vapply(tb$cells, `[`, "", 5L)),
               round(s$r2_mean, 3), tolerance = 5e-4)

  # The prose states the profile count; it said 1 095 while the bundle used
  # 1 081. Matched on the single line rather than on the whole file collapsed
  # into one string: a failure here should print that line, not 110 kB of
  # README, and the whole-file form reports only that "something, somewhere,
  # does not match".
  hdr <- grep("Cerrado profiles \\(synthetic-stack mode\\)", md, value = TRUE)
  expect_length(hdr, 1L)
  expect_true(grepl(format(B$n_profiles_used, big.mark = " "), hdr, fixed = TRUE))
})

test_that("the quantum bundle carries no censored R-squared", {
  # The defect this whole section documents, asserted directly: a goodness-of
  # fit column with exact zeros in it is the signature of a floor. Negative
  # values are expected here and must survive into the artefact.
  f <- system.file("extdata", "quantum_foundation_cerrado.rds", package = "edaphos")
  if (!nzchar(f)) f <- file.path("inst", "extdata", "quantum_foundation_cerrado.rds")
  skip_if_not(file.exists(f), "quantum bundle not built")

  B <- readRDS(f)
  expect_equal(sum(B$cv_table$r2 == 0), 0L)
  expect_gt(B$n_negative_r2, 0L)
  expect_equal(B$n_negative_r2, sum(B$cv_table$r2 < 0))

  # And the bundle must say what it is, so a reader of the .rds alone cannot
  # mistake a white-noise negative control for a covariate benchmark.
  expect_identical(B$stack_mode, "synthetic")
  expect_match(B$stack_note, "negative control")

  # Every pooled R-squared is negative: the finding the README states.
  expect_true(all(as.data.frame(B$cv_summary)$r2_pooled < 0))
})
