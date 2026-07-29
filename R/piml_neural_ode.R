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
#' @examples
#' # torch is a Suggests dependency and libtorch is a separate binary
#' # download, so requireNamespace() alone is not a sufficient guard.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   # An A-E-Bt sequence: SOC falls into a bleached E horizon at 15 cm
#'   # and partly recovers in the clay-illuvial Bt below it. This is the
#'   # non-monotone shape the parametric ODE cannot represent.
#'   depths <- c(5, 15, 30, 50, 80)
#'   soc    <- c(22, 9, 16, 14, 11)
#'
#'   fit <- piml_neural_ode_fit(depths, soc, epochs = 80L, n_steps = 3L,
#'                              seed = 1L)
#'   print(fit)
#'
#'   # Three numbers, never one. At the 80 epochs this example can
#'   # afford, the Neural ODE is BEATEN by the 4-parameter ODE, and both
#'   # beat the mean-only baseline.
#'   par_fit <- piml_profile_fit(depths, soc)
#'   print(round(c(neural     = fit$rmse,                     # 3.5703
#'                 parametric = par_fit$rmse,                 # 2.4084
#'                 mean_only  = sqrt(mean((soc - mean(soc))^2))), 4))
#'
#'   # Read the fitted vectors before trusting that ranking. The
#'   # parametric fit wins on RMSE by degenerating into a step: below
#'   # 15 cm its predictions are constant to 1.63e-06, i.e. it returns
#'   # the mean of the four deep horizons (12.5) and models no shape.
#'   print(round(par_fit$fitted, 4))
#'   print(signif(max(abs(diff(par_fit$fitted[2:5]))), 3))
#'   print(mean(soc[2:5]))
#'
#'   # The Neural ODE is smooth but, at this budget, still monotone ---
#'   # it has not found the E-horizon dip either. Neither fit has earned
#'   # the word "non-monotone" here.
#'   print(round(fit$fitted, 4))
#'   print(all(diff(fit$fitted) < 0))
#'
#'   # Why: the loss is still falling at the last epoch, so this is an
#'   # under-trained fit rather than the model's ceiling (the default is
#'   # epochs = 500L, six times this budget). Quote the trace, never the
#'   # single final number.
#'   print(round(fit$loss_history[c(1, 20, 40, 60, 80)], 5))
#' }
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   depths <- c(5, 15, 30, 50, 80)
#'   soc    <- c(22, 9, 16, 14, 11)
#'   fit <- piml_neural_ode_fit(depths, soc, hidden = c(8L, 8L),
#'                              epochs = 60L, n_steps = 2L, seed = 1L)
#'
#'   # On the training depths this reproduces $fitted to the last bit:
#'   # same RK4 grid, same answer.
#'   print(max(abs(piml_neural_ode_predict(fit, depths) - fit$fitted)))
#'
#'   # TRAP. `n_steps` RK4 steps are taken between CONSECUTIVE requested
#'   # depths, so the integration grid --- and therefore the answer ---
#'   # depends on which OTHER depths you asked for. Same fit, same 200
#'   # cm: 2 steps when asked alone, 40 when asked on a 10 cm grid.
#'   print(round(c(
#'     alone  = piml_neural_ode_predict(fit, 200),
#'     grid10 = tail(piml_neural_ode_predict(fit, seq(0, 200, by = 10)), 1),
#'     grid2  = tail(piml_neural_ode_predict(fit, seq(0, 200, by = 2)), 1)),
#'     4))
#'   # 14.0248 / 13.5046 / 13.5046 --- 0.52 g/kg of pure discretisation,
#'   # and the 10 cm grid has already converged.
#'
#'   # The gap shrinks inside the sampled range: 0.07 g/kg at 80 cm.
#'   # When you need one deep value, refine the request rather than the
#'   # model --- `n_steps` is frozen inside the fit and predict() has no
#'   # argument to raise it.
#'   print(round(c(
#'     alone  = piml_neural_ode_predict(fit, 80),
#'     grid10 = tail(piml_neural_ode_predict(fit, seq(0, 80, by = 10)), 1)),
#'     4))
#'   print(fit$n_steps)
#'
#'   # The ORDER of `newdepths` is irrelevant --- the internal sort is
#'   # undone --- so only the set you request matters.
#'   print(round(c(asc  = piml_neural_ode_predict(fit, c(5, 80)),
#'                 desc = rev(piml_neural_ode_predict(fit, c(80, 5)))), 4))
#'
#'   # z = 0 returns the learned surface value: with y_surface = NULL,
#'   # y0 is a free parameter and lands 1.7 g/kg below the shallowest
#'   # observation. Pass y_surface to pin it to a measured 0 cm value.
#'   print(round(c(z0 = piml_neural_ode_predict(fit, 0),
#'                 shallowest_obs = soc[1]), 4))
#'
#'   # Depths are distances below the surface; negatives are rejected.
#'   print(tryCatch(piml_neural_ode_predict(fit, c(0, -5)),
#'                  error = function(e) conditionMessage(e)))
#' }
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
