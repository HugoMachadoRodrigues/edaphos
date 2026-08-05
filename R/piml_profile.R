# Physics-Informed depth-profile model.
#
# Models a soil property y(z) as the solution of
#
#   dy/dz = -lambda(z) * (y - y_inf)          (1)
#   lambda(z) = lambda0 * exp(-mu * z)        (2)
#
# where
#   y_inf   = the equilibrium COORDINATE of the equation. It is NOT the deep
#             asymptote and NOT a parent-material value: because lambda(z)
#             decays, the profile traverses only 1 - exp(-kappa) of the
#             y0 -> y_inf gap, kappa = lambda0/mu, and settles at
#             y(Inf) = y_inf + (y0 - y_inf) exp(-kappa). See .piml_asymptote().
#   lambda0 = decay rate at the surface (> 0; estimated on the log scale),
#   mu      = how quickly that rate decays with depth (>= 0; estimated on the
#             log scale. It was previously free-signed, and 55% of 207 real
#             WoSIS profiles fitted mu < 0 -- a rate GROWING exponentially
#             with depth),
#   y0      = surface value, either estimated from data or fixed.
#
# What this equation is, and is not
# ---------------------------------
# It is the Russell & Moore (1968) exponential depth function (reviewed in
# Minasny et al. 2016) carrying a fourth shape parameter. It is NOT derived
# from a soil-carbon balance: there is no conservation law, no source term,
# and no process in soil physics from which a relaxation rate decaying
# exponentially with depth follows. Being first order in y, it also cannot
# represent the bioturbation-diffusion operator, and being monotone it cannot
# represent an argillic bulge, an E horizon under an A, or a buried A.
#
# The derivable counterpart is in R/piml_mechanistic.R: the advection-reaction
# limit v dC/dz = I(z) - kC puts the depth-dependence in the ASYMPTOTE (root
# input) rather than in the rate, and every parameter of it is positive and
# has a literature prior. Prefer it when the claim being made is mechanistic.
#
# Note on lineage: Jenny (1941) and Minasny & McBratney write kinetics in
# TIME. Substituting depth for time is legitimate only in a Lagrangian frame
# on a steadily aggrading or eroding profile -- that is, only through the
# advection velocity v, with dt/dz = 1/v. This file's equation does not carry
# v, so it should not be read as a pedogenic rate law in disguise.

.piml_unpack <- function(theta, y_surface = NULL) {
  # Identified, positivity-constrained coordinates.
  #
  # The original parameterisation was (log lambda0, mu, y_inf, y0) with mu and
  # y_inf free-signed. It had three defects, all of which bit on real data:
  #
  #   * y_inf is not the asymptote (see .piml_asymptote), so the parameter the
  #     user reads and puts priors on is not the quantity they think it is;
  #   * lambda0 and mu are near-collinear -- the likelihood constrains their
  #     ratio kappa = lambda0/mu far better than either alone;
  #   * nothing kept mu >= 0 or the concentrations positive, so fits returned
  #     rates that GROW exponentially with depth and negative surface carbon.
  #
  # We therefore estimate (y0, A, kappa, mu) on the log scale, where A = y(Inf)
  # is the attainable deep value and kappa = lambda0/mu is the total relaxation.
  # All four are positive by construction and each means something a soil
  # scientist can put a prior on. lambda0 and y_inf are recovered for the public
  # interface, inverting y(Inf) = y_inf + (y0 - y_inf) e^{-kappa}.
  #
  #   theta[1] = log(kappa)
  #   theta[2] = log(mu)
  #   theta[3] = log(A)
  #   theta[4] = log(y0)   (only when y_surface is NULL)
  kappa <- exp(theta[1])
  mu    <- exp(theta[2])
  A     <- exp(theta[3])
  y0    <- if (is.null(y_surface)) exp(theta[4]) else y_surface
  ek    <- exp(-kappa)
  # y_inf = (A - y0 e^{-kappa}) / (1 - e^{-kappa}); guard the kappa -> 0 branch,
  # where the profile barely relaxes and y_inf is not recoverable from A.
  y_inf <- if (1 - ek < 1e-10) A else (A - y0 * ek) / (1 - ek)
  list(
    lambda0 = kappa * mu,
    mu      = mu,
    y_inf   = y_inf,
    y0      = y0,
    # the identified coordinates, carried through for reporting
    kappa   = kappa,
    y_asym  = A
  )
}

