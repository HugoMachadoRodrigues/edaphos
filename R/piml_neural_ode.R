# Neural Ordinary Differential Equation for soil depth profiles.
#
# Replaces the parametric lambda(z)*exp(-mu*z) in piml_profile with a
# small MLP f_theta(z, y) -> dy/dz, trained by back-propagating through
# a fixed-step RK4 integrator implemented on top of torch ops.
#
# Requires the `torch` Suggests dependency. All torch calls are guarded
# by `.piml_require_torch()` so the package loads cleanly on systems
# without libtorch.

.piml_require_torch <- function() {
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("Install the `torch` package (and run torch::install_torch() ",
         "once) to use piml_neural_ode_*().", call. = FALSE)
  }
  invisible(TRUE)
}

.piml_rk4_step <- function(f, z, y, h) {
  k1 <- f(z,            y)
  k2 <- f(z + 0.5 * h,  y + 0.5 * h * k1)
  k3 <- f(z + 0.5 * h,  y + 0.5 * h * k2)
  k4 <- f(z +       h,  y +       h * k3)
  y + (h / 6) * (k1 + 2 * k2 + 2 * k3 + k4)
}

.piml_mlp <- function(hidden, input_dim = 2L) {
  layers <- list()
  prev <- input_dim
  for (h in hidden) {
    layers[[length(layers) + 1L]] <- torch::nn_linear(prev, h)
    layers[[length(layers) + 1L]] <- torch::nn_tanh()
    prev <- h
  }
  layers[[length(layers) + 1L]] <- torch::nn_linear(prev, 1L)
  do.call(torch::nn_sequential, layers)
}

# Build the nn_module lazily so the package loads without torch installed.
.piml_build_module <- function() {
  torch::nn_module(
    "NeuralProfileODE",
    initialize = function(hidden, y0_init, y0_learn) {
      self$mlp <- .piml_mlp(hidden, input_dim = 2L)
      if (y0_learn) {
        self$y0 <- torch::nn_parameter(
          torch::torch_tensor(c(as.numeric(y0_init)))
        )
      } else {
        self$register_buffer(
          "y0",
          torch::torch_tensor(c(as.numeric(y0_init)))
        )
      }
    },
    dydz = function(z, y) {
      input <- torch::torch_cat(list(z, y), dim = 1L)$reshape(c(1L, 2L))
      self$mlp(input)$reshape(c(1L))
    },
    forward = function(depths_num, n_steps_per_depth = 4L) {
      ord <- order(depths_num)
      sorted <- depths_num[ord]
      y <- self$y0$clone()
      z <- torch::torch_tensor(c(0.0))
      preds <- vector("list", length(sorted))
      prev <- 0
      for (i in seq_along(sorted)) {
        target <- as.numeric(sorted[i])
        remaining <- target - prev
        if (remaining <= 1e-9) {
          preds[[i]] <- y
        } else {
          steps <- n_steps_per_depth
          h <- remaining / steps
          h_t <- torch::torch_tensor(c(h))
          for (k in seq_len(steps)) {
            y <- .piml_rk4_step(self$dydz, z, y, h_t)
            z <- z + h
          }
          preds[[i]] <- y
        }
        prev <- target
      }
      out <- torch::torch_stack(preds)$reshape(c(length(preds)))
      # Undo the sort.
      inv <- order(ord)
      out[inv]
    }
  )
}

