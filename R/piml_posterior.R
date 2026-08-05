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
#' @examples
#' # torch is a Suggests dependency AND its libtorch binaries are a
#' # separate download, so both halves of the guard are needed.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   depths <- c(5, 30, 60, 100)
#'   soc    <- c(24, 15, 9.5, 7)      # g/kg, a decaying Latossolo
#'
#'   # 30 epochs over 4 horizons is a runtime stub, not a trained model.
#'   # Say so with numbers before reading anything into the spread: the
#'   # ensemble clears the mean-only baseline but is two orders of
#'   # magnitude worse than the 4-parameter ODE on the same points.
#'   ens <- piml_neural_ode_fit_ensemble(depths, soc, K = 3L,
#'                                       hidden = c(8L, 8L), n_steps = 2L,
#'                                       epochs = 30L, seed = 1L)
#'   print(round(c(ensemble   = ens$rmse,
#'                 parametric = piml_profile_fit(depths, soc)$rmse,
#'                 mean_only  = sqrt(mean((soc - mean(soc))^2))), 4))
#'   #   ensemble 2.1506   parametric 0.0209   mean_only 6.5228
#'
#'   post <- piml_neural_ode_posterior(ens, newdepths = c(10, 40, 70),
#'                                     units = "g/kg")
#'   print(post)
#'
#'   # The sample axis IS the ensemble members, so n_samples = K = 3.
#'   # The stored q05 / q95 are therefore interpolations between the
#'   # smallest and the largest of three numbers, not tail quantiles.
#'   # K = 5 (the default) does not fix that, it makes them a 5-number
#'   # range.
#'   print(dim(post$samples))
#'   print(round(rbind(q05 = post$quantiles$q05,
#'                     min = apply(post$samples, 2L, min),
#'                     q95 = post$quantiles$q95,
#'                     max = apply(post$samples, 2L, max)), 4))
#'
#'   # include_obs_noise adds N(0, sigma^2) to each of those K draws,
#'   # sigma being the pooled member training RMSE:
#'   print(round(sqrt(mean(vapply(ens$members,
#'                                function(m) m$rmse^2, 0))), 4))   # 2.5407
#'
#'   # With K = 3 the resulting sd is itself computed from 3 numbers, so
#'   # it need not even increase: at 40 and 70 cm it FALLS, because the
#'   # three noise draws happened to push the members together. An
#'   # aleatoric term that shrinks the reported sd is the diagnostic
#'   # that K is far too small, not a property of the soil.
#'   pn <- piml_neural_ode_posterior(ens, newdepths = c(10, 40, 70),
#'                                   include_obs_noise = TRUE, seed = 7)
#'   print(round(rbind(mean_fn = post$sd, plus_noise = pn$sd), 4))
#'
#'   # A single depth is tagged "feature", several are "sample" --- the
#'   # downstream calibration helpers branch on that. as_edaphos_posterior()
#'   # routes here but refuses to guess the depths.
#'   print(piml_neural_ode_posterior(ens, newdepths = 40)$query_type)
#'   print(tryCatch(as_edaphos_posterior(ens),
#'                  error = function(e) conditionMessage(e)))
#' }
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
#' @examples
#' # Simulate a Latossolo SOC profile FROM the ODE the model fits, so
#' # the true mean function g(z) is known and the band can be scored
#' # against it rather than against the data it was fitted to.
#' truth <- list(lambda0 = 0.045, mu = 0.012, y_inf = 5.5, y0 = 26)
#' zobs  <- c(2.5, 7.5, 15, 25, 40, 60, 80, 100)
#' set.seed(11)
#' soc <- round(piml_profile_predict(truth, zobs) +
#'                stats::rnorm(8L, sd = 0.8), 2)
#'
#' fit  <- piml_profile_fit_bayesian(zobs, soc, seed = 1)
#' zg   <- seq(5, 95, by = 10)
#' post <- piml_bayes_posterior(fit, newdepths = zg, seed = 1,
#'                              units = "g/kg")
#' post
#'
#' # edaphos_posterior()'s default probs are 5 / 50 / 95, so q05..q95 is
#' # a 90% band. It contains the true g(z) at 7 of the 10 depths --- and
#' # depths within one profile are strongly correlated, so read that as
#' # roughly one test, not ten.
#' gz <- piml_profile_predict(truth, zg)
#' sum(gz >= post$quantiles$q05 & gz <= post$quantiles$q95)
#'
#' # The misses are not scatter. At 95 cm the Laplace posterior mean
#' # sits at 9.116 g/kg where the truth is 7.100.
#' round(c(post_mean = post$mean[10], truth = gz[10]), 3)
#'
#' # include_obs_noise = FALSE is a band on the MEAN FUNCTION. It covers
#' # a future observation at 2 of 10 depths; the noise-inflated version
#' # covers 7. Never quote the first as a prediction interval.
#' pn <- piml_bayes_posterior(fit, newdepths = zg, seed = 1,
#'                            include_obs_noise = TRUE)
#' set.seed(12)
#' ynew <- gz + stats::rnorm(10L, sd = 0.8)
#' c(mean_fn = sum(ynew >= post$quantiles$q05 & ynew <= post$quantiles$q95),
#'   plus_noise = sum(ynew >= pn$quantiles$q05 & ynew <= pn$quantiles$q95))
#'
#' # Same data, same seed, Metropolis instead of Laplace. Its band is
#' # 2.3x NARROWER on average yet covers 10 of 10: narrower AND better,
#' # because the Laplace Gaussian here is mis-centred rather than
#' # over-confident. Width alone would have ranked the two backwards.
#' fm <- piml_profile_fit_bayesian(zobs, soc, method = "mcmc",
#'                                 n_iter = 3000L, n_burn = 1000L, seed = 1)
#' pm <- piml_bayes_posterior(fm, newdepths = zg, seed = 1)
#' round(c(laplace = mean(post$quantiles$q95 - post$quantiles$q05),
#'         mcmc    = mean(pm$quantiles$q95 - pm$quantiles$q05)), 3)
#' c(laplace = sum(gz >= post$quantiles$q05 & gz <= post$quantiles$q95),
#'   mcmc    = sum(gz >= pm$quantiles$q05 & gz <= pm$quantiles$q95))
#' round(c(laplace = post$mean[10], mcmc = pm$mean[10], truth = gz[10]), 3)
#'
#' # Where the mis-centring comes from: 8 horizons identify the ODE
#' # coordinate y_inf (which the profile never attains) only weakly, and
#' # the Gaussian approximation to that
#' # skewed marginal is pulled upwards (6.795 against the true 5.5),
#' # which is exactly the depths at which the band misses.
#' round(rbind(laplace = subset(summary(fit), parameter == "y_inf",
#'                              c("mean", "sd", "q2.5", "q97.5")),
#'             mcmc    = subset(summary(fm), parameter == "y_inf",
#'                              c("mean", "sd", "q2.5", "q97.5"))), 3)
#'
#' # `seed` is not bookkeeping: it fixes WHICH n_draws of the stored
#' # draws are propagated. At n_draws = 50 the posterior mean at 30 cm
#' # moves by 0.12 g/kg between two seeds.
#' round(c(seed1 = piml_bayes_posterior(fit, 30, n_draws = 50L,
#'                                      seed = 1)$mean,
#'         seed2 = piml_bayes_posterior(fit, 30, n_draws = 50L,
#'                                      seed = 2)$mean), 4)
#'
#' # One depth is tagged "feature", several are "sample".
#' c(one = piml_bayes_posterior(fit, 30, seed = 1)$query_type,
#'   many = post$query_type)
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
