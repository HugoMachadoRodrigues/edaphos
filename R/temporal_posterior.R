# Pillar 3 adapter to the unified v1.6.0 uncertainty API.
#
# Pillar 3 now exposes three natural posteriors over the ConvLSTM
# forecast:
#
#   (A) K-seed deep ensemble of temporal_convlstm_fit() models.
#       v1.5.0 runs this loop by hand in
#       data-raw/temporal_cerrado_run.R; v1.6.0 promotes it to a
#       proper exported function, temporal_convlstm_ensemble_fit().
#
#   (B) MC-dropout at inference time (Gal & Ghahramani 2016).
#       temporal_convlstm_fit() gains an optional dropout_p knob;
#       temporal_convlstm_mcdropout_predict() runs M forward passes
#       with dropout kept in train mode, producing M posterior draws.
#
#   (C) The analysis ensemble of temporal_kalman_update() after a
#       sequential Bayesian assimilation step -- which is already an
#       (N_ens, H, W) sample of posterior maps.
#
# This file wires (A) and (B) as new entry points and registers
# `as_edaphos_posterior` methods for (A), (B) wrappers and (C) the
# temporal_kalman_update output. The temporal_kalman_update() return
# value now carries a class ("edaphos_temporal_kalman") so the
# adapter can dispatch.

# ---------------------------------------------------------------------------
# (A) K-seed deep ensemble
# ---------------------------------------------------------------------------

#' K-seed deep ensemble of stacked ConvLSTMs
#'
#' Trains `K_ens` independent [`temporal_convlstm_fit()`] models with
#' different random seeds and collects them in a single object. This
#' formalises the hand-rolled ensemble loop from the v1.5.0 Pillar 3
#' Cerrado runner (`data-raw/temporal_cerrado_run.R`) and produces the
#' natural forecast-ensemble input for [`temporal_kalman_update()`] or
#' for [`as_edaphos_posterior()`].
#'
#' @param sequence,target,hidden_dims,kernel_size,return_sequence,epochs,lr,physics_lambda,physics_k_in,physics_k_out,physics_driver_channel,verbose
#'   Passed through unchanged to [`temporal_convlstm_fit()`].
#' @param K_ens Integer; number of ensemble members. Defaults to
#'   `10L`.
#' @param base_seed Integer; each member uses `base_seed + k - 1L`.
#' @return A list with class `edaphos_temporal_convlstm_ensemble`
#'   containing
#' \describe{
#'   \item{members}{List of K `edaphos_temporal_convlstm` fits.}
#'   \item{K_ens}{Integer, the ensemble size.}
#'   \item{final_losses}{Numeric vector of per-member final training
#'     losses.}
#'   \item{loss_histories}{List of K numeric vectors (one per member).}
#' }
#' @seealso [`temporal_convlstm_rollout()`] to roll each member forward,
#'   [`temporal_kalman_update()`] to assimilate observations into the
#'   forecast ensemble, [`as_edaphos_posterior()`] for the unified
#'   uncertainty wrapper.
#' @export
temporal_convlstm_ensemble_fit <- function(sequence, target,
                                             hidden_dims = c(8L, 4L),
                                             kernel_size = 3L,
                                             return_sequence = FALSE,
                                             epochs = 80L, lr = 0.02,
                                             K_ens = 10L,
                                             base_seed = 101L,
                                             physics_lambda = 0,
                                             physics_k_in = 0.03,
                                             physics_k_out = 0.015,
                                             physics_driver_channel = 2L,
                                             verbose = FALSE) {
  K_ens <- as.integer(K_ens)
  stopifnot(K_ens >= 2L)
  members <- vector("list", K_ens)
  for (k in seq_len(K_ens)) {
    seed_k <- as.integer(base_seed + k - 1L)
    members[[k]] <- temporal_convlstm_fit(
      sequence = sequence, target = target,
      hidden_dims = hidden_dims, kernel_size = kernel_size,
      return_sequence = return_sequence,
      epochs = epochs, lr = lr,
      physics_lambda = physics_lambda,
      physics_k_in = physics_k_in,
      physics_k_out = physics_k_out,
      physics_driver_channel = physics_driver_channel,
      seed = seed_k, verbose = verbose
    )
  }
  structure(
    list(
      members        = members,
      K_ens          = K_ens,
      final_losses   = vapply(members, `[[`, numeric(1L), "final_loss"),
      loss_histories = lapply(members, `[[`, "loss_history"),
      config = list(hidden_dims = hidden_dims, kernel_size = kernel_size,
                     return_sequence = return_sequence,
                     epochs = epochs, lr = lr, base_seed = base_seed)
    ),
    class = "edaphos_temporal_convlstm_ensemble"
  )
}

