# Physics-Informed depth-profile model.
#
# Models a soil property y(z) as the solution of
#
#   dy/dz = -lambda(z) * (y - y_inf)          (1)
#   lambda(z) = lambda0 * exp(-mu * z)        (2)
#
# where
#   y_inf   = deep asymptote (parent-material value),
#   lambda0 = decay rate at the surface (> 0),
#   mu      = how quickly the decay rate decreases with depth (free),
#   y0      = surface value, either estimated from data or fixed.
#
# This is the simplest ODE that (i) enforces a physical asymptote
# (parent material), (ii) allows depth-varying dynamics (horizons react
# differently), and (iii) admits closed-form behaviour consistent with
# Jenny 1941 / Minasny & McBratney pedogenic dynamics when mu -> 0.

.piml_unpack <- function(theta, y_surface = NULL) {
  # theta[1] = log(lambda0)   (reparametrised for positivity)
  # theta[2] = mu             (free sign; depth-change of decay rate)
  # theta[3] = y_inf          (free)
  # theta[4] = y0             (only if y_surface is NULL)
  list(
    lambda0 = exp(theta[1]),
    mu      = theta[2],
    y_inf   = theta[3],
    y0      = if (is.null(y_surface)) theta[4] else y_surface
  )
}

.piml_dydz <- function(z, y, parms) {
  lambda <- parms$lambda0 * exp(-parms$mu * z)
  list(-lambda * (y - parms$y_inf))
}

#' Forward-integrate a Physics-Informed depth profile
#'
#' Solves ODE (1)-(2) from z = 0 down to the requested `depths`, starting
#' at `y(0) = params$y0`. Uses a fixed-step RK4 solver from the
#' `deSolve` package.
#'
#' @param params Named list with numeric elements `lambda0`, `mu`,
#'   `y_inf`, `y0`.
#' @param depths Numeric vector of positive depths (same units as the
#'   depths used at fit time).
#'
#' @return Numeric vector of predicted values, one per element of
#'   `depths`.
#' @export
piml_profile_predict <- function(params, depths) {
  stopifnot(is.list(params),
            all(c("lambda0", "mu", "y_inf", "y0") %in% names(params)))
  stopifnot(is.numeric(depths), all(depths >= 0))
  times <- sort(unique(c(0, depths)))
  sol <- deSolve::ode(
    y      = c(y = params$y0),
    times  = times,
    func   = .piml_dydz,
    parms  = params,
    method = "lsoda"
  )
  sol <- as.data.frame(sol)
  idx <- match(depths, sol$time)
  if (anyNA(idx)) {
    # Fallback: nearest-time interpolation (handles floating-point drift)
    idx <- sapply(depths, function(d) which.min(abs(sol$time - d)))
  }
  as.numeric(sol$y[idx])
}

.piml_loss <- function(theta, depths, obs, y_surface = NULL,
                       lambda_reg = 1e-3) {
  params <- .piml_unpack(theta, y_surface)
  pred <- tryCatch(
    piml_profile_predict(params, depths),
    error = function(e) rep(NA_real_, length(depths))
  )
  if (any(!is.finite(pred))) return(1e12)
  sse <- sum((pred - obs)^2)
  sse + lambda_reg * sum(theta^2)
}