#' Fit a Neural ODE depth profile (Pillar 2, deep variant)
#'
#' Models the vector field \eqn{dy/dz = f_\theta(z, y)} where
#' \eqn{f_\theta} is a small MLP (default `2 x 16` + tanh). The forward
#' model is a fixed-step RK4 integrator that runs end-to-end on `torch`,
#' so training drives the MLP weights — and, optionally, the surface
#' value \eqn{y_0} — by back-propagating through the whole integration
#' (a proper Neural ODE, Chen et al. 2018).
#'
#' Compared to [piml_profile_fit()], the Neural ODE variant can capture
#' **non-monotone** profiles (E horizons below an A, bulge in a Bt) that
#' the parametric exponential-asymptote ODE cannot represent.
#'
#' @param depths Numeric vector of horizon mid-depths.
#' @param values Numeric vector of observed values, same length.
#' @param y_surface Optional numeric; if supplied, $y_0$ is fixed (no
#'   learnable parameter) — used when you trust a specific 0 cm reading.
#' @param hidden Integer vector with MLP hidden-layer widths.
#' @param n_steps Integer, RK4 steps between successive observation
#'   depths. Higher = more accurate, slower.
#' @param epochs,lr Integer and numeric — training hyperparameters for
#'   Adam.
#' @param seed Optional integer — forwarded to `torch::torch_manual_seed`
#'   for reproducibility.
#' @param verbose Logical; print training loss every 50 epochs.
#'
#' @return A `edaphos_piml_neural_ode` object (S3).
#' @export
piml_neural_ode_fit <- function(depths, values, y_surface = NULL,
                                hidden = c(16L, 16L),
                                n_steps = 4L,
                                epochs = 500L, lr = 0.01,
                                seed = NULL, verbose = FALSE) {
  .piml_require_torch()
  stopifnot(length(depths) == length(values),
            length(depths) >= 2L,
            all(is.finite(depths)), all(is.finite(values)),
            all(depths >= 0))
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  z_scale <- max(depths, 1)
  y_center <- mean(values)
  y_scale <- max(stats::sd(values), 1e-3)
  depths_n <- as.numeric(depths) / z_scale
  values_n <- (as.numeric(values) - y_center) / y_scale

  y0_init <- if (is.null(y_surface))
    values_n[which.min(depths)]
  else
    (y_surface - y_center) / y_scale

  ModuleCtor <- .piml_build_module()
  model <- ModuleCtor(
    hidden   = as.integer(hidden),
    y0_init  = y0_init,
    y0_learn = is.null(y_surface)
  )

  y_obs <- torch::torch_tensor(values_n)
  optimizer <- torch::optim_adam(model$parameters, lr = lr)

  loss_history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    optimizer$zero_grad()
    pred  <- model(depths_n, n_steps_per_depth = as.integer(n_steps))
    loss  <- torch::nnf_mse_loss(pred, y_obs)
    loss$backward()
    optimizer$step()
    loss_history[ep] <- as.numeric(loss$item())
    if (verbose && (ep %% 50L == 0L || ep == 1L || ep == epochs)) {
      message(sprintf("[ep %4d / %d] loss = %.6f",
                      ep, epochs, loss_history[ep]))
    }
  }

  fitted_n <- torch::with_no_grad({
    as.numeric(model(depths_n, n_steps_per_depth = as.integer(n_steps)))
  })
  fitted <- fitted_n * y_scale + y_center
  structure(
    list(
      model        = model,
      hidden       = hidden,
      n_steps      = as.integer(n_steps),
      y_surface    = y_surface,
      z_scale      = z_scale,
      y_center     = y_center,
      y_scale      = y_scale,
      depths       = depths,
      values       = values,
      fitted       = fitted,
      loss_history = loss_history,
      rmse         = .rmse(values, fitted)
    ),
    class = "edaphos_piml_neural_ode"
  )
}

#' Predict a depth profile from a fitted Neural ODE
#'
#' @param object A `edaphos_piml_neural_ode`.
#' @param newdepths Numeric vector of depths at which to evaluate the
#'   profile.
#' @param ... Unused.
#' @return Numeric vector, one value per element of `newdepths`.
#' @export
piml_neural_ode_predict <- function(object, newdepths, ...) {
  .piml_require_torch()
  stopifnot(inherits(object, "edaphos_piml_neural_ode"),
            is.numeric(newdepths), all(newdepths >= 0))
  depths_n <- as.numeric(newdepths) / object$z_scale
  pred_n <- torch::with_no_grad({
    as.numeric(object$model(depths_n,
                             n_steps_per_depth = object$n_steps))
  })
  pred_n * object$y_scale + object$y_center
}

#' @export
predict.edaphos_piml_neural_ode <- function(object, newdepths, ...) {
  piml_neural_ode_predict(object, newdepths, ...)
}

#' @export
print.edaphos_piml_neural_ode <- function(x, ...) {
  cat("<edaphos_piml_neural_ode>\n")
  cat("  dy/dz = f_theta(z, y), MLP hidden =",
      paste(x$hidden, collapse = " -> "), "\n")
  cat(sprintf("  n obs = %d  rmse = %.4g  final loss = %.4g\n",
              length(x$depths), x$rmse,
              x$loss_history[length(x$loss_history)]))
  invisible(x)
}
