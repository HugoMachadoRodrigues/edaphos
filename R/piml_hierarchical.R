# Covariate-conditioned hierarchical Neural ODE for soil depth profiles.
#
# Pillar 2 upgrade: instead of fitting one Neural ODE per pedon, we fit
# ONE network over the whole dataset whose input is (z, y, covariates).
# The surface value y_0 is itself predicted from covariates by a sibling
# MLP. Both nets train jointly, minimising the sum of squared errors
# across every horizon of every pedon.
#
# Paying off the abstraction: once fitted, the model gives a
# *per-location* depth envelope (Y_min, Y_max), which is exactly what
# al_physics_gate_piml_hierarchical() feeds into the Pillar 5 AL loop —
# replacing the global [y_inf, y0] envelope of the single-pedon gate.

.piml_hier_build_module <- function() {
  torch::nn_module(
    "HierarchicalNeuralODE",
    initialize = function(n_covs, hidden = c(32L, 16L),
                          y0_hidden = c(16L)) {
      self$n_covs  <- as.integer(n_covs)
      self$f_mlp   <- .piml_mlp(hidden, input_dim = 2L + self$n_covs)
      # y_0 covariate model
      layers <- list()
      prev <- self$n_covs
      for (h in as.integer(y0_hidden)) {
        layers[[length(layers) + 1L]] <- torch::nn_linear(prev, h)
        layers[[length(layers) + 1L]] <- torch::nn_tanh()
        prev <- h
      }
      layers[[length(layers) + 1L]] <- torch::nn_linear(prev, 1L)
      self$y0_mlp <- do.call(torch::nn_sequential, layers)
    },
    dydz = function(z, y, covs) {
      inp <- torch::torch_cat(list(z, y, covs), dim = 1L)$reshape(
        c(1L, 2L + self$n_covs))
      self$f_mlp(inp)$reshape(c(1L))
    },
    y0 = function(covs) {
      self$y0_mlp(covs$reshape(c(1L, self$n_covs)))$reshape(c(1L))
    },
    forward = function(depths_num, covs, n_steps = 4L) {
      # depths_num: R numeric vector (unnormalised-to-model? here they
      # arrive already normalised by caller). covs: 1-D torch tensor.
      y <- self$y0(covs)
      z <- torch::torch_tensor(c(0.0))
      ord <- order(depths_num)
      sorted <- depths_num[ord]
      preds <- vector("list", length(sorted))
      prev <- 0
      n_steps <- as.integer(n_steps)
      for (i in seq_along(sorted)) {
        target <- sorted[i]
        remaining <- target - prev
        if (remaining <= 1e-9) {
          preds[[i]] <- y
        } else {
          h <- remaining / n_steps
          h_t <- torch::torch_tensor(c(h))
          f_fn <- function(zz, yy) self$dydz(zz, yy, covs)
          for (k in seq_len(n_steps)) {
            y <- .piml_rk4_step(f_fn, z, y, h_t)
            z <- z + h
          }
          preds[[i]] <- y
        }
        prev <- target
      }
      out <- torch::torch_stack(preds)$reshape(c(length(preds)))
      out[order(ord)]
    }
  )
}

