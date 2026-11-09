## Tests for the Pillar 1 x Pillar 4 IV estimator.

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_fit_2sls: synthetic DGP with known truth
# ─────────────────────────────────────────────────────────────────────────────
test_that("causal_iv_fit_2sls: recovers true beta under valid IVs", {
  set.seed(42L)
  n <- 800L
  Z <- matrix(stats::rnorm(n * 3L), n, 3L,
               dimnames = list(NULL, paste0("Z", 1:3)))
  U <- stats::rnorm(n)
  X <- 0.7 * Z[, 1] + 0.5 * Z[, 2] + 0.4 * Z[, 3] + 0.6 * U +
        stats::rnorm(n, sd = 0.5)
  beta_true <- 1.5
  Y <- beta_true * X + 0.8 * U + stats::rnorm(n, sd = 0.5)
  df <- data.frame(Y = Y, X = X, Z)
  fit <- causal_iv_fit_2sls(df, "X", "Y", c("Z1", "Z2", "Z3"))
  expect_s3_class(fit, "edaphos_causal_iv")
  # 95% CI should cover the truth
  expect_gt(fit$ci_lo, beta_true - 0.2)
  expect_lt(fit$ci_hi, beta_true + 0.2)
  expect_lt(abs(fit$effect - beta_true), 0.1)
  # Instruments are strong
  expect_gt(fit$stage1_F, 100)
  # Sargan p with valid instruments should NOT reject
  expect_gt(fit$sargan_p, 0.05)
})

