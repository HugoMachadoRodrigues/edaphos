test_that("quantum_feature_map returns a normalised quantum state", {
  set.seed(1)
  x <- c(pi / 4, pi / 3, pi / 2)
  psi <- quantum_feature_map(x, reps = 2L)
  expect_equal(length(psi), 2L ^ length(x))
  # <psi|psi> = 1
  expect_lt(abs(sum(Mod(psi) ^ 2) - 1), 1e-10)
})

test_that("quantum_feature_map is deterministic for the same input", {
  x <- c(0.3, 0.7, 1.1)
  psi1 <- quantum_feature_map(x, reps = 2L)
  psi2 <- quantum_feature_map(x, reps = 2L)
  expect_equal(psi1, psi2)
})

test_that("quantum_kernel is symmetric, PSD, K(x,x) = 1, K in [0,1]", {
  set.seed(2)
  X <- quantum_scale(matrix(runif(30), ncol = 3L))
  K <- quantum_kernel(X, reps = 2L)

  expect_equal(dim(K), c(nrow(X), nrow(X)))
  expect_true(isSymmetric(K))
  expect_true(all(abs(diag(K) - 1) < 1e-10))
  expect_true(all(K >= -1e-10))
  expect_true(all(K <=  1 + 1e-10))

  # PSD — smallest eigenvalue must be non-negative up to numerical noise
  lambda_min <- min(eigen(K, symmetric = TRUE, only.values = TRUE)$values)
  expect_gt(lambda_min, -1e-8)
})

test_that("quantum_kernel handles rectangular (train, test) pairs", {
  set.seed(3)
  X_train <- quantum_scale(matrix(runif(20), ncol = 4L))
  X_test  <- quantum_scale(matrix(runif(12), ncol = 4L))
  K <- quantum_kernel(X_test, X_train, reps = 2L)
  expect_equal(dim(K), c(nrow(X_test), nrow(X_train)))
  expect_true(all(K >= -1e-10 & K <= 1 + 1e-10))
})

test_that("quantum_kernel errors on mismatched column counts", {
  X <- matrix(runif(12), ncol = 3L)
  Y <- matrix(runif(12), ncol = 4L)
  expect_error(quantum_kernel(X, Y), "ncol")
})

test_that("quantum_scale rescales column-wise to [0, pi]", {
  X <- matrix(c(-1, 0, 1, 0, 5, 10), nrow = 3L)
  S <- quantum_scale(X)
  expect_equal(dim(S), dim(X))
  expect_equal(apply(S, 2L, min), c(0, 0))
  expect_equal(apply(S, 2L, max), c(pi, pi))
})

test_that("quantum_krr_fit recovers a linearly-separable binary label", {
  set.seed(4)
  n <- 24L
  X <- quantum_scale(matrix(runif(n * 3L), ncol = 3L))
  y <- sign(X[, 1L] - mean(X[, 1L]))
  fit <- quantum_krr_fit(X, y, reps = 2L, lambda = 0.05)
  expect_s3_class(fit, "edaphos_quantum_krr")
  # Training accuracy should be 100 % for a trivial separable task.
  expect_equal(mean(predict(fit, X, type = "class") == y), 1)
})

test_that("quantum_krr_fit generalises on held-out data", {
  # Deterministic kernel-friendly task: axis-aligned two-cluster
  # separation with 60 train / 40 test, averaged across three
  # independent splits to dampen the small-sample variance that
  # a single seed would expose.
  set.seed(5)
  n_total <- 100L
  X_all <- quantum_scale(matrix(runif(n_total * 3L), ncol = 3L))
  y_all <- sign(X_all[, 1L] - pi / 2)  # balanced threshold

  accs <- vapply(1:3, function(r) {
    set.seed(100L + r)
    idx_train <- sample.int(n_total, 60L)
    idx_test  <- setdiff(seq_len(n_total), idx_train)
    fit <- quantum_krr_fit(X_all[idx_train, ], y_all[idx_train],
                           reps = 2L, lambda = 0.1)
    mean(predict(fit, X_all[idx_test, ], type = "class") ==
           y_all[idx_test])
  }, numeric(1))

  expect_gt(mean(accs), 0.6)   # strictly above random across splits
})

test_that("predict handles both `numeric` and `class` types", {
  set.seed(6)
  X <- quantum_scale(matrix(runif(15), ncol = 3L))
  y <- sign(X[, 1L] - mean(X[, 1L]))
  fit <- quantum_krr_fit(X, y, reps = 2L, lambda = 0.1)
  num <- predict(fit, X, type = "numeric")
  cls <- predict(fit, X, type = "class")
  expect_type(num, "double")
  expect_type(cls, "integer")
  expect_length(num, nrow(X))
  expect_length(cls, nrow(X))
  expect_true(all(cls %in% c(-1L, 1L)))
})

test_that("print.edaphos_quantum_krr runs without error", {
  X <- quantum_scale(matrix(runif(12), ncol = 3L))
  y <- sign(X[, 1L] - mean(X[, 1L]))
  fit <- quantum_krr_fit(X, y, reps = 1L, lambda = 0.1)
  expect_output(print(fit), "edaphos_quantum_krr")
})
