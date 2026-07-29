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
#' @examples
#' # lantern is a separate binary download, so requireNamespace() alone
#' # is not enough -- torch_is_installed() is the half that matters.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   torch::torch_manual_seed(1)
#'   cell <- temporal_convlstm_cell(input_dim = 2, hidden_dim = 3)
#'
#'   # All four gates come out of ONE convolution: out_channels is
#'   # 4 * hidden_dim and in_channels is input_dim + hidden_dim,
#'   # because the input and the previous h are concatenated first.
#'   print(dim(cell$conv$weight))          # 12 5 3 3
#'
#'   # init_state() returns (h, c) -- both zeros, both hidden_dim
#'   # channels. Height and width are yours to supply; the cell is
#'   # fully convolutional and has no built-in grid size.
#'   state <- cell$init_state(batch = 1, height = 8, width = 8)
#'   print(vapply(state, function(s) paste(dim(s), collapse = " x "), ""))
#'   # "1 x 3 x 8 x 8" "1 x 3 x 8 x 8"
#'
#'   cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
#'   tt   <- temporal_cube_to_tensor(cube)
#'   x1 <- torch::torch_tensor(
#'     tt$sequence[, 1, , , , drop = FALSE])$squeeze(2)
#'   print(x1$shape)                       # 1 2 8 8 = (batch, C, H, W)
#'
#'   state <- cell(x1, state)
#'   # The cell emits hidden_dim feature channels, NOT a prediction.
#'   # The 1x1 head that turns them into one soil property lives in
#'   # temporal_convlstm_fit()'s stack, not here.
#'   print(state[[1]]$shape)               # 1 3 8 8
#'
#'   # h = o * tanh(c) with o in (0, 1), so |h| can never exceed
#'   # |tanh(c)|. Read c as the retained memory and h as the part of
#'   # it the next layer is allowed to see.
#'   print(round(c(h_absmax = as.numeric(state[[1]]$abs()$max()$item()),
#'                 c_absmax = as.numeric(state[[2]]$abs()$max()$item())), 4))
#'   # h_absmax c_absmax
#'   #   0.1323   0.2638
#'
#'   # Trap: padding is floor((kernel_size - 1) / 2), which preserves
#'   # H and W only for ODD kernels. kernel_size = 2 gives padding 0,
#'   # so the gates come back 7 x 7 while c_prev is still 8 x 8 and
#'   # the cell dies on f * c_prev. There is no check for this.
#'   torch::torch_manual_seed(1)
#'   even <- temporal_convlstm_cell(2, 3, kernel_size = 2)
#'   print(tryCatch(even(x1, even$init_state(1, 8, 8)),
#'                  error = function(e) trimws(
#'                    sub("Exception raised.*", "", conditionMessage(e)))))
#'   # "The size of tensor a (7) must match the size of tensor b (8) at
#'   #  non-singleton dimension 3"
#' }
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
#'   tt   <- temporal_cube_to_tensor(cube)
#'
#'   # Sequence-to-one: six months of (elev, precip) -> the month-6 SOC
#'   # map. `target` must keep its batch axis, so 3-D (1, H, W). The
#'   # 2-D map that tt$target[1, 6, , ] returns is rejected by
#'   # stopifnot(target$dim() == 3L).
#'   y6  <- array(tt$target[1, 6, , ], dim = c(1, 8, 8))
#'   fit <- temporal_convlstm_fit(tt$sequence, y6, hidden_dims = 4L,
#'                                epochs = 150L, lr = 0.05, seed = 1L)
#'   print(fit)
#'
#'   # A loss number alone means nothing. The reference that makes it
#'   # readable is the constant map: mean(y6) predicted everywhere.
#'   baseline <- mean((y6 - mean(y6))^2)
#'   print(round(c(final = fit$final_loss, baseline = baseline,
#'                 ratio = fit$final_loss / baseline), 4))
#'   #   final baseline    ratio
#'   #  0.0091   0.5382   0.0169
#'
#'   # Adam at lr = 0.05 is not monotone: 7 of the 149 steps go uphill,
#'   # so never read final_loss as "the best loss reached".
#'   print(sum(diff(fit$loss_history) > 0))          # 7
#'
#'   # And keep the ratio in proportion -- this fits 64 pixels with
#'   # this many parameters and no held-out month, so 0.0169 measures
#'   # capacity, not skill. temporal_convlstm_rollout() is where the
#'   # same model has to face months it never saw.
#'   print(sum(vapply(fit$model$parameters,
#'                    function(p) prod(dim(p)), 0)))  # 885
#'
#'   # Trap 1: the physics regulariser is silently inert unless
#'   # return_sequence = TRUE. physics_lambda is stored on the object
#'   # either way, so loss_phys_history is the only proof it ever ran.
#'   off <- temporal_convlstm_fit(tt$sequence, y6, epochs = 20L, lr = 0.05,
#'                                seed = 1L, physics_lambda = 10)
#'   print(c(lambda = off$physics_lambda,
#'           phys_loss = max(off$loss_phys_history)))
#'   #    lambda phys_loss
#'   #        10         0
#'
#'   # Trap 2: when it IS active, the mass-balance term divides by the
#'   # mean of the driver channel -- and temporal_cube_to_tensor() hands
#'   # over a z-scored driver whose mean is zero to machine precision.
#'   # The 1e-6 guard turns that into a division by 1e-6.
#'   print(mean(tt$sequence[1, , 2, , ]))            # 1.225871e-16
#'
#'   on <- temporal_convlstm_fit(tt$sequence, tt$target, hidden_dims = 4L,
#'                               return_sequence = TRUE, epochs = 5L,
#'                               lr = 0.05, seed = 1L, physics_lambda = 1)
#'   print(signif(c(fit  = on$loss_fit_history[1],
#'                  phys = on$loss_phys_history[1],
#'                  ratio = on$loss_phys_history[1] /
#'                          on$loss_fit_history[1]), 3))
#'   #      fit     phys    ratio
#'   # 1.07e+00 2.76e+07 2.58e+07
#'
#'   # So the "prior" arrives ~2.6e7 times heavier than the fit term it
#'   # is meant to regularise, and training optimises the regulariser.
#'   # physics_k_in / physics_k_out default to 0.03 / 0.015, which are
#'   # the RAW g/kg-per-mm rates of temporal_synth_soc_cube(), not the
#'   # rates of the standardised problem the loss actually sees. Use
#'   # physics_lambda > 0 only with a strictly positive driver channel
#'   # whose mean is far from zero, and rescale both coefficients to
#'   # match those units.
#' }
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
#'   tt   <- temporal_cube_to_tensor(cube)
#'   y6   <- array(tt$target[1, 6, , ], dim = c(1, 8, 8))
#'   fit  <- temporal_convlstm_fit(tt$sequence, y6, hidden_dims = 4L,
#'                                 epochs = 150L, lr = 0.05, seed = 1L)
#'
#'   p1 <- temporal_convlstm_predict(fit, tt$sequence)
#'   print(dim(p1))                          # 1 8 8
#'
#'   # return_sequence is an override, not a retrain: the same 1x1 head
#'   # is simply read at every step instead of only the last one. So
#'   # the last slice of the sequence output is bit-identical to the
#'   # sequence-to-one output -- no second model is involved.
#'   ps <- temporal_convlstm_predict(fit, tt$sequence,
#'                                   return_sequence = TRUE)
#'   print(dim(ps))                          # 1 6 8 8
#'   print(max(abs(ps[1, 6, , ] - p1[1, , ])))   # 0
#'
#'   # The five earlier maps are not free predictions. This model was
#'   # only ever scored on month 6, and the per-step RMSE (z units)
#'   # says so: month 1 is off by nearly two standard deviations.
#'   print(round(vapply(1:6, function(t)
#'     sqrt(mean((ps[1, t, , ] - tt$target[1, t, , ])^2)), 0), 3))
#'   # 1.883 1.727 1.463 1.153 0.703 0.095
#'
#'   # Output is in the z units of tt$scaling, never g/kg. Rescale
#'   # before reporting, and read the error next to the spread of the
#'   # month it is scoring.
#'   sc <- tt$scaling
#'   y6z <- tt$target[1, 6, , ]
#'   print(round(c(
#'     rmse_gkg  = sc$soc_sd * sqrt(mean((p1[1, , ] - y6z)^2)),
#'     sd_month6 = sd(as.vector(cube$soc[6, , ]))), 3))
#'   #  rmse_gkg sd_month6
#'   #     0.410     3.189
#' }
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   cube <- temporal_synth_soc_cube(H = 8, W = 8, T_total = 6, seed = 42)
#'   # ONE call, so the train and forecast windows share a scaling and
#'   # the two error numbers below are comparable at all.
#'   tt <- temporal_cube_to_tensor(cube)
#'   past   <- tt$sequence[, 1:4, , , , drop = FALSE]
#'   past_y <- tt$target[,   1:4, , , drop = FALSE]
#'   fut    <- tt$sequence[, 5:6, , , , drop = FALSE]
#'   fut_y  <- tt$target[,   5:6, , , drop = FALSE]
#'
#'   fit <- temporal_convlstm_fit(past, past_y, hidden_dims = 8L,
#'                                return_sequence = TRUE,
#'                                epochs = 150L, lr = 0.05, seed = 1L)
#'   fc <- temporal_convlstm_rollout(fit, past, fut)
#'   print(dim(fc))                       # 1 2 8 8
#'
#'   # This rollout is NOT autoregressive. The two input channels are
#'   # elevation and precipitation -- SOC is never one of them -- so
#'   # the model cannot see its own predictions and nothing is fed
#'   # back. It is exactly predict() on the concatenated window, then
#'   # sliced to the future part.
#'   print(dim(tt$sequence)[3])           # 2
#'   both <- temporal_convlstm_predict(fit, tt$sequence)
#'   print(max(abs(fc[1, , , ] - both[1, 5:6, , ])))   # 0
#'
#'   # The scoring that matters. A forecast has to beat carrying the
#'   # last observed SOC map forward, so report that baseline beside
#'   # the model, in g/kg, at every horizon.
#'   rmse <- function(a, b) sqrt(mean((a - b)^2))
#'   sd_  <- tt$scaling$soc_sd
#'   print(round(rbind(
#'     convlstm    = sd_ * c(h1 = rmse(fc[1, 1, , ], fut_y[1, 1, , ]),
#'                           h2 = rmse(fc[1, 2, , ], fut_y[1, 2, , ])),
#'     persistence = c(h1 = rmse(cube$soc[4, , ], cube$soc[5, , ]),
#'                     h2 = rmse(cube$soc[4, , ], cube$soc[6, , ]))), 3))
#'   #                h1    h2
#'   # convlstm    1.875 4.635
#'   # persistence 3.094 6.822
#'
#'   # It does beat persistence at both horizons -- and the in-sample
#'   # error still oversells it by a factor of six at h = 1. A fitted
#'   # window and a forecast are two different claims; print them
#'   # together or the first will be mistaken for the second.
#'   ins <- temporal_convlstm_predict(fit, past)
#'   print(round(sd_ * rmse(ins, past_y), 3))          # 0.288
#'
#'   # Training longer widens that gap rather than closing it: the fit
#'   # keeps improving while the forecast decays.
#'   more <- temporal_convlstm_fit(past, past_y, hidden_dims = 8L,
#'                                 return_sequence = TRUE,
#'                                 epochs = 300L, lr = 0.05, seed = 1L)
#'   fc2 <- temporal_convlstm_rollout(more, past, fut)
#'   print(round(c(
#'     in_sample = sd_ * rmse(temporal_convlstm_predict(more, past), past_y),
#'     h1 = sd_ * rmse(fc2[1, 1, , ], fut_y[1, 1, , ]),
#'     h2 = sd_ * rmse(fc2[1, 2, , ], fut_y[1, 2, , ])), 3))
#'   # in_sample        h1        h2
#'   #     0.176     2.451     5.685
#'
#'   # The cause is not compounding feedback -- there is none -- it is
#'   # extrapolation. A third of the forecast window is wetter than
#'   # any month the model trained on, and most of its SOC sits above
#'   # the training range, so the head is asked for values it was
#'   # never shown. Check this BEFORE trusting a rollout.
#'   print(round(c(
#'     drivers_above_train = mean(fut[1, , 2, , ] > max(past[1, , 2, , ])),
#'     target_above_train  = mean(fut_y > max(past_y))), 3))
#'   # drivers_above_train  target_above_train
#'   #               0.328               0.578
#'
#'   # A sequence-to-one model has no per-step head to roll forward,
#'   # and is refused rather than silently reinterpreted.
#'   s2o <- temporal_convlstm_fit(
#'     past, array(past_y[1, 4, , ], dim = c(1, 8, 8)),
#'     epochs = 1L, seed = 1L)
#'   print(tryCatch(temporal_convlstm_rollout(s2o, past, fut),
#'                  error = function(e) conditionMessage(e)))
#'   # "isTRUE(object$return_sequence) is not TRUE"
#' }
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