.piml_dydz <- function(z, y, parms) {
  lambda <- parms$lambda0 * exp(-parms$mu * z)
  list(-lambda * (y - parms$y_inf))
}

# Closed-form solution of dy/dz = -lambda0 e^{-mu z} (y - y_inf).
#
# Separating and integrating gives
#     y(z) = y_inf + (y0 - y_inf) exp( -(lambda0/mu) (1 - e^{-mu z}) ).
# The equation has an analytic solution, so numerically integrating it (as this
# file used to, via deSolve::lsoda) is both slower and less accurate. It also
# made the depth-averaged forward operator below impractical.
#
# The mu -> 0 limit is (lambda0/mu)(1 - e^{-mu z}) -> lambda0 z, i.e. a plain
# exponential; expm1 keeps that branch accurate for small |mu z|.
.piml_solution <- function(z, params) {
  l0 <- params$lambda0; mu <- params$mu
  kz <- if (abs(mu) < 1e-8) l0 * z else -(l0 / mu) * expm1(-mu * z)
  params$y_inf + (params$y0 - params$y_inf) * exp(-kz)
}

# The value the profile ACTUALLY converges to as z -> Inf.
#
# This is NOT y_inf. Because the rate lambda(z) = lambda0 e^{-mu z} decays with
# depth, the exponent saturates at -kappa with kappa = lambda0/mu, so the
# solution only traverses a fraction 1 - e^{-kappa} of the y0 -> y_inf gap:
#
#     y(Inf) = y_inf + (y0 - y_inf) e^{-kappa}.
#
# Reporting y_inf as "the deep asymptote" (as this package did) therefore
# reports a coordinate the profile never reaches. On the shipped pedon (WoSIS
# 1115679, nine horizons to 550 cm) y_inf = 2.50 g/kg against an attained
# 4.33; on the shallower profiles that dominate the archive the two routinely
# differ in sign. For mu <= 0 the rate does not decay and the solution does
# reach y_inf (or diverges), so the limit is y_inf itself.
.piml_asymptote <- function(params) {
  if (!is.finite(params$mu) || params$mu <= 0) return(params$y_inf)
  kappa <- params$lambda0 / params$mu
  params$y_inf + (params$y0 - params$y_inf) * exp(-kappa)
}

# Depth-averaged forward operator: the prediction that corresponds to a horizon.
#
# A horizon is an INTERVAL [zu, zl] and its reported value is a layer average,
# not a point reading at the mid-depth. Fitting g(z_mid) to it is a
# mis-specified observation operator -- the same equal-area / mass-preserving
# spline problem the depth-function literature solves explicitly (Bishop et al.
# 1999; Malone et al. 2009). Gauss-Legendre on the closed form is exact enough
# at 8 nodes for this smooth integrand and costs nothing.
.piml_layer_mean <- function(zu, zl, params, n_node = 8L) {
  gl <- .piml_gauss_legendre(n_node)
  vapply(seq_along(zu), function(i) {
    a <- zu[i]; b <- zl[i]
    if (!is.finite(a) || !is.finite(b) || b <= a) return(.piml_solution(a, params))
    zz <- 0.5 * (b - a) * gl$x + 0.5 * (a + b)
    sum(gl$w * .piml_solution(zz, params)) * 0.5
  }, numeric(1))
}

# Gauss-Legendre nodes/weights on [-1, 1], computed once per call via the
# Golub-Welsch eigenvalue construction (no external dependency).
.piml_gauss_legendre <- function(n) {
  n <- as.integer(n)
  i <- seq_len(n - 1L)
  b <- i / sqrt(4 * i^2 - 1)
  J <- matrix(0, n, n)
  J[cbind(i, i + 1L)] <- b
  J[cbind(i + 1L, i)] <- b
  e <- eigen(J, symmetric = TRUE)
  o <- order(e$values)
  list(x = e$values[o], w = 2 * (e$vectors[1L, o])^2)
}

