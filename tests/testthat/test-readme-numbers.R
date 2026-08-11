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
