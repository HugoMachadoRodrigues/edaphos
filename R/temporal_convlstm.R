# Pillar 3 — 4D Pedometry.
#
# Stacked ConvLSTM (Shi et al. 2015) with both sequence-to-one and
# sequence-to-sequence training, plus a one-shot rollout wrapper that
# reapplies the trained model to unseen driver windows (the canonical
# forecasting pattern when future drivers are known, e.g. from weather
# forecasts).
#
# All torch code is guarded by `requireNamespace("torch")` so the
# package loads cleanly without libtorch.

.temporal_require_torch <- function() {
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("Install the `torch` package to use temporal_convlstm_*().",
         call. = FALSE)
  }
  invisible(TRUE)
}

.temporal_build_cell <- function() {
  torch::nn_module(
    "ConvLSTMCell",
    initialize = function(input_dim, hidden_dim, kernel_size = 3L) {
      self$input_dim  <- as.integer(input_dim)
      self$hidden_dim <- as.integer(hidden_dim)
      padding <- (as.integer(kernel_size) - 1L) %/% 2L
      self$conv <- torch::nn_conv2d(
        in_channels  = self$input_dim + self$hidden_dim,
        out_channels = 4L * self$hidden_dim,
        kernel_size  = as.integer(kernel_size),
        padding      = padding
      )
    },
    forward = function(input, state) {
      h_prev <- state[[1L]]; c_prev <- state[[2L]]
      combined <- torch::torch_cat(list(input, h_prev), dim = 2L)
      gates <- self$conv(combined)
      chunks <- torch::torch_split(gates, self$hidden_dim, dim = 2L)
      i <- torch::torch_sigmoid(chunks[[1L]])
      f <- torch::torch_sigmoid(chunks[[2L]])
      g <- torch::torch_tanh(chunks[[3L]])
      o <- torch::torch_sigmoid(chunks[[4L]])
      c_next <- f * c_prev + i * g
      h_next <- o * torch::torch_tanh(c_next)
      list(h_next, c_next)
    },
    init_state = function(batch, height, width) {
      zeros <- torch::torch_zeros(
        c(as.integer(batch), self$hidden_dim,
          as.integer(height), as.integer(width))
      )
      list(zeros, zeros$clone())
    }
  )
}

#' Build a standalone ConvLSTM cell (Pillar 3 primitive)
#'
#' @param input_dim,hidden_dim,kernel_size See [temporal_convlstm_fit()].
#' @return An `nn_module` cell with methods `forward(input, state)` and
#'   `init_state(batch, height, width)`.
#' @export
temporal_convlstm_cell <- function(input_dim, hidden_dim, kernel_size = 3L) {
  .temporal_require_torch()
  CellCtor <- .temporal_build_cell()
  CellCtor(input_dim = input_dim, hidden_dim = hidden_dim,
           kernel_size = kernel_size)
}

.temporal_build_stack <- function() {
  torch::nn_module(
    "ConvLSTMStack",
    initialize = function(input_dim, hidden_dims, kernel_size = 3L,
                          out_dim = 1L) {
      CellCtor <- .temporal_build_cell()
      self$n_layers    <- length(hidden_dims)
      self$hidden_dims <- as.integer(hidden_dims)
      cells <- list()
      prev <- as.integer(input_dim)
      for (i in seq_along(hidden_dims)) {
        cells[[i]] <- CellCtor(prev, as.integer(hidden_dims[i]),
                               as.integer(kernel_size))
        prev <- as.integer(hidden_dims[i])
      }
      self$cells <- torch::nn_module_list(cells)
      self$head  <- torch::nn_conv2d(prev, as.integer(out_dim),
                                     kernel_size = 1L)
    },

    # Run the stack for T_ time steps. Returns either the last-step
    # prediction (seq-to-one) or the per-step sequence of predictions
    # (seq-to-seq), and the full layer states at the end.
    run_sequence = function(sequence, return_sequence = FALSE) {
      dims <- sequence$size()
      batch <- dims[1L]; ts <- dims[2L]
      H <- dims[4L]; W <- dims[5L]
      states <- vector("list", self$n_layers)
      for (i in seq_len(self$n_layers)) {
        states[[i]] <- self$cells[[i]]$init_state(batch, H, W)
      }
      per_step <- if (return_sequence) vector("list", ts) else NULL
      for (t in seq_len(ts)) {
        x_t <- sequence[, t, , , , drop = FALSE]$squeeze(2L)
        for (i in seq_len(self$n_layers)) {
          states[[i]] <- self$cells[[i]](x_t, states[[i]])
          x_t <- states[[i]][[1L]]
        }
        if (return_sequence) {
          per_step[[t]] <- self$head(x_t)$squeeze(2L)
        }
      }
      last <- self$head(x_t)$squeeze(2L)
      list(last = last, per_step = per_step, states = states)
    },

    # Forward: seq-to-one by default, set return_sequence to get every step.
    forward = function(sequence, return_sequence = FALSE) {
      out <- self$run_sequence(sequence, return_sequence = return_sequence)
      if (return_sequence) {
        torch::torch_stack(out$per_step, dim = 2L)   # (B, T, H, W)
      } else {
        out$last                                     # (B, H, W)
      }
    }
  )
}

