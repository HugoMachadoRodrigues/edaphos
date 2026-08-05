# ---------------------------------------------------------------------------
# The simultaneous (sup-t) band on a fitted depth curve.
#
# Every band in this package used to be `apply(pred, 2, quantile)` -- a
# POINTWISE band, covering each depth taken alone. The manuscript drew one as
# a ribbon over 300-odd depths and called it "the 95% posterior band" for the
# profile, which is a claim about the whole curve that a pointwise band does
# not support. These tests check the fix where it matters: empirical coverage
# of a WHOLE curve, measured on the draws themselves.
# ---------------------------------------------------------------------------

fit_once <- function() {
  piml_profile_fit_bayesian(c(5, 15, 30, 60, 100),
                            c(25, 18, 12, 8, 6.5), seed = 1)
}

test_that("the pointwise band undercovers a whole curve and the sup-t band does not", {
  fit <- fit_once()
  z <- seq(0, 120, by = 2)
  p <- predict(fit, newdepths = z, interval = 0.95, seed = 1)
  M <- predict(fit, newdepths = z, seed = 1)          # the same draws

  inside <- function(lo, hi)
    mean(apply(M, 1L, function(r) all(r >= lo & r <= hi)))

  cov_pw  <- inside(p$lower, p$upper)
  cov_sim <- inside(p$lower_sim, p$upper_sim)

  # The point of the exercise: pointwise is not simultaneous.
  expect_lt(cov_pw, 0.90)
  # sup-t is calibrated by construction on these draws, so it should land on
  # nominal rather than merely above it.
  expect_gt(cov_sim, 0.92)
  expect_lt(cov_sim, 0.99)
  expect_gt(cov_sim, cov_pw)
})

test_that("the simultaneous band contains the pointwise one at every depth", {
  fit <- fit_once()
  p <- predict(fit, newdepths = seq(0, 100, by = 5), interval = 0.9, seed = 2)
  expect_true(all(p$lower_sim <= p$lower))
  expect_true(all(p$upper_sim >= p$upper))
  # The calibrated one-sided level must be at or below the nominal one --
  # that inequality is exactly what guarantees the containment just checked.
  expect_lte(attr(p, "supt_level"), (1 - 0.9) / 2)
  expect_gt(attr(p, "supt_level"), 0)
  expect_equal(attr(p, "interval"), 0.9)
})

test_that("the band widens with the number of depths, which is why it exists", {
  fit <- fit_once()
  # More depths means more chances for a draw to escape, so the calibrated
  # level must fall -- a LOWER level is a WIDER band.
  few  <- predict(fit, newdepths = c(10, 50), interval = 0.95, seed = 3)
  many <- predict(fit, newdepths = seq(0, 200, by = 1), interval = 0.95,
                  seed = 3)
  expect_lte(attr(many, "supt_level"), attr(few, "supt_level"))

  # and that must show up as width at a depth both bands cover
  w <- function(p, z) {
    i <- which.min(abs(p$depth - z))
    (p$upper_sim[i] - p$lower_sim[i]) / (p$upper[i] - p$lower[i])
  }
  expect_gte(w(many, 50), w(few, 50))
})

test_that("a single depth degenerates to the pointwise interval", {
  fit <- fit_once()
  p <- predict(fit, newdepths = 25, interval = 0.95, seed = 4)
  # With one depth the supremum over depths is just |z|, so the sup-t band is
  # the pointwise band up to the median/MAD versus mean/quantile parameterisation.
  expect_equal(nrow(p), 1L)
  expect_lt(abs((p$upper_sim - p$lower_sim) / (p$upper - p$lower) - 1), 0.15)
})
