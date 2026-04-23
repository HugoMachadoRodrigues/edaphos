# Pillar 6 adapter to the unified v1.6.0 uncertainty API.
#
# The Quantum Kernel Ridge Regression of [`quantum_krr_fit()`] is a
# ridge-regularised kernel regressor on the quantum-kernel Gram
# matrix K. Rasmussen and Williams (2006, eq. 2.3) show that ridge
# regression with kernel K and regularisation lambda is equivalent
# to the posterior mean of a Gaussian-process regression with
# covariance K and noise variance `lambda`. The matching predictive
# variance is
#
#   sigma_eps^2(x*) = k(x*, x*)                        (aleatoric)
#                    - k(x*, X) (K + lambda I)^{-1} k(X, x*)
#                                                      (epistemic)
#                    + sigma_n^2                        (data noise)
#
# where `sigma_n^2` is the residual noise variance estimated from
# the leave-one-out cross-validation residuals.
#
# This file wraps that calculation in a dedicated function and an
# `as_edaphos_posterior` adapter. No new quantum circuitry; the
# heavy lifting is already done by `quantum_kernel()`.

#' GP-equivalent posterior for a Quantum Kernel Ridge Regression fit
#'
#' Given a fitted [`quantum_krr_fit()`] model, returns the predictive
#' posterior at new inputs as an [`edaphos_posterior()`]. Using the
#' well-known equivalence between Kernel Ridge Regression and
#' Gaussian-process regression (Rasmussen & Williams 2006, §2.3), the
#' predictive variance is derived analytically from the same gram
#' matrix `K + lambda I` that produces the point prediction. Aleatoric
#' noise is estimated from leave-one-out residuals.
#'
#' @param object An `edaphos_quantum_krr`.
#' @param newdata A matrix (or data frame) with `ncol(newdata) ==
#'   object$n_qubits`.
#' @param n_samples Integer; the Gaussian posterior is analytic, so
#'   sampling is only needed for the `edaphos_posterior` machinery
#'   (CRPS estimation etc.). Defaults to `500L`.
#' @param units Optional free-text units tag.
#' @return An `edaphos_posterior` with `method = "analytic"` and
#'   `query_type = "sample"`. The epistemic/aleatoric decomposition
#'   is carried through `post$epistemic_sd` and `post$aleatoric_sd`.
#' @references
#' Rasmussen, C. E. and Williams, C. K. I. (2006). *Gaussian Processes
#' for Machine Learning*. MIT Press, §2.3.
#' @export
quantum_krr_posterior <- function(object, newdata,
                                    n_samples = 500L,
                                    units = NULL) {
  stopifnot(inherits(object, "edaphos_quantum_krr"))
  Xt <- as.matrix(newdata)
  stopifnot(ncol(Xt) == object$n_qubits)

  # Cached training quantities.
  K_train <- object$K_train
  lambda  <- object$lambda
  n       <- nrow(K_train)
  # Mix matrix -- reused for point prediction and for variance.
  A       <- K_train + lambda * diag(n)
  A_inv   <- solve(A)

  # Test-train and test-test quantum kernels.
  K_nt <- quantum_kernel(Xt, object$X_train, reps = object$reps)
  # The quantum-kernel diagonal is |<phi(x), phi(x)>|^2 = 1 for any
  # normalised state, so k(x*, x*) = 1 for every test point.
  k_tt_diag <- rep(1, nrow(Xt))

  # Predictive mean.
  mu <- as.vector(K_nt %*% object$alpha)

  # Epistemic variance: diag(k(X*, X*) - K_nt A^{-1} K_nt^T).
  # Use per-row quadratic form to avoid forming the full n_test x n_test.
  var_epi <- k_tt_diag -
             vapply(seq_len(nrow(K_nt)), function(i) {
               v <- K_nt[i, , drop = TRUE]
               as.numeric(v %*% A_inv %*% v)
             }, numeric(1L))
  var_epi <- pmax(var_epi, 0)  # numerical clamp

  # Aleatoric variance: MSE of the leave-one-out residuals.
  loo_resid <- (object$y_train - object$fitted) /
                 (1 - pmax(diag(K_train %*% A_inv), 1e-12))
  sigma_n2  <- mean(loo_resid^2)

  sd_epi <- sqrt(var_epi)
  sd_ale <- sqrt(sigma_n2)
  sd_tot <- sqrt(var_epi + sigma_n2)

  edaphos_posterior(
    mean          = mu,
    sd            = sd_tot,
    epistemic_sd  = sd_epi,
    aleatoric_sd  = rep(sd_ale, length(mu)),
    method        = "analytic",
    query_type    = "sample",
    units         = units,
    metadata      = list(
      n_qubits = object$n_qubits,
      reps     = object$reps,
      lambda   = object$lambda,
      source   = "quantum_krr_fit (GP-equivalent posterior)"
    ),
    n_samples_if_gaussian = as.integer(n_samples)
  )
}

#' @export
as_edaphos_posterior.edaphos_quantum_krr <- function(x, newdata = NULL,
                                                       n_samples = 500L,
                                                       units = NULL, ...) {
  if (is.null(newdata)) {
    stop("Supply `newdata = ...` to adapt a Quantum-KRR fit.", call. = FALSE)
  }
  quantum_krr_posterior(x, newdata = newdata, n_samples = n_samples,
                          units = units)
}
