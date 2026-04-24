# Pilar 1 x Pilar 3 bridge -- Causal 4D (time-varying effects)
# (v2.2.1 scope).
#
# Status: SCAFFOLD.
#
# Why this bridge?
# ----------------
# The backdoor-adjusted effect of Pilar 1 is a time-invariant scalar
# -- beta(MAP -> SOC) averaged over the entire observation window.
# But soil carbon dynamics are non-stationary: the causal effect of
# MAP on SOC is almost certainly different in the dry vs. wet season,
# different pre- vs. post-land-use-change, and varies on a decadal
# scale in response to climate drift.
#
# `causal_effect_time_varying()` estimates beta(t) on a sliding time
# window, using:
#   1. A temporal cube (lon, lat, t, covariates) from Pilar 3 as the
#      data source.
#   2. The same DAG from Pilar 1 applied WITHIN each window.
#   3. A smoothed time-series of beta_hat(t) with block-bootstrap CIs.
#
# The output is a 1-D trajectory of the causal effect through time,
# plus a test of whether the trajectory has a statistically
# significant trend (Mann-Kendall) -- the conceptual analogue, in
# causal DSM, of what the Pilar 3 EnKF does for predictive estimates.
#
# TODO (v2.2.1)
# -------------
#  - [ ] `causal_effect_time_varying(cube, dag, exposure, outcome,
#                                     window, step, ...)`
#  - [ ] Mann-Kendall trend test + CI via bootstrap
#  - [ ] autoplot method producing the beta(t) trajectory plot
#  - [ ] Benchmark on the Cerrado 168-month cube
#  - [ ] `vignettes/pilar1-pilar3-causal-4d.Rmd`

#' Estimate a time-varying causal effect beta(t) (scaffold, v2.2.1)
#'
#' @description **Not yet implemented.**  Scheduled for v2.2.1.
#' @param cube A temporal cube (dimnames `(t, h, w)`) plus a
#'   coordinate frame -- same schema as [`temporal_cube_to_tensor()`].
#' @param dag A `dagitty` DAG.
#' @param exposure,outcome Character column names of the causal query.
#' @param window Integer; number of time-slices per window.
#' @param step Integer; window stride.
#' @param ... Reserved for backend-specific options.
#' @return (When implemented) A data frame with columns `t_centre`,
#'   `beta_hat`, `ci_lo`, `ci_hi`, suitable for `ggplot2::geom_line`.
#' @export
causal_effect_time_varying <- function(cube, dag,
                                         exposure, outcome,
                                         window = 24L, step = 6L, ...) {
  stop(
    "`causal_effect_time_varying()` is scheduled for edaphos v2.2.1\n",
    "(Pilar 1 x Pilar 3 -- Causal 4D).",
    call. = FALSE
  )
}