#' Forward-integrate a Physics-Informed depth profile
#'
#' Evaluates the solution of ODE (1)-(2) at the requested `depths`, with
#' `y(0) = params$y0`. The equation is separable and its solution is
#' analytic, so this is a direct evaluation of the closed form rather than a
#' numerical integration -- earlier versions called `deSolve::lsoda` on every
#' prediction, which was slower and less accurate, and made the depth-averaged
#' observation operator impractical. The closed form is held to the
#' integrator's own answer in `tests/testthat/test-piml-closed-form.R`.
#'
#' @param params Named list with numeric elements `lambda0`, `mu`,
#'   `y_inf`, `y0`.
#' @param depths Numeric vector of positive depths (same units as the
#'   depths used at fit time).
#'
#' @return Numeric vector of predicted values, one per element of
#'   `depths`.
#' @examples
#' # A synthetic profile from the pedogenetic ODE itself, so the true
#' # parameters are known.
#' set.seed(1)
#' z <- c(5, 15, 30, 60, 100)
#' y <- 8 + (32 - 8) * exp(-(0.06 / 0.025) * (1 - exp(-0.025 * z))) +
#'      stats::rnorm(5, 0, 0.4)
#'
#' fit <- piml_profile_fit(z, y)
#'
#' # Predict at depths that were never sampled: the ODE solution is
#' # continuous in z, so the profile can be evaluated anywhere.
#' piml_profile_predict(fit$params, depths = c(10, 45, 80))
#'
#' # Monotone decay with depth is a property of the governing equation,
#' # not something the fit has to be asked for.
#' p <- piml_profile_predict(fit$params, depths = seq(5, 100, by = 5))
#' all(diff(p) < 0)
#' @export
piml_profile_predict <- function(params, depths) {
  stopifnot(is.list(params),
            all(c("lambda0", "mu", "y_inf", "y0") %in% names(params)))
  stopifnot(is.numeric(depths), all(depths >= 0))
  # The ODE has a closed-form solution, so evaluate it directly. This used to
  # call deSolve::lsoda for every prediction, which was slower, less accurate
  # and made the depth-averaged operator impractical. `.piml_solution()` is
  # checked against the numerical integrator in the test suite.
  as.numeric(.piml_solution(depths, params))
}

# How far down the y0 -> y(Inf) journey the deepest observation actually got.
#
# This is the diagnostic that says whether the deep value is estimated or
# extrapolated. If the deepest horizon has traversed most of the gap, the
# plateau is inside the data; if it has barely started, y(Inf) is whatever the
# curve happens to point at, and the fit cannot be read as a parent-material
# value however plausible the number looks.
.piml_progress <- function(params, depths) {
  zmax <- max(depths)
  y_end <- .piml_asymptote(params)
  gap <- y_end - params$y0
  if (!is.finite(gap) || abs(gap) < 1e-12) return(1)
  travelled <- .piml_solution(zmax, params) - params$y0
  min(max(travelled / gap, 0), 1)
}

# How far ABOVE the data the fitted surface value sits.
#
# The deep end is not the only place this model extrapolates. A steep drop
# between a thick topsoil horizon and the next one forces a monotone
# exponential to leave z = 0 from very high up: on a real WoSIS profile whose
# 0-10 cm horizon averages 96 g/kg and whose 10-30 cm horizon averages 8, the
# fit needs y0 = 775 g/kg -- more carbon than pure organic matter contains.
# The fit is not wrong about the horizon averages; the point value at z = 0 is
# simply not something the data determine. Report the ratio so the caller can
# see it rather than reading y0 as "the surface concentration".
.piml_surface_ratio <- function(params, values) {
  m <- max(values, na.rm = TRUE)
  if (!is.finite(m) || m <= 0 || !is.finite(params$y0)) return(NA_real_)
  params$y0 / m
}

