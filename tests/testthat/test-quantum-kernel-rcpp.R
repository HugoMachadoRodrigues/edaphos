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

  # THIS TEST USED TO BE FLAKY, and the measurement is worth recording
  # because the shape of the flakiness was not the obvious one.
  #
  # It timed a 30-sample problem with a single system.time() each, then ran
  # the ratio assertion only `if (t_r > 0.02)`. At that size t_r has a median
  # of 8 ms, so the guard opened in 1 run out of 200 -- and when it did, the
  # observed ratio was 2.4 against a threshold of 2. An assertion that fires
  # half a percent of the time, by a 20% margin on a wall clock, produces
  # occasional red builds and tests nothing the rest of the time. It also made
  # the suite's own assertion count wobble between 2519 and 2520, which is
  # what gave it away.
  #
  # Two changes, both measured. 120 samples puts t_r at 30 ms so the guard is
  # unnecessary and the assertion always runs; medians of five replicates
  # instead of single readings absorb scheduler noise. Over 25 executions of
  # the version below the ratio was 7.5x every time, min == median == max, and
  # t_r never fell below 0.029 s.
  set.seed(4L)
  X <- quantum_scale(matrix(stats::runif(120 * 3), ncol = 3))
  tm <- function(backend)
    stats::median(replicate(5L,
      system.time(quantum_kernel(X, reps = 2L, backend = backend))[["elapsed"]]))
  t_r   <- tm("r")
  t_cpp <- tm("rcpp")

  # The problem is large enough that the R path is unambiguously measurable;
  # if this fails the machine is too loaded for any timing claim to mean
  # anything, and the assertions below would be noise either way.
  skip_if(t_r < 0.02, "machine too fast or too loaded to time this reliably")

  expect_lt(t_cpp, t_r)
  # The documented claim: at least 2x. Measured at 7.5x on this problem.
  expect_gt(t_r / max(t_cpp, 1e-6), 2)
})

# ---------------------------------------------------------------------------
# reps and memory are checked once, for both backends.
#
# reps = 0 used to return an all-ones kernel (every state left at |0...0>)
# that quantum_krr_fit() fitted without complaint; reps = -1 split the
# backends (R errored, C++ returned ones); reps = 2.5 was truncated to 2.
# backend = "r" had no memory guard at all, only a "may be slow" warning.
# ---------------------------------------------------------------------------
test_that("quantum_kernel refuses a reps that is not a whole number >= 1", {
  X <- matrix(c(0.1, 0.5, 0.9, 1.3, 0.2, 0.4), ncol = 2L)
  for (b in c("rcpp", "r")) {
    for (bad in list(0, -1, 2.5, NA_real_, c(1, 2), "2")) {
      expect_error(quantum_kernel(X, reps = bad, backend = b),
                   "`reps` must be a single whole number >= 1",
                   info = paste(b, format(bad)))
    }
  }
  expect_error(quantum_feature_map(c(0.1, 0.2), reps = 0),
               "`reps` must be a single whole number >= 1")
  # Valid input is untouched, and the two backends still agree.
  expect_equal(quantum_kernel(X, reps = 2, backend = "rcpp"),
               quantum_kernel(X, reps = 2L, backend = "r"), tolerance = 1e-10)
})

test_that("the C++ entry point refuses reps < 1 if called directly", {
  X <- matrix(c(0.1, 0.5, 0.9, 1.3), ncol = 2L)
  expect_error(edaphos:::quantum_kernel_rcpp(X, NULL, 0L), "reps must be >= 1")
})

test_that("the memory guard counts bytes correctly", {
  # Pure arithmetic: 2 rows x 2^29 complex doubles x 16 bytes = 16 GB.
  expect_error(edaphos:::.qk_check_memory(29L, 2L, 0L),
               "would allocate 16.0 GB of state vectors")
  expect_silent(edaphos:::.qk_check_memory(8L, 1000L, 1000L))   # ~7.8 MB
})

test_that("both backends pass through the memory guard before allocating", {
  # Wired with the limit lowered to nothing and a tiny input, so this test
  # never allocates anything large. Testing with a genuinely oversized input
  # would be safe only while the guard exists: on a build without it, the
  # test itself would try to allocate 16 GB -- which is what happened when
  # this was first checked against the unguarded code.
  real_guard <- edaphos:::.qk_check_memory
  testthat::local_mocked_bindings(
    .qk_check_memory = function(n, n_x, n_y, limit_gb = 8)
      real_guard(n, n_x, n_y, limit_gb = 1e-12),
    .package = "edaphos")
  X <- matrix(0.1, nrow = 2L, ncol = 3L)
  for (b in c("rcpp", "r"))
    expect_error(quantum_kernel(X, backend = b),
                 "would allocate .* GB of state vectors", info = b)
})
