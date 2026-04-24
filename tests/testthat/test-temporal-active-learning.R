## Tests for the Pilar 3 x Pilar 5 Temporal AL bridge (v2.1.2).

test_that("al_query_temporal: returns top cells sorted by priority", {
  # Build a minimal edaphos_temporal_kalman-like object (just the
  # two slots al_query_temporal actually uses)
  set.seed(1L)
  gain <- matrix(stats::runif(25), 5L, 5L)
  sd_m <- matrix(stats::runif(25), 5L, 5L)
  ku <- structure(list(
    gain_row_norm = gain,
    analysis_sd   = sd_m
  ), class = "edaphos_temporal_kalman")

  q <- al_query_temporal(ku, n_select = 5L, combine = "gain")
  expect_s3_class(q, "edaphos_temporal_al_query")
  expect_equal(nrow(q), 5L)
  expect_true(all(c("row", "col", "gain", "analysis_sd", "priority")
                    %in% names(q)))
  # Top row has the highest priority
  expect_gte(q$priority[1], q$priority[nrow(q)])
})

test_that("al_query_temporal: combine modes change the ranking coherently", {
  set.seed(1L)
  gain <- matrix(stats::runif(16), 4L, 4L)
  sd_m <- matrix(stats::runif(16), 4L, 4L)
  ku <- structure(list(gain_row_norm = gain, analysis_sd = sd_m),
                   class = "edaphos_temporal_kalman")

  q_gain    <- al_query_temporal(ku, n_select = 16L, combine = "gain")
  q_gainsd  <- al_query_temporal(ku, n_select = 16L, combine = "gain_sd")
  q_norm    <- al_query_temporal(ku, n_select = 16L,
                                   combine = "gain_sd_normalised")
  # All three return 16 rows, sorted by priority
  for (q in list(q_gain, q_gainsd, q_norm)) {
    expect_equal(nrow(q), 16L)
    expect_true(!is.unsorted(-q$priority))
  }
  # The three rankings generally differ unless matrices are degenerate
  expect_false(identical(q_gain$row, q_gainsd$row))
})

test_that("al_query_temporal: candidate_coords filter restricts scoring", {
  gain <- matrix(runif(25), 5L, 5L)
  sd_m <- matrix(runif(25), 5L, 5L)
  ku <- structure(list(gain_row_norm = gain, analysis_sd = sd_m),
                   class = "edaphos_temporal_kalman")
  cand <- data.frame(row = c(1, 3), col = c(1, 2))
  q <- al_query_temporal(ku, candidate_coords = cand,
                           n_select = 5L, combine = "gain")
  # Only the 2 candidate cells should be returned
  expect_equal(nrow(q), 2L)
  expect_true(all(paste(q$row, q$col)
                    %in% paste(cand$row, cand$col)))
})

test_that("al_query_temporal: errors without required Kalman fields", {
  bad <- structure(list(other = 1),
                     class = "edaphos_temporal_kalman")
  expect_error(al_query_temporal(bad))
})
