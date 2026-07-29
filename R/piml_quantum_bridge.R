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
#   piml_quantum_kernel(X, y, depths, ode_fit, ...) : PI Gram matrix
#   piml_qkrr_fit(X, y, depths, ode_fit, ...)       : closed-form KRR
#                                                      on top of the PI
#                                                      kernel.

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
#'   Default: the median absolute deviation of the training residuals
#'   *about their median*, unscaled --- which is neither the median
#'   absolute residual nor `stats::mad()`, the latter multiplying the
#'   same quantity by 1.4826. The example prints all three.
#' @param reps Integer; ZZFeatureMap repetitions (forwarded to
#'   [`quantum_kernel()`]).
#' @param backend Forwarded to [`quantum_kernel()`]; `"rcpp"` by
#'   default.
#' @return A PSD matrix of shape `(n, n)`.
#' @references
#' Bishop, T. F. A. et al. (1999). Modelling soil attribute depth
#' functions with equal-area quadratic smoothing splines.
#' *Geoderma* **91**, 27-45.
#' @examples
#' data(br_cerrado)
#' set.seed(2)
#' d <- br_cerrado[sample(nrow(br_cerrado), 60L), ]
#' X <- quantum_scale(as.matrix(d[, c("elev", "slope", "twi", "ndvi")]))
#'
#' # The reference pedon the residuals are measured against. br_cerrado
#' # ships a single 0-5 cm layer, so every site enters at the same
#' # mid-depth of 2.5 cm --- which is where the first trap lives.
#' ref <- piml_profile_fit(c(5, 15, 30, 60, 100), c(25, 18, 12, 8, 6.5))
#' K <- piml_quantum_kernel(X, d$soc, depths = rep(2.5, 60L), ode_fit = ref)
#'
#' # TRAP. With one sampling depth the ODE prediction is one number, so
#' # e_i = y_i - 27.361 and the physics half is EXACTLY a Gaussian
#' # kernel on the response. 30% of this Gram matrix is the label.
#' unique(round(d$soc - attr(K, "residuals"), 6))
#' Kq <- quantum_kernel(X, reps = 2L)
#' Kp <- (K - 0.7 * Kq) / 0.3
#' max(abs(Kp - exp(-outer(d$soc, d$soc, "-")^2 /
#'                  (2 * attr(K, "sigma")^2))))
#'
#' # The mixture is PSD as advertised (smallest eigenvalue 0.0266) ...
#' signif(min(eigen(unclass(K), symmetric = TRUE,
#'                  only.values = TRUE)$values), 4)
#'
#' # ... but "alpha = 0.7 is quantum-heavy" is not what the numbers say
#' # on these four covariates. The ZZ kernel's off-diagonals sit near
#' # zero (median 0.072), so after weighting, the 30% physics block
#' # carries MORE off-diagonal variation than the 70% quantum block,
#' # and the mixture tracks the physics block more closely.
#' od <- upper.tri(K)
#' round(stats::quantile(Kq[od], c(0.5, 0.9, 1)), 4)
#' round(c(quantum = stats::sd(0.7 * Kq[od]),
#'         physics = stats::sd(0.3 * Kp[od])), 4)
#' round(c(quantum = stats::cor(K[od], Kq[od]),
#'         physics = stats::cor(K[od], Kp[od])), 4)
#'
#' # Read that next to what the quantum block encodes at all: on these
#' # covariates it barely tracks feature-space proximity (r = 0.23
#' # against -distance), where a plain RBF at the median-distance
#' # bandwidth is nearly collinear with it (0.99).
#' D <- as.matrix(stats::dist(X))
#' Krbf <- exp(-D^2 / (2 * stats::median(D[od])^2))
#' round(c(quantum = stats::cor(Kq[od], -D[od]),
#'         rbf     = stats::cor(Krbf[od], -D[od])), 4)
#'
#' # The default `sigma` is the median absolute deviation of the
#' # residuals about their median, unscaled --- 3.115 here, against
#' # 8.221 for the median absolute residual and 4.618 for stats::mad().
#' # Pass `sigma` explicitly if you meant one of the other two.
#' r <- attr(K, "residuals")
#' round(c(default    = attr(K, "sigma"),
#'         mad_median = stats::median(abs(r - stats::median(r))),
#'         median_abs = stats::median(abs(r)),
#'         stats_mad  = stats::mad(r)), 4)
#'
#' # alpha = 1 and alpha = 0 recover the two ends exactly.
#' K1 <- piml_quantum_kernel(X, d$soc, rep(2.5, 60L), ref, alpha = 1)
#' K0 <- piml_quantum_kernel(X, d$soc, rep(2.5, 60L), ref, alpha = 0)
#' c(alpha1_is_quantum = max(abs(unclass(K1) - Kq)),
#'   alpha0_is_physics = max(abs(unclass(K0) - Kp)))
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
#' @examples
#' # br_cerrado ships 0-5 cm only, so extend each site downwards with
#' # the closed form of the Pillar-2 ODE at mu = 0, giving every site
#' # its own decay rate: wetter hollows (high TWI) keep carbon deeper.
#' # The physics is therefore exactly right by construction, which
#' # FLATTERS the residual half of the kernel.
#' data(br_cerrado)
#' set.seed(4)
#' sit <- br_cerrado[sample(nrow(br_cerrado), 16L), ]
#' zh  <- c(5, 15, 30, 60, 100)
#' g   <- expand.grid(h = seq_along(zh), s = seq_len(16L))
#' z   <- zh[g$h]
#' lam <- 0.010 + 0.030 * (1 - (sit$twi - min(sit$twi)) / diff(range(sit$twi)))
#' soc <- 6 + (sit$soc[g$s] - 6) * exp(-lam[g$s] * z) +
#'   stats::rnorm(80L, sd = 1)
#' Xa <- quantum_scale(cbind(twi = sit$twi[g$s], ndvi = sit$ndvi[g$s],
#'                           elev = sit$elev[g$s], depth = z))
#'
#' set.seed(5)
#' tr <- sample(80L, 55L)
#' te <- setdiff(seq_len(80L), tr)
#' mean_prof <- vapply(zh, function(zz)
#'   mean(soc[z == zz & seq_len(80L) %in% tr]), 0)
#' ref <- piml_profile_fit(zh, mean_prof)
#'
#' qk <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 0.7,
#'                     lambda = 0.1)
#' qk
#'
#' # Score every claim on the same held-out 25 horizons, with a
#' # baseline and an RBF on the SAME features in the same table. The
#' # quantum kernel improves on predicting the training mean by 1%;
#' # the RBF is 4x better than either. `pi_quantum` --- the honest use
#' # of this fit, with no test y to hand --- is worse than the
#' # baseline, and the reference ODE on its own beats the whole
#' # bridge, leaky variant included.
#' rmse <- function(a, b) sqrt(mean((a - b)^2))
#' p_def  <- stats::predict(qk, Xa[te, ], newdepths = z[te])
#' p_leak <- stats::predict(qk, Xa[te, ], newdepths = z[te], newy = soc[te])
#' qk1 <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 1,
#'                      lambda = 0.1)
#' p_q <- stats::predict(qk1, Xa[te, ], newdepths = z[te])
#' sqd <- function(A, B) outer(rowSums(A^2), rowSums(B^2), "+") - 2 * A %*% t(B)
#' ell <- stats::median(sqrt(pmax(sqd(Xa[tr, ], Xa[tr, ]), 0)))
#' Ktr <- exp(-sqd(Xa[tr, ], Xa[tr, ]) / (2 * ell^2))
#' Kte <- exp(-sqd(Xa[te, ], Xa[tr, ]) / (2 * ell^2))
#' p_rbf <- as.numeric(Kte %*% solve(Ktr + 0.1 * diag(55L), soc[tr]))
#' round(c(train_mean    = rmse(soc[te], mean(soc[tr])),      # 4.7919
#'         ode_only      = rmse(soc[te],
#'                              stats::predict(ref, newdepths = z[te])),
#'         quantum       = rmse(soc[te], p_q),                # 4.7456
#'         pi_quantum    = rmse(soc[te], p_def),              # 5.5793
#'         rbf_krr       = rmse(soc[te], p_rbf),              # 1.1869
#'         pi_with_truth = rmse(soc[te], p_leak)), 4)         # 3.5720
#'
#' # Training RMSE would have told the opposite story: the quantum fit
#' # interpolates its 55 training points to 0.88 g/kg and then lands
#' # within 1% of the training mean out of sample.
#' round(c(train = qk1$rmse, test = rmse(soc[te], p_q)), 4)
#'
#' # Not a ridge artefact --- the ordering survives three lambdas.
#' for (lb in c(0.01, 0.1, 1)) {
#'   q  <- piml_qkrr_fit(Xa[tr, ], soc[tr], z[tr], ref, alpha = 1,
#'                       lambda = lb)
#'   pq <- stats::predict(q, Xa[te, ], newdepths = z[te])
#'   pr <- as.numeric(Kte %*% solve(Ktr + lb * diag(55L), soc[tr]))
#'   cat(sprintf("lambda %-5g quantum %.3f  rbf %.3f\n", lb,
#'               rmse(soc[te], pq), rmse(soc[te], pr)))
#' }
#'
#' # Why `pi_with_truth` looks good: the physics half needs e_i = y_i -
#' # ODE(z_i), i.e. the response at the site you are predicting. That is
#' # the thing you do not have. Its absence is not signalled --- the
#' # default `newy` silently substitutes the training mean, so the
#' # physics block degenerates into a function of depth alone:
#' identical(p_def, stats::predict(qk, Xa[te, ], newdepths = z[te],
#'                                 newy = rep(mean(soc[tr]), 25L)))
#'
#' # TRAP, sharper. Omit `newdepths` as well and predict() takes the
#' # first nrow(newdata) TRAINING depths, in training-row order. No
#' # error, no warning, silently misaligned depths:
#' round(rmse(soc[te], stats::predict(qk, Xa[te, ])), 4)
#' rbind(used = qk$depths[1:6], actual = z[te][1:6])
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
