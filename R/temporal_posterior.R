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
#       temporal_convlstm_mcdropout_predict() runs M forward passes
#       with dropout kept in train mode, producing M posterior draws.
#       NOTE: temporal_convlstm_fit() takes no dropout argument and
#       the stack it builds contains no dropout layers, so unless the
#       caller inserts one the M draws are bit-identical. See the
#       examples on temporal_convlstm_mcdropout_predict().
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
#' @examples
#' # Pillar 3 on a 12-month synthetic Cerrado SOC cube: 8 x 8 cells,
#' # two channels (standardised elevation, monthly precipitation) and
#' # SOC in g/kg. Months 1-9 are the training window.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'
#'   cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L,
#'                                   seed = 42L)
#'   tt   <- temporal_cube_to_tensor(cube)
#'   past_seq <- tt$sequence[, 1:9, , , , drop = FALSE]  # (1, 9, 2, 8, 8)
#'   past_tgt <- tt$target[,   1:9, , , drop = FALSE]    # (1, 9, 8, 8)
#'
#'   # return_sequence = TRUE is not the default here, but it is what
#'   # temporal_convlstm_ensemble_rollout() insists on further down.
#'   ens <- temporal_convlstm_ensemble_fit(
#'     sequence = past_seq, target = past_tgt,
#'     hidden_dims = 4L, return_sequence = TRUE,
#'     epochs = 20L, lr = 0.05, K_ens = 3L, base_seed = 7L)
#'   print(ens)
#'
#'   # base_seed is the ONLY source of diversity: no bagging, no
#'   # augmentation, every member sees the identical cube and differs
#'   # purely by initialisation. At 20 epochs that has not settled --
#'   # the worst member's loss is 2.1x the best member's. K_ens = 3 is
#'   # kept here only for run time; it leaves the across-member sd with
#'   # 2 degrees of freedom, which is why the default is 10.
#'   print(round(ens$final_losses, 4))
#'
#'   # final_loss is MSE in the standardised units of tt$target, so
#'   # quote it against the MSE of predicting the training-window mean.
#'   # Even the worst member beats that trivial model 9x.
#'   print(round(c(worst_member     = max(ens$final_losses),
#'                 predict_the_mean = mean((past_tgt -
#'                                          mean(past_tgt))^2)), 4))
#'
#'   # Rescaled, those are in-sample RMSEs of 1.8-2.6 g/kg on a cube
#'   # whose SOC spans 16.7-52.2 g/kg. In-sample only -- the forecast
#'   # picture is in ?temporal_convlstm_ensemble_rollout.
#'   print(round(sqrt(ens$final_losses) * tt$scaling$soc_sd, 2))
#'   print(round(range(cube$soc), 1))
#'
#'   # loss_histories keeps the full per-member Adam trace.
#'   print(round(ens$loss_histories[[1L]][c(1L, 10L, 20L)], 4))
#'
#'   # Trap: the default return_sequence = FALSE trains happily on a
#'   # (batch, H, W) target, and only the rollout helper complains.
#'   flat <- temporal_convlstm_ensemble_fit(
#'     sequence = past_seq,
#'     target   = array(past_tgt[1L, 9L, , ], dim = c(1L, 8L, 8L)),
#'     hidden_dims = 4L, epochs = 3L, K_ens = 2L, base_seed = 7L)
#'   print(tryCatch(temporal_convlstm_ensemble_rollout(
#'                    flat, past_seq,
#'                    tt$sequence[, 10:12, , , , drop = FALSE]),
#'                  error = function(e) conditionMessage(e)))
#' }
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
#' @examples
#' # Forecast months 10-12 of the synthetic Cerrado SOC cube from an
#' # ensemble trained on months 1-9, then score the across-member
#' # spread as if it were a predictive interval.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'
#'   cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L,
#'                                   seed = 42L)
#'   tt   <- temporal_cube_to_tensor(cube)
#'   past_seq <- tt$sequence[, 1:9,   , , , drop = FALSE]
#'   past_tgt <- tt$target[,   1:9,   , , drop = FALSE]
#'   fut_seq  <- tt$sequence[, 10:12, , , , drop = FALSE]  # known drivers
#'
#'   ens <- temporal_convlstm_ensemble_fit(
#'     sequence = past_seq, target = past_tgt, hidden_dims = 4L,
#'     return_sequence = TRUE, epochs = 20L, lr = 0.05,
#'     K_ens = 3L, base_seed = 7L)
#'
#'   rolls <- temporal_convlstm_ensemble_rollout(
#'     ens, past_sequence = past_seq, future_drivers = fut_seq)
#'   print(dim(rolls))                # (K_ens, T_future, H, W) = 3 3 8 8
#'
#'   # Undo the z-scaling so every number below is in g/kg.
#'   gkg   <- rolls * tt$scaling$soc_sd + tt$scaling$soc_mu
#'   truth <- cube$soc[10:12, , ]
#'
#'   # Spread and error, side by side, per lead time. The nominal-90%
#'   # band is mean +/- 1.645 * across-member sd and `covered` is the
#'   # PICP numerator out of the 64 grid cells.
#'   print(round(t(vapply(1:3, function(h) {
#'     mu <- apply(gkg[, h, , ], c(2, 3), mean)
#'     sm <- apply(gkg[, h, , ], c(2, 3), stats::sd)
#'     y  <- as.numeric(truth[h, , ])
#'     c(spread  = mean(sm),
#'       rmse    = edaphos_rmse(y, as.numeric(mu)),
#'       bias    = edaphos_bias(y, as.numeric(mu)),
#'       picp90  = edaphos_picp(y, as.numeric(mu - 1.645 * sm),
#'                                 as.numeric(mu + 1.645 * sm)),
#'       covered = sum(abs(y - as.numeric(mu)) <= 1.645 * as.numeric(sm)),
#'       persistence_rmse = edaphos_rmse(y, as.numeric(cube$soc[9L, , ])))
#'   }, numeric(6))), 3))
#'
#'   # Two readings. (1) The spread barely doubles across the horizon
#'   # (4.13 -> 8.83 g/kg) while RMSE more than quadruples (3.35 ->
#'   # 15.13), so coverage falls from 0.922 to 0.406. (2) Carrying
#'   # month 9 forward unchanged has RMSE 3.23 g/kg at +3 months
#'   # against this ensemble's 15.13: persistence wins by 4.7x. Treat
#'   # the fit as a harness for the uncertainty API, not as a forecast.
#'
#'   # Why it drifts: the network sees elevation and precipitation, no
#'   # calendar. Months 10-12 are the driest quarter and their drivers
#'   # look like months 1-2, when SOC was 20 g/kg -- so the +3-month
#'   # forecast lands 14.7 g/kg low, back at the month-5/6 level of the
#'   # cube, instead of continuing the 20 -> 43 g/kg accumulation. A
#'   # confounded driver, not a flaw in the ensembling.
#'   print(round(rbind(precip = apply(cube$precip, 1L, mean),
#'                     soc    = apply(cube$soc,    1L, mean)), 1))
#'
#'   mu <- apply(gkg[, 3L, , ], c(2, 3), mean)
#'   sm <- apply(gkg[, 3L, , ], c(2, 3), stats::sd)
#'   y  <- as.numeric(truth[3L, , ])
#'
#'   # At +3 months the error is almost pure bias: residuals scatter by
#'   # 3.57 g/kg about a mean miss of 14.71, and the ensemble spread
#'   # (8.83) is 2.5x that scatter. The members disagree plenty; they
#'   # are simply all wrong in the same direction, because they share
#'   # an architecture and a training window. A deep ensemble measures
#'   # disagreement, never the bias its members hold in common.
#'   b <- edaphos_bias(y, as.numeric(mu))
#'   print(round(c(bias       = b,
#'                 resid_sd   = stats::sd(y - as.numeric(mu)),
#'                 ens_spread = mean(sm)), 2))
#'
#'   # So the interval score refuses the usual repair. Tripling the
#'   # band buys PICP 1.000 and scores WORSE than the honest narrow one
#'   # (87.11 vs 66.90); only recentring pays (29.04) -- and that used
#'   # the truth, so it is a diagnosis, not something you can deploy.
#'   sc <- function(lo, hi) c(
#'     picp = edaphos_picp(y, as.numeric(lo), as.numeric(hi)),
#'     IS   = edaphos_interval_score(y, as.numeric(lo), as.numeric(hi),
#'                                   alpha = 0.10))
#'   print(round(rbind(
#'     as_is      = sc(mu - 1.645 * sm,     mu + 1.645 * sm),
#'     widened_3x = sc(mu - 3 * 1.645 * sm, mu + 3 * 1.645 * sm),
#'     debiased   = sc(mu + b - 1.645 * sm, mu + b + 1.645 * sm)), 3))
#'
#'   # The same rollout in the unified container. The adapter re-runs
#'   # the rollout internally and keeps the LAST future step by default
#'   # (time_step = 3 here), which is the worst-calibrated one.
#'   post <- as_edaphos_posterior(ens, past_sequence = past_seq,
#'                                future_drivers = fut_seq,
#'                                units = "SOC z-units")
#'   print(post)
#'   print(unlist(post$metadata))
#' }
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
#' the predictive posterior (Gal and Ghahramani 2016).
#'
#' The module has to contain dropout layers for the sample to be
#' non-degenerate. [`temporal_convlstm_fit()`] takes no dropout
#' argument and the stack it builds -- ConvLSTM cells plus a 1x1
#' convolutional head -- contains none, so on an unmodified fit every
#' draw is bit-identical and the posterior sd is exactly zero, not
#' merely small. Splicing an `nn_dropout2d` in front of the head, as
#' the example does, is the shortest route to a real MC-dropout
#' posterior; it samples the head's weights only and stays blind to
#' the frozen ConvLSTM backbone beneath it.
#'
#' @param object An `edaphos_temporal_convlstm` whose underlying
#'   `nn_module` contains `nn_dropout2d` layers. A fit taken straight
#'   from [`temporal_convlstm_fit()`] is accepted, but returns
#'   `n_draws` identical copies of the deterministic forward pass.
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'
#'   cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L,
#'                                   seed = 42L)
#'   tt   <- temporal_cube_to_tensor(cube)
#'   past_seq <- tt$sequence[, 1:9, , , , drop = FALSE]
#'   past_tgt <- tt$target[,   1:9, , , drop = FALSE]
#'   fit <- temporal_convlstm_fit(past_seq, past_tgt, hidden_dims = 4L,
#'                                return_sequence = TRUE, epochs = 20L,
#'                                lr = 0.05, seed = 7L)
#'
#'   # First trap: this fit contains no dropout layer, so MC-dropout on
#'   # it is a no-op. The 20 draws are bit-identical -- the posterior sd
#'   # is 0, not 1e-6. A silent zero-width posterior is exactly the
#'   # failure mode you must check for before trusting any spread.
#'   draws <- temporal_convlstm_mcdropout_predict(
#'     fit, sequence = tt$sequence, n_draws = 20L, seed = 11L,
#'     return_sequence = TRUE)
#'   print(dim(draws))                       # (n_draws, batch, T, H, W)
#'   print(max(apply(draws, 2:5, stats::sd)))          # 0
#'   print(grep("dropout", names(fit$model$modules), value = TRUE,
#'              ignore.case = TRUE))                   # character(0)
#'
#'   # Put a dropout layer in front of the 1x1 head to get a real
#'   # posterior. Second trap: torch modules are references, so `fit2`
#'   # and `fit` share one module and this edits both.
#'   fit2 <- fit
#'   fit2$model$head <- torch::nn_sequential(torch::nn_dropout2d(p = 0.2),
#'                                           fit2$model$head)
#'   print(any(names(fit$model$modules) == "head.1"))  # TRUE: fit too
#'
#'   draws <- temporal_convlstm_mcdropout_predict(
#'     fit2, sequence = tt$sequence, n_draws = 40L, seed = 11L,
#'     return_sequence = TRUE)
#'   mu_z <- apply(draws, 2:5, mean)
#'   sd_z <- apply(draws, 2:5, stats::sd)
#'
#'   # Score that one posterior on the last training month and on month
#'   # 12, three months past the end of the training window.
#'   score <- function(m) {
#'     mu <- as.numeric(mu_z[1L, m, , ]) * tt$scaling$soc_sd +
#'           tt$scaling$soc_mu
#'     s  <- as.numeric(sd_z[1L, m, , ]) * tt$scaling$soc_sd
#'     y  <- as.numeric(cube$soc[m, , ])
#'     c(spread = mean(s),
#'       rmse   = edaphos_rmse(y, mu),
#'       bias   = edaphos_bias(y, mu),
#'       picp90 = edaphos_picp(y, mu - 1.645 * s, mu + 1.645 * s),
#'       IS     = edaphos_interval_score(y, mu - 1.645 * s,
#'                                       mu + 1.645 * s, alpha = 0.10))
#'   }
#'   print(round(rbind(month_09_in_sample = score(9L),
#'                     month_12_forecast  = score(12L)), 3))
#'
#'   # The spread hardly moves between the two rows (4.72 -> 4.43 g/kg)
#'   # while RMSE nearly quadruples (2.17 -> 8.46) and the bias goes
#'   # from 0.09 to 8.01 g/kg, dropping coverage 1.000 -> 0.438.
#'   # MC-dropout samples the head's weights, not the lead time: it
#'   # cannot see the frozen backbone's extrapolation error, the same
#'   # blind spot a deep ensemble has -- see
#'   # ?temporal_convlstm_ensemble_rollout.
#'
#'   # And read the in-sample row sceptically too: PICP 1.000 comes
#'   # from a band 2 * 1.645 * 4.72 = 15.5 g/kg wide on a variable
#'   # whose whole-cube sd is 9.58 g/kg. The interval score charges for
#'   # that width -- 15.52 there is all width and no miss penalty.
#'   print(round(stats::sd(cube$soc), 2))
#' }
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
