# Pillar 1 -- Cinelli & Hazlett (2020) sensitivity analysis (v1.9.2).
#
# Given a backdoor-adjusted (or IV) causal effect and standard error,
# this module quantifies how strong an unobserved confounder U would
# need to be -- in terms of its partial R-squared with exposure X and
# outcome Y -- to zero out or reverse the sign of the estimated
# effect.  The two canonical outputs:
#
#   - Robustness Value (RV):  the single number RV in [0, 1] such
#     that U with partial R^2 = RV on BOTH X and Y suffices to bring
#     the estimate to zero.  RV * 100 % is a widely-reported
#     interpretable scalar.
#
#   - Extreme Scenario bound: the bias-adjusted estimate under the
#     worst-case assumption that U explains ALL residual variance of
#     either X or Y.
#
#   - Bias-contour grid: a 2-D grid of (R^2_{Y~U|X,Z},
#     R^2_{X~U|Z}) -> adjusted beta, plotted as a contour map.
#     Classic for papers: the reader sees the ridge where the effect
#     vanishes.
#
# Exports
#   causal_sensitivity_summary()   : point estimates of RV, RV_q,
#                                     and the extreme-scenario bound.
#   causal_sensitivity_grid()      : 2-D bias-adjustment grid, ready
#                                     for contour plotting.
#   causal_sensitivity_from_lm()   : convenience wrapper over an
#                                     `lm` backdoor fit.
#   causal_sensitivity_from_iv()   : convenience wrapper over an
#                                     `edaphos_causal_iv` fit.
#
# Reference
#   Cinelli, C. and Hazlett, C. (2020). Making sense of sensitivity:
#   Extending omitted variable bias.  Journal of the Royal
#   Statistical Society: Series B, 82(1), 39-67.

# ---------------------------------------------------------------------------
# Core equations (pure linear algebra; no dependencies)
# ---------------------------------------------------------------------------

# Equation 2.14 of Cinelli & Hazlett (2020):
#
#   RV = (1/2) ( sqrt(f_q^4 + 4 f_q^2) - f_q^2 )
#
# where f_q = |t| * q / sqrt(df) is the "required" t-ratio reduction
# in units of standard errors.  q is a user-chosen multiplier
# (q = 1 -> zero-out; q = |t|/2 -> reduce by half).
.cinelli_rv <- function(t_stat, df, q = 1) {
  if (any(df <= 1)) return(NA_real_)
  fq2 <- (abs(t_stat) * q)^2 / df
  0.5 * (sqrt(fq2^2 + 4 * fq2) - fq2)
}