#' Hierarchical Neural ODE over multiple pedons (Pillar 2 × Pillar 5)
#'
#' Fits a covariate-conditioned Neural ODE
#' \eqn{dy/dz = f_\theta(z, y, \mathbf{x})}
#' jointly across every pedon in a long-format data frame, plus a
#' sibling MLP \eqn{y_0(\mathbf{x})} that predicts the surface value
#' from covariates. The two nets share the optimiser so training sees
#' all pedons at once.
#'
#' Once fitted, `piml_hierarchical_predict()` returns a profile for **any
#' new location** given its covariates — no horizon measurement required.
#' Pair with [al_physics_gate_piml_hierarchical()] to use that per-location
#' envelope as a rejection filter inside the Active Learning loop.
#'
#' @param pedons Data frame in long form (one row per horizon) with
#'   columns for pedon id, depth, value, and one or more covariates.
#' @param id_col,depth_col,value_col Character, column names.
#' @param covariate_cols Character vector, names of covariate columns.
#'   Assumed constant within a pedon — the first row of each pedon is
#'   used.
#' @param hidden Integer vector, MLP widths for the ODE vector field
#'   \eqn{f_\theta}.
#' @param y0_hidden Integer vector, MLP widths for the surface-value
#'   head \eqn{y_0(\mathbf{x})}.
#' @param n_steps Integer, RK4 steps between successive observation
#'   depths.
#' @param epochs,lr Integer and numeric — Adam hyperparameters.
#' @param seed,verbose As elsewhere in edaphos.
#'
#' @return A `edaphos_piml_hierarchical` object (S3).
#' @export
piml_hierarchical_fit <- function(pedons,
                                  id_col, depth_col, value_col,
                                  covariate_cols,
                                  hidden    = c(32L, 16L),
                                  y0_hidden = c(16L),
                                  n_steps   = 4L,
                                  epochs    = 500L, lr = 0.01,
                                  seed = NULL, verbose = FALSE) {
  .piml_require_torch()
  .assert_covariates(pedons,
                     c(id_col, depth_col, value_col, covariate_cols))
  stopifnot(length(covariate_cols) >= 1L)
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  depth_scale <- max(pedons[[depth_col]], 1)
  value_mu    <- mean(pedons[[value_col]])
  value_sd    <- max(stats::sd(pedons[[value_col]]), 1e-3)
  cov_mu <- colMeans(pedons[, covariate_cols, drop = FALSE])
  cov_sd <- apply(pedons[, covariate_cols, drop = FALSE], 2L, stats::sd)
  cov_sd[!is.finite(cov_sd) | cov_sd == 0] <- 1

  split_data <- split(pedons, pedons[[id_col]])

  ModCtor <- .piml_hier_build_module()
  model <- ModCtor(
    n_covs    = length(covariate_cols),
    hidden    = as.integer(hidden),
    y0_hidden = as.integer(y0_hidden)
  )
  optimizer <- torch::optim_adam(model$parameters, lr = lr)

  loss_history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    optimizer$zero_grad()
    total_loss <- torch::torch_tensor(0.0)
    for (sub in split_data) {
      covs_row  <- as.numeric(sub[1L, covariate_cols])
      covs_norm <- (covs_row - cov_mu) / cov_sd
      covs_t    <- torch::torch_tensor(covs_norm)
      depths_n  <- as.numeric(sub[[depth_col]]) / depth_scale
      values_n  <- (as.numeric(sub[[value_col]]) - value_mu) / value_sd
      y_obs     <- torch::torch_tensor(values_n)
      pred      <- model(depths_n, covs_t, n_steps = n_steps)
      total_loss <- total_loss + torch::nnf_mse_loss(pred, y_obs)
    }
    total_loss <- total_loss / length(split_data)
    total_loss$backward()
    optimizer$step()
    loss_history[ep] <- as.numeric(total_loss$item())
    if (verbose && (ep %% 50L == 0L || ep == 1L || ep == epochs)) {
      message(sprintf("[ep %4d/%d] mean pedon loss = %.6f",
                      ep, epochs, loss_history[ep]))
    }
  }

  structure(
    list(
      model         = model,
      id_col        = id_col,
      depth_col     = depth_col,
      value_col     = value_col,
      covariate_cols = covariate_cols,
      depth_scale   = depth_scale,
      value_mu      = value_mu,
      value_sd      = value_sd,
      cov_mu        = cov_mu,
      cov_sd        = cov_sd,
      n_pedons      = length(split_data),
      n_steps       = as.integer(n_steps),
      loss_history  = loss_history,
      final_loss    = loss_history[epochs]
    ),
    class = "edaphos_piml_hierarchical"
  )
}

