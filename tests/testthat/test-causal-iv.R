## Tests for the Pillar 1 x Pillar 4 IV estimator (v1.9.0-v1.9.1).

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
