# Pilar 2 x Pilar 6 bridge -- Physics-informed quantum kernels
# (edaphos v2.2.0).
#
# Mathematical setup
# ------------------
# The ZZFeatureMap of Pilar 6 is physics-agnostic: it maps the raw
# feature vector x into the 2^n-dim Hilbert space with no knowledge
# of the pedogenetic process that generated x.  For pedology we have
# strong prior information: soil depth profiles follow
#
#     dy/dz = -lambda_0 * exp(-mu z) * (y - y_inf)
#
# (Pilar 2, Bishop et al. 1999 depth-harmonisation generalised; see
# `piml_profile_fit()`).  Given an ODE fit `f_theta` trained on a
# representative set of pedons, the *physics residual* for a new
# observation is
#
#     e_i = y_i - f_theta(z_i, x_i)
#
# Small |e_i| means "this observation is consistent with pedogenesis
# under the fitted ODE".  Two observations are physically similar if
# their depth + covariate + residual profiles are close.  Two
# observations whose raw (y, x) happen to coincide but whose
# residuals differ are physically UNRELATED.
#
# A physics-informed kernel combines the quantum-kernel expressivity
# with an additive physics-residual similarity term:
#
#     K_PI(x_i, x_j) = alpha * K_quantum(x_i, x_j)
#                      + (1 - alpha) * K_phys(e_i, e_j)
#
# with K_phys a radial basis function on the fitted residuals.  The
# mixture is PSD for any alpha in [0, 1] because a convex combination
# of two PSD kernels is PSD.  Setting alpha = 1 recovers the v2.0.0
# Quantum-only kernel; alpha = 0 recovers a pure physics-residual
# kernel.  alpha = 0.7 is a reasonable default when the ODE fit is
# trustworthy.
#
# Exports
#   piml_quantum_kernel(X, ode_fit, depths, ...) : PI-QKRR Gram matrix
#   piml_qkrr_fit(X, y, ode_fit, depths, ...)    : closed-form KRR
#                                                   on top of the PI
#                                                   kernel.

#' Physics-informed quantum kernel via ODE-residual fusion
#'
#' Builds a physics-informed Gram matrix by combining the Pilar 6
#' ZZFeatureMap kernel over raw features with an RBF similarity over
#' the depth-profile residuals of a fitted Pilar 2 ODE:
#'
#' \deqn{K_{PI}(x_i, x_j) = \alpha\, K_{quantum}(x_i, x_j) + (1 - \alpha)\,
#'       \exp\!\Bigl(-\frac{(e_i - e_j)^2}{2\,\sigma^2}\Bigr)}
#'
#' where \eqn{e_i = y_i - \hat y_{ODE}(z_i, x_i)} is the residual
#' between the observed \eqn{y_i} and the ODE-predicted value at
#' depth \eqn{z_i}.  The output is PSD for any \eqn{\alpha \in [0, 1]}.
#'
#' @param X Numeric matrix (rows = samples, columns = features to
#'   encode through the ZZFeatureMap).  Features should already be in
#'   `[0, pi]` -- use [`quantum_scale()`] if needed.
#' @param y Numeric response vector (one per row of `X`) used to
#'   compute residuals against the ODE fit.
#' @param depths Numeric vector of depths (same length as `y`) at
#'   which observations were taken.
#' @param ode_fit A fitted object from [`piml_profile_fit()`] or
#'   [`piml_profile_fit_bayesian()`] providing a `predict()` method.
#' @param alpha Numeric in `[0, 1]`; mixing weight.  Default `0.7`
#'   (quantum-heavy, physics-informed but not physics-dominated).
#' @param sigma Numeric; RBF bandwidth on the residual scale.
#'   Default: median absolute residual over the training set
#'   (Silverman's rule of thumb).
#' @param reps Integer; ZZFeatureMap repetitions (forwarded to
#'   [`quantum_kernel()`]).
#' @param backend Forwarded to [`quantum_kernel()`]; `"rcpp"` by
#'   default.
#' @return A PSD matrix of shape `(n, n)`.
#' @references
#' Bishop, T. F. A. et al. (1999). Modelling soil attribute depth
#' functions with equal-area quadratic smoothing splines.
#' *Geoderma* **91**, 27-45.
#' @export
piml_quantum_kernel <- function(X, y, depths, ode_fit,
                                  alpha = 0.7, sigma = NULL,
                                  reps = 2L,
                                  backend = c("rcpp", "r")) {
  backend <- match.arg(backend)
  stopifnot(is.numeric(y), is.numeric(depths),
             length(y) == length(depths),
             length(y) == NROW(X),
             is.numeric(alpha), length(alpha) == 1L,
             alpha >= 0, alpha <= 1)

  # Physics residuals
  pred_fn <- tryCatch(stats::predict, error = function(e) NULL)
  y_hat <- tryCatch(
    as.numeric(stats::predict(ode_fit, newdepths = depths)),
    error = function(e) {
      # Fall back to a cheap exponential-decay surrogate if the fit
      # object's predict method is unavailable (e.g. a list carrying
      # only lambda0, mu, y_inf).
      if (!is.list(ode_fit)) stop("ode_fit has no usable predict method.",
                                    call. = FALSE)
      l0  <- ode_fit$lambda0 %||% 0.01
      mu  <- ode_fit$mu      %||% 0
      yi  <- ode_fit$y_inf   %||% 0
      y0  <- ode_fit$y0      %||% y[1]
      yi + (y0 - yi) * exp(-l0 * depths * exp(-mu * depths))
    }
  )
  resid <- as.numeric(y) - y_hat

  # Default sigma via median of absolute residuals
  if (is.null(sigma)) {
    sigma <- max(stats::median(abs(resid - stats::median(resid))),
                   1e-6)
  }

  # Quantum part
  K_q <- quantum_kernel(as.matrix(X), reps = reps, backend = backend)
  # Physics part: RBF on residuals (1-D distance matrix)
  d  <- outer(resid, resid, `-`)
  K_p <- exp(- d^2 / (2 * sigma^2))

  K <- alpha * K_q + (1 - alpha) * K_p
  # Symmetric PSD hygiene
  K <- (K + t(K)) / 2
  diag(K)[diag(K) > 1] <- 1
  structure(K,
             alpha        = alpha,
             sigma        = sigma,
             reps         = reps,
             residuals    = resid,
             class        = c("edaphos_piml_quantum_kernel", "matrix",
                               "array"))
}