# Is the profile the shape this model can represent?
#
# lambda > 0 and a first-order relaxation make y(z) monotone, so an argillic
# bulge, an E horizon under an A, a calcic accumulation or a buried A cannot be
# represented -- the fit degenerates instead of failing. 20.8% of the >= 4
# horizon WoSIS Cerrado profiles shipped with the package are not monotone.
# The model's validity domain has to be stated, not assumed.
.piml_is_monotone <- function(depths, values) {
  o <- order(depths)
  v <- values[o]
  all(diff(v) <= 0) || all(diff(v) >= 0)
}

# --- observation families ------------------------------------------------
#
# The likelihood used to be Gaussian on g/kg with a single sigma. That is wrong
# in three ways for a soil concentration, and the third is the one that bites.
#
#   1. Support. A Gaussian puts mass below zero. The fitted profile cannot go
#      negative under the positive parameterisation, but the OBSERVATION model
#      can, so a predictive interval for a deep horizon routinely reaches into
#      impossible concentrations.
#   2. Error structure. Laboratory error on organic carbon is closer to
#      multiplicative than additive: a 5% error on 40 g/kg is 2 g/kg, on 2 g/kg
#      it is 0.1.
#   3. WEIGHTING, which is the consequential one. With sigma constant, every
#      horizon contributes to the loss in the same absolute units, so a profile
#      running from 30 g/kg at the surface to 2 g/kg at 5 m is fitted almost
#      entirely by its topsoil. The deep horizons -- the ones that carry all
#      the information about the asymptote -- are effectively ignored.
#
# Two mean-preserving alternatives are offered, both parameterised so that
# `sigma` is the coefficient of variation and the model's prediction is the
# MEAN of the observation. Mean-preserving matters here because the prediction
# is a horizon average, i.e. a mass-preserving quantity; a median-preserving
# lognormal would bias every layer downward by exp(sigma^2/2).
.piml_families <- c("gaussian", "lognormal", "gamma")

# Negative log-likelihood. `sigma` is the SD in the property's units for
# "gaussian", and the coefficient of variation for the other two.
.piml_nll <- function(obs, pred, sigma, family = "gaussian") {
  n <- length(obs)
  if (!is.finite(sigma) || sigma <= 0) return(Inf)
  if (any(!is.finite(pred))) return(Inf)
  switch(family,
    gaussian = 0.5 * n * log(2 * pi * sigma^2) +
               sum((obs - pred)^2) / (2 * sigma^2),
    lognormal = {
      if (any(pred <= 0) || any(obs <= 0)) return(Inf)
      s2 <- log1p(sigma^2)                    # log-scale variance for CV sigma
      # location shifted by -s2/2 so that E[obs] = pred
      mu <- log(pred) - s2 / 2
      sum(log(obs)) + 0.5 * n * log(2 * pi * s2) +
        sum((log(obs) - mu)^2) / (2 * s2)
    },
    gamma = {
      if (any(pred <= 0) || any(obs <= 0)) return(Inf)
      shape <- 1 / sigma^2                    # CV = 1/sqrt(shape)
      -sum(stats::dgamma(obs, shape = shape, rate = shape / pred, log = TRUE))
    },
    stop("unknown family: ", family, call. = FALSE))
}

# The discrepancy a point fit minimises: the family's deviance, which is the
# negative log-likelihood with the scale profiled out.
.piml_deviance <- function(obs, pred, family = "gaussian") {
  if (any(!is.finite(pred))) return(Inf)
  switch(family,
    gaussian  = sum((obs - pred)^2),
    lognormal = {
      if (any(pred <= 0)) return(Inf)
      sum((log(obs) - log(pred))^2)
    },
    gamma = {
      if (any(pred <= 0)) return(Inf)
      2 * sum(-log(obs / pred) + (obs - pred) / pred)
    },
    stop("unknown family: ", family, call. = FALSE))
}