#' Predict depth profiles for new locations from covariates
#'
#' @param object A `edaphos_piml_hierarchical`.
#' @param new_covariates Data frame with at least the covariate columns
#'   used at training time (one row per location).
#' @param newdepths Numeric vector of depths.
#' @return Numeric matrix, one row per location in `new_covariates`, one
#'   column per depth in `newdepths`.
#' @export
piml_hierarchical_predict <- function(object, new_covariates, newdepths) {
  .piml_require_torch()
  stopifnot(inherits(object, "edaphos_piml_hierarchical"))
  .assert_covariates(new_covariates, object$covariate_cols)

  n_new       <- nrow(new_covariates)
  depths_n    <- as.numeric(newdepths) / object$depth_scale
  out <- matrix(NA_real_, n_new, length(newdepths))
  cov_mu <- object$cov_mu; cov_sd <- object$cov_sd

  torch::with_no_grad({
    for (i in seq_len(n_new)) {
      covs_row <- as.numeric(new_covariates[i, object$covariate_cols])
      covs_norm <- (covs_row - cov_mu) / cov_sd
      covs_t <- torch::torch_tensor(covs_norm)
      pred_t <- object$model(depths_n, covs_t,
                              n_steps = object$n_steps)
      out[i, ] <- as.numeric(pred_t) * object$value_sd + object$value_mu
    }
  })
  out
}

#' @export
print.edaphos_piml_hierarchical <- function(x, ...) {
  cat("<edaphos_piml_hierarchical>\n")
  cat("  n pedons   :", x$n_pedons, "\n")
  cat("  covariates :", paste(x$covariate_cols, collapse = ", "), "\n")
  cat(sprintf("  final loss : %.4g  (epochs = %d)\n",
              x$final_loss, length(x$loss_history)))
  invisible(x)
}

#' Per-location physics gate backed by a hierarchical PIML fit
#'
#' Upgrades the global-envelope [al_physics_gate_piml()] to a
#' **per-candidate** envelope: each candidate's profile is predicted
#' from its own covariates, giving a tighter physical plausibility
#' window driven by the local pedogenic context.
#'
#' @param hier_fit A `edaphos_piml_hierarchical`.
#' @param candidate_covariate_cols Character vector with the column
#'   names in the candidate table that correspond to the training
#'   covariates (must be the same set, can have different order — the
#'   function reorders them).
#' @param safety_factor Numeric `>= 1`, widening factor on each side.
#' @param envelope_depths Numeric, depths (same units as training) at
#'   which the profile is probed to compute `min` and `max` for each
#'   candidate. Defaults span surface to a deep horizon.
#' @return A function suitable for
#'   `al_query(..., physics_gate = <this>)`.
#' @export
al_physics_gate_piml_hierarchical <- function(
    hier_fit,
    candidate_covariate_cols = hier_fit$covariate_cols,
    safety_factor = 1.2,
    envelope_depths = c(0, 5, 15, 30, 60)) {
  stopifnot(inherits(hier_fit, "edaphos_piml_hierarchical"),
            length(candidate_covariate_cols) ==
              length(hier_fit$covariate_cols))
  function(candidates, predicted_mean, ...) {
    cand_covs <- candidates[, candidate_covariate_cols, drop = FALSE]
    # Ensure column order matches training
    names(cand_covs) <- hier_fit$covariate_cols
    profiles <- piml_hierarchical_predict(
      hier_fit, cand_covs, envelope_depths
    )
    mins <- apply(profiles, 1L, min, na.rm = TRUE)
    maxs <- apply(profiles, 1L, max, na.rm = TRUE)
    slack <- safety_factor - 1
    span  <- pmax(abs(maxs - mins), 1e-9)
    predicted_mean >= mins - slack * span &
      predicted_mean <= maxs + slack * span
  }
}