#' Fit a stacked ConvLSTM on a 4D covariate cube
#'
#' Trains a multi-layer ConvLSTM + 1x1 head on an input tensor shaped
#' `(batch, T, C, H, W)`. Supports two objectives:
#' \itemize{
#'   \item **sequence-to-one** (`return_sequence = FALSE`, default) —
#'     `target` is `(batch, H, W)`, typically the last-month property;
#'   \item **sequence-to-sequence** (`return_sequence = TRUE`) —
#'     `target` is `(batch, T, H, W)`, which is the setup used by
#'     [temporal_convlstm_rollout()] to forecast a whole horizon when
#'     future driver channels are known (e.g. weather forecasts).
#' }
#'
#' @param sequence R array or `torch_tensor` of shape
#'   `(batch, T, C, H, W)`.
#' @param target R array or tensor; shape depends on `return_sequence`.
#' @param hidden_dims Integer vector — one entry per ConvLSTM layer.
#'   Length determines depth. Default `c(4L)` (single-layer).
#' @param kernel_size Integer, spatial kernel size (odd).
#' @param return_sequence Logical; see objectives above.
#' @param epochs,lr Adam hyperparameters.
#' @param physics_lambda Numeric `>= 0`; weight of the physics-informed
#'   mass-balance regulariser. When `> 0` (and `return_sequence = TRUE`),
#'   the loss becomes
#'   \deqn{\mathrm{MSE}(\hat y, y) + \lambda_{\text{phys}}\,
#'          \mathrm{MSE}\!\left(\Delta\hat y_t,\,
#'          k_{\text{in}} P_t - k_{\text{out}} \hat y_t P_t / \bar P\right),}
#'   i.e. the predicted per-step change \eqn{\Delta\hat y_t =
#'   \hat y_{t+1} - \hat y_t} is pushed towards the mass-balance increment
#'   implied by the driver channel. This is the Pillar 2 × Pillar 3 fusion
#'   — a Physics-Informed ConvLSTM.
#' @param physics_k_in,physics_k_out Numeric rate coefficients of the
#'   mass-balance prior in the *normalised* units the model sees at
#'   training time. Setting both to zero collapses the physics loss to
#'   a pure temporal smoothness penalty.
#' @param physics_driver_channel Integer, index (1-based) of the input
#'   channel that carries the driver \eqn{P_t} (e.g. precipitation).
#' @param seed Optional integer for reproducibility.
#' @param verbose Logical; print loss every 10 epochs.
#'
#' @return A `edaphos_temporal_convlstm` object (list) with the trained
#'   model, config, and loss history.
#' @export
temporal_convlstm_fit <- function(sequence, target,
                                  hidden_dims = 4L, kernel_size = 3L,
                                  return_sequence = FALSE,
                                  epochs = 80L, lr = 0.01,
                                  physics_lambda = 0,
                                  physics_k_in = 0.03,
                                  physics_k_out = 0.015,
                                  physics_driver_channel = 2L,
                                  seed = NULL, verbose = FALSE) {
  .temporal_require_torch()
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  if (!inherits(sequence, "torch_tensor")) {
    sequence <- torch::torch_tensor(sequence)$to(dtype = torch::torch_float())
  }
  if (!inherits(target, "torch_tensor")) {
    target <- torch::torch_tensor(target)$to(dtype = torch::torch_float())
  }
  stopifnot(sequence$dim() == 5L)
  if (return_sequence) {
    stopifnot(target$dim() == 4L)
  } else {
    stopifnot(target$dim() == 3L)
  }

  input_dim <- sequence$size(3L)
  StackCtor <- .temporal_build_stack()
  model <- StackCtor(
    input_dim   = input_dim,
    hidden_dims = as.integer(hidden_dims),
    kernel_size = as.integer(kernel_size),
    out_dim     = 1L
  )
  optimizer <- torch::optim_adam(model$parameters, lr = lr)

  physics_active <- isTRUE(physics_lambda > 0) && return_sequence
  if (physics_active) {
    # Pre-extract the driver channel once (its values do not depend on
    # the model, so we can precompute the long-term mean).
    driver_full <- sequence[, , as.integer(physics_driver_channel), , ]
    p_bar <- driver_full$mean()
  }

  loss_history     <- numeric(epochs)
  loss_fit_history <- numeric(epochs)
  loss_phys_history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    optimizer$zero_grad()
    pred <- model(sequence, return_sequence = return_sequence)
    loss_fit <- torch::nnf_mse_loss(pred, target)
    if (physics_active) {
      # pred is (B, T, H, W)
      T_   <- pred$size(2L)
      yt   <- pred[, 1L:(T_ - 1L), , ]
      yt1  <- pred[, 2L:T_,        , ]
      dpred <- yt1 - yt
      P_t   <- driver_full[, 1L:(T_ - 1L), , ]
      expected <- physics_k_in * P_t -
                  physics_k_out * yt * P_t / (p_bar + 1e-6)
      loss_phys <- torch::nnf_mse_loss(dpred, expected)
      loss <- loss_fit + physics_lambda * loss_phys
      loss_phys_history[ep] <- as.numeric(loss_phys$item())
    } else {
      loss <- loss_fit
    }
    loss$backward()
    optimizer$step()
    loss_history[ep]     <- as.numeric(loss$item())
    loss_fit_history[ep] <- as.numeric(loss_fit$item())
    if (verbose && (ep %% 10L == 0L || ep == 1L || ep == epochs)) {
      if (physics_active) {
        message(sprintf(
          "[ep %3d/%d] total=%.5f  fit=%.5f  phys=%.5f",
          ep, epochs, loss_history[ep],
          loss_fit_history[ep], loss_phys_history[ep]))
      } else {
        message(sprintf("[ep %3d/%d] loss = %.6f",
                        ep, epochs, loss_history[ep]))
      }
    }
  }

  structure(
    list(
      model              = model,
      input_dim          = input_dim,
      hidden_dims        = as.integer(hidden_dims),
      kernel_size        = as.integer(kernel_size),
      return_sequence    = return_sequence,
      physics_lambda     = physics_lambda,
      physics_k_in       = physics_k_in,
      physics_k_out      = physics_k_out,
      physics_driver_channel = as.integer(physics_driver_channel),
      loss_history       = loss_history,
      loss_fit_history   = loss_fit_history,
      loss_phys_history  = loss_phys_history,
      final_loss         = loss_history[epochs]
    ),
    class = "edaphos_temporal_convlstm"
  )
}

