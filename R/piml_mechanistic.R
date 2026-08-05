# ---------------------------------------------------------------------------
# Pillar 2b -- the depth function DERIVED from a carbon balance.
#
# The parametric model in piml_profile.R,
#
#     dy/dz = -lambda0 e^{-mu z} (y - y_inf),
#
# is not derived from anything. There is no process in soil physics that yields
# a relaxation rate decaying exponentially with depth; the equation is the
# Russell & Moore (1968) exponential depth function (reviewed in Minasny et al.
# 2016) with a fourth shape parameter attached. A reviewer who knows the
# depth-function literature recognises it on sight.
#
# On real multi-horizon profiles the two are equally accurate once both are
# fitted with a correctly specified likelihood, so preferring the derived one
# costs nothing in prediction and gains a derivation.
#
# There IS a derivable equation for soil organic carbon with depth. Take the
# standard steady-state advection-reaction-diffusion balance (Elzein &
# Balesdent 1995; Braakhekke et al. 2011; Koven et al. 2013)
#
#     d/dz [ D(z) dC/dz - v C ] + I(z) - k(z) C = 0,
#
# and drop bioturbation (D = 0), valid below the mixed surface layer. With v
# the downward advection velocity and k the decomposition rate constant,
#
#     v dC/dz = I(z) - k C     =>     dC/dz = -(k/v) ( C - I(z)/k ).
#
# That is a relaxation equation with a CONSTANT rate lambda = k/v and a
# DEPTH-VARYING target I(z)/k. The depth-dependence belongs in the asymptote,
# not in the rate. Root carbon input declines exponentially with depth
# (Gale & Grigal 1987; Jackson et al. 1996 tabulate the rooting parameter by
# biome), I(z) = I0 e^{-z/z_r}, so with a mineral-associated floor A the target
# is A + B e^{-z/z_r} where B = I0/k.
#
# Every parameter is positive, named, and has a literature prior:
#   y0    surface concentration
#   A     deep, mineral-associated floor       (Hassink 1997 saturation)
#   B     root-input contribution at z = 0     (= I0/k)
#   z_r   rooting depth scale                  (Jackson et al. 1996: beta)
#   lam   k/v, decomposition per unit advection
#
# Closed form
# -----------
# With beta = 1/z_r, integrating dC/dz + lam C = lam (A + B e^{-beta z}):
#
#     C(z) = A + (y0 - A) e^{-lam z}
#              + (lam B / (lam - beta)) ( e^{-beta z} - e^{-lam z} ),
#
# and for lam = beta the limit is lam B z e^{-lam z}. C(0) = y0 and
# C(Inf) = A exactly -- unlike the attenuating-rate model, the asymptote of
# this equation IS a parameter of it, and it is non-negative by construction.
#
# The layer average over a horizon is analytic too, since every term is an
# exponential, so the horizon-interval observation operator costs nothing.
# ---------------------------------------------------------------------------

# exp integral helper: (1/(l-u)) * integral_u^l exp(-a z) dz
.pmech_expmean <- function(a, u, l) {
  d <- l - u
  ifelse(abs(a) * d < 1e-8,
         exp(-a * (u + l) / 2),                       # a -> 0 limit
         (exp(-a * u) - exp(-a * l)) / (a * d))
}

.pmech_unpack <- function(theta, y_surface = NULL) {
  A   <- exp(theta[1L])
  B   <- exp(theta[2L])
  lam <- exp(theta[3L])
  zr  <- exp(theta[4L])
  y0  <- if (is.null(y_surface)) exp(theta[5L]) else y_surface
  list(A = A, B = B, lambda = lam, z_r = zr, y0 = y0,
       beta = 1 / zr,
       # the mechanistic reading of the fitted numbers
       I0_over_k = B,
       k_over_v  = lam)
}

.pmech_solution <- function(z, p) {
  lam <- p$lambda; beta <- p$beta
  base <- p$A + (p$y0 - p$A) * exp(-lam * z)
  d <- lam - beta
  src <- if (abs(d) < 1e-10) {
    lam * p$B * z * exp(-lam * z)                     # confluent case
  } else {
    (lam * p$B / d) * (exp(-beta * z) - exp(-lam * z))
  }
  base + src
}

# Depth-average over [zu, zl] -- the operator that matches a horizon datum.
.pmech_layer_mean <- function(zu, zl, p) {
  lam <- p$lambda; beta <- p$beta
  d <- lam - beta
  out <- p$A + (p$y0 - p$A) * .pmech_expmean(lam, zu, zl)
  if (abs(d) < 1e-10) {
    # (1/(l-u)) integral of lam B z e^{-lam z} dz
    f <- function(z) -(z / lam + 1 / lam^2) * exp(-lam * z)
    out <- out + lam * p$B * (f(zl) - f(zu)) / (zl - zu)
  } else {
    out <- out + (lam * p$B / d) *
      (.pmech_expmean(beta, zu, zl) - .pmech_expmean(lam, zu, zl))
  }
  out
}

