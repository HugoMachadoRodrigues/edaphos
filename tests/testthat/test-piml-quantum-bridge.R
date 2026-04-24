## Tests for the Pilar 2 x Pilar 6 physics-informed quantum kernel
## bridge (v2.2.0).

# Helper: synthesize an ODE-like pedon and a cheap mock fit
.mk_ode_pedon <- function(n = 30L) {
  set.seed(1L)
  z <- seq(5, 150, length.out = n)
  lambda0 <- 0.015; mu <- -0.01; yinf <- 5; y0 <- 28
  y_true <- yinf + (y0 - yinf) * exp(-lambda0 * z * exp(-mu * z))
  y_obs  <- y_true + stats::rnorm(n, 0, 1.5)
  list(z = z, y = y_obs, y_true = y_true,
        mock_fit = list(lambda0 = lambda0, mu = mu, y_inf = yinf, y0 = y0))
}

test_that("piml_quantum_kernel: returns a PSD Gram matrix for alpha in [0,1]", {
  p <- .mk_ode_pedon(20L)
  X <- quantum_scale(cbind(p$z / max(p$z), p$y / max(p$y)))
  for (alpha in c(0, 0.3, 0.7, 1)) {
    K <- piml_quantum_kernel(X, p$y, p$z, p$mock_fit,
                               alpha = alpha, reps = 1L)
    expect_true(is.matrix(K))
    expect_equal(dim(K), c(20L, 20L))
    expect_true(isSymmetric(K))
    ev <- eigen(K, symmetric = TRUE, only.values = TRUE)$values
    expect_true(all(ev >= -1e-8),
      info = sprintf("eigenvalue PSD failed at alpha = %g", alpha))
  }
})

test_that("piml_quantum_kernel: alpha=1 recovers pure quantum kernel", {
  p <- .mk_ode_pedon(10L)
  X <- quantum_scale(cbind(p$z / max(p$z), p$y / max(p$y)))
  K_pi <- piml_quantum_kernel(X, p$y, p$z, p$mock_fit,
                                alpha = 1, reps = 2L)
  K_q  <- quantum_kernel(X, reps = 2L)
  expect_equal(unclass(K_pi), unclass(K_q), tolerance = 1e-10,
                ignore_attr = TRUE)
})

test_that("piml_qkrr_fit + predict round-trips without error", {
  p <- .mk_ode_pedon(30L)
  X <- quantum_scale(cbind(p$z / max(p$z), p$y / max(p$y)))
  train <- 1:20; test <- 21:30
  fit <- piml_qkrr_fit(X[train, ], p$y[train], p$z[train],
                         ode_fit = p$mock_fit,
                         alpha = 0.7, reps = 2L, lambda = 0.5)
  expect_s3_class(fit, "edaphos_piml_qkrr")
  pr <- predict(fit, X[test, ],
                 newdepths = p$z[test],
                 newy       = p$y[test])
  expect_equal(length(pr), 10L)
  expect_true(is.numeric(pr))
  # On the smooth pedon trajectory, we should at least be in the
  # right ballpark (within 10 g/kg of the true response).
  expect_lt(mean(abs(pr - p$y[test])), 10)
})

test_that("piml_qkrr_fit: print() emits a readable header", {
  p <- .mk_ode_pedon(10L)
  X <- quantum_scale(cbind(p$z / max(p$z), p$y / max(p$y)))
  fit <- piml_qkrr_fit(X, p$y, p$z, p$mock_fit,
                         alpha = 0.5, reps = 1L, lambda = 0.1)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("edaphos_piml_qkrr", out)))
  expect_true(any(grepl("Pilar 2 x Pilar 6", out)))
})
