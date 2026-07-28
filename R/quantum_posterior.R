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
#' @examples
#' ## Soil organic carbon (g/kg) from three covariates: 60 calibration
#' ## sites, 30 held out.
#' set.seed(11)
#' n    <- 90
#' clay <- runif(n,   8,  62)
#' ph   <- runif(n, 4.5, 7.5)
#' elev <- runif(n,  60, 340)
#' soc  <- 24 + 0.10 * (clay - 35) + 2.2 * (ph - 6) -
#'         0.010 * (elev - 200) + rnorm(n, 0, 1.5)
#' X    <- quantum_scale(cbind(clay, ph, elev))  # ZZFeatureMap wants [0, pi]
#' tr <- 1:60; te <- 61:90
#'
#' fit  <- quantum_krr_fit(X[tr, ], soc[tr], reps = 2L, lambda = 0.1)
#' set.seed(11)          # edaphos_posterior() synthesises Gaussian draws
#' post <- quantum_krr_posterior(fit, X[te, ], units = "g/kg")
#' post
#'
#' ## TRAP -- `post$mean` is on the CENTRED scale. quantum_krr_fit()
#' ## subtracts mean(y) and predict() adds it back; this function does
#' ## not, so the posterior must be shifted by `fit$y_mean` before it
#' ## meets an observation in g/kg.
#' pred <- predict(fit, X[te, ])
#' round(c(post_mean = post$mean[1L], predict = pred[1L],
#'         y_mean    = fit$y_mean), 3)          # 1.024, 24.430, 23.406
#'
#' lo <- post$mean + fit$y_mean - 1.96 * post$sd
#' up <- post$mean + fit$y_mean + 1.96 * post$sd
#' round(c(unshifted = edaphos_picp(soc[te], post$mean - 1.96 * post$sd,
#'                                  post$mean + 1.96 * post$sd),
#'         shifted   = edaphos_picp(soc[te], lo, up)), 3)   # 0.000, 0.933
#'
#' ## 0.933 against a nominal 0.95 reads like a calibrated model. It is
#' ## not one: on this split the point predictions are WORSE than the
#' ## training mean (negative R2), while an ordinary linear fit on the
#' ## same three covariates is not.
#' d   <- data.frame(soc, clay, ph, elev)
#' lin <- lm(soc ~ clay + ph + elev, data = d[tr, ])
#' round(c(qkrr   = edaphos_r2(soc[te], pred),
#'         linear = edaphos_r2(soc[te], predict(lin, d[te, ]))), 3)
#' #  -0.37 and 0.72
#'
#' ## PICP cannot see that; the interval score can. A constant band
#' ## around the training mean -- no model at all -- is both narrower
#' ## and better scored.
#' nl <- rep(fit$y_mean - 1.96 * sd(soc[tr]), length(te))
#' nu <- rep(fit$y_mean + 1.96 * sd(soc[tr]), length(te))
#' round(c(is_qkrr = edaphos_interval_score(soc[te], lo, up),   # 16.90
#'         is_null = edaphos_interval_score(soc[te], nl, nu),   # 11.82
#'         w_qkrr  = mean(up - lo),                             # 13.47
#'         w_null  = mean(nu - nl)), 2)                         # 10.59
#'
#' ## Which half of the decomposition earned the coverage? The aleatoric
#' ## one: it is a leave-one-out estimate, and it lands on the held-out
#' ## residual sd while the training RMSE is 3.7x optimistic.
#' round(c(aleatoric  = post$aleatoric_sd[1L],   # 3.404
#'         heldout_sd = sd(soc[te] - pred),      # 3.351
#'         train_rmse = fit$rmse), 3)            # 0.899
#'
#' ## The epistemic half is decoration here. k(x*, x*) = 1 for any
#' ## normalised state, so the implied GP prior sd is 1 g/kg by
#' ## construction and not from the data, and `lambda` stands in for a
#' ## noise variance the same residuals put two orders of magnitude
#' ## higher. Delete the epistemic term and nothing moves:
#' a <- post$aleatoric_sd[1L]
#' round(c(sigma_n2  = a^2, lambda = fit$lambda,          # 11.589, 0.100
#'         picp_full = edaphos_picp(soc[te], lo, up),     # 0.933
#'         picp_ale  = edaphos_picp(soc[te], pred - 1.96 * a,
#'                                  pred + 1.96 * a),     # 0.933
#'         is_full   = edaphos_interval_score(soc[te], lo, up),   # 16.905
#'         is_ale    = edaphos_interval_score(soc[te], pred - 1.96 * a,
#'                                            pred + 1.96 * a)), 3)  # 17.010
#'
#' ## Nor does it flag extrapolation, the one job an epistemic term is
#' ## usually hired for: the corners of the encoding cube, far from any
#' ## calibration site, sit inside the range seen at the held-out sites.
#' far <- X[te, ]; far[1L, ] <- 0; far[2L, ] <- pi
#' set.seed(11)
#' pf <- quantum_krr_posterior(fit, far)
#' round(c(corner_0     = pf$epistemic_sd[1L],
#'         corner_pi    = pf$epistemic_sd[2L],
#'         interior_min = min(pf$epistemic_sd[-(1:2)]),
#'         interior_max = max(pf$epistemic_sd[-(1:2)])), 3)
#' #  0.488, 0.467, 0.294, 0.618 -- the corners are not the extremes
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
