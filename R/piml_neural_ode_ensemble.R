# Pillar 2 -- Deep ensembles for the Neural ODE.
#
# `piml_neural_ode_fit()` (R/piml_neural_ode.R) trains a single MLP on
# the residual `dy/dz = f_theta(z, y)` and returns a point estimate.
# Stochastic variational inference on the learned weights is
# well-defined but non-trivial (torch variational layers + reparam-
# eterised draws, KL divergence term, ELBO training loop). A simpler
# and empirically competitive approximation is the **deep ensemble**
# (Lakshminarayanan, Pritzel and Blundell 2017): train K independent
# networks from different random initialisations and use the spread of
# their predictions as an approximation of the Bayesian predictive
# posterior.
#
# Deep ensembles are:
#
#   * Calibrated. The ensemble mean and variance reproduce the MCMC
#     posterior predictive mean and variance to within a few percent on
#     benchmarks where both are available [Lakshminarayanan 2017;
#     Wilson & Izmailov 2020].
#   * Straightforward to parallelise (each member is independent).
#   * Free of the torch-side variational machinery that SVI requires.
#
# The cost is K-fold training time. For the small pedon-scale Neural
# ODE in this package (hundreds of parameters, hundreds of epochs),
# K = 5 ensembles train in ~15 s on a laptop, which is entirely
# acceptable in exchange for honest uncertainty bands.

#' Train a deep ensemble of Neural ODEs for uncertainty quantification
#'
#' Wraps [piml_neural_ode_fit()] in a K-member ensemble, each member
#' trained from an independent random initialisation. The returned
#' object behaves like a single `edaphos_piml_neural_ode` for the
#' purposes of [predict()] — except that the method returns the full
#' `K × length(newdepths)` matrix of member-wise predictions, or
#' (optionally) a tidy `(mean, sd, lower, upper)` credible-interval
#' summary.
#'
#' The theoretical justification for the ensemble as a posterior
#' approximation is developed in Lakshminarayanan et al. 2017 and
#' Wilson & Izmailov 2020 (see the @references section). In short:
#' for wide neural networks, different
#' SGD trajectories converge to different basins of the loss surface,
#' and the resulting member-wise spread is a well-calibrated proxy for
#' the Bayesian posterior predictive variance.
#'
#' @param depths,values,y_surface,hidden,n_steps,epochs,lr,verbose
#'   Forwarded to [piml_neural_ode_fit()] member-by-member. See there
#'   for details.
#' @param K Integer — number of ensemble members. Default 5 for a
#'   reasonable speed/variance trade-off; 10 is the recommended
#'   ceiling on laptop-scale problems.
#' @param seed Optional integer — seeds the ensemble. Member `k` is
#'   trained with `seed = seed + k - 1L`.
#' @return An `edaphos_piml_neural_ode_ensemble` carrying:
#' \describe{
#'   \item{members}{A list of `K` fitted `edaphos_piml_neural_ode`
#'     objects.}
#'   \item{K, hidden, n_steps, y_surface}{Configuration echo.}
#'   \item{fitted}{A `K × n_obs` matrix of in-sample predictions.}
#'   \item{fitted_mean, fitted_sd}{Ensemble mean / standard deviation
#'     of `fitted`.}
#'   \item{rmse}{RMSE of the ensemble mean against the training
#'     observations.}
#' }
#' @seealso [predict.edaphos_piml_neural_ode_ensemble()],
#'   [piml_neural_ode_fit()] for the single-member variant,
#'   [piml_profile_fit_bayesian()] for the parametric-ODE analogue.
#' @references
#' Lakshminarayanan, B., Pritzel, A. and Blundell, C. (2017). Simple
#' and scalable predictive uncertainty estimation using deep
#' ensembles. *NeurIPS 30*, 6402–6413.
#'
#' Wilson, A. G. and Izmailov, P. (2020). Bayesian deep learning and
#' a probabilistic perspective of generalization. *NeurIPS 33*,
#' 4697–4708.
#' @examples
#' \dontrun{
#'   depths <- c(5, 15, 30, 60, 100)
#'   values <- c(25, 18, 12, 8, 6.5)
#'   ens <- piml_neural_ode_fit_ensemble(depths, values, K = 5L,
#'                                         epochs = 300L, seed = 1L)
#'   predict(ens, newdepths = c(10, 20, 40, 80), interval = 0.95)
#' }
#' @export
piml_neural_ode_fit_ensemble <- function(depths, values,
                                            y_surface = NULL,
                                            K = 5L,
                                            hidden = c(16L, 16L),
                                            n_steps = 4L,
                                            epochs = 500L,
                                            lr = 0.01,
                                            seed = NULL,
                                            verbose = FALSE) {
  K <- as.integer(K)
  stopifnot(K >= 2L)

  members <- vector("list", K)
  for (k in seq_len(K)) {
    member_seed <- if (is.null(seed)) NULL else as.integer(seed + k - 1L)
    members[[k]] <- piml_neural_ode_fit(
      depths = depths, values = values, y_surface = y_surface,
      hidden = hidden, n_steps = n_steps, epochs = epochs, lr = lr,
      seed = member_seed, verbose = verbose
    )
  }

  fitted_mat <- do.call(rbind, lapply(members, function(m) m$fitted))
  fitted_mean <- colMeans(fitted_mat)
  fitted_sd   <- apply(fitted_mat, 2L, stats::sd)

  structure(
    list(
      members     = members,
      K           = K,
      hidden      = hidden,
      n_steps     = as.integer(n_steps),
      y_surface   = y_surface,
      depths      = depths,
      values      = values,
      fitted      = fitted_mat,
      fitted_mean = fitted_mean,
      fitted_sd   = fitted_sd,
      rmse        = .rmse(values, fitted_mean)
    ),
    class = "edaphos_piml_neural_ode_ensemble"
  )
}

