# ---------------------------------------------------------------------------
# A convergence diagnostic that certified a frozen chain as converged.
#
# `.piml_rhat_ess()` was correct: on a chain whose within-split variance is
# exactly zero it returned NA, which is what Vehtari et al. (2021) call for --
# split-R-hat is undefined for a constant chain. The inversion happened one
# level up. `max(x, na.rm = TRUE)` over an all-NA vector empties the argument
# set, and R returns the identity element of the maximum over an empty set,
# -Inf. Likewise min gives +Inf. Both sit on the PASSING side of a one-sided
# threshold, so `rh > 1.01 || es < 400` was FALSE and a chain with acceptance
# rate 0.00 printed clean, with no banner.
#
# Measured on 60 WoSIS Cerrado profiles: 5 of the 20 fits the package
# certified were of this kind -- a quarter of every positive verdict.
#
# The repair is an encoding, not a patched comparison: failure is carried as
# rhat = Inf and ess = 0, values chosen so that EVERY reduction in the
# repository fails on them, including call sites nobody remembers to fix. So
# these tests assert the encoding and the reductions, not one code path.
# ---------------------------------------------------------------------------

frozen_chains <- function(m = 4L, n = 200L, d = 3L, distinct = TRUE) {
  # Each chain stuck at its own starting point: within-chain variance 0,
  # between-chain variance large. This is the real failure mode -- dispersed
  # starts, zero acceptance -- not the trivial all-identical one.
  lapply(seq_len(m), function(k) {
    v <- if (distinct) rnorm(d, mean = k) else rep(0, d)
    matrix(rep(v, each = n), n, d)
  })
}

test_that("a frozen chain is encoded so that every reduction fails on it", {
  set.seed(1L)
  dg <- edaphos:::.piml_rhat_ess(frozen_chains())

  # NOT NA. NA is honest and unsafe; these values are honest AND survive the
  # reductions in the direction a diagnostic needs.
  expect_false(anyNA(dg$rhat))
  expect_false(anyNA(dg$ess))
  expect_true(all(dg$rhat == Inf))
  expect_true(all(dg$ess == 0))

  # The exact reductions that were inverted, each asserted directly.
  expect_gt(max(dg$rhat, na.rm = TRUE), 1.01)
  expect_lt(min(dg$ess,  na.rm = TRUE), 400)
  expect_gt(max(dg$rhat), 1.01)
  expect_lt(min(dg$ess),  400)

  # and the honest report travels alongside
  expect_true(any(grepl("degenerate", dg$status)))
})

test_that("the all-identical chain fails too, by the same encoding", {
  set.seed(2L)
  dg <- edaphos:::.piml_rhat_ess(frozen_chains(distinct = FALSE))
  expect_true(all(dg$rhat == Inf))
  expect_true(all(dg$ess == 0))
  expect_gt(max(dg$rhat, na.rm = TRUE), 1.01)
})

test_that("a chain too short to split fails rather than passing vacuously", {
  # The h < 2 early return was a second, independent route into the same
  # inversion: it also emitted all-NA.
  short <- lapply(1:4, function(k) matrix(rnorm(6), 3, 2))
  dg <- edaphos:::.piml_rhat_ess(short)
  expect_true(all(dg$rhat == Inf))
  expect_gt(max(dg$rhat, na.rm = TRUE), 1.01)
})

test_that("a PARTIALLY frozen chain is not laundered by the healthy coordinates", {
  # The subtler inversion: na.rm silently DROPS the frozen coordinate and
  # certifies the fit on the ones that moved.
  set.seed(3L)
  m <- 4L; n <- 400L
  chains <- lapply(seq_len(m), function(k)
    cbind(rep(k, n),              # frozen
          rnorm(n)))              # healthy
  dg <- edaphos:::.piml_rhat_ess(chains)

  expect_equal(dg$rhat[1L], Inf)
  expect_true(is.finite(dg$rhat[2L]))
  # the reduction must see the frozen coordinate, not skip it
  expect_gt(max(dg$rhat, na.rm = TRUE), 1.01)
  expect_lt(min(dg$ess,  na.rm = TRUE), 400)
})