.piml_loss <- function(theta, depths, obs, y_surface = NULL,
                       lambda_reg = 1e-3, top = NULL, bottom = NULL,
                       center = NULL, family = "gaussian") {
  params <- .piml_unpack(theta, y_surface)
  # A laboratory value is the average over a horizon, not a point reading at
  # its mid-depth. When the horizon boundaries are known, compare the datum to
  # the model's depth-average over that interval; otherwise fall back to the
  # point evaluation.
  #
  # For a convex profile the point-at-midpoint shortcut predicts too low, by
  # the mid-point rule error f''(z) h^2 / 24. That is quadratic in horizon
  # thickness but proportional to curvature, and curvature collapses with
  # depth -- so on real profiles the correction lands almost entirely on the
  # surface horizons. Across 207 WoSIS pedons it moves the fitted y0 by a
  # median 0.28 g/kg and the asymptote by only 0.03.
  pred <- tryCatch(
    if (is.null(top) || is.null(bottom)) {
      .piml_solution(depths, params)
    } else {
      .piml_layer_mean(top, bottom, params)
    },
    error = function(e) rep(NA_real_, length(obs))
  )
  if (any(!is.finite(pred))) return(1e12)
  sse <- .piml_deviance(obs, pred, family)
  if (!is.finite(sse)) return(1e12)
  # Ridge toward the data-driven start, not toward the origin.
  #
  # On the log coordinates, shrinking theta to 0 means shrinking every rate and
  # every concentration toward 1 -- meaningless for g/kg or clay percent. Worse,
  # the previous version penalised the RAW y_inf, so the penalty scaled with the
  # square of the property's units and silently did part of the fitting: on the
  # `sp4` colusa pedon it pinned y_inf at 61.9% clay, a value the README then
  # reported as "the argillic-horizon asymptote". With the penalty removed the
  # same data give 533%. That number was imposed, not estimated.
  #
  # Centring makes the penalty a scale-free shrinkage toward the observed range
  # and keeps `reg` interpretable as "log-units of allowed departure".
  dev <- if (is.null(center)) theta else theta - center
  sse + lambda_reg * sum(dev^2)
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
#' @param top,bottom Optional numeric vectors giving the upper and lower
#'   boundary of each horizon, same length as `values`. When supplied, each
#'   observation is compared to the model's **depth-average over its horizon**
#'   rather than to a point evaluation at the mid-depth, which is what a
#'   laboratory value actually measures. Recommended whenever the boundaries
#'   are known: the point-at-midpoint shortcut predicts too low on a convex
#'   profile, by the mid-point rule error. The correction is concentrated in
#'   the thick, strongly curved surface horizons — across 207 WoSIS pedons it
#'   moves the fitted `y0` by a median 0.28 g/kg and the asymptote by 0.03.
#' @param family Observation family. `"gaussian"` (default, for backward
#'   compatibility) assumes additive error of constant absolute size;
#'   `"lognormal"` and `"gamma"` assume multiplicative error of constant
#'   *relative* size, which is what laboratory error on a concentration looks
#'   like, and both keep the prediction as the mean of the observation. The
#'   choice is not cosmetic: with a constant absolute error, a profile running
#'   from 30 g/kg at the surface to 2 g/kg at 5 m is fitted almost entirely by
#'   its topsoil, and the deep horizons that carry the asymptote contribute
#'   almost nothing.
#' @param start Optional named numeric vector of starting parameters on the
#'   internal log scale (`log_kappa`, `log_mu`, `log_y_asym`, and optionally
#'   `log_y0`). If `NULL`, several data-driven starts are tried and the best
#'   is kept.
#' @param reg Numeric L2 regularisation strength on the parameter
#'   vector.
#' @param control List passed to `stats::optim`'s `control` argument
#'   (default is `list(maxit = 2000)`).
#'
#' @section Parameterisation:
#' The model is estimated in the identified, positive coordinates
#' \eqn{(y_0, A, \kappa, \mu)}, where \eqn{A = y(\infty)} is the **attainable
#' deep value** and \eqn{\kappa = \lambda_0/\mu} is the total relaxation. The
#' familiar `lambda0` and `y_inf` are recovered for reporting. This matters
#' because \eqn{y_\infty} is *not* the asymptote of the solution: since the rate
#' decays with depth, the profile only traverses a fraction \eqn{1 - e^{-\kappa}}
#' of the \eqn{y_0 \to y_\infty} gap. Estimating \eqn{A} directly also removes
#' the near-collinearity of \eqn{\lambda_0} and \eqn{\mu} (the data constrain
#' their ratio far better than either alone) and, because all four coordinates
#' are exponentiated, it rules out the physically impossible fits the old
#' free-sign parameterisation returned on real data: negative surface carbon and
#' rates that *grow* exponentially with depth.
#'
#' @return A `edaphos_piml_profile` object with components:
#'   \describe{
#'     \item{params}{Named list with the fitted `lambda0`, `mu`, `y_inf`, `y0`,
#'       plus the identified coordinates `kappa` and `y_asym`.}
#'     \item{theta}{The unconstrained parameter vector the optimiser found.}
#'     \item{objective}{Final regularised SSE loss.}
#'     \item{converged}{Logical, whether `optim` reported convergence.}
#'     \item{depths, values, y_surface, top, bottom}{Inputs echoed back.}
#'     \item{rmse}{Unregularised RMSE on the training data.}
#'   }
#' @export
#' @examples
#' depths <- c(5, 15, 30, 60, 100)
#' values <- c(25, 18, 12, 8, 6.5)   # e.g. SOC (g/kg) decreasing with depth
#' fit <- piml_profile_fit(depths, values)
#' fit
#' piml_profile_predict(fit$params, c(10, 50))
#'
#' # With horizon boundaries, each value is matched to the layer average:
#' piml_profile_fit(depths, values,
#'                  top    = c(0, 10, 20, 40, 80),
#'                  bottom = c(10, 20, 40, 80, 120))
piml_profile_fit <- function(depths, values, y_surface = NULL,
                             top = NULL, bottom = NULL,
                             family = c("lognormal", "gaussian", "gamma"),
                             start = NULL, reg = 1e-3,
                             control = list(maxit = 2000)) {
  family <- match.arg(family)
  stopifnot(length(depths) == length(values),
            length(depths) >= 2L,
            all(is.finite(depths)), all(is.finite(values)),
            all(depths >= 0))
  if (!is.null(top) || !is.null(bottom)) {
    stopifnot(!is.null(top), !is.null(bottom),
              length(top) == length(values), length(bottom) == length(values),
              all(is.finite(top)), all(is.finite(bottom)),
              all(top >= 0), all(bottom > top))
  }
  # The likelihood is on positive concentrations; a non-positive observation has
  # no place on this scale and signals a units or missing-value problem.
  if (any(values <= 0)) {
    stop("piml_profile_fit() models a positive soil property; ",
         sum(values <= 0), " of ", length(values),
         " observed values are <= 0. Check units and missing-value codes.",
         call. = FALSE)
  }
  starts <- if (!is.null(start)) list(start) else {
    ord <- order(depths)
    zd  <- depths[ord]; yd <- values[ord]
    y0_guess <- if (is.null(y_surface)) yd[1L] else y_surface
    # The attainable deep value is bracketed by the deepest observation; start
    # at it, and also below it, since the profile may still be descending.
    A_guess <- max(yd[length(yd)], 1e-3)
    dy0 <- (yd[2L] - yd[1L]) / max(zd[2L] - zd[1L], 1e-3)
    denom <- max(abs(y0_guess - A_guess), 1e-3)
    lambda0_guess <- max(abs(dy0) / denom, 1e-4)
    zmax <- max(zd)
    # mu sets the depth scale over which the rate decays; sweep it across the
    # observed range (fast, slow, essentially constant). kappa follows from
    # lambda0/mu. The surface is a poor place to start a Nelder-Mead simplex on
    # a ridge-shaped likelihood, so use several and keep the best.
    grid <- expand.grid(mu_scale = c(0.5, 2, 20) / max(zmax, 1),
                        A_mult   = c(1, 0.5))
    lapply(seq_len(nrow(grid)), function(i) {
      mu0 <- grid$mu_scale[i]
      th <- c(log_kappa  = log(max(lambda0_guess / mu0, 1e-6)),
              log_mu     = log(mu0),
              log_y_asym = log(max(A_guess * grid$A_mult[i], 1e-4)))
      if (is.null(y_surface)) c(th, log_y0 = log(max(y0_guess, 1e-4))) else th
    })
  }
  fit <- NULL
  for (s in starts) {
    f <- tryCatch(
      stats::optim(par = s, fn = .piml_loss,
                   depths = depths, obs = values, y_surface = y_surface,
                   lambda_reg = reg, top = top, bottom = bottom,
                   center = s, family = family,
                   method = "Nelder-Mead", control = control),
      error = function(e) NULL)
    if (!is.null(f) && (is.null(fit) || f$value < fit$value)) fit <- f
  }
  if (is.null(fit)) {
    stop("piml_profile_fit(): the optimiser failed from every starting point.",
         call. = FALSE)
  }
  params <- .piml_unpack(fit$par, y_surface)
  pred   <- if (is.null(top)) piml_profile_predict(params, depths) else
    .piml_layer_mean(top, bottom, params)
  structure(
    list(
      params    = params,
      theta     = fit$par,
      objective = fit$value,
      converged = fit$convergence == 0L,
      depths    = depths,
      values    = values,
      y_surface = y_surface,
      top       = top,
      bottom    = bottom,
      family    = family,
      fitted    = pred,
      rmse      = .rmse(values, pred),
      # Fraction of the y0 -> y(Inf) journey the deepest horizon reached. Below
      # ~0.5 the deep value is an extrapolation the data do not support, and
      # print() says so rather than letting the number stand unqualified.
      progress  = .piml_progress(params, depths),
      # y0 relative to the largest observation: the surface counterpart of the
      # same problem.
      surface_ratio = .piml_surface_ratio(params, values),
      # Whether the data are the monotone shape this model can represent.
      in_scope  = .piml_is_monotone(depths, values)
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
  cat(sprintf("  y0      = %-8.4g  y(Inf) = %-8.4g   (kappa = %.3g)\n",
              x$params$y0, .piml_asymptote(x$params),
              x$params$lambda0 / x$params$mu))
  # y_inf is a coordinate of the differential equation, not a depth the profile
  # reaches; print it as such so it is never read as "the deep value".
  cat(sprintf("  y_inf   = %-8.4g  (ODE coordinate, not the attained value)\n",
              x$params$y_inf))
  cat(sprintf("  n obs   = %d %s        rmse = %.4g\n",
              length(x$values),
              if (is.null(x$top)) "(point)" else "(layer) ", x$rmse))
  cat("  converged =", x$converged, "\n")
  pg <- x$progress %||% .piml_progress(x$params, x$depths)
  if (is.finite(pg) && pg < 0.5) {
    cat(sprintf(paste0("  NOTE: the deepest horizon (%g cm) has travelled only ",
                       "%.0f%% of the\n        way to y(Inf), so the deep value ",
                       "is an extrapolation, not an\n        estimate. Do not ",
                       "read it as a parent-material value.\n"),
                max(x$depths), 100 * pg))
  }
  sr <- x$surface_ratio %||% .piml_surface_ratio(x$params, x$values)
  if (is.finite(sr) && sr > 2) {
    cat(sprintf(paste0("  NOTE: y0 is %.1fx the largest observation. A monotone ",
                       "exponential can only\n        match a steep near-surface ",
                       "drop by leaving z = 0 from far above the\n        data; ",
                       "y0 here is an extrapolation, not a measured surface ",
                       "value.\n"), sr))
  }
  sc <- x$in_scope %||% .piml_is_monotone(x$depths, x$values)
  if (isFALSE(sc)) {
    cat(paste0("  NOTE: the observations are not monotone in depth, and this ",
               "model is monotone\n        by construction (first-order ",
               "relaxation, lambda > 0). It cannot represent\n        an ",
               "argillic bulge, an E horizon under an A, or a buried A. The fit ",
               "is a\n        least-squares compromise, not a description of ",
               "the profile.\n"))
  }
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
#' @examples
#' data(br_cerrado)
#'
#' # Five pedons generated FROM the model, so the parameters the fit
#' # has to recover are known.  The closed form of
#' # dy/dz = -lambda0 exp(-mu z) (y - y_inf) is
#' #   y(z) = y_inf + (y0 - y_inf) exp(-(lambda0/mu)(1 - exp(-mu z)))
#' # and here surface SOC and the decay rate come from each Cerrado
#' # site's own soc and twi.
#' sites  <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
#' depths <- c(5, 15, 30, 60, 100)
#' set.seed(42)
#' pedons <- do.call(rbind, lapply(1:5, function(i) {
#'   y0    <- sites$soc[i]                 # topsoil SOC, g/kg
#'   y_inf <- 0.30 * y0                    # parent material
#'   lam0  <- 0.02 + 0.004 * sites$twi[i]
#'   data.frame(
#'     pedon = c("P1", "P2", "P3", "P4", "P10")[i],
#'     depth = depths,
#'     soc   = y_inf + (y0 - y_inf) *
#'             exp(-(lam0 / 0.02) * (1 - exp(-0.02 * depths))) +
#'             rnorm(5, 0, 0.3),           # 0.3 g/kg of lab noise
#'     yinf_true = y_inf)
#' }))
#'
#' fits <- piml_profile_fit_group(pedons, "pedon", "depth", "soc")
#'
#' # The list is keyed by split(), which orders the ids as CHARACTERS.
#' # fits[[2]] is pedon "P10", not the second pedon of the data frame.
#' names(fits)
#' unique(pedons$pedon)
#'
#' # Every pedon is fitted on its own, four parameters to five points,
#' # so a good rmse is cheap.  Read it next to the recovered asymptote:
#' # each profile is reproduced down to the 0.3 g/kg noise floor and
#' # `converged` is TRUE everywhere, while y_inf -- which describes the
#' # profile BELOW the deepest horizon and is constrained by no
#' # observation -- comes back between 0.35 and 1.27 times the truth.
#' truth <- unique(pedons[, c("pedon", "yinf_true")])
#' tab <- data.frame(
#'   rmse      = round(vapply(fits, function(f) f$rmse, 0), 3),
#'   converged = vapply(fits, function(f) f$converged, TRUE),
#'   yinf_hat  = round(vapply(fits, function(f) f$params$y_inf, 0), 2),
#'   yinf_true = round(truth$yinf_true[match(names(fits), truth$pedon)], 2))
#' tab
#' round(range(tab$yinf_hat / tab$yinf_true), 2)
#'
#' # A pedon with a single horizon cannot be fitted (four parameters,
#' # one observation).  The wrapper warns and keeps a NULL in that
#' # slot rather than dropping it, so downstream code has to test.
#' two <- rbind(pedons[pedons$pedon %in% c("P1", "P2"),
#'                     c("pedon", "depth", "soc")],
#'              data.frame(pedon = "P99", depth = 5, soc = 21))
#' f2 <- piml_profile_fit_group(two, "pedon", "depth", "soc")
#' vapply(f2, is.null, TRUE)
#'
#' # `...` reaches piml_profile_fit(), but there is one `...` for the
#' # whole group: y_surface = 30 pins EVERY surface at 30 g/kg, above
#' # the true surface of all five pedons, and the misfit grows by up
#' # to nineteenfold.  Per-pedon surface values need a loop over
#' # piml_profile_fit(), not this wrapper.
#' round(range(sites$soc), 1)
#' fixed <- piml_profile_fit_group(pedons, "pedon", "depth", "soc",
#'                                 y_surface = 30)
#' vapply(fixed, function(f) f$params$y0, 0)
#' r_free  <- vapply(fits,  function(f) f$rmse, 0)
#' r_fixed <- vapply(fixed, function(f) f$rmse, 0)
#' round(rbind(free = r_free, fixed = r_fixed,
#'             ratio = r_fixed / r_free), 2)
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
