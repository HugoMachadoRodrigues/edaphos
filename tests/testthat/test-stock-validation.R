# ---------------------------------------------------------------------------
# Table 7's claim, bound to the bundle that produced it.
#
# The paper says the equation beats its baselines when scored in Mg/ha rather
# than g/kg, and that this survives the change of units. Two things could
# quietly invalidate it: the conversion could stop using the MEASURED density
# (at which point the number scores a pedotransfer function, not the depth
# model), and the task could drift back to the deepest-horizon holdout, which
# this archive cannot support in stock units.
# ---------------------------------------------------------------------------

bundle_sv <- function() {
  p <- system.file("extdata", "piml_stock_validation.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "piml_stock_validation.rds")
  skip_if_not(file.exists(p), "stock validation bundle not built")
  readRDS(p)
}

test_that("the stock is built from a MEASURED density, not a predicted one", {
  S <- bundle_sv()
  sv <- S$stock
  expect_false(is.null(sv))
  expect_true(all(is.finite(sv$bd)), info = "a missing density means a gap-fill crept in")
  expect_true(all(sv$bd > 0.1 & sv$bd < 2.5), info = "outside any real soil density")

  # The observation and the prediction must go through the SAME arithmetic --
  # otherwise the comparison scores the conversion rather than the model.
  expect_equal(sv$stock_ode, sv$conc_hat * sv$bd * sv$thickness * 0.1,
               tolerance = 1e-8)
  expect_equal(sv$stock_obs, sv$conc_obs * sv$bd * sv$thickness * 0.1,
               tolerance = 1e-6)
})

test_that("the held-out horizon is interior, which is what the caption claims", {
  S <- bundle_sv()
  # An interior holdout always leaves horizons on BOTH sides, so the training
  # set is larger than what a deepest-horizon split would leave.
  expect_true(all(S$stock$n_train >= 3L))
  expect_match(S$task, "interior")
  # and the paper's statement about why: the deepest-horizon task is not
  # available in stock units on this archive
  expect_lt(nrow(S$stock), S$n_eligible + 1L)
})

test_that("the equation beats both zero-parameter baselines", {
  S <- bundle_sv(); sv <- S$stock
  e_ode  <- abs(sv$stock_ode  - sv$stock_obs)
  e_last <- abs(sv$stock_last - sv$stock_obs)
  e_mean <- abs(sv$stock_mean - sv$stock_obs)

  expect_lt(mean(e_ode), mean(e_last))
  expect_lt(mean(e_ode), mean(e_mean))
  expect_lt(suppressWarnings(
    stats::wilcox.test(e_ode, e_last, paired = TRUE))$p.value, 0.05)
})

test_that("the ranking is the same in g/kg as in Mg/ha", {
  S <- bundle_sv(); sv <- S$stock
  # This is the sentence the paper rests on -- that the conclusion survives
  # the change of units. Converting the baseline back out of stock recovers
  # the concentration it was built from.
  conc_last <- sv$stock_last / (sv$bd * sv$thickness * 0.1)
  wins_conc  <- mean(abs(sv$conc_hat  - sv$conc_obs)) <
                mean(abs(conc_last    - sv$conc_obs))
  wins_stock <- mean(abs(sv$stock_ode - sv$stock_obs)) <
                mean(abs(sv$stock_last - sv$stock_obs))
  expect_equal(wins_conc, wins_stock)
})