#' @export
print.edaphos_temporal_convlstm_ensemble <- function(x, ...) {
  cat("<edaphos_temporal_convlstm_ensemble>\n")
  cat(sprintf("  K_ens         : %d\n", x$K_ens))
  cat(sprintf("  hidden_dims   : %s\n",
              paste(x$config$hidden_dims, collapse = "-")))
  cat(sprintf("  final_losses  : min=%.4f  median=%.4f  max=%.4f\n",
              min(x$final_losses), stats::median(x$final_losses),
              max(x$final_losses)))
  invisible(x)
}

#' Roll every ensemble member forward and stack the forecasts
#'
#' Produces the `(K_ens, T_future, H, W)` array that
#' [`temporal_kalman_update()`] and
#' [`as_edaphos_posterior()`] consume.
#'
#' @param object An `edaphos_temporal_convlstm_ensemble`.
#' @param past_sequence,future_drivers Passed through to
#'   [`temporal_convlstm_rollout()`] for each member.
#' @return A 4-D numeric array `(K_ens, T_future, H, W)`.
#' @export
temporal_convlstm_ensemble_rollout <- function(object,
                                                 past_sequence,
                                                 future_drivers) {
  stopifnot(inherits(object, "edaphos_temporal_convlstm_ensemble"))
  K <- object$K_ens
  first <- temporal_convlstm_rollout(object$members[[1L]],
                                       past_sequence = past_sequence,
                                       future_drivers = future_drivers)
  # first has shape (1, T_future, H, W)
  T_fut <- dim(first)[2L]
  H     <- dim(first)[3L]
  W     <- dim(first)[4L]
  out <- array(NA_real_, dim = c(K, T_fut, H, W))
  out[1L, , , ] <- first[1L, , , ]
  if (K >= 2L) {
    for (k in 2L:K) {
      fc <- temporal_convlstm_rollout(object$members[[k]],
                                        past_sequence = past_sequence,
                                        future_drivers = future_drivers)
      out[k, , , ] <- fc[1L, , , ]
    }
  }
  out
}

# ---------------------------------------------------------------------------
# (B) Inference-time MC-dropout wrapper
# ---------------------------------------------------------------------------