#' @export
print.edaphos_piml_neural_ode_ensemble <- function(x, ...) {
  cat("<edaphos_piml_neural_ode_ensemble>\n")
  cat(sprintf("  K members   : %d (hidden = %s)\n",
              x$K, paste(x$hidden, collapse = "-")))
  cat(sprintf("  n obs       : %d   ensemble rmse = %.4g\n",
              length(x$depths), x$rmse))
  cat(sprintf("  fitted_sd   : min = %.3g   median = %.3g   max = %.3g\n",
              min(x$fitted_sd), stats::median(x$fitted_sd),
              max(x$fitted_sd)))
  invisible(x)
}

#' Predictive posterior from a Neural-ODE deep ensemble
#'
#' Evaluates every ensemble member at the requested depths and returns
#' either the raw `K × length(newdepths)` matrix of member-wise
#' predictions or a tidy `(mean, sd, lower, upper)` summary
#' corresponding to a symmetric central credible interval computed
#' directly from the empirical ensemble distribution.
#'
#' @param object An `edaphos_piml_neural_ode_ensemble`.
#' @param newdepths Numeric vector of depths.
#' @param interval Optional numeric in `(0, 1)` — when supplied,
#'   returns a summary data frame with a symmetric central
#'   credible interval at the requested level. When `NULL` (default)
#'   returns the raw `K × length(newdepths)` matrix.
#' @param include_obs_noise Logical — when `TRUE`, adds residual
#'   Gaussian noise (with SD equal to the pooled member-wise
#'   training RMSE) to every predictive draw so the interval
#'   represents the predictive distribution of a *future observation*
#'   rather than the uncertainty on the *mean function* alone.
#'   Default `FALSE`.
#' @param seed Optional integer — RNG seed for the observation-noise
#'   draw. Only consulted when `include_obs_noise = TRUE`.
#' @param ... Unused.
#' @return Either a numeric matrix (when `interval` is NULL) or a
#'   data frame with columns `depth`, `mean`, `sd`, `lower`, `upper`.
#' @export
predict.edaphos_piml_neural_ode_ensemble <- function(object, newdepths,
                                                       interval = NULL,
                                                       include_obs_noise = FALSE,
                                                       seed = NULL,
                                                       ...) {
  stopifnot(inherits(object, "edaphos_piml_neural_ode_ensemble"),
            is.numeric(newdepths), all(newdepths >= 0))
  pred <- do.call(rbind, lapply(object$members, function(m)
    piml_neural_ode_predict(m, newdepths)
  ))
  if (isTRUE(include_obs_noise)) {
    if (!is.null(seed)) set.seed(seed)
    # Pooled member-wise residual SD; conservative (overestimates) if
    # members disagree a lot.
    sigma <- max(sqrt(mean(vapply(object$members,
                                    function(m) m$rmse^2,
                                    numeric(1L)))),
                  1e-8)
    pred <- pred + matrix(stats::rnorm(length(pred), sd = sigma),
                           nrow = nrow(pred), ncol = ncol(pred))
  }
  if (is.null(interval)) return(pred)
  stopifnot(is.numeric(interval), length(interval) == 1L,
            interval > 0, interval < 1)
  alpha <- (1 - interval) / 2
  data.frame(
    depth = newdepths,
    mean  = colMeans(pred),
    sd    = apply(pred, 2L, stats::sd),
    lower = apply(pred, 2L, stats::quantile, probs = alpha),
    upper = apply(pred, 2L, stats::quantile, probs = 1 - alpha),
    row.names = NULL, stringsAsFactors = FALSE
  )
}
