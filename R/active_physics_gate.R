#' Build a physics gate from a PIML profile fit
#'
#' Convenience helper for constructing the `physics_gate` argument of
#' [al_query()] and [al_loop()] from an existing PIML fit — either the
#' parametric profile ([piml_profile_fit()]) or the Neural ODE variant
#' ([piml_neural_ode_fit()]).
#'
#' The gate rejects any candidate whose model-predicted target value falls
#' outside a physically plausible envelope derived from the PIML fit. For
#' the parametric ODE the envelope is
#' `[min(y0, y_inf), max(y0, y_inf)]`; for the Neural ODE it is the
#' range of predictions between `z = 0` and the deepest training depth
#' (extrapolated to `2 * max(depth)` as a conservative floor). Both are
#' widened by `safety_factor`.
#'
#' @param profile_fit A `edaphos_piml_profile` or
#'   `edaphos_piml_neural_ode` object.
#' @param safety_factor Numeric (>= 1). 1 = strict envelope; 1.2 = allow
#'   20 % slack on each side.
#' @param lower Optional hard lower bound in the target units
#'   (e.g. `0` for mass fractions). If supplied, overrides the lower
#'   end of the envelope.
#' @param upper Optional hard upper bound.
#'
#' @return A function `function(candidates, predicted_mean)` suitable for
#'   `al_query(..., physics_gate = <this>)`.
#' @export
al_physics_gate_piml <- function(profile_fit, safety_factor = 1.2,
                                 lower = NULL, upper = NULL) {
  stopifnot(is.numeric(safety_factor), length(safety_factor) == 1L,
            safety_factor >= 1)

  if (inherits(profile_fit, "edaphos_piml_profile")) {
    lo <- min(profile_fit$params$y0, profile_fit$params$y_inf)
    hi <- max(profile_fit$params$y0, profile_fit$params$y_inf)
  } else if (inherits(profile_fit, "edaphos_piml_neural_ode")) {
    ref_z <- c(0, profile_fit$depths, max(profile_fit$depths) * 2)
    ref_y <- piml_neural_ode_predict(profile_fit, ref_z)
    lo <- min(ref_y, na.rm = TRUE)
    hi <- max(ref_y, na.rm = TRUE)
  } else {
    stop("`profile_fit` must be a edaphos_piml_profile or ",
         "edaphos_piml_neural_ode.", call. = FALSE)
  }

  slack  <- safety_factor - 1
  span   <- max(abs(hi - lo), 1e-9)
  lo_env <- lo - slack * span
  hi_env <- hi + slack * span
  if (!is.null(lower)) lo_env <- max(lo_env, lower)
  if (!is.null(upper)) hi_env <- min(hi_env, upper)

  function(candidates, predicted_mean, ...) {
    predicted_mean >= lo_env & predicted_mean <= hi_env
  }
}