# Extreme-scenario bound (Cinelli & Hazlett 2020, eq 4.3):
#
#   |bias|_max = |t| * SE(beta) * 1 / sqrt(df)  * sqrt(R^2_Y / (1 - R^2_X))
#
# Below we take R^2_X = R^2_Y = R^2 (the "equal confounding"
# benchmark) and solve for the adjusted estimate.
.cinelli_adjusted_estimate <- function(beta, se, df,
                                         r2_xu_z, r2_yu_xz) {
  # Equation 4.2
  bf <- sqrt(r2_yu_xz * r2_xu_z / (1 - r2_xu_z))
  bias <- se * bf * sqrt(df)
  list(
    adjusted_estimate = beta - sign(beta) * bias,
    bias              = bias,
    bias_factor       = bf
  )
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Cinelli & Hazlett (2020) sensitivity summary for a causal effect
#'
#' Computes the **Robustness Value (RV)**: the minimum partial
#' R-squared (on *both* exposure and outcome, with the observed
#' adjustments partialed out) that an unobserved confounder U would
#' need to have to bring the estimate to zero (`q = 1`) or reduce it
#' by a fraction `q` of its magnitude.  Also reports the **RV at 5%
#' significance** (RV_q): the minimum R-squared to push the t-ratio
#' below the critical value.
#'
#' Interpretation: if RV = 0.10, then any confounder explaining more
#' than 10 percent of the residual variance in both X and Y (jointly)
#' would be enough to kill the effect.  Small RV = fragile estimate.
#'
#' @param effect Numeric; point estimate of the causal effect.
#' @param se Numeric; standard error of the estimate.
#' @param df Numeric; degrees of freedom (n - k - 1).
#' @param q Numeric; the fraction of the estimate we want to neutralise.
#'   `q = 1` is zero-out; `q = 0.5` is half-reduction.
#' @param alpha Significance level for RV_alpha (default `0.05`).
#' @return Named list with `rv`, `rv_alpha`, `t_stat`, and a verbal
#'   interpretation.
#' @export
#' @examples
#' # A 2SLS effect of beta = 0.008, SE = 0.003, df = 1080:
#' causal_sensitivity_summary(0.008, 0.003, 1080)
causal_sensitivity_summary <- function(effect, se, df,
                                         q = 1, alpha = 0.05) {
  stopifnot(length(effect) == 1L, length(se) == 1L, length(df) == 1L,
            se > 0, df > 1)
  t_stat <- effect / se
  rv     <- .cinelli_rv(t_stat, df, q = q)

  # Critical t for a two-sided test at alpha
  t_crit <- stats::qt(1 - alpha / 2, df = df)
  # RV_alpha: the R^2 such that |t_adj| = t_crit
  # solve for q_alpha: (|t| * q_alpha)^2 / df = f^2 at the critical level
  q_alpha <- max(0, (abs(t_stat) - t_crit) / abs(t_stat))
  rv_alpha <- .cinelli_rv(t_stat, df, q = q_alpha)

  verbal <- sprintf(
    "An unobserved confounder explaining %.1f%% of the residual variance in BOTH X and Y would suffice to zero out the estimate. At the %d%% significance threshold, %.1f%% is enough to make the result statistically insignificant.",
    rv * 100, round((1 - alpha) * 100), rv_alpha * 100
  )
  list(
    effect         = effect, se = se, df = df,
    t_stat         = t_stat,
    rv             = rv, rv_alpha = rv_alpha,
    q              = q, alpha = alpha,
    interpretation = verbal
  )
}

#' Bias-adjustment grid for a Cinelli & Hazlett sensitivity contour
#'
#' Builds a 2-D grid over (R^2 of U with X | Z, R^2 of U with Y | X,
#' Z) and returns the bias-adjusted estimate at each cell, ready for
#' `contour()` / `ggplot2::geom_contour()`.  The grid is dense enough
#' (51 x 51 by default) to render smooth contours.
#'
#' @param effect,se,df Point estimate, SE, degrees of freedom of the
#'   causal effect.
#' @param grid_size Integer; grid resolution per axis. Default `51L`.
#' @param r2_max Numeric in (0, 1); maximum partial-R^2 to plot.
#'   Default `0.6` (values above this are typically unrealistic for
#'   real covariates).
#' @return A long-format data frame with columns `r2_xu_z`,
#'   `r2_yu_xz`, `adjusted_estimate`, `bias`, `bias_factor`.
#' @export
causal_sensitivity_grid <- function(effect, se, df,
                                      grid_size = 51L,
                                      r2_max    = 0.6) {
  stopifnot(r2_max < 1)
  rx <- seq(0, r2_max, length.out = grid_size)
  ry <- seq(0, r2_max, length.out = grid_size)
  grid <- expand.grid(r2_xu_z = rx, r2_yu_xz = ry)
  out <- vapply(seq_len(nrow(grid)), function(i) {
    adj <- .cinelli_adjusted_estimate(effect, se, df,
                                        r2_xu_z  = grid$r2_xu_z[i],
                                        r2_yu_xz = grid$r2_yu_xz[i])
    c(adj$adjusted_estimate, adj$bias, adj$bias_factor)
  }, numeric(3L))
  grid$adjusted_estimate <- out[1L, ]
  grid$bias              <- out[2L, ]
  grid$bias_factor       <- out[3L, ]
  grid
}

#' Sensitivity analysis of an `lm` backdoor fit
#'
#' Convenience wrapper around [`causal_sensitivity_summary()`] that
#' extracts the effect, SE and df from a fitted `lm`.
#'
#' @param fit An `lm` object.
#' @param exposure Character; the exposure coefficient name.
#' @param q,alpha See [`causal_sensitivity_summary()`].
#' @return List identical to [`causal_sensitivity_summary()`].
#' @export
causal_sensitivity_from_lm <- function(fit, exposure,
                                         q = 1, alpha = 0.05) {
  stopifnot(inherits(fit, "lm"))
  co <- summary(fit)$coefficients
  if (!exposure %in% rownames(co))
    stop(sprintf("Exposure `%s` not among the `lm` coefficients.",
                   exposure), call. = FALSE)
  effect <- unname(co[exposure, "Estimate"])
  se     <- unname(co[exposure, "Std. Error"])
  df     <- stats::df.residual(fit)
  causal_sensitivity_summary(effect, se, df, q = q, alpha = alpha)
}

#' Sensitivity analysis of an `edaphos_causal_iv` fit
#'
#' The 2SLS estimator of [`causal_iv_fit_2sls()`] is consistent when
#' IV conditions hold.  This wrapper gives a classical Cinelli-Hazlett
#' envelope **treating the 2SLS estimate AS IF it were a backdoor
#' OLS estimate**.  This is a conservative sensitivity check: the
#' IV effect is bias-adjusted against a hypothetical remaining
#' confounder U that affects BOTH the exposure and the outcome
#' **after** the instruments have been projected out.  It is the
#' right envelope to report alongside the Sargan test.
#'
#' @param fit An `edaphos_causal_iv` object.
#' @param q,alpha See [`causal_sensitivity_summary()`].
#' @return List identical to [`causal_sensitivity_summary()`] with
#'   an extra `fit_estimator` field.
#' @export
causal_sensitivity_from_iv <- function(fit, q = 1, alpha = 0.05) {
  stopifnot(inherits(fit, "edaphos_causal_iv"))
  # df for 2SLS: n - (p_w + 1)  (intercept + exogenous + endogenous)
  k <- 1L + length(fit$covariates) + 1L
  df <- fit$n - k
  res <- causal_sensitivity_summary(fit$effect, fit$se, df,
                                      q = q, alpha = alpha)
  res$fit_estimator <- fit$estimator
  res
}