test_that("a healthy chain still passes, so the encoding is not just strict", {
  set.seed(4L)
  chains <- lapply(1:4, function(k) matrix(rnorm(4000 * 2), 4000, 2))
  dg <- edaphos:::.piml_rhat_ess(chains)
  expect_true(all(is.finite(dg$rhat)))
  expect_lt(max(dg$rhat), 1.01)
  expect_gt(min(dg$ess), 400)
  expect_true(all(dg$status == "ok" | grepl("upper bound", dg$status)))
})

test_that("piml_bayes_converged reports the acceptance rate in its own right", {
  set.seed(5L)
  fake <- structure(list(
    diagnostics = list(rhat = c(1.001, 1.002), ess = c(900, 1200),
                       status = c("ok", "ok")),
    accept_rate = 0), class = "edaphos_piml_bayes")
  v <- piml_bayes_converged(fake)
  # R-hat and ESS both look fine; the chain still never moved. A user should
  # not have to infer that from a diagnostic.
  expect_false(v$ok)
  expect_true(any(grepl("acceptance rate", v$reasons)))
})

test_that("the fit object carries the verdict and a real pedon still converges", {
  skip_on_cran()
  f <- system.file("extdata", "piml_wosis_cerrado.rds", package = "edaphos")
  if (!nzchar(f)) f <- file.path("inst", "extdata", "piml_wosis_cerrado.rds")
  skip_if_not(file.exists(f), "WoSIS bundle not installed")
  H <- readRDS(f)$horizons

  # The pedon the manuscript reports: 9 horizons, genuinely converged.
  p <- H[H$profile_id == "1115679", ]
  p <- p[order(p$top), ]
  skip_if(nrow(p) < 5L, "reference pedon not in this bundle")
  ok <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg, top = p$top,
                                  bottom = p$bottom, method = "mcmc",
                                  seed = 7L)
  expect_true(isTRUE(ok$converged))
  expect_length(ok$conv_reasons, 0L)
  expect_true(all(is.finite(ok$diagnostics$rhat)))

  # A three-horizon profile from the over-parameterised regime: must be
  # reported as failed, whatever else it does.
  q <- H[H$profile_id == "848921", ]
  q <- q[order(q$top), ]
  skip_if(nrow(q) < 4L, "degenerate reference profile not in this bundle")
  q <- q[-nrow(q), ]
  bad <- piml_profile_fit_bayesian(q$depth_mid, q$soc_g_kg, top = q$top,
                                   bottom = q$bottom, method = "mcmc",
                                   seed = 11L)
  expect_false(isTRUE(bad$converged))
  expect_gt(length(bad$conv_reasons), 0L)
  expect_gt(max(bad$diagnostics$rhat, na.rm = TRUE), 1.01)
})

test_that("the diagnostic does not cost more than the sampler it diagnoses", {
  skip_on_cran()
  # The Geyer initial-positive-sequence walk recomputed acf() inside its loop
  # at a growing lag.max, so its cost was quadratic in exactly the quantity
  # that signals failure: on one real profile it took 197 s of a 202 s fit,
  # and a third of a 60-profile sample timed out before it could report.
  # A badly mixed chain is the worst case, so that is what is timed.
  set.seed(6L)
  n <- 8000L
  slow <- lapply(1:4, function(k) {
    x <- cumsum(rnorm(n, sd = 0.01)) + k    # near-random-walk: barely mixes
    cbind(x, x + rnorm(n, sd = 1e-3))
  })
  t0 <- Sys.time()
  dg <- edaphos:::.piml_rhat_ess(slow)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_lt(el, 20)
  # and it must still call the failure
  expect_gt(max(dg$rhat), 1.01)
})