#' MC-dropout predictive draws from a ConvLSTM fit
#'
#' Runs `n_draws` forward passes through a fitted `edaphos_temporal_convlstm`
#' with dropout active in train mode, producing a Monte-Carlo sample of
#' the predictive posterior (Gal and Ghahramani 2016). The fit must
#' have been trained with `dropout_p > 0` for this to give a
#' non-degenerate sample; when the fit has no dropout layers the draws
#' collapse to the deterministic forward pass.
#'
#' @param object An `edaphos_temporal_convlstm` whose underlying
#'   `nn_module` contains `nn_dropout2d` layers. Fits produced by
#'   [`temporal_convlstm_fit()`] with the default `dropout_p = 0` work
#'   but produce a degenerate constant draw.
#' @param sequence 5-D input tensor `(batch, T, C, H, W)` or equivalent
#'   R array.
#' @param n_draws Integer; number of MC forward passes.
#' @param return_sequence Logical override; defaults to the value used
#'   at training time.
#' @param seed Optional integer seed.
#' @return A numeric array; first axis is the draw axis. Shape:
#'   `(n_draws, batch, T, H, W)` when `return_sequence = TRUE`, else
#'   `(n_draws, batch, H, W)`.
#' @references
#' Gal, Y. and Ghahramani, Z. (2016). Dropout as a Bayesian
#' approximation: representing model uncertainty in deep learning.
#' *ICML 33*, 1050-1059.
#' @export
temporal_convlstm_mcdropout_predict <- function(object, sequence,
                                                  n_draws = 50L,
                                                  return_sequence = NULL,
                                                  seed = NULL) {
  stopifnot(inherits(object, "edaphos_temporal_convlstm"))
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("torch is required for temporal_convlstm_mcdropout_predict().",
         call. = FALSE)
  }
  if (!is.null(seed)) torch::torch_manual_seed(seed)
  if (!inherits(sequence, "torch_tensor")) {
    sequence <- torch::torch_tensor(sequence)$to(dtype = torch::torch_float())
  }
  if (is.null(return_sequence)) return_sequence <- object$return_sequence
  n_draws <- as.integer(n_draws)
  stopifnot(n_draws >= 1L)

  # Keep dropout layers active by putting the module in train mode.
  object$model$train()
  on.exit(object$model$eval(), add = TRUE)

  draws <- vector("list", n_draws)
  for (m in seq_len(n_draws)) {
    pred <- torch::with_no_grad({
      as.array(object$model(sequence,
                             return_sequence = return_sequence)$cpu())
    })
    draws[[m]] <- pred
  }
  # Stack along a new first axis (the draw axis).
  arr <- array(unlist(draws, use.names = FALSE),
               dim = c(dim(draws[[1L]]), n_draws))
  # Move the new draw axis to position 1.
  .perm <- c(length(dim(arr)), seq_len(length(dim(arr)) - 1L))
  aperm(arr, .perm)
}

# ---------------------------------------------------------------------------
# Adapters
# ---------------------------------------------------------------------------

#' @export
as_edaphos_posterior.edaphos_temporal_convlstm_ensemble <- function(x,
                                                                      past_sequence = NULL,
                                                                      future_drivers = NULL,
                                                                      time_step = NULL,
                                                                      units = NULL, ...) {
  if (is.null(past_sequence) || is.null(future_drivers)) {
    stop("Supply `past_sequence` and `future_drivers` to roll the ensemble forward.",
         call. = FALSE)
  }
  rolls <- temporal_convlstm_ensemble_rollout(x,
                                                past_sequence = past_sequence,
                                                future_drivers = future_drivers)
  # rolls: (K, T_future, H, W). Pick a time slice -> (K, H, W).
  if (is.null(time_step)) time_step <- dim(rolls)[2L]     # last month
  stopifnot(time_step >= 1L, time_step <= dim(rolls)[2L])
  slice <- rolls[, time_step, , ]
  edaphos_posterior(
    samples    = slice,
    method     = "ensemble",
    query_type = "map",
    units      = units,
    metadata   = list(K_ens = x$K_ens, time_step = as.integer(time_step),
                       source = "temporal_convlstm_ensemble_rollout")
  )
}

#' @export
as_edaphos_posterior.edaphos_temporal_kalman <- function(x,
                                                            time_step = NULL,
                                                            units = NULL, ...) {
  # analysis_ensemble is either (N_ens, H, W) or (N_ens, H, W, T).
  ens <- x$analysis_ensemble
  dd  <- dim(ens)
  if (length(dd) == 4L) {
    if (is.null(time_step)) time_step <- dd[4L]
    stopifnot(time_step >= 1L, time_step <= dd[4L])
    samples <- ens[, , , time_step]
  } else {
    samples <- ens
  }
  edaphos_posterior(
    samples    = samples,
    method     = "ensemble",
    query_type = "map",
    units      = units,
    metadata   = list(n_ens = x$n_ens, n_obs = x$n_obs,
                       gain_row_norm = x$gain_row_norm,
                       innovation    = x$innovation,
                       source = "temporal_kalman_update")
  )
}
