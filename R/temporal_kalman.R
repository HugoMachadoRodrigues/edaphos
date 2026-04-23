# Pillar 3 -- Ensemble Kalman update for sequential assimilation of
# new ground observations into a ConvLSTM forecast.
#
# The ConvLSTM trained by `temporal_convlstm_fit()` produces a
# forecast grid of the target variable (e.g. monthly NDVI or SOC
# anomaly). In a real DSM pipeline, new in-situ observations keep
# arriving -- a soil sampling campaign lands 30 new WoSIS profiles,
# a flux tower returns a year of new NDVI. The forecast should
# *update*, Bayesian-style, to reflect that new evidence without
# re-training the network.
#
# The canonical tool is the Ensemble Kalman Filter (Evensen 1994;
# Burgers, van Leeuwen and Evensen 1998), which represents the
# forecast distribution as an ensemble of plausible grid states,
# applies a gain matrix at each new observation, and returns the
# posterior ensemble without ever storing the full NxN covariance.
#
# For the pedometric setting -- sparse ground observations relative
# to a dense forecast grid, observations linked to grid cells by a
# linear indexing operator H -- the EnKF analysis step reduces to
#
#   K  = P_f H^T (H P_f H^T + R)^{-1}
#   X_a^(i) = X_f^(i) + K (y + eps^(i) - H X_f^(i)),    i = 1..N_ens
#
# where X_f is the forecast ensemble (grid x ensemble), H is the
# sparse sampling operator, R is the observation-noise covariance,
# and eps^(i) ~ N(0, R) are perturbed-observation draws (stochastic
# EnKF).
#
# This file implements exactly that update for the output of
# `temporal_convlstm_fit()` / `_rollout()`, with P_f estimated
# directly from the ensemble rather than the full grid covariance.