#' Predict with a fitted stacked ConvLSTM
#'
#' @param object A `edaphos_temporal_convlstm`.
#' @param sequence Array / `torch_tensor` of shape `(batch, T, C, H, W)`.
#' @param return_sequence Logical override; defaults to the value used
#'   at training time.
#' @param ... Unused.
#' @return An R array. Shape is `(batch, T, H, W)` when
#'   `return_sequence = TRUE`, otherwise `(batch, H, W)`.
#' @export
temporal_convlstm_predict <- function(object, sequence,
                                      return_sequence = NULL, ...) {
  .temporal_require_torch()
  stopifnot(inherits(object, "edaphos_temporal_convlstm"))
  if (!inherits(sequence, "torch_tensor")) {
    sequence <- torch::torch_tensor(sequence)$to(dtype = torch::torch_float())
  }
  if (is.null(return_sequence)) return_sequence <- object$return_sequence
  pred <- torch::with_no_grad({
    as.array(object$model(sequence,
                          return_sequence = return_sequence)$cpu())
  })
  pred
}

#' Multi-step rollout forecast
#'
#' When future driver channels are known (e.g. climate forecasts,
#' calendar-based covariates, planned irrigation), a ConvLSTM trained
#' with `return_sequence = TRUE` can simply be re-applied to a longer
#' sequence covering **past + future** time steps — the hidden state
#' propagates the soil memory, and every step gets its own prediction.
#' This function automates that call and returns only the future part
#' of the prediction.
#'
#' @param object A `edaphos_temporal_convlstm` trained with
#'   `return_sequence = TRUE`.
#' @param past_sequence Array `(batch, T_past, C, H, W)` — the observed
#'   window used for state warm-up.
#' @param future_drivers Array `(batch, T_future, C, H, W)` with the
#'   same channel layout as `past_sequence`.
#' @return Array `(batch, T_future, H, W)` with per-step predictions.
#' @export
temporal_convlstm_rollout <- function(object, past_sequence, future_drivers) {
  .temporal_require_torch()
  stopifnot(inherits(object, "edaphos_temporal_convlstm"),
            isTRUE(object$return_sequence))
  if (!inherits(past_sequence, "torch_tensor")) {
    past_sequence <- torch::torch_tensor(past_sequence)$to(
      dtype = torch::torch_float())
  }
  if (!inherits(future_drivers, "torch_tensor")) {
    future_drivers <- torch::torch_tensor(future_drivers)$to(
      dtype = torch::torch_float())
  }
  full <- torch::torch_cat(list(past_sequence, future_drivers), dim = 2L)
  T_past   <- past_sequence$size(2L)
  T_future <- future_drivers$size(2L)
  pred_all <- torch::with_no_grad({
    object$model(full, return_sequence = TRUE)
  })
  # Keep only the future segment.
  as.array(pred_all[, (T_past + 1L):(T_past + T_future), , ]$cpu())
}

#' @export
predict.edaphos_temporal_convlstm <- function(object, sequence,
                                               return_sequence = NULL, ...) {
  temporal_convlstm_predict(object, sequence,
                            return_sequence = return_sequence, ...)
}

#' @export
print.edaphos_temporal_convlstm <- function(x, ...) {
  cat("<edaphos_temporal_convlstm>\n")
  cat(sprintf("  input_dim = %d   hidden = [%s]   kernel = %d\n",
              x$input_dim,
              paste(x$hidden_dims, collapse = ", "),
              x$kernel_size))
  cat(sprintf("  return_sequence = %s   epochs = %d   final loss = %.4g\n",
              x$return_sequence, length(x$loss_history),
              x$final_loss))
  invisible(x)
}
