# ---------------------------------------------------------------------------
# Table 9's claim, bound to the bundle that produced it.
#
# The paper now says that none of the four acquisition policies separates
# itself from a uniform random draw, and that BatchBALD -- the most elaborate
# of them -- finishes behind it. That is a negative result, and negative
# results are exactly the ones that quietly invert when a default changes: a
# retuned surrogate, a different batch size, and the sentence in the paper is
# wrong with nothing to catch it.
#
# These tests do not re-run the loop. They pin the qualitative claims and the
# properties of the protocol the claims depend on.
# ---------------------------------------------------------------------------

bundle_al <- function() {
  p <- system.file("extdata", "al_policy_benchmark.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "al_policy_benchmark.rds")
  skip_if_not(file.exists(p), "AL policy bundle not built")
  readRDS(p)
}

test_that("the protocol is a fair comparison, not a demonstration", {
  A <- bundle_al()
  expect_true(all(c("random", "clhs", "batchbald") %in% A$arms))
  expect_gte(A$n_rep, 3L)

  # Every arm must appear in every repeat and reach the final round, or the
  # means being compared are over different things.
  fin <- A$runs[A$runs$round == A$rounds, ]
  n_per_arm <- table(fin$arm)
  expect_true(all(n_per_arm == A$n_rep))

  # Every arm must start from the SAME seed design: if round 0 differs between
  # arms within a repeat, the curves differ in more than acquisition.
  r0 <- A$runs[A$runs$round == 0L, ]
  by_rep <- split(r0$rmse, r0$rep)
  expect_true(all(vapply(by_rep, function(x) diff(range(x)) < 1e-9, TRUE)))
})

test_that("no acquisition silently degraded to random", {
  A <- bundle_al()
  # A policy that errors and falls back would score like random and be
  # reported as itself. The runner counts those; the count has to be visible.
  expect_true("n_fallback" %in% names(A))
  expect_equal(A$n_fallback, 0L)
})

test_that("no policy separates itself from a random draw", {
  A <- bundle_al()
  fin <- A$runs[A$runs$round == A$rounds, ]
  rnd <- fin$rmse[fin$arm == "random"]

  for (a in setdiff(A$arms, "random")) {
    x <- fin$rmse[fin$arm == a]
    # the difference is small in absolute terms ...
    expect_lt(abs(mean(x) - mean(rnd)), 0.02)
    # ... and not distinguishable by a paired test
    p <- suppressWarnings(stats::wilcox.test(x, rnd, paired = TRUE))$p.value
    expect_gt(p, 0.05)
  }
})

test_that("BatchBALD does not beat the random draw", {
  A <- bundle_al()
  fin <- A$runs[A$runs$round == A$rounds, ]
  # The paper singles this one out, so it gets its own assertion. If a future
  # change makes BatchBALD win, this fails and the sentence must be rewritten
  # rather than left standing.
  expect_gte(mean(fin$rmse[fin$arm == "batchbald"]),
             mean(fin$rmse[fin$arm == "random"]))
})

test_that("the error falls with the number of labels, which is the real finding", {
  A <- bundle_al()
  ag <- A$aggregate
  first <- ag$rmse[ag$arm == "random" & ag$round == 0L]
  last  <- ag$rmse[ag$arm == "random" & ag$round == A$rounds]
  expect_lt(last, first)
  # and the labelled set genuinely grew
  expect_gt(max(ag$n_labelled), A$seed_n)
})
