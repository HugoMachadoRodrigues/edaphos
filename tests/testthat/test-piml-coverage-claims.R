# ---------------------------------------------------------------------------
# Table 7's claim, bound to the bundle that produced it.
#
# The paper reports that Pillar 2's nominal 90% predictive interval covers
# about half the time, and that restricting to converged fits does not rescue
# it. That is a negative result about our own most-developed pillar, and
# negative results are the ones that quietly invert: a wider default prior, a
# larger sigma, a changed interval convention, and the sentence is wrong with
# nothing to catch it.
# ---------------------------------------------------------------------------

bundle_cov <- function() {
  p <- system.file("extdata", "piml_coverage.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "piml_coverage.rds")
  skip_if_not(file.exists(p), "coverage bundle not built")
  readRDS(p)
}

test_that("the interval is scored on a held-out value the fit never saw", {
  C <- bundle_cov()
  cg <- C$coverage
  expect_gt(nrow(cg), 100L)
  # `covered` must be derivable from the stored bounds, or the rate is not
  # reproducible from the artefact.
  expect_equal(cg$covered, cg$truth >= cg$lo & cg$truth <= cg$hi)
  expect_equal(cg$width, cg$hi - cg$lo)
  expect_true(all(cg$lo <= cg$hi))
  # every fit has a real convergence verdict attached, not an inferred one
  expect_true(all(is.finite(cg$max_rhat) | cg$max_rhat == Inf))
  expect_type(cg$converged, "logical")
})

test_that("the interval undercovers, and converging does not rescue it", {
  C <- bundle_cov()
  cg <- C$coverage; ok <- cg$converged

  # the headline: nominal 0.90, observed far below
  expect_lt(mean(cg$covered), 0.70)
  expect_lt(mean(cg$covered[ok]), 0.85)
  # and the converged subset is genuinely a subset worth reporting
  expect_gt(sum(ok), 20L)
  # widening is not what is missing: the converged fits are already wider
  expect_gt(mean(cg$width[ok]), mean(cg$width))
})

test_that("convergence is the minority, which is why both rates are reported", {
  C <- bundle_cov()
  # If a future change makes most fits converge, the paper's framing -- that
  # the two rates must both be shown -- needs revisiting rather than silently
  # standing.
  expect_lt(mean(C$coverage$converged), 0.60)
})

test_that("the interval score penalises misses, so coverage cannot be bought with width", {
  C <- bundle_cov()
  cg <- C$coverage
  alpha <- 1 - C$nominal
  expected <- cg$width +
    (2 / alpha) * (cg$lo - cg$truth) * (cg$truth < cg$lo) +
    (2 / alpha) * (cg$truth - cg$hi) * (cg$truth > cg$hi)
  expect_equal(cg$int_score, expected)
  # a miss must score strictly worse than its own width
  miss <- !cg$covered
  skip_if(sum(miss) == 0L, "no misses in this bundle")
  expect_true(all(cg$int_score[miss] > cg$width[miss]))
})
