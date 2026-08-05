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
#' @section What the `piml_` prefix does and does not mean here:
#' Despite the prefix, this function shares the family name with
#' [piml_profile_fit()] and not its physics. There, the depth function IS the
#' closed-form solution of a stated equation and the four fitted numbers are
#' that equation's symbols. Here, \eqn{f_\theta} is an unconstrained
#' multi-layer perceptron taking \eqn{(z, y, \mathbf{x})} as input channels;
#' the covariates do not enter as \eqn{\lambda_0(\mathbf{x})},
#' \eqn{\mu(\mathbf{x})}, \eqn{y_\infty(\mathbf{x})}, and no conservation law
#' or monotonicity constrains the result.
#'
#' Two consequences follow and neither is hypothetical. The state can cross
#' zero, so a strictly positive property can be predicted negative — see the
#' `clamp` argument of [piml_hierarchical_predict()]. And the fitted
#' parameters are not interpretable as rates or asymptotes, so none of the
#' identifiability results reported for [piml_profile_fit_bayesian()] carry
#' over. Treat this as a flexible depth-profile regressor conditioned on
#' covariates, which is what it is.
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
#' @examples
#' # torch is a Suggests dependency AND the lantern binaries are a
#' # separate download, so both halves of the guard are needed.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   data(br_cerrado)
#'
#'   # Five Cerrado sites.  Each pedon is the noise-free closed-form
#'   # solution of dy/dz = -lambda0 exp(-mu z) (y - y_inf) with
#'   # lambda0 = 0.02 + 0.004 twi, mu = 0.02 and y_inf = 0.30 y0, so
#'   # the covariates genuinely drive the shape of the profile.
#'   sites <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
#'   hz <- c(5, 15, 30, 60)
#'   pedons <- do.call(rbind, lapply(1:5, function(i) {
#'     y0   <- sites$soc[i]
#'     lam0 <- 0.02 + 0.004 * sites$twi[i]
#'     data.frame(pedon = paste0("P", i), depth = hz,
#'                soc = 0.30 * y0 + 0.70 * y0 *
#'                      exp(-(lam0 / 0.02) * (1 - exp(-0.02 * hz))),
#'                twi = sites$twi[i], ndvi = sites$ndvi[i],
#'                map_mm = sites$map_mm[i])
#'   }))
#'
#'   # 20 epochs, not the 500 of the default, to keep this short.
#'   # `seed` seeds torch, so the loss below is reproducible.
#'   fit <- piml_hierarchical_fit(
#'     pedons, "pedon", "depth", "soc",
#'     covariate_cols = c("twi", "ndvi", "map_mm"),
#'     epochs = 20L, lr = 0.05, n_steps = 2L, seed = 1L)
#'   print(fit)
#'
#'   # `final_loss` is an MSE in standardised units, so the number it
#'   # has to beat is the loss of predicting the global mean of `soc`.
#'   vn <- (pedons$soc - mean(pedons$soc)) / sd(pedons$soc)
#'   print(round(c(global_mean = mean(tapply(vn^2, pedons$pedon, mean)),
#'                 epoch_1     = fit$loss_history[1],
#'                 final       = fit$final_loss), 4))
#'
#'   # Read that final loss against the size of what produced it: two
#'   # MLPs, 818 weights, fitted to 20 numbers.  A five-pedon fit is an
#'   # interface demonstration and the loss above measures
#'   # memorisation, not pedology.  ?piml_hierarchical_predict holds
#'   # one pedon out and the model then loses to the depthwise mean of
#'   # the others.
#'   print(c(weights = sum(vapply(fit$model$parameters,
#'                                function(p) p$numel(), 0)),
#'           values  = nrow(pedons)))
#'
#'   # Covariates are taken from the FIRST ROW of each pedon.  Permuting
#'   # them among the deeper horizons -- which leaves the column mean
#'   # and sd, hence the standardisation, untouched -- changes nothing,
#'   # while touching the topsoil row moves the loss.  So a
#'   # horizon-level covariate (clay of each horizon, say) is silently
#'   # truncated to its topsoil value.
#'   deep <- pedons$depth > 5
#'   perm <- pedons; perm$twi[deep] <- rev(perm$twi[deep])
#'   top  <- pedons; top$twi[!deep] <- 99
#'   short_fit <- function(d)
#'     piml_hierarchical_fit(d, "pedon", "depth", "soc",
#'       covariate_cols = c("twi", "ndvi", "map_mm"),
#'       epochs = 2L, lr = 0.05, n_steps = 2L, seed = 1L)$final_loss
#'   print(c(base = short_fit(pedons), deep_permuted = short_fit(perm),
#'           topsoil_changed = short_fit(top)))
#' }
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
      # The observed range of the response. Both the prediction guard and the
      # physics gate need it: without it, each is anchored only to what this
      # network happens to output, so a badly fitted model certifies its own
      # errors as plausible and rejects candidates the data call ordinary.
      value_range   = range(pedons[[value_col]], na.rm = TRUE),
      value_positive = all(pedons[[value_col]] > 0, na.rm = TRUE),
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
#' @param clamp Logical, default `TRUE`. When the training response was
#'   strictly positive and the model returns negative predictions, clamp them
#'   to zero and warn. The model has **no structural positivity** -- the state
#'   is integrated by RK4 over an unconstrained network -- so a negative
#'   prediction means the fit has gone wrong, and the clamp is a guard against
#'   publishing impossible numbers rather than a repair. `FALSE` returns them
#'   unmodified, still with a warning.
#' @return Numeric matrix, one row per location in `new_covariates`, one
#'   column per depth in `newdepths`.
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   data(br_cerrado)
#'   # The five noise-free ODE pedons of ?piml_hierarchical_fit.
#'   sites <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
#'   hz <- c(5, 15, 30, 60)
#'   pedons <- do.call(rbind, lapply(1:5, function(i) {
#'     y0   <- sites$soc[i]
#'     lam0 <- 0.02 + 0.004 * sites$twi[i]
#'     data.frame(pedon = paste0("P", i), depth = hz,
#'                soc = 0.30 * y0 + 0.70 * y0 *
#'                      exp(-(lam0 / 0.02) * (1 - exp(-0.02 * hz))),
#'                twi = sites$twi[i], ndvi = sites$ndvi[i],
#'                map_mm = sites$map_mm[i])
#'   }))
#'
#'   # Hold pedon P4 out.  Its twi, ndvi and map_mm all sit INSIDE the
#'   # range of the four training pedons, so predicting it is
#'   # interpolation in covariate space, not extrapolation.
#'   train <- pedons[pedons$pedon != "P4", ]
#'   held  <- pedons[pedons$pedon == "P4", ]
#'   print(vapply(c("twi", "ndvi", "map_mm"), function(v)
#'     held[1L, v] > min(train[[v]]) && held[1L, v] < max(train[[v]]),
#'     TRUE))
#'   fit <- piml_hierarchical_fit(
#'     train, "pedon", "depth", "soc",
#'     covariate_cols = c("twi", "ndvi", "map_mm"),
#'     epochs = 20L, lr = 0.05, n_steps = 2L, seed = 1L)
#'
#'   # One row of covariates in, one row of the profile out.  No
#'   # horizon of the new location is needed -- or used.
#'   unseen <- piml_hierarchical_predict(fit, held[1, ], hz)
#'   print(dim(unseen))
#'   print(round(rbind(pred = as.numeric(unseen), obs = held$soc), 2))
#'
#'   # The baseline any location-free prediction must beat is the
#'   # depthwise mean of the training pedons.  Four pedons and 20
#'   # epochs lose to it by a factor of five, and 60 cm comes back
#'   # NEGATIVE: the ODE form is learned by an MLP, not imposed, so
#'   # nothing keeps a profile positive or monotone.  This is what a
#'   # five-pedon hierarchical fit is -- an interface, not a model.
#'   seen  <- piml_hierarchical_predict(fit,
#'              train[train$pedon == "P1", ][1, ], hz)
#'   dmean <- as.numeric(
#'     tapply(train$soc, train$depth, mean)[as.character(hz)])
#'   print(round(c(
#'     trained_on_this_pedon = sqrt(mean((as.numeric(seen) -
#'                             train$soc[train$pedon == "P1"])^2)),
#'     held_out_pedon        = sqrt(mean((as.numeric(unseen) -
#'                             held$soc)^2)),
#'     depthwise_mean        = sqrt(mean((dmean - held$soc)^2))), 2))
#'
#'   # `newdepths` need not be sorted: the integrator sorts, marches
#'   # and un-sorts, so column j always belongs to newdepths[j].
#'   p1 <- piml_hierarchical_predict(fit, held[1, ], c(5, 15, 30, 60))
#'   p2 <- piml_hierarchical_predict(fit, held[1, ], c(60, 5, 30, 15))
#'   print(all.equal(as.numeric(p1), as.numeric(p2[, c(2, 4, 3, 1)])))
#'
#'   # Depths are divided by the deepest TRAINING horizon, so asking
#'   # for 100 or 200 cm marches the network past everything it saw.
#'   # It answers anyway, and the answer leaves the observed range.
#'   print(fit$depth_scale)
#'   print(round(
#'     piml_hierarchical_predict(fit, held[1, ], c(60, 100, 200)), 2))
#'   print(round(range(train$soc), 2))
#' }
#' @export
piml_hierarchical_predict <- function(object, new_covariates, newdepths,
                                     clamp = TRUE) {
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
  # NO STRUCTURAL POSITIVITY. The state is marched by RK4 over an
  # unconstrained MLP vector field, so nothing stops a profile from crossing
  # zero -- and the function's own documented example did exactly that,
  # returning -2.56 g/kg of organic carbon at 60 cm and -10.46 at 200 cm.
  #
  # Clamping is a guard, not a fix: a model that predicts negative carbon has
  # gone wrong somewhere the clamp does not reach. So it clamps AND says so,
  # with the worst value, rather than quietly returning zeros that look like
  # data.
  if (isTRUE(object$value_positive) && any(out < 0, na.rm = TRUE)) {
    n_bad <- sum(out < 0, na.rm = TRUE)
    worst <- min(out, na.rm = TRUE)
    if (isTRUE(clamp)) {
      out[out < 0] <- 0
      warning(sprintf(paste(
        "piml_hierarchical_predict(): %d of %d predicted values were negative",
        "(worst %.3g) for a strictly positive training response, and have been",
        "clamped to 0. The model has no positivity constraint -- the state is",
        "integrated over an unconstrained network -- so this is a symptom, not",
        "a rounding issue. Inspect the fit before using these predictions;",
        "`clamp = FALSE` returns them unmodified."),
        n_bad, length(out), worst), call. = FALSE)
    } else {
      warning(sprintf(paste(
        "piml_hierarchical_predict(): %d of %d predicted values are negative",
        "(worst %.3g) for a strictly positive training response, and are",
        "returned unmodified because `clamp = FALSE`."),
        n_bad, length(out), worst), call. = FALSE)
    }
  }
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
#' @param candidate_covariate_cols Character vector naming the columns
#'   of the candidate table that correspond to the training
#'   covariates, **in the same order as** `hier_fit$covariate_cols`.
#'   The mapping is positional — the i-th name given here is renamed
#'   to the i-th training covariate — so this argument exists to
#'   translate different column *names*, not a different order. A
#'   permuted order silently feeds each covariate to the wrong input.
#' @param safety_factor Numeric `>= 1`, widening factor on each side.
#' @param envelope_depths Numeric, depths (same units as training) at
#'   which the profile is probed to compute `min` and `max` for each
#'   candidate. Defaults span surface to a deep horizon.
#' @return A function suitable for
#'   `al_query(..., physics_gate = <this>)`.
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   data(br_cerrado)
#'   # The five noise-free ODE pedons of ?piml_hierarchical_fit.
#'   sites <- br_cerrado[c(1, 400, 900, 1400, 1900), ]
#'   hz <- c(5, 15, 30, 60)
#'   pedons <- do.call(rbind, lapply(1:5, function(i) {
#'     y0   <- sites$soc[i]
#'     lam0 <- 0.02 + 0.004 * sites$twi[i]
#'     data.frame(pedon = paste0("P", i), depth = hz,
#'                soc = 0.30 * y0 + 0.70 * y0 *
#'                      exp(-(lam0 / 0.02) * (1 - exp(-0.02 * hz))),
#'                twi = sites$twi[i], ndvi = sites$ndvi[i],
#'                map_mm = sites$map_mm[i])
#'   }))
#'   fit <- piml_hierarchical_fit(
#'     pedons, "pedon", "depth", "soc",
#'     covariate_cols = c("twi", "ndvi", "map_mm"),
#'     epochs = 20L, lr = 0.05, n_steps = 2L, seed = 1L)
#'
#'   gate <- al_physics_gate_piml_hierarchical(
#'     fit, safety_factor = 1.2, envelope_depths = c(0, 30, 60))
#'
#'   # The predicted means the gate judges come from the QRF, exactly
#'   # as al_query() computes them internally.
#'   set.seed(11)
#'   labeled <- br_cerrado[sample(nrow(br_cerrado), 120), ]
#'   m <- al_fit(labeled, target = "soc",
#'               covariates = c("twi", "ndvi", "map_mm", "elev"),
#'               num.trees = 100L)
#'   cand <- br_cerrado[seq(2, 2025, length.out = 8), ]
#'   pm <- predict(m$model, data = cand[, m$covariates])$predictions
#'
#'   # Each candidate is judged against ITS OWN predicted profile:
#'   # [min, max] over `envelope_depths`, widened by
#'   # (safety_factor - 1) * (max - min) on each side.
#'   env <- piml_hierarchical_predict(fit, cand, c(0, 30, 60))
#'   print(data.frame(pred = round(pm, 2),
#'                    lo   = round(apply(env, 1L, min), 2),
#'                    hi   = round(apply(env, 1L, max), 2),
#'                    keep = gate(cand, pm)))
#'
#'   # Six of the eight are rejected even though every predicted value
#'   # lies inside the SOC actually measured in br_cerrado.  The
#'   # envelope inherits everything wrong with a five-pedon fit, so
#'   # read the rejection rate -- and sweep safety_factor -- before
#'   # wiring a gate into al_loop().
#'   print(round(range(pm), 1))
#'   print(round(range(br_cerrado$soc), 1))
#'   print(vapply(c(1, 1.2, 2, 5), function(s)
#'     sum(al_physics_gate_piml_hierarchical(
#'           fit, safety_factor = s,
#'           envelope_depths = c(0, 30, 60))(cand, pm)), 0))
#'
#'   # A gate can also shrink the batch: al_query() clamps `n` to the
#'   # number of survivors, so n = 3 returns 2 rows here -- and none
#'   # of the three ungated picks is among them.
#'   print(al_query(m, cand, n = 3L, physics_gate = gate))
#'   print(al_query(m, cand, n = 3L))
#'
#'   # `candidate_covariate_cols` is a positional rename, not a lookup.
#'   # Given in training order it reproduces the gate above; permuted,
#'   # it feeds rainfall into the twi input and silently flips two of
#'   # the eight decisions -- no error, no warning.
#'   cand2 <- cand
#'   names(cand2)[match(c("twi", "ndvi", "map_mm"), names(cand2))] <-
#'     c("wetness", "greenness", "rain")
#'   ok  <- al_physics_gate_piml_hierarchical(
#'     fit, c("wetness", "greenness", "rain"),
#'     envelope_depths = c(0, 30, 60))
#'   bad <- al_physics_gate_piml_hierarchical(
#'     fit, c("rain", "greenness", "wetness"),
#'     envelope_depths = c(0, 30, 60))
#'   print(identical(ok(cand2, pm), gate(cand, pm)))
#'   print(sum(ok(cand2, pm) != bad(cand2, pm)))
#'
#'   # Cost: one ODE integration per candidate per call, times
#'   # length(envelope_depths).  Eight rows are instant, 400 rows with
#'   # the default five depths take a few seconds -- gate a subset,
#'   # not a whole raster.
#' }
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
    lo <- mins - slack * span
    hi <- maxs + slack * span

    # ANCHOR TO THE DATA, NOT ONLY TO THE MODEL. The envelope above is built
    # entirely from this network's own predictions, so a fit that came out low
    # rejects candidates the training data call ordinary. On the function's own
    # documented example it rejected 6 of 8 candidates whose predicted means
    # all sat inside the observed range of the response.
    #
    # A physics gate is meant to exclude the impossible, not the unfamiliar.
    # Widening the envelope to at least the observed range restores that: a
    # candidate is rejected only if it falls outside BOTH what the model
    # expects and what has actually been measured.
    if (!is.null(hier_fit$value_range)) {
      lo <- pmin(lo, hier_fit$value_range[1L])
      hi <- pmax(hi, hier_fit$value_range[2L])
    }
    # And floor at zero for a strictly positive response, the same correction
    # al_physics_gate_piml() already carries. Without it the `slack * span`
    # widening certifies negative carbon as plausible.
    if (isTRUE(hier_fit$value_positive)) lo <- pmax(lo, 0)

    predicted_mean >= lo & predicted_mean <= hi
  }
}
