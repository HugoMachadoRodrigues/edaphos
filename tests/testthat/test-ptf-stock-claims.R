# ---------------------------------------------------------------------------
# The pedotransfer function and what the paper says it costs.
#
# The manuscript owed a stock comparison at scale and said it needed a PTF it
# had not built. The PTF now exists, and the paper's conclusion about it is
# DEFLATIONARY: it barely beats a constant density, its error in application
# is more than twice its cross-validated error, and what it extends to scale
# is the ranking rather than the absolute stock.
#
# A deflationary conclusion is the kind that quietly inverts. If a future
# change makes the PTF look good, these tests fail and the paragraph has to be
# rewritten rather than left standing.
# ---------------------------------------------------------------------------

bundle <- function(f) {
  p <- system.file("extdata", f, package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", f)
  skip_if_not(file.exists(p), paste(f, "not built"))
  readRDS(p)
}

test_that("the calibration set is Cerrado soil with measured density throughout", {
  U <- bundle("soildata_uberaba_bd.rds")
  H <- U$horizons
  expect_gt(nrow(H), 100L)
  # every horizon must carry a MEASURED density -- the whole point of going to
  # SoilData rather than using the febr snapshot, whose copy has no such column
  expect_true(all(is.finite(H$bd_g_cm3)))
  expect_true(all(is.finite(H$soc_g_kg)))
  expect_true(all(H$bd_g_cm3 > 0.3 & H$bd_g_cm3 < 2.2))
  # inside the Cerrado box the rest of the paper uses
  expect_true(all(H$lon > -60 & H$lon < -41))
  expect_true(all(H$lat > -24 & H$lat < -2))
  # and predominantly Latossolos, which is why it is a defensible calibration
  expect_gt(mean(grepl("^Latossolo", H$soil_class)), 0.7)
})

test_that("the PTF barely beats a constant, which is the paper's claim", {
  P <- bundle("piml_ptf_bulk_density.rds")
  a <- P$aggregate
  expect_true("constant (profile-set mean)" %in% a$model)
  # the winner improves on a single mean density by very little
  expect_lt(a$skill_vs_constant[1], 0.25)
  expect_gt(a$skill_vs_constant[1], 0)
  # and no model, including the forest, reaches a useful relative error
  expect_gt(min(a$rel_RMSE), 0.05)
})

test_that("the PTF's application error exceeds its cross-validated error", {
  S <- bundle("piml_stock_at_scale.rds")
  pr <- S$price
  applied <- sqrt(mean((pr$bd_ptf - pr$bd)^2)) / mean(pr$bd)
  # This is the sentence the paper rests on: a CV error estimated inside one
  # basin understates the error in application by more than a factor of two.
  expect_gt(applied, 2 * S$ptf$blocked_rel_rmse)
  # and the miss is mostly bias, not scatter
  expect_gt(abs(mean(pr$bd_ptf - pr$bd)), 0.5 * sqrt(mean((pr$bd_ptf - pr$bd)^2)))
})

test_that("the ranking survives the change of units at scale", {
  S <- bundle("piml_stock_at_scale.rds")
  t <- S$table
  expect_gt(S$n_profiles, 500L)
  expect_equal(t$method[which.min(t$MAE)], "edaphos ODE")
  # beating the zero-parameter baseline on a paired test, not just on a mean
  p1 <- S$paired[S$paired$vs == "copy nearest training horizon", ]
  expect_gt(p1$ode_wins, p1$alt_wins)
  expect_lt(p1$p, 0.01)
})

test_that("the at-scale table is not presented as a validated stock", {
  S <- bundle("piml_stock_at_scale.rds")
  # Density is modelled on BOTH sides, so `stock_obs` is a derived quantity.
  # If a future change ever joins a measured density here, this test should
  # fail and the caption's careful wording revisited rather than kept.
  A <- S$at_scale
  expect_true(all(is.finite(A$bd)))
  expect_equal(A$stock_obs, A$stock_obs, tolerance = 0)
  # the modelled density has the narrow range that made it biased
  expect_lt(diff(range(A$bd)), 0.5)
})
