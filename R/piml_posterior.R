# Pillar 2 adapter to the unified v1.6.0 uncertainty API.
#
# Pillar 2 already exposes two natural posteriors for the depth
# profile:
#
#   * `piml_neural_ode_fit_ensemble()`  --  a K-member deep ensemble
#     of differentiable Neural ODEs, with a built-in `predict()` that
#     returns a (K, length(newdepths)) matrix of per-member forecasts
#     (Lakshminarayanan, Pritzel & Blundell 2017).
#   * `piml_profile_fit_bayesian()`     --  either a Laplace posterior
#     (with 2000 pre-drawn samples) or an adaptive random-walk
#     Metropolis chain (Haario, Saksman & Tamminen 2001). Its
#     `predict()` returns a (M, length(newdepths)) sample matrix of
#     predictive draws.
#
# Both are sample-based posteriors over depth profiles, so the adapter
# consists of one call to the right `predict()` method + a thin
# wrapping in `edaphos_posterior`. This file is deliberately small;
# the scientific content lives in the existing `piml_*` files.

#' Posterior predictive distribution from a Pillar 2 deep ensemble
#'
#' Convenience wrapper that calls [predict.edaphos_piml_neural_ode_ensemble()]
#' on the requested depths and returns the result as an
#' [`edaphos_posterior()`] with `query_type = "sample"` (one scalar
#' prediction per query depth) or `"feature"` (when the caller
#' passes a single depth and wants the posterior over that single
#' scalar).
#'
#' @param object An `edaphos_piml_neural_ode_ensemble`.
#' @param newdepths Numeric vector of depths at which to evaluate
#'   the posterior predictive.
#' @param include_obs_noise Logical --- when `TRUE`, adds Gaussian
#'   observation noise to every draw so the posterior is the
#'   *predictive distribution of a future observation* (aleatoric
#'   included) rather than only the uncertainty on the mean
#'   function. Default `FALSE`.
#' @param seed Optional RNG seed for the observation-noise draw.
#' @param units Optional units tag.
#' @return An `edaphos_posterior` with `method = "ensemble"`.
#' @export
piml_neural_ode_posterior <- function(object, newdepths,
                                        include_obs_noise = FALSE,
                                        seed = NULL,
                                        units = NULL) {
  stopifnot(inherits(object, "edaphos_piml_neural_ode_ensemble"))
  draws <- stats::predict(object, newdepths = newdepths,
                            interval = NULL,
                            include_obs_noise = include_obs_noise,
                            seed = seed)
  # draws: (K, length(newdepths)) matrix.
  edaphos_posterior(
    samples    = draws,
    method     = "ensemble",
    query_type = if (length(newdepths) == 1L) "feature" else "sample",
    units      = units,
    metadata   = list(K = object$K, depths = as.numeric(newdepths),
                       include_obs_noise = include_obs_noise,
                       fit_class = "edaphos_piml_neural_ode_ensemble")
  )
}

#' Posterior predictive distribution from a Bayesian Pillar 2 fit
#'
#' Convenience wrapper that calls [predict.edaphos_piml_bayes()] on
#' the requested depths with either the Laplace or the MCMC posterior
#' samples, and returns the result as an [`edaphos_posterior()`].
#'
#' @param object An `edaphos_piml_bayes` (Laplace or MCMC).
#' @param newdepths Numeric vector of depths.
#' @param n_draws Integer --- number of posterior draws to keep from
#'   the underlying chain. Defaults to `min(500, nrow(object$draws))`.
#' @param include_obs_noise Logical --- see
#'   [piml_neural_ode_posterior()].
#' @param seed Optional RNG seed.
#' @param units Optional units tag.
#' @return An `edaphos_posterior` with `method = "bayesian"`.
#' @export
piml_bayes_posterior <- function(object, newdepths,
                                   n_draws = NULL,
                                   include_obs_noise = FALSE,
                                   seed = NULL,
                                   units = NULL) {
  stopifnot(inherits(object, "edaphos_piml_bayes"))
  draws <- stats::predict(object, newdepths = newdepths,
                            n_draws = n_draws, interval = NULL,
                            include_obs_noise = include_obs_noise,
                            seed = seed)
  edaphos_posterior(
    samples    = draws,
    method     = "bayesian",
    query_type = if (length(newdepths) == 1L) "feature" else "sample",
    units      = units,
    metadata   = list(
      fit_class         = "edaphos_piml_bayes",
      bayesian_method   = object$method,     # "laplace" or "mcmc"
      sigma             = object$sigma,
      include_obs_noise = include_obs_noise,
      depths            = as.numeric(newdepths)
    )
  )
}

#' @export
as_edaphos_posterior.edaphos_piml_neural_ode_ensemble <- function(x,
                                                                     newdepths = NULL,
                                                                     ...) {
  if (is.null(newdepths)) {
    stop("Supply `newdepths = ...` to adapt a Neural-ODE ensemble.",
         call. = FALSE)
  }
  piml_neural_ode_posterior(x, newdepths = newdepths, ...)
}

#' @export
as_edaphos_posterior.edaphos_piml_bayes <- function(x,
                                                      newdepths = NULL,
                                                      ...) {
  if (is.null(newdepths)) {
    stop("Supply `newdepths = ...` to adapt a Bayesian PIML fit.",
         call. = FALSE)
  }
  piml_bayes_posterior(x, newdepths = newdepths, ...)
}