#' Ensemble Kalman update of a Pillar 3 forecast by new point observations
#'
#' Nudges a `temporal_convlstm_rollout` forecast toward a set of new
#' in-situ observations at known grid coordinates, using the
#' stochastic Ensemble Kalman Filter of Evensen (1994) and Burgers,
#' van Leeuwen and Evensen (1998).
#'
#' The forecast must be an ensemble: the stochastic EnKF treats the
#' first dimension of `forecast_ensemble` as the ensemble axis (size
#' \eqn{N_{\mathrm{ens}}}). A point estimate (single-member "ensemble")
#' is supported but the update collapses to a deterministic nudge and
#' the posterior uncertainty cannot be recovered from a single run.
#'
#' **Algorithm (stochastic EnKF)**. For each ensemble member
#' \eqn{X_f^{(i)}}:
#'
#' 1. Draw an observation perturbation
#'    \eqn{\varepsilon^{(i)} \sim \mathcal N(0, R)}.
#' 2. Compute the Kalman gain
#'    \eqn{K = P_f H^T (H P_f H^T + R)^{-1}}, where
#'    \eqn{P_f} is estimated from the ensemble and \eqn{H} is the
#'    linear operator mapping the full grid to the observed cells.
#' 3. Analysis step:
#'    \eqn{X_a^{(i)} = X_f^{(i)} + K (y + \varepsilon^{(i)} - H X_f^{(i)})}.
#'
#' @section Spatial localization:
#' For small ensembles (`N_ens < ~100`), the raw sample covariance
#' develops spurious long-range correlations that drag the analysis
#' away from the truth far from the observations. The optional
#' `localization_radius` argument applies a Gaspari-Cohn (1999)
#' 5th-order polynomial taper to the Kalman gain, zeroing the update
#' outside a neighbourhood of each observation. Without localization
#' (`localization_radius = NULL`, the default), small ensembles often
#' exhibit the classic ensemble-collapse pathology in which the
#' analysis RMSE grows above the prior RMSE even as the posterior
#' spread shrinks.
#'
#' @param forecast_ensemble A 3-D array `(N_ens, H, W)` (single-step
#'   forecast) or 4-D array `(N_ens, H, W, T)` (multi-step). For 4-D
#'   input the update is applied at `time_step`.
#' @param obs_value Numeric vector of length `n_obs` — the observed
#'   values to assimilate.
#' @param obs_row,obs_col Integer vectors of length `n_obs` — the
#'   row / column indices (1-based, row-major from the top-left of
#'   the grid) at which the observations were taken.
#' @param obs_sd Numeric scalar or vector of length `n_obs` — the
#'   standard deviation of each observation. Sets the diagonal of
#'   the observation-noise covariance matrix \eqn{R}.
#' @param time_step Integer — when `forecast_ensemble` is 4-D, which
#'   time slice to update. Ignored for 3-D input.
#' @param localization_radius Optional numeric — if supplied, applies a
#'   Gaspari-Cohn (1999) 5th-order polynomial taper to the Kalman gain
#'   as a function of grid-cell distance from each observation. The
#'   taper is 1 at distance 0, half-bandwidth `localization_radius`
#'   cells, and identically zero beyond `2 * localization_radius`
#'   cells. Typical choices are `localization_radius = 2`..`5` cells
#'   for ensembles in the `K = 5`..`30` range. The default `NULL`
#'   disables localization (pure stochastic EnKF).
#' @param seed Optional integer — seeds the Gaussian perturbations.
#'
#' @return A list with:
#' \describe{
#'   \item{analysis_ensemble}{The updated ensemble, same shape as
#'     `forecast_ensemble`.}
#'   \item{analysis_mean, analysis_sd}{Pointwise posterior mean /
#'     standard deviation across ensemble members, at the updated
#'     time step.}
#'   \item{gain_row_norm}{For diagnostics: the \eqn{L_2} norm of each
#'     column of the Kalman gain, one per observation. Large values
#'     indicate observations that moved the posterior a lot.}
#'   \item{innovation}{The vector \eqn{y - H \bar X_f} of
#'     observation-minus-forecast differences, a standard EnKF
#'     diagnostic.}
#' }
#' @references
#' Evensen, G. (1994). Sequential data assimilation with a
#' nonlinear quasi-geostrophic model using Monte Carlo methods to
#' forecast error statistics. *Journal of Geophysical Research:
#' Oceans* **99**(C5), 10143-10162.
#'
#' Burgers, G., van Leeuwen, P. J. and Evensen, G. (1998). Analysis
#' scheme in the ensemble Kalman filter. *Monthly Weather Review*
#' **126**, 1719-1724.
#' @examples
#' \dontrun{
#'   # Forecast ensemble from a ConvLSTM with K members
#'   fc <- array(rnorm(10 * 20 * 20), dim = c(10, 20, 20))
#'
#'   # Three in-situ observations at known grid cells
#'   assim <- temporal_kalman_update(
#'     forecast_ensemble = fc,
#'     obs_value = c(0.62, 0.58, 0.51),
#'     obs_row   = c(5L, 10L, 15L),
#'     obs_col   = c(5L, 10L, 15L),
#'     obs_sd    = 0.02,
#'     seed      = 1L
#'   )
#'   assim$analysis_mean          # posterior mean field
#'   assim$analysis_sd            # posterior SD field
#' }
#' @export
temporal_kalman_update <- function(forecast_ensemble,
                                     obs_value,
                                     obs_row,
                                     obs_col,
                                     obs_sd,
                                     time_step = 1L,
                                     localization_radius = NULL,
                                     seed = NULL) {
  stopifnot(is.array(forecast_ensemble),
            length(dim(forecast_ensemble)) %in% c(3L, 4L),
            is.numeric(obs_value),
            length(obs_row) == length(obs_value),
            length(obs_col) == length(obs_value),
            all(obs_row >= 1L), all(obs_col >= 1L))
  if (!is.null(seed)) set.seed(seed)

  four_d <- length(dim(forecast_ensemble)) == 4L
  N_ens  <- dim(forecast_ensemble)[1L]
  H_grid <- dim(forecast_ensemble)[2L]
  W_grid <- dim(forecast_ensemble)[3L]
  if (four_d) {
    stopifnot(time_step >= 1L, time_step <= dim(forecast_ensemble)[4L])
    X_f <- forecast_ensemble[, , , time_step, drop = TRUE]
  } else {
    X_f <- forecast_ensemble
  }

  # Flatten each ensemble member to a length-(H*W) state vector.
  # `X_flat` has shape (N_ens, H*W); P_f is the implicit ensemble
  # covariance (we never materialise the full H*W x H*W matrix).
  N_state <- H_grid * W_grid
  X_flat <- matrix(X_f, nrow = N_ens, ncol = N_state)

  # Observation operator H: linear pick-out of the observed cells.
  # H is a (n_obs, N_state) 0/1 matrix. We use the sparse equivalent.
  stopifnot(all(obs_row <= H_grid), all(obs_col <= W_grid))
  obs_lin <- (obs_col - 1L) * H_grid + obs_row   # column-major flatten
  n_obs   <- length(obs_value)
  if (length(obs_sd) == 1L) obs_sd <- rep(obs_sd, n_obs)
  stopifnot(length(obs_sd) == n_obs, all(obs_sd > 0))

  # Ensemble anomalies.
  X_mean <- colMeans(X_flat)
  A      <- sweep(X_flat, 2L, X_mean)           # (N_ens, N_state)

  # H A^T has shape (n_obs, N_ens).
  HA <- t(A[, obs_lin, drop = FALSE])           # (n_obs, N_ens)
  # Sample covariance of HA (i.e. H P_f H^T) is HA HA^T / (N_ens - 1).
  R_mat  <- diag(obs_sd^2, n_obs, n_obs)
  HPfHt  <- (HA %*% t(HA)) / max(N_ens - 1L, 1L)

  # Kalman gain K applied to each member: we can work with the
  # reduced form K = P_f H^T S^{-1} where S = H P_f H^T + R.
  S_inv   <- solve(HPfHt + R_mat)
  # Beware R operator precedence: `%*%` binds tighter than `/`, so we
  # need explicit parentheses around the scaled anomaly-cross-product
  # before multiplying by S_inv.
  K_reduced <- ((t(A) %*% t(HA)) / max(N_ens - 1L, 1L)) %*% S_inv
  # K_reduced has shape (N_state, n_obs).

  # Optional Gaspari-Cohn spatial localization. Builds a per-(state_cell,
  # observation) taper that is 1 at distance 0, falls to 0 at distance
  # 2 * localization_radius, and is strictly zero beyond. This is the
  # standard remedy (Houtekamer & Mitchell 2001) for spurious long-range
  # correlations in small-ensemble EnKFs.
  if (!is.null(localization_radius)) {
    stopifnot(is.numeric(localization_radius),
              length(localization_radius) == 1L,
              localization_radius > 0)
    cr <- as.numeric(localization_radius)
    # (row, col) for every state cell, and distances to each obs.
    state_row <- rep(seq_len(H_grid), times = W_grid)
    state_col <- rep(seq_len(W_grid), each  = H_grid)
    taper <- matrix(0, nrow = N_state, ncol = n_obs)
    for (k in seq_len(n_obs)) {
      d <- sqrt((state_row - obs_row[k])^2 +
                (state_col - obs_col[k])^2) / cr
      # Gaspari-Cohn (1999), their equation (4.10).
      z  <- d
      w  <- numeric(length(z))
      i1 <- z <= 1
      i2 <- z >  1 & z <= 2
      w[i1] <- 1 - (5/3) * z[i1]^2 + (5/8) * z[i1]^3 +
                (1/2) * z[i1]^4 - (1/4) * z[i1]^5
      w[i2] <- 4 - 5 * z[i2] + (5/3) * z[i2]^2 +
                (5/8) * z[i2]^3 - (1/2) * z[i2]^4 +
                (1/12) * z[i2]^5 - (2/3) / pmax(z[i2], 1e-12)
      w[w < 0] <- 0
      taper[, k] <- w
    }
    K_reduced <- K_reduced * taper
  }

  # Perturbed observations; one perturbation per ensemble member.
  eps <- matrix(stats::rnorm(N_ens * n_obs, sd = rep(obs_sd, each = N_ens)),
                 nrow = N_ens, ncol = n_obs)
  # Innovation (observation - forecast-at-obs-cell) per member.
  Y_obs_perturbed <- sweep(eps, 2L, obs_value, `+`)
  innovation_i    <- Y_obs_perturbed - X_flat[, obs_lin, drop = FALSE]

  # Analysis: X_a = X_f + K * innovation (per member).
  X_analysis_flat <- X_flat + innovation_i %*% t(K_reduced)

  # Reshape back to (N_ens, H, W).
  X_analysis <- array(X_analysis_flat, dim = c(N_ens, H_grid, W_grid))

  # If caller passed 4D, splice the analysis back in at time_step.
  out_ensemble <- if (four_d) {
    o <- forecast_ensemble
    o[, , , time_step] <- X_analysis
    o
  } else {
    X_analysis
  }

  # Diagnostics.
  analysis_mean <- apply(X_analysis, c(2L, 3L), mean)
  analysis_sd   <- apply(X_analysis, c(2L, 3L), stats::sd)
  gain_row_norm <- sqrt(colSums(K_reduced^2))
  innovation    <- obs_value - X_mean[obs_lin]

  structure(
    list(
      analysis_ensemble = out_ensemble,
      analysis_mean     = analysis_mean,
      analysis_sd       = analysis_sd,
      gain_row_norm     = gain_row_norm,
      innovation        = innovation,
      n_obs             = n_obs,
      n_ens             = N_ens
    ),
    class = "edaphos_temporal_kalman"
  )
}

#' @export
print.edaphos_temporal_kalman <- function(x, ...) {
  cat("<edaphos_temporal_kalman>\n")
  cat(sprintf("  n_ens  : %d\n", x$n_ens))
  cat(sprintf("  n_obs  : %d\n", x$n_obs))
  cat(sprintf("  innovation : mean=%+.4f  |max|=%.4f\n",
              mean(x$innovation, na.rm = TRUE),
              max(abs(x$innovation), na.rm = TRUE)))
  cat(sprintf("  gain_row_norm : mean=%.4f  max=%.4f\n",
              mean(x$gain_row_norm, na.rm = TRUE),
              max(x$gain_row_norm, na.rm = TRUE)))
  cat(sprintf("  analysis_sd   : mean=%.4f  max=%.4f\n",
              mean(x$analysis_sd, na.rm = TRUE),
              max(x$analysis_sd, na.rm = TRUE)))
  invisible(x)
}
