# ---------------------------------------------------------------------------
# Table 5's claims, bound to the bundle that produced them.
#
# The manuscript now asserts something specific and falsifiable: that the
# geostatistical model's interval widens with distance to the training data
# while the graph network's does not, even though its error grows. Those are
# three signs and one significance, and they are the kind of statement that
# quietly inverts when a method is re-tuned or a fold definition changes.
#
# These tests do not re-derive the correlations -- that is the data-raw
# script's job. They pin the QUALITATIVE claims the paper makes, so that a
# re-run which reverses one of them fails here rather than in review.
# ---------------------------------------------------------------------------

bundle_extra <- function() {
  p <- system.file("extdata", "interval_width_vs_extrapolation.rds",
                   package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata",
                                 "interval_width_vs_extrapolation.rds")
  skip_if_not(file.exists(p), "extrapolation bundle not built")
  readRDS(p)
}

test_that("the extrapolation bundle has the shape the manuscript reads", {
  E <- bundle_extra()
  expect_true(all(c("per_profile", "summary", "n_folds", "buffer_km") %in%
                    names(E)))
  expect_setequal(E$summary$method, c("P7", "P5", "P10"))
  expect_true(all(c("width_rho", "width_p", "width_rho_pc", "error_rho",
                    "error_p") %in% names(E$summary)))

  # every held-out profile is scored, and the buffer is honoured
  expect_gt(nrow(E$per_profile), 1000)
  expect_gte(min(E$per_profile$d_km), E$buffer_km)
})

test_that("the geostatistical interval widens with distance and the graph one does not", {
  E <- bundle_extra()
  g <- function(m, col) E$summary[[col]][E$summary$method == m]

  # P7: strongly positive, and it survives the covariate-space control --
  # which is what licenses calling the widening geographic rather than a
  # response to unusual covariates.
  expect_gt(g("P7", "width_rho"), 0.5)
  expect_gt(g("P7", "width_rho_pc"), 0.5)

  # P10: not positive. Stated as "not greater than a trivial amount" rather
  # than "negative", because the claim in the paper is that the interval
  # carries no extrapolation information, not that it is perverse.
  expect_lt(g("P10", "width_rho"), 0.05)
  expect_lt(g("P10", "width_rho_pc"), 0.05)

  # and the ordering between them, which is the sentence in the abstract
  expect_gt(g("P7", "width_rho_pc"), g("P5", "width_rho_pc"))
  expect_gt(g("P5", "width_rho_pc"), g("P10", "width_rho_pc"))
})

test_that("the graph network's error does grow with extrapolation distance", {
  E <- bundle_extra()
  g <- function(m, col) E$summary[[col]][E$summary$method == m]

  # This is the half that makes the previous test a defect rather than a
  # curiosity: the error moves and the interval does not.
  expect_gt(g("P10", "error_rho"), 0)
  expect_lt(g("P10", "error_p"), 0.01)

  # and P7's does not -- kriging degrades toward the mean, which is a decent
  # predictor, so its errors do not grow the way the network's do
  expect_gt(g("P7", "error_p"), 0.05)
})

test_that("the six-pillar bundle still supports the ranking claims after the interval fixes", {
  p <- system.file("extdata", "benchmark_wosis_6pilar.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "benchmark_wosis_6pilar.rds")
  skip_if_not(file.exists(p))
  a <- readRDS(p)$cv_aggregate
  pick <- function(m) a[a$method == m, ]

  # The effective-df correction moved P6's coverage a long way. It must not
  # have moved its ACCURACY, because it only touches the noise injected into
  # the interval -- if RMSE changed, something else changed too.
  expect_lt(pick("P6 Quantum KRR")$nse_mean, 0)
  expect_lt(pick("P10 GAT (trained attention)")$nse_mean, 0)
  expect_gt(pick("P1 OLS (DAG-selected covariates)")$nse_mean, 0.15)

  # P6 remains the sharpest and the least covered: the overconfidence the
  # paper points at survived the correction rather than being an artefact of it
  expect_equal(a$method[which.min(a$mpiw90_mean)], "P6 Quantum KRR")
  expect_equal(a$method[which.min(a$picp90_mean)], "P6 Quantum KRR")
})