.pmech_loss <- function(theta, depths, obs, y_surface, lambda_reg, center,
                        top = NULL, bottom = NULL, family = "gaussian") {
  p <- .pmech_unpack(theta, y_surface)
  pred <- tryCatch(
    if (is.null(top) || is.null(bottom)) .pmech_solution(depths, p)
    else .pmech_layer_mean(top, bottom, p),
    error = function(e) NULL)
  if (is.null(pred) || any(!is.finite(pred))) return(1e12)
  dev <- .piml_deviance(obs, pred, family)
  if (!is.finite(dev)) return(1e12)
  dev + lambda_reg * sum((theta - center)^2)
}

#' Fit the depth profile derived from a steady-state carbon balance (Pillar 2b)
#'
#' Fits
#' \deqn{v \frac{dC}{dz} = I(z) - kC, \qquad I(z) = I_0 e^{-z/z_r},}
#' the advection-reaction limit of the standard soil-carbon depth balance with
#' bioturbation neglected, plus a mineral-associated floor. Equivalently
#' \deqn{\frac{dC}{dz} = -\lambda\,\bigl(C - [A + B e^{-z/z_r}]\bigr),
#'       \qquad \lambda = k/v,\; B = I_0/k,}
#' a relaxation with a **constant** rate toward a **depth-varying** target.
#'
#' This is the mechanistic counterpart to [piml_profile_fit()]. The two differ
#' in where the depth-dependence sits: [piml_profile_fit()] attenuates the
#' *rate* with depth, which no process produces and which pushes its
#' equilibrium coordinate outside the admissible range; this model attenuates
#' the *target*, following root input, and every parameter is positive with a
#' literature prior.
#'
#' On accuracy the two are a tie, and the honest statement of that took two
#' attempts. Under a Gaussian likelihood this model appeared to win decisively
#' on leave-the-deepest-horizon-out prediction across the 875 monotone profiles
#' in `inst/extdata/piml_wosis_cerrado.rds` (p = 2e-6). Correcting the
#' likelihood for BOTH models removed the difference: RMSE 1.483 against 1.507,
#' winning on 454 of 875 profiles against 421, paired Wilcoxon p = 0.25. The
#' Gaussian had been penalising the attenuating-rate form more heavily, because
#' weighting every horizon by the same absolute error hurts the model whose
#' flexibility lies in the deep tail.
#'
#' Prefer this model because it can be defended, not because it predicts
#' better. On the nine-horizon pedon shipped with the package it does fit
#' markedly better (RMSE 0.44 against 2.52 g/kg), but one pedon is one pedon.
#'
#' @param depths Numeric vector of horizon mid-depths (cm).
#' @param values Numeric vector of concentrations, same length, strictly
#'   positive.
#' @param y_surface Optional fixed surface value; if supplied it is not
#'   estimated.
#' @param top,bottom Optional horizon boundaries. When supplied each datum is
#'   compared to the model's depth-average over its horizon (analytic here,
#'   since every term is an exponential) rather than to a point evaluation.
#' @param family Observation family, as in [piml_profile_fit()]. Defaults to
#'   `"lognormal"`: soil carbon is positive and right-skewed, and a Gaussian
#'   on g/kg weights every horizon by the same absolute error, so a profile
#'   spanning 30 to 2 g/kg is fitted almost entirely by its topsoil.
#' @param reg L2 shrinkage toward the data-driven start, on the log scale.
#' @param control `stats::optim` control list.
#'
#' @return An `edaphos_piml_mech` object with `params` (`A`, `B`, `lambda`,
#'   `z_r`, `y0`), `rmse`, `fitted`, `converged`, and the inputs.
#'
#' @references
#' Elzein A, Balesdent J (1995). Mechanistic simulation of vertical
#' distribution of carbon concentrations and residence times in soils.
#' *Soil Science Society of America Journal* 59:1328–1335.
#'
#' Jackson RB, Canadell J, Ehleringer JR, Mooney HA, Sala OE, Schulze ED
#' (1996). A global analysis of root distributions for terrestrial biomes.
#' *Oecologia* 108:389–411.
#'
#' Braakhekke MC, Beer C, Hoosbeek MR, et al. (2011). SOMPROF: a vertically
#' explicit soil organic matter model. *Ecological Modelling* 222:1712–1730.
#'
#' @section What this model does not identify:
#' `lambda` is the ratio \eqn{k/v} of the decomposition rate constant to the
#' advection velocity, and `B` is the ratio \eqn{I_0/k} of the surface root
#' input to the same rate constant. A depth profile alone cannot separate
#' them: doubling both \eqn{k} and \eqn{v} leaves every prediction unchanged.
#' The fitted numbers are therefore *ratios with soil-physical meaning*, not
#' decomposition rates, and reporting `lambda` as a turnover rate would be
#' wrong. Separating \eqn{k} from \eqn{v} needs an independent constraint —
#' radiocarbon ages, a chronosequence, or a measured erosion or deposition
#' rate — none of which is in this package.
#'
#' The same applies to the neglected bioturbation term: setting \eqn{D = 0} is
#' an assumption about the depth range, valid below the mixed surface layer,
#' and it is not testable from a single profile.
#'
#' @seealso [piml_profile_fit()] for the attenuating-rate form, and
#'   `vignette("pilar2-piml-profile")` for the comparison.
#' @export
#' @examples
#' # A real WoSIS Cerrado profile shipped with the package.
#' D <- readRDS(system.file("extdata", "piml_wosis_cerrado.rds",
#'                          package = "edaphos"))
#' h <- D$horizons[D$horizons$profile_id == D$profiles$profile_id[1], ]
#' fit <- piml_profile_fit_mechanistic(h$depth_mid, h$soc_g_kg,
#'                                     top = h$top, bottom = h$bottom)
#' fit
piml_profile_fit_mechanistic <- function(depths, values, y_surface = NULL,
                                         top = NULL, bottom = NULL,
                                         family = c("lognormal", "gaussian",
                                                    "gamma"),
                                         reg = 1e-3,
                                         control = list(maxit = 4000)) {
  family <- match.arg(family)
  stopifnot(length(depths) == length(values), length(depths) >= 3L,
            all(is.finite(depths)), all(is.finite(values)), all(depths >= 0))
  if (any(values <= 0)) {
    stop("piml_profile_fit_mechanistic() models a positive concentration; ",
         sum(values <= 0), " of ", length(values), " values are <= 0.",
         call. = FALSE)
  }
  if (!is.null(top) || !is.null(bottom)) {
    stopifnot(!is.null(top), !is.null(bottom),
              length(top) == length(values), length(bottom) == length(values),
              all(is.finite(top)), all(is.finite(bottom)), all(bottom > top))
  }

  o  <- order(depths)
  zd <- depths[o]; yd <- values[o]
  y0g <- if (is.null(y_surface)) yd[1L] else y_surface
  Ag  <- max(yd[length(yd)], 1e-3)
  Bg  <- max(y0g - Ag, 1e-3)
  zmax <- max(zd)

  # Rooting depth scale: Jackson et al. (1996) give beta ~ 0.972 for tropical
  # savanna, i.e. z_r = -1/log(beta) ~ 35 cm. Sweep around it, and sweep the
  # k/v ratio over three orders of magnitude.
  grid <- expand.grid(zr = c(15, 35, 80), lam = c(0.005, 0.03, 0.15))
  starts <- lapply(seq_len(nrow(grid)), function(i) {
    th <- c(log(Ag), log(Bg), log(grid$lam[i]), log(grid$zr[i]))
    if (is.null(y_surface)) c(th, log(max(y0g, 1e-4))) else th
  })

  fit <- NULL
  for (s in starts) {
    f <- tryCatch(stats::optim(s, .pmech_loss, depths = depths, obs = values,
                               y_surface = y_surface, lambda_reg = reg,
                               center = s, top = top, bottom = bottom,
                               family = family,
                               method = "Nelder-Mead", control = control),
                  error = function(e) NULL)
    if (!is.null(f) && (is.null(fit) || f$value < fit$value)) fit <- f
  }
  if (is.null(fit))
    stop("piml_profile_fit_mechanistic(): optimiser failed from every start.",
         call. = FALSE)

  params <- .pmech_unpack(fit$par, y_surface)
  pred <- if (is.null(top)) .pmech_solution(depths, params) else
    .pmech_layer_mean(top, bottom, params)
  structure(list(params = params, theta = fit$par, objective = fit$value,
                 converged = fit$convergence == 0L,
                 depths = depths, values = values, y_surface = y_surface,
                 top = top, bottom = bottom, family = family, fitted = pred,
                 rmse = .rmse(values, pred)),
            class = "edaphos_piml_mech")
}

