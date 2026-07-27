## Regression for the Pilar 8 target un-standardisation defect.
##
## `.no_standardise()` centres and scales targets per depth, so
## `tgt_std$center` / `$scale` are vectors of length n_depths.  Every
## predict() path used `[1L]` -- the topsoil constants -- for all
## depths, so deep predictions were shifted by (topsoil mean - subsoil
## mean) and mis-scaled by the ratio of their standard deviations.
##
## The training loss is computed entirely on the standardised scale, so
## it fell normally while the returned predictions were unusable: on the
## v4.0.0 code the DeepONet scored R^2 = -10.6 on a problem where a
## random forest scored +0.985.

.mk_profiles <- function(n = 90L, n_depths = 20L, seed = 5L) {
  set.seed(seed)
  depths <- seq(2.5, 150, length.out = n_depths)
  cov <- cbind(clay   = stats::runif(n, 0.10, 0.60),
               map    = stats::runif(n, 0.80, 1.60),
               relief = stats::runif(n, 0.00, 1.00))
  prof <- function(p, z) {
    y0 <- 20 + 25 * p[["clay"]]; yinf <- 2 + 6 * p[["map"]]
    lam <- 0.05 + 0.04 * p[["relief"]]; mu <- 0.02 + 0.01 * p[["clay"]]
    yinf + (y0 - yinf) * exp(-(lam / mu) * (1 - exp(-mu * z)))
  }
  y <- t(apply(cov, 1L, prof, z = depths))
  list(depths = depths, cov = cov, y = y, prof = prof)
}

test_that(".no_unstandardise_targets inverts .no_standardise exactly", {
  d <- .mk_profiles()
  st <- edaphos:::.no_standardise(d$y)

  back <- edaphos:::.no_unstandardise_targets(st$X, st, d$depths)
  expect_equal(back, d$y, tolerance = 1e-10)

  # The per-depth constants must genuinely differ -- otherwise this
  # test would pass even with the scalar bug in place.  The topsoil /
  # subsoil mean gap has to dominate the within-depth spread for the
  # `[1L]` shortcut to be detectably wrong.
  expect_gt(max(st$center) - min(st$center), 3 * max(st$scale))
})

test_that(".no_unstandardise_targets interpolates constants off-grid", {
  d  <- .mk_profiles()
  st <- edaphos:::.no_standardise(d$y)

  z_new <- c(10, 45, 90, 140)
  Z <- matrix(0, 3L, length(z_new))     # standardised zeros -> the mean
  out <- edaphos:::.no_unstandardise_targets(Z, st, d$depths, z_new)

  # A standardised zero must map onto the (interpolated) profile mean
  # at that depth, which decreases monotonically down the profile.
  expect_equal(dim(out), c(3L, length(z_new)))
  expect_true(all(diff(out[1, ]) < 0))
  expect_equal(out[1, ], stats::approx(d$depths, st$center,
                                       xout = z_new, rule = 2)$y,
               tolerance = 1e-10)
})

test_that(".no_unstandardise_targets rejects a grid/constant mismatch", {
  d  <- .mk_profiles()
  st <- edaphos:::.no_standardise(d$y)
  expect_error(
    edaphos:::.no_unstandardise_targets(matrix(0, 2L, 3L), st, d$depths),
    "un-standardisation expects"
  )
})

test_that("no_deeponet_fit predicts on the response scale, not the topsoil scale", {
  d  <- .mk_profiles()
  tr <- 1:60; te <- 61:90

  fit <- no_deeponet_fit(d$depths, d$y[tr, ], d$cov[tr, ],
                         branch_hidden = 16L, trunk_hidden = 16L,
                         output_dim = 8L, epochs = 300L, lr = 0.02,
                         seed = 1L)
  p <- predict(fit, d$cov[te, ])
  truth <- d$y[te, ]

  r2 <- 1 - sum((p - truth)^2) / sum((truth - mean(d$y[tr, ]))^2)
  expect_gt(r2, 0.9)                       # was -10.6 before the fix

  # The decisive signature: predicted column means must track the
  # observed per-depth means.  The bug pinned every column near the
  # topsoil mean, so this correlation collapsed.
  expect_gt(stats::cor(colMeans(p), colMeans(truth)), 0.99)

  # And the deepest layer must not be predicted at the topsoil level.
  expect_lt(abs(mean(p[, ncol(p)]) - mean(truth[, ncol(truth)])),
            0.25 * abs(mean(truth[, 1]) - mean(truth[, ncol(truth)])))
})

test_that("no_fno_fit predicts on the response scale", {
  d  <- .mk_profiles(n = 60L, n_depths = 12L)
  tr <- 1:40; te <- 41:60

  cube <- function(x) {
    a <- array(0, dim = c(nrow(x), length(d$depths), ncol(x)))
    for (j in seq_len(ncol(x))) a[, , j] <- x[, j]
    a
  }

  fit <- no_fno_fit(d$depths, d$y[tr, ], cube(d$cov[tr, ]),
                    n_modes = 4L, width = 6L, n_blocks = 1L,
                    epochs = 40L, lr = 0.01, seed = 1L)
  p <- predict(fit, cube(d$cov[te, ]))
  truth <- d$y[te, ]

  # This model is under-trained on purpose to keep the suite fast, so
  # the bar is the scale of the output rather than its accuracy: the
  # per-depth structure must be there at all.
  expect_gt(stats::cor(colMeans(p), colMeans(truth)), 0.95)
  expect_lt(abs(mean(p) - mean(truth)), 0.5 * stats::sd(truth))
})

test_that("DeepONet off-grid predictions stay on the response scale", {
  d  <- .mk_profiles()
  tr <- 1:60; te <- 61:90

  fit <- no_deeponet_fit(d$depths, d$y[tr, ], d$cov[tr, ],
                         branch_hidden = 16L, trunk_hidden = 16L,
                         output_dim = 8L, epochs = 300L, lr = 0.02,
                         seed = 1L)

  z_new <- c(7.5, 33, 61, 97, 133)          # between training nodes
  p     <- predict(fit, d$cov[te, ], newdepths = z_new)
  truth <- t(apply(d$cov[te, ], 1L, d$prof, z = z_new))

  expect_equal(dim(p), c(length(te), length(z_new)))
  # Bar: RMSE under a fifth of the response spread.  The pre-fix code
  # returned ~2.7x the response spread here, so this catches the
  # regression by more than an order of magnitude while leaving room
  # for the small training budget this test runs on.
  expect_lt(sqrt(mean((p - truth)^2)), 0.20 * stats::sd(truth))
})
