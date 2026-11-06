## print.edaphos_spatial_folds: the buffer percentage must be taken over the
## rows that could have been discarded.

test_that("discarded-to-buffer percentage is over candidate training rows", {
  data(br_cerrado, package = "edaphos", envir = environment())
  xy <- br_cerrado[seq(1, nrow(br_cerrado), by = 25), c("x", "y")]
  f <- spatial_block_folds(xy, k = 5, buffer_km = 10, seed = 1)
  # each fold's candidates are the rows outside its test block
  n_cand <- sum(f$n - lengths(f$test))
  expect_equal(n_cand, (f$k - 1L) * f$n)
  expect_equal(n_cand, sum(lengths(f$train)) + sum(f$n_buffered))
  out <- paste(utils::capture.output(print(f)), collapse = "\n")
  expect_match(out, sprintf("(%.1f%% of %d candidate training rows)",
                            100 * sum(f$n_buffered) / n_cand, n_cand),
               fixed = TRUE)
  # the old denominator, n * k, printed a smaller share
  expect_false(grepl(sprintf("%.1f%%", 100 * sum(f$n_buffered) / (f$n * f$k)),
                     out, fixed = TRUE))
})