#' Fit a Physics-Informed Quantum Kernel Ridge Regression
#'
#' Composes [`piml_quantum_kernel()`] with the closed-form KRR dual
#' solution \eqn{\boldsymbol{\alpha} = (K + \lambda I)^{-1} y}.  The
#' returned object carries the training-time residuals and ODE fit so
#' `predict()` handles the full forward pipeline (ODE predict ->
#' residual -> PI kernel row -> dual sum).
#'
#' @param X,y,depths,ode_fit,alpha,sigma,reps,backend See
#'   [`piml_quantum_kernel()`].
#' @param lambda Ridge regulariser; positive.
#' @return An `edaphos_piml_qkrr` fit.
#' @export
piml_qkrr_fit <- function(X, y, depths, ode_fit,
                            alpha = 0.7, sigma = NULL,
                            reps = 2L, lambda = 0.1,
                            backend = c("rcpp", "r")) {
  backend <- match.arg(backend)
  K <- piml_quantum_kernel(X, y, depths, ode_fit,
                             alpha = alpha, sigma = sigma,
                             reps = reps, backend = backend)
  sigma_used <- attr(K, "sigma")
  resid      <- attr(K, "residuals")
  n <- nrow(K)
  al <- solve(K + lambda * diag(n), as.numeric(y))
  fitted_vals <- as.numeric(K %*% al)
  rmse <- sqrt(mean((fitted_vals - y)^2))
  structure(list(
    X_train  = as.matrix(X),
    y_train  = as.numeric(y),
    depths   = depths,
    ode_fit  = ode_fit,
    alpha    = alpha,
    sigma    = sigma_used,
    reps     = as.integer(reps),
    lambda   = lambda,
    resid    = resid,
    alpha_dual = as.numeric(al),
    K_train  = K,
    fitted   = fitted_vals,
    rmse     = rmse,
    backend  = backend,
    n_qubits = ncol(X)
  ), class = "edaphos_piml_qkrr")
}

#' @export
predict.edaphos_piml_qkrr <- function(object, newdata,
                                        newdepths = NULL,
                                        newy      = NULL,
                                        ...) {
  newdata <- as.matrix(newdata)
  stopifnot(ncol(newdata) == object$n_qubits)
  if (is.null(newdepths)) newdepths <- object$depths[seq_len(nrow(newdata))]
  if (is.null(newy))      newy      <- rep(mean(object$y_train), nrow(newdata))
  # Physics residuals at new points
  y_hat_new <- tryCatch(
    as.numeric(stats::predict(object$ode_fit, newdepths = newdepths)),
    error = function(e) {
      l0 <- object$ode_fit$lambda0 %||% 0.01
      mu <- object$ode_fit$mu      %||% 0
      yi <- object$ode_fit$y_inf   %||% 0
      y0 <- object$ode_fit$y0      %||% mean(object$y_train)
      yi + (y0 - yi) * exp(-l0 * newdepths * exp(-mu * newdepths))
    }
  )
  resid_new <- as.numeric(newy) - y_hat_new

  # PI kernel row: quantum part + RBF residual part
  K_q_new <- quantum_kernel(newdata, object$X_train,
                              reps = object$reps,
                              backend = object$backend)
  d_new   <- outer(resid_new, object$resid, `-`)
  K_p_new <- exp(- d_new^2 / (2 * object$sigma^2))
  K_new   <- object$alpha * K_q_new + (1 - object$alpha) * K_p_new
  as.numeric(K_new %*% object$alpha_dual)
}

#' @export
print.edaphos_piml_qkrr <- function(x, ...) {
  cat("<edaphos_piml_qkrr>  (Pilar 2 x Pilar 6 bridge)\n")
  cat(sprintf("  n_qubits = %d   reps = %d   lambda = %.3g\n",
               x$n_qubits, x$reps, x$lambda))
  cat(sprintf("  alpha    = %.2f  (quantum weight; 1-alpha on physics)\n",
               x$alpha))
  cat(sprintf("  sigma    = %.3g  (residual RBF bandwidth)\n", x$sigma))
  cat(sprintf("  n_train  = %d   training RMSE = %.4g\n",
               length(x$y_train), x$rmse))
  invisible(x)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