#' Fit a Physics-Informed depth-profile model (Pillar 2)
#'
#' Fits the ODE
#' \deqn{\frac{dy}{dz} = -\lambda_0 e^{-\mu z} (y - y_\infty)}
#' to one soil pedon by minimising the sum of squared errors between the
#' ODE-predicted and the observed values, with an L2 regulariser on the
#' (re-parametrised) parameters. Physics is encoded in **the forward
#' model itself** — the fit can never produce a profile that violates the
#' prescribed exponential-asymptote dynamics.
#'
#' @param depths Numeric vector of horizon mid-depths (same units, e.g.
#'   centimetres below surface).
#' @param values Numeric vector of observed property values, same length
#'   as `depths`.
#' @param y_surface Optional numeric; if supplied, the surface value
#'   `y(0) = y_surface` is fixed and not optimised. Use this when you
#'   have a reliable 0 cm observation (or a laboratory A-horizon value).
#' @param start Optional named numeric vector of starting parameters
#'   (`log_lambda0`, `mu`, `y_inf`, and optionally `y0`). If `NULL`, a
#'   data-driven guess is built from the observed range and depths.
#' @param reg Numeric L2 regularisation strength on the parameter
#'   vector.
#' @param control List passed to `stats::optim`'s `control` argument
#'   (default is `list(maxit = 2000)`).
#'
#' @return A `edaphos_piml_profile` object with components:
#'   \describe{
#'     \item{params}{Named list with the fitted `lambda0`, `mu`, `y_inf`, `y0`.}
#'     \item{theta}{The unconstrained parameter vector the optimiser found.}
#'     \item{objective}{Final regularised SSE loss.}
#'     \item{converged}{Logical, whether `optim` reported convergence.}
#'     \item{depths, values, y_surface}{Inputs echoed back.}
#'     \item{rmse}{Unregularised RMSE on the training data.}
#'   }
#' @export
#' @examples
#' depths <- c(5, 15, 30, 60, 100)
#' values <- c(25, 18, 12, 8, 6.5)   # e.g. SOC (g/kg) decreasing with depth
#' fit <- piml_profile_fit(depths, values)
#' fit
#' piml_profile_predict(fit$params, c(10, 50))
piml_profile_fit <- function(depths, values, y_surface = NULL,
                             start = NULL, reg = 1e-3,
                             control = list(maxit = 2000)) {
  stopifnot(length(depths) == length(values),
            length(depths) >= 2L,
            all(is.finite(depths)), all(is.finite(values)),
            all(depths >= 0))
  if (is.null(start)) {
    ord <- order(depths)
    zd  <- depths[ord]; yd <- values[ord]
    rng <- range(values)
    # Data-driven guess for the surface decay rate from the first two
    # (shallowest) horizons: dy/dz ~ -lambda0 * (y0 - y_inf).
    dy0 <- (yd[2] - yd[1]) / max(zd[2] - zd[1], 1e-3)
    y_inf_guess <- rng[1]
    y0_guess    <- if (is.null(y_surface)) rng[2] else y_surface
    denom       <- max(abs(y0_guess - y_inf_guess), 1e-3)
    lambda0_guess <- max(abs(dy0) / denom, 1e-4)
    if (is.null(y_surface)) {
      start <- c(
        log_lambda0 = log(lambda0_guess),
        mu          = 0.0,
        y_inf       = y_inf_guess,
        y0          = y0_guess
      )
    } else {
      start <- c(
        log_lambda0 = log(lambda0_guess),
        mu          = 0.0,
        y_inf       = y_inf_guess
      )
    }
  }
  fit <- stats::optim(
    par        = start,
    fn         = .piml_loss,
    depths     = depths,
    obs        = values,
    y_surface  = y_surface,
    lambda_reg = reg,
    method     = "Nelder-Mead",
    control    = control
  )
  params <- .piml_unpack(fit$par, y_surface)
  pred   <- piml_profile_predict(params, depths)
  structure(
    list(
      params    = params,
      theta     = fit$par,
      objective = fit$value,
      converged = fit$convergence == 0L,
      depths    = depths,
      values    = values,
      y_surface = y_surface,
      fitted    = pred,
      rmse      = .rmse(values, pred)
    ),
    class = "edaphos_piml_profile"
  )
}

#' @export
print.edaphos_piml_profile <- function(x, ...) {
  cat("<edaphos_piml_profile>\n")
  cat("  dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)\n")
  cat(sprintf("  lambda0 = %-8.4g  mu = %-8.4g\n",
              x$params$lambda0, x$params$mu))
  cat(sprintf("  y_inf   = %-8.4g  y0 = %-8.4g\n",
              x$params$y_inf, x$params$y0))
  cat(sprintf("  n obs   = %d         rmse = %.4g\n",
              length(x$depths), x$rmse))
  cat("  converged =", x$converged, "\n")
  invisible(x)
}

#' @export
predict.edaphos_piml_profile <- function(object, newdepths, ...) {
  stopifnot(inherits(object, "edaphos_piml_profile"))
  piml_profile_predict(object$params, newdepths)
}

#' Fit the Pillar 2 profile model to a group of pedons independently
#'
#' Convenience wrapper that calls [piml_profile_fit()] separately on each
#' pedon in a long-format data frame, returning a list of fits keyed by
#' `id`. This is the baseline against which a future pooled
#' (covariate-conditioned) PIML model will be compared.
#'
#' @param data Data frame in long form with one row per horizon.
#' @param id Character, name of the column identifying each pedon.
#' @param depth Character, name of the column with horizon mid-depths.
#' @param value Character, name of the column with observed values.
#' @param ... Forwarded to [piml_profile_fit()].
#'
#' @return A named list of `edaphos_piml_profile` fits.
#' @export
piml_profile_fit_group <- function(data, id, depth, value, ...) {
  .assert_covariates(data, c(id, depth, value))
  out <- lapply(split(data, data[[id]]), function(sub) {
    tryCatch(
      piml_profile_fit(sub[[depth]], sub[[value]], ...),
      error = function(e) {
        warning(sprintf("Pedon '%s' failed: %s",
                        as.character(sub[[id]][1]), conditionMessage(e)),
                call. = FALSE)
        NULL
      }
    )
  })
  out
}
