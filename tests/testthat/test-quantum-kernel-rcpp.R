## Tests for the v2.1.3 Rcpp port of quantum_kernel().
##
## Validates numerical agreement with the pure-R reference AND the
## promised speed-up.

test_that("quantum_kernel rcpp agrees with R reference to machine precision", {
  set.seed(1L)
  for (n_qubits in c(2L, 3L, 4L, 5L)) {
    for (reps in 1:2) {
      X <- quantum_scale(
        matrix(stats::runif(10L * n_qubits), ncol = n_qubits)
      )
      K_r   <- quantum_kernel(X, reps = reps, backend = "r")
      K_cpp <- quantum_kernel(X, reps = reps, backend = "rcpp")
      expect_equal(K_r, K_cpp, tolerance = 1e-10,
                    info = sprintf("n_qubits=%d, reps=%d",
                                    n_qubits, reps))
    }
  }
})

test_that("quantum_kernel rcpp handles asymmetric (X, Y) correctly", {
  set.seed(2L)
  X <- quantum_scale(matrix(stats::runif(8 * 3), ncol = 3))
  Y <- quantum_scale(matrix(stats::runif(6 * 3), ncol = 3))
  K_r   <- quantum_kernel(X, Y, reps = 2L, backend = "r")
  K_cpp <- quantum_kernel(X, Y, reps = 2L, backend = "rcpp")
  expect_equal(dim(K_r),   c(8L, 6L))
  expect_equal(dim(K_cpp), c(8L, 6L))
  expect_equal(K_r, K_cpp, tolerance = 1e-10)
})

test_that("quantum_kernel rcpp preserves kernel invariants", {
  set.seed(3L)
  X <- quantum_scale(matrix(stats::runif(15 * 3), ncol = 3))
  K <- quantum_kernel(X, reps = 2L, backend = "rcpp")
  expect_true(isSymmetric(K))
  expect_equal(diag(K), rep(1, nrow(K)), tolerance = 1e-10)
  expect_true(all(K >= 0 & K <= 1 + 1e-10))
  # PSD check: eigenvalues non-negative
  ev <- eigen(K, symmetric = TRUE, only.values = TRUE)$values
  expect_true(all(ev >= -1e-8))
})

test_that("quantum_kernel rcpp provides measurable speedup", {
  skip_on_cran()  # timing tests are noisy on CRAN builders
  set.seed(4L)
  # 30 samples x 3 qubits -- small but enough to see the gap.
  X <- quantum_scale(matrix(stats::runif(30 * 3), ncol = 3))
  t_r   <- system.time(quantum_kernel(X, reps = 2L, backend = "r"))["elapsed"]
  t_cpp <- system.time(quantum_kernel(X, reps = 2L, backend = "rcpp"))["elapsed"]
  # Expect at least a 2x speedup; typical is 10-50x on larger problems.
  expect_lt(t_cpp, t_r)
  # Allow very small absolute times (1-2 ms) not to flag false failures.
  if (t_r > 0.02) {
    expect_gt(t_r / t_cpp, 2)
  }
})
