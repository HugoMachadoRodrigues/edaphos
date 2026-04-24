## Tests for the Pilar 4 x Pilar 6 quantum-foundation bridge (v2.0.0).

test_that("qf_embed_reduce: produces PCs in [-pi, pi]", {
  set.seed(1L)
  emb <- matrix(stats::rnorm(100 * 16), 100L, 16L)
  colnames(emb) <- paste0("e", 1:16)
  red <- qf_embed_reduce(emb, n_pcs = 4L)
  expect_equal(ncol(red$X_q), 4L)
  expect_true(all(red$X_q >= -pi - 1e-9))
  expect_true(all(red$X_q <= pi  + 1e-9))
  # Variance explained should sum to something reasonable
  expect_true(sum(red$variance_explained) > 0.2)
  # Key metadata slots for predict-time projection
  expect_true(!is.null(red$rotation))
  expect_true(!is.null(red$pca_center))
  expect_true(!is.null(red$kept_columns))
})

test_that("qf_embed_reduce: errors when n_pcs exceeds available columns", {
  emb <- matrix(stats::rnorm(50 * 3), 50L, 3L)
  expect_error(
    qf_embed_reduce(emb, n_pcs = 10L),
    regexp = "non-constant"
  )
})

test_that("qf_kernel_compare: quantum/RBF/linear Gram matrices are symmetric PSD", {
  skip_if_not_installed("torch")
  set.seed(1L)
  X_q <- matrix(stats::runif(30 * 4, -pi, pi), 30L, 4L)
  cmp <- qf_kernel_compare(X_q, reps = 2L)
  for (K in list(cmp$K_quantum, cmp$K_rbf, cmp$K_linear)) {
    expect_equal(dim(K), c(30L, 30L))
    # Symmetric
    expect_true(max(abs(K - t(K))) < 1e-8)
  }
  expect_s3_class(cmp$diagnostics, "data.frame")
  expect_equal(nrow(cmp$diagnostics), 3L)
  expect_true(all(cmp$diagnostics$frob >= 0))
})

test_that("qf_krr_fit + predict round-trips without error", {
  skip_if_not_installed("torch")
  set.seed(1L)
  n <- 80L
  emb <- matrix(stats::rnorm(n * 10L), n, 10L)
  colnames(emb) <- paste0("e", 1:10)
  y   <- sin(emb[, 1]) + 0.3 * emb[, 2] + stats::rnorm(n, 0, 0.3)
  train <- 1:60; test <- 61:n
  fit <- qf_krr_fit(emb[train, ], y[train],
                      n_pcs = 4L, reps = 2L, lambda = 0.1)
  expect_s3_class(fit, "edaphos_qf_krr")
  expect_equal(fit$n_pcs, 4L)
  # Predict on test data
  pred <- predict(fit, emb[test, ])
  expect_equal(length(pred), length(test))
  expect_true(is.numeric(pred))
  expect_false(any(is.na(pred)))
})

test_that("qf_krr_fit: print method emits the expected header", {
  skip_if_not_installed("torch")
  set.seed(1L)
  emb <- matrix(stats::rnorm(40 * 6), 40L, 6L)
  y <- stats::rnorm(40)
  fit <- qf_krr_fit(emb, y, n_pcs = 3L, reps = 1L, lambda = 0.1)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("edaphos_qf_krr", out)))
  expect_true(any(grepl("n_pcs", out)))
})

test_that("qf_krr_benchmark: 4-way comparison returns a well-shaped frame", {
  skip_if_not_installed("torch")
  skip_if_not_installed("ranger")
  set.seed(1L)
  n <- 100L
  emb <- matrix(stats::rnorm(n * 8L), n, 8L); colnames(emb) <- paste0("e", 1:8)
  cov <- matrix(stats::rnorm(n * 5L), n, 5L); colnames(cov) <- paste0("c", 1:5)
  y   <- emb[, 1] * 0.5 + cov[, 1] * 0.3 + stats::rnorm(n, 0, 0.5)
  bm <- qf_krr_benchmark(emb, cov, y,
                           train_ix = 1:70, test_ix = 71:n,
                           n_pcs = 4L, reps = 1L, lambda = 0.5)
  expect_s3_class(bm, "data.frame")
  expect_true(all(c("method", "rmse", "mae", "r2",
                      "n_train", "n_test") %in% names(bm)))
  expect_gte(nrow(bm), 2L)
  expect_true(all(bm$rmse >= 0))
})