test_that("causal_iv_fit_2sls: Sargan rejects with an invalid instrument", {
  set.seed(42L)
  n <- 800L
  Z <- matrix(stats::rnorm(n * 3L), n, 3L,
               dimnames = list(NULL, paste0("Z", 1:3)))
  U <- stats::rnorm(n)
  X <- 0.7*Z[,1] + 0.5*Z[,2] + 0.4*Z[,3] + 0.6*U + stats::rnorm(n, 0, 0.5)
  # Z3 also directly affects Y => violates exclusion
  Y <- 1.5*X + 0.8*U + 1.2*Z[,3] + stats::rnorm(n, 0, 0.5)
  df <- data.frame(Y = Y, X = X, Z)
  fit <- causal_iv_fit_2sls(df, "X", "Y", c("Z1", "Z2", "Z3"))
  # Sargan J-stat should strongly reject validity
  expect_lt(fit$sargan_p, 0.01)
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_first_stage
# ─────────────────────────────────────────────────────────────────────────────
test_that("causal_iv_first_stage: F and partial R^2 are reasonable", {
  set.seed(1L)
  n <- 300L
  Z <- stats::rnorm(n)
  X <- 0.8 * Z + stats::rnorm(n, sd = 0.3)
  fs <- causal_iv_first_stage(
    data = data.frame(X = X, Z = Z),
    exposure = "X", instruments = "Z"
  )
  expect_true(is.list(fs))
  expect_gt(fs$F, 100)         # Z strongly predicts X
  expect_gt(fs$R2_partial, 0.5)
  expect_lt(fs$F_pvalue, 1e-6)
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_sargan_test
# ─────────────────────────────────────────────────────────────────────────────
test_that("causal_iv_sargan_test: returns NA for exactly-identified model", {
  set.seed(1L)
  n <- 200L
  Z <- stats::rnorm(n);  U <- stats::rnorm(n)
  X <- 0.6 * Z + 0.4 * U + stats::rnorm(n, 0, 0.3)
  Y <- 1.5 * X + 0.5 * U + stats::rnorm(n, 0, 0.3)
  s <- causal_iv_sargan_test(
    data.frame(Y = Y, X = X, Z = Z),
    "X", "Y", "Z"
  )
  expect_true(is.list(s))
  expect_true(is.na(s$p))
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_from_embeddings: PCA reduction + 2SLS in one call
# ─────────────────────────────────────────────────────────────────────────────
test_that("causal_iv_from_embeddings: builds 5-PC instruments correctly", {
  set.seed(1L)
  n <- 300L
  # Fake embeddings
  emb <- matrix(stats::rnorm(n * 10L), n, 10L)
  # Fake data with one endogenous exposure
  X <- emb[, 1] + emb[, 2] + stats::rnorm(n, 0, 0.5)
  Y <- 2 * X + stats::rnorm(n, 0, 0.5)
  df <- data.frame(Y = Y, X = X)
  fit <- causal_iv_from_embeddings(
    data       = df,
    embeddings = emb,
    exposure   = "X",
    outcome    = "Y",
    n_pcs      = 5L
  )
  expect_s3_class(fit, "edaphos_causal_iv")
  expect_equal(length(fit$instruments), 5L)
  expect_true(all(grepl("^PC_", fit$instruments)))
  expect_true(!is.null(fit$pca_variance_explained))
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_posterior: bootstrap posterior integrates with uncertainty API
# ─────────────────────────────────────────────────────────────────────────────
test_that("causal_iv_posterior: returns a valid edaphos_posterior", {
  set.seed(1L)
  n <- 200L
  Z1 <- stats::rnorm(n); Z2 <- stats::rnorm(n); U <- stats::rnorm(n)
  X  <- 0.7*Z1 + 0.4*Z2 + 0.5*U + stats::rnorm(n, 0, 0.3)
  Y  <- 1.2*X + 0.6*U + stats::rnorm(n, 0, 0.3)
  df <- data.frame(Y = Y, X = X, Z1 = Z1, Z2 = Z2)
  post <- causal_iv_posterior(df, "X", "Y", c("Z1", "Z2"),
                                B = 50L, seed = 1L)
  expect_s3_class(post, "edaphos_posterior")
  # Posterior mean close to truth under weak assumptions
  expect_lt(abs(mean(post$samples) - 1.2), 0.25)
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_posterior: failed replicates are counted, reported, not absorbed
# ─────────────────────────────────────────────────────────────────────────────
# A rare binary instrument: 1 of 60 rows carries Z = 1, so a row resample
# misses it -- leaving Z constant -- with probability (59/60)^60 = 0.365.
# Such a resample does not identify the effect. causal_iv_fit_2sls() does
# not error on it -- the pseudo-inverse returns an effect near zero with NA
# se and NA first-stage F -- and the bootstrap used to take that number as
# a draw.
.rare_iv_data <- function(n = 60L, seed = 3L) {
  set.seed(seed)
  Z <- c(rep(0, n - 1L), 1)
  X <- 2 * Z + stats::rnorm(n)
  data.frame(X = X, Y = 1.5 * X + stats::rnorm(n), Z = Z)
}

test_that("causal_iv_posterior: a clean bootstrap reports every replicate used", {
  set.seed(1L)
  n <- 200L
  Z1 <- stats::rnorm(n); X <- 0.8 * Z1 + stats::rnorm(n)
  df <- data.frame(X = X, Y = 1.2 * X + stats::rnorm(n), Z1 = Z1)
  expect_no_warning(post <- causal_iv_posterior(df, "X", "Y", "Z1",
                                                B = 40L, seed = 1L))
  m <- post$metadata
  expect_identical(m$B_requested, 40L)
  expect_identical(m$B_effective, 40L)
  expect_identical(m$n_failed, 0L)
  expect_null(m$B)
})

test_that("causal_iv_posterior: unidentified resamples are dropped with a warning", {
  skip_on_cran()  # over 0.5 s on a Windows runner; runs on every GitHub Actions leg
  df <- .rare_iv_data()
  expect_warning(
    post <- causal_iv_posterior(df, "X", "Y", "Z", B = 200L, seed = 1L),
    "bootstrap replicates did not give an identified 2SLS fit")
  m <- post$metadata
  expect_identical(m$B_requested, 200L)
  expect_identical(m$B_effective + m$n_failed, 200L)
  # The failures are exactly the resamples that miss the single Z = 1 row:
  # expected 200 * 0.365 = 73, binomial sd 6.8. Measured 71 at this seed.
  # A criterion that also dropped weak-but-identified fits, or that missed
  # some unidentified ones, would land far from 73.
  expect_lt(abs(m$n_failed - 200 * (59 / 60)^60), 5 * sqrt(200 * 0.365 * 0.635))
  expect_identical(nrow(post$samples), m$B_effective)
  # No fabricated near-zero draws: every surviving draw came from a
  # resample in which Z varied, and none sits at the pseudo-inverse value.
  expect_false(any(abs(post$samples) < 1e-2))
})

test_that("causal_iv_posterior: no identified replicate is an error, not a posterior", {
  df <- .rare_iv_data(); df$Z <- 0
  expect_error(causal_iv_posterior(df, "X", "Y", "Z", B = 20L, seed = 1L),
               "only 0 of 20 bootstrap replicates")
})

# ─────────────────────────────────────────────────────────────────────────────
# causal_iv_fit_2sls: identification is checked, not assumed
# ─────────────────────────────────────────────────────────────────────────────
# Before this check, .safe_inverse()'s pseudo-inverse turned unidentified
# designs into numbers: a constant instrument gave an effect of 0.0096, an
# instrument equal to 3 x a covariate gave 0.57, an exposure equal to a
# covariate gave 0.67 -- no error, no warning. And a duplicated covariate,
# which does identify the effect, gave the right effect with se = NA.
.iv_design_data <- function() {
  set.seed(11L)
  n  <- 120L
  W1 <- stats::rnorm(n); Zc <- stats::rnorm(n); Z3 <- stats::rnorm(n)
  X  <- 0.8 * Zc + 0.4 * Z3 + 0.5 * W1 + stats::rnorm(n)
  Y  <- 1.5 * X + 0.7 * W1 + stats::rnorm(n)
  data.frame(X = X, Y = Y, W1 = W1, W1b = W1, Zc = Zc, Z2 = 2 * Zc, Z3 = Z3,
             Zk = 1, Zw = 3 * W1)
}

test_that("causal_iv_fit_2sls refuses designs that do not identify the effect", {
  d <- .iv_design_data()
  expect_error(causal_iv_fit_2sls(d, "X", "Y", "Zk"),
               "not identified: the instrument carries no variation")
  expect_error(causal_iv_fit_2sls(d, "X", "Y", "Zw", "W1"),
               "not identified: the instrument carries no variation")
  expect_error(causal_iv_fit_2sls(d, "X", "Y", c("Zk", "Zw"), "W1"),
               "not identified: the instruments carry no variation")
  d2 <- d; d2$X <- d2$W1
  expect_error(causal_iv_fit_2sls(d2, "X", "Y", "Zc", "W1"),
               "the exposure is a linear combination")
  d3 <- d; d3$Zr <- stats::lm.fit(cbind(1, d$X), d$Zc)$residuals   # orthogonal to X
  d3$X <- d3$X - mean(d3$X)
  expect_error(causal_iv_fit_2sls(d3, "X", "Y", "Zr"),
               "explain none of the exposure")
})

test_that("redundant columns are dropped with a warning, and the fit is the clean one", {
  d <- .iv_design_data()
  clean_w <- causal_iv_fit_2sls(d, "X", "Y", "Zc", "W1")
  expect_warning(dup_w <- causal_iv_fit_2sls(d, "X", "Y", "Zc", c("W1", "W1b")),
                 "covariate 'W1b' is a linear combination")
  expect_equal(dup_w$effect, clean_w$effect, tolerance = 1e-10)
  expect_equal(dup_w$se, clean_w$se, tolerance = 1e-10)   # was NA before
  expect_identical(dup_w$covariates, "W1")
  expect_identical(dup_w$dropped_covariates, "W1b")

  clean_z <- causal_iv_fit_2sls(d, "X", "Y", "Zc")
  expect_warning(dup_z <- causal_iv_fit_2sls(d, "X", "Y", c("Zc", "Z2")),
                 "instrument 'Z2' is redundant")
  expect_equal(dup_z$effect, clean_z$effect, tolerance = 1e-10)
  # Zc and 2*Zc are one instrument: just identified, so no Sargan test --
  # with both kept it reported an over-identification test on 1 df.
  expect_true(is.na(dup_z$sargan_df))

  two <- causal_iv_fit_2sls(d, "X", "Y", c("Zc", "Z3"), "W1")
  expect_warning(with_flat <- causal_iv_fit_2sls(d, "X", "Y", c("Zc", "Zk", "Z3"), "W1"),
                 "instrument 'Zk' is redundant")
  expect_equal(with_flat$effect, two$effect, tolerance = 1e-10)
  expect_identical(with_flat$sargan_df, two$sargan_df)
})

test_that("weak but identified instruments are reported, not refused", {
  d <- .iv_design_data()
  d$Zb <- c(1, rep(0, nrow(d) - 1L))
  d$X  <- d$X + 3 * d$Zb
  expect_no_error(f <- causal_iv_fit_2sls(d, "X", "Y", "Zb"))
  expect_true(is.finite(f$effect) && is.finite(f$se) && is.finite(f$stage1_F))
  expect_identical(f$dropped_instruments, character(0))
})