#' @export
print.edaphos_piml_mech <- function(x, ...) {
  p <- x$params
  cat("<edaphos_piml_mech>\n")
  cat("  v dC/dz = I0 exp(-z/z_r) - k C     (steady-state advection-reaction)\n")
  cat("  dC/dz   = -lambda (C - [A + B exp(-z/z_r)]),  lambda = k/v, B = I0/k\n")
  cat(sprintf("  y0    = %-9.4g  A (deep floor) = %-9.4g\n", p$y0, p$A))
  cat(sprintf("  B     = %-9.4g  z_r = %-9.4g cm   lambda = %.4g /cm\n",
              p$B, p$z_r, p$lambda))
  # Jackson et al. (1996) parameterise rooting by beta with Y = 1 - beta^d;
  # z_r maps to beta = exp(-1/z_r), which is the number that literature reports.
  cat(sprintf("  implied Jackson beta = %.4f\n", exp(-1 / p$z_r)))
  cat(sprintf("  n obs = %d %s       rmse = %.4g   converged = %s\n",
              length(x$values), if (is.null(x$top)) "(point)" else "(layer)",
              x$rmse, x$converged))
  invisible(x)
}

#' @export
predict.edaphos_piml_mech <- function(object, newdepths, ...) {
  stopifnot(inherits(object, "edaphos_piml_mech"))
  as.numeric(.pmech_solution(newdepths, object$params))
}
