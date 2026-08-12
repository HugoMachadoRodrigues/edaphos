# ---------------------------------------------------------------------------
# A masked loss for ragged depth supports, and the negative result it enabled.
#
# `no_deeponet_fit()` wanted a rectangular target matrix over one shared depth
# vector. Real pedons carry four to thirty-one horizons at irregular
# boundaries, so that layout cannot hold them, and the manuscript reported the
# pillar as demonstrated on synthetic profiles for want of it. NA in `targets`
# is now the mask.
#
# Two things need pinning: that the mask actually works (an NA must not become
# a NaN loss, and must not be trained on), and that the negative result it
# produced still holds -- on measured pedons the operator loses to the mean
# value at each depth node.
# ---------------------------------------------------------------------------

toy <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  z <- c(5, 15, 30, 60, 100)
  cov <- matrix(rnorm(n * 3), n, 3)
  tg <- outer(seq_len(n), z,
              function(i, d) 25 * exp(-d / 60) + cov[i, 1] * 2 + rnorm(length(d), 0, 0.3))
  list(z = z, cov = cov, tg = tg)
}

test_that("an NA target does not poison the loss", {
  d <- toy()
  tg <- d$tg
  tg[sample(length(tg), round(0.25 * length(tg)))] <- NA
  fit <- no_deeponet_fit(d$z, tg, d$cov, epochs = 100L, seed = 1L)
  # Before the mask an NA produced a NaN loss and the fit ran on regardless.
  expect_true(all(is.finite(fit$history)))
  p <- predict(fit, d$cov)
  expect_true(all(is.finite(p)))
  expect_equal(dim(p), dim(tg))
})

test_that("the mask excludes the hidden cells from training, not from prediction", {
  d <- toy()
  tg <- d$tg
  hidden <- sample(length(tg), round(0.25 * length(tg)))
  tg_na <- tg; tg_na[hidden] <- NA

  fit <- no_deeponet_fit(d$z, tg_na, d$cov, epochs = 300L, seed = 1L)
  p <- predict(fit, d$cov)
  # The operator must still predict at the hidden cells -- that is the whole
  # point of a trunk that takes a depth as a query -- and do it worse there
  # than where it was trained, or the mask was not doing anything.
  e_seen   <- sqrt(mean((p - tg)[-hidden]^2))
  e_hidden <- sqrt(mean((p - tg)[hidden]^2))
  expect_true(is.finite(e_hidden))
  expect_gt(e_hidden, e_seen)
  # but not catastrophically: it learned a depth function, not noise
  expect_lt(e_hidden, 5 * e_seen)
})

test_that("a fully unobserved row or column is refused, not silently fitted", {
  d <- toy()
  tg <- d$tg; tg[3, ] <- NA
  expect_error(no_deeponet_fit(d$z, tg, d$cov, epochs = 10L, seed = 1L),
               "no measured depth")
  tg2 <- d$tg; tg2[, 2] <- NA
  expect_error(no_deeponet_fit(d$z, tg2, d$cov, epochs = 10L, seed = 1L),
               "unmeasured in every observation")
})

test_that("on measured pedons the operator loses to the depth-node mean", {
  p <- system.file("extdata", "pilar8_real_pedons.rds", package = "edaphos")
  if (!nzchar(p)) p <- file.path("inst", "extdata", "pilar8_real_pedons.rds")
  skip_if_not(file.exists(p), "Pillar 8 real-pedon bundle not built")
  R8 <- readRDS(p)
  t8 <- R8$table

  expect_gt(R8$n_profiles, 500L)
  expect_gt(R8$frac_observed, 0.5)   # standard nodes, not the sparse union
  # The paper's claim, which is negative and therefore the kind that inverts
  # quietly: the operator is beaten by the training-set mean at each node.
  dn <- t8$RMSE[t8$method == "DeepONet (real pedons)"]
  mn <- t8$RMSE[t8$method == "training-set node mean"]
  expect_gt(dn, mn)
  expect_lt(t8$skill[t8$method == "DeepONet (real pedons)"], 0)
  # and it does clear the one-sample baseline, which is the other half
  expect_lt(dn, t8$RMSE[t8$method == "carry the shallowest value down"])
  # losing at every node separately, not on average
  expect_true(all(R8$by_node$rmse_deeponet >= R8$by_node$rmse_mean))
})
