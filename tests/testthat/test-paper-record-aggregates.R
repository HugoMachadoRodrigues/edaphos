# ---------------------------------------------------------------------------
# The manuscript's prose claims, bound to paper_record_aggregates.rds.
#
# These numbers were computed at render time from records the 2026-08-28
# strip removed. data-raw/paper_record_aggregates.R recomputes them from the
# pre-strip records and ships the aggregates. Each test below is a sentence
# in paper/plos-manuscript.Rmd that would become false, with nothing else to
# catch it, if the bundle changed under it.
# ---------------------------------------------------------------------------

pra <- function() {
  p <- system.file("extdata", "paper_record_aggregates.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "paper_record_aggregates.rds")
  skip_if_not(file.exists(p), "paper_record_aggregates.rds not built")
  readRDS(p)
}

test_that("Table 7: the Pillar-2 interval undercovers, converged or not", {
  cg <- pra()$coverage
  expect_identical(cg$subset, c("all fits", "converged fits only"))
  # "covers about half the time against a nominal 90%"
  expect_gt(cg$picp[1], 0.40); expect_lt(cg$picp[1], 0.60)
  # "still misses a quarter of the time"
  expect_gt(1 - cg$picp[2], 0.20); expect_lt(1 - cg$picp[2], 0.30)
  # "the converged subset already has intervals ... times wider"
  expect_gt(cg$mpiw[2], cg$mpiw[1])
})

test_that("Table 9 and the PTF paragraph: the function barely beats a constant", {
  a <- pra()
  pt <- a$ptf_cv
  expect_identical(pt$model[1], "carbon only (log-linear)")
  expect_lt(pt$skill_vs_constant[1], 0.10)
  # "understates the error in application by more than a factor of two"
  expect_gt(a$ptf_in_application$rel_rmse / pt$rel_RMSE[1], 2)
  # "the function never predicts below" the lightest measured density
  expect_gt(a$ptf_in_application$bd_ptf_min, a$ptf_in_application$bd_range[1])
  # substituting it raises the stock error
  expect_gt(a$ptf_in_application$stock_mae_ptf,
            a$ptf_in_application$stock_mae_measured)
})

test_that("Table 15: held-out profiles lie 68 to 870 km from training data", {
  ed <- pra()$extrapolation_distance
  expect_equal(round(ed$min_km), 68)
  expect_equal(round(ed$max_km), 870)
  expect_equal(ed$n, 1095L)
})

test_that("the DAG fails its own test on both the pooled and spatial versions", {
  dt <- pra()$dag_test
  expect_equal(dt$n, 3077L)
  expect_gt(dt$n_rejected / dt$n_tests, 0.5)
  expect_gt(dt$n_rejected_spatial / dt$n_tests, 0.5)
  # "reduces the count", and the stated number of verdict changes is the
  # difference measured, not typed
  expect_lt(dt$n_rejected_spatial, dt$n_rejected)
  expect_gte(dt$n_verdict_changes, dt$n_rejected - dt$n_rejected_spatial)
  # "(clay against sand, conditioning on slope)"
  expect_match(dt$max_abs_r_test, "slgrds_c.*slgrds_s.*slop")
})

test_that("the bundle carries aggregates only", {
  a <- pra()
  flat <- unlist(a[setdiff(names(a), "provenance")], recursive = TRUE)
  expect_false(any(grepl("^(lon|lat|profile_id)$", names(flat))))
  expect_lt(length(flat), 1000L)
})
