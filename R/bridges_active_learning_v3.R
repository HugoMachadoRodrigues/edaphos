# Active-Learning bridges for Pilar 5 (edaphos v3.0.0).
#
# Three bridges that feed posterior-like uncertainty signals from
# Pilares 7, 8 and 9 into Pilar 5's query step:
#
#   al_query_neural_operator()  (Pilar 8 x Pilar 5)
#   al_query_diffusion()        (Pilar 9 x Pilar 5)
#   al_query_bhs()              (Pilar 7 x Pilar 5)
#
# All three return an `edaphos_al_query` data frame with `pool_index`,
# `score`, and optional auxiliary columns for diagnostics.  They
# follow the v2.1.1 `al_query_causal()` signature pattern so they
# plug straight into Pilar 5's existing `al_loop()` machinery by way
# of a custom acquisition-function callback.

# ---------------------------------------------------------------------------
# P8 x P5 -- Neural Operator as uncertainty prior
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# A DeepONet trained on labelled profiles produces mean-field
# predictions at every candidate site.  Candidates whose NO
# prediction DISAGREES with the Pilar 2 local ODE fit are where the
# operator's extrapolation is most uncertain, and therefore the
# highest-value next samples for a campaign that targets the
# process-model / operator-model alignment.
#
# `al_query_neural_operator()` computes, for each candidate,
#
#     score = | y_hat_NO(site) - y_hat_ODE(site) | / sigma_NO
#
# where sigma_NO is a per-site uncertainty proxy built by
# perturbing the covariate input with Gaussian noise and measuring
# the spread of resulting profiles (in the absence of a proper
# Bayesian NO, this perturbation proxy is a lightweight alternative).

#' Causal-driven AL via Neural Operator disagreement (Pilar 8 x Pilar 5)
#'
#' Ranks candidate sites by the disagreement between a Neural
#' Operator's predicted depth profile and a classical Pilar 2
#' pedogenetic ODE's predicted profile, normalised by the NO's
#' perturbation-spread uncertainty.
#'
#' @param no_fit A fit from [`no_deeponet_fit()`] or [`no_fno_fit()`].
#' @param ode_fit A fit from [`piml_profile_fit()`] or
#'   [`piml_profile_fit_bayesian()`].
#' @param pool_covariates Matrix of per-site summary covariates
#'   (n_pool x p_in) matching the branch input of `no_fit`.
#' @param pool_depths Optional depths to evaluate at; defaults to
#'   the training depths of `no_fit`.
#' @param n_select Integer; number of candidates to return.
#' @param n_pert Integer; number of Gaussian-noise perturbations per
#'   candidate to estimate NO uncertainty.
#' @param pert_sd Numeric; standard deviation of the Gaussian
#'   perturbation (in covariate-standard-deviation units).
#' @param seed Optional RNG seed.
#' @return A data frame of class `edaphos_al_neural_operator_query`
#'   sorted by descending score.
#' @export
al_query_neural_operator <- function(no_fit, ode_fit,
                                        pool_covariates,
                                        pool_depths = NULL,
                                        n_select = 5L,
                                        n_pert = 20L, pert_sd = 0.1,
                                        seed = NULL) {
  stopifnot(inherits(no_fit, c("edaphos_no_deeponet", "edaphos_no_fno")))
  if (!is.null(seed)) set.seed(seed)
  if (is.null(pool_depths)) pool_depths <- no_fit$depths
  pool_covariates <- as.matrix(pool_covariates)
  n_pool <- nrow(pool_covariates)

  # NO mean prediction
  pr_no <- stats::predict(no_fit, pool_covariates,
                            newdepths = pool_depths)

  # ODE prediction (shared across sites, depth-only)
  pr_ode <- tryCatch(
    as.numeric(stats::predict(ode_fit, newdepths = pool_depths)),
    error = function(e) {
      # Fallback: exponential-decay surrogate using whichever params
      # happen to live on the fit object (handled by .piml_extract_params).
      pars <- .piml_extract_params(ode_fit)
      yi <- pars$y_inf; y0 <- pars$y0
      l0 <- pars$lambda0; mu <- pars$mu
      yi + (y0 - yi) * exp(-l0 * pool_depths * exp(-mu * pool_depths))
    }
  )

  # Mean absolute disagreement across the depth grid, per candidate
  disagree <- rowMeans(abs(sweep(pr_no, 2L, pr_ode, "-")))

  # NO uncertainty via covariate perturbation spread
  pert_preds <- array(NA_real_,
                        dim = c(n_pert, n_pool, length(pool_depths)))
  for (k in seq_len(n_pert)) {
    noise <- matrix(stats::rnorm(n_pool * ncol(pool_covariates),
                                    sd = pert_sd),
                      n_pool, ncol(pool_covariates))
    pr_k <- stats::predict(no_fit, pool_covariates + noise,
                             newdepths = pool_depths)
    pert_preds[k, , ] <- pr_k
  }
  # Per-site SD collapsed across depths
  site_sd <- apply(pert_preds, 2L, function(mat) {
    per_depth <- apply(mat, 2L, stats::sd, na.rm = TRUE)
    mean(per_depth, na.rm = TRUE)
  })
  site_sd[!is.finite(site_sd) | site_sd < 1e-6] <- 1e-6

  score <- disagree / site_sd
  out <- data.frame(
    pool_index = seq_len(n_pool),
    score      = score,
    no_ode_disagreement = disagree,
    no_uncertainty_sd   = site_sd,
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$score), ]
  structure(out,
             class    = c("edaphos_al_neural_operator_query", "data.frame"),
             n_select = n_select)
}

#' @export
print.edaphos_al_neural_operator_query <- function(x, ...) {
  cat("<edaphos_al_neural_operator_query>  (Pilar 8 x Pilar 5)\n")
  cat(sprintf("  pool size : %d\n", nrow(x)))
  cat(sprintf("  n_select  : %d\n", attr(x, "n_select")))
  cat("  top candidates (NO vs ODE disagreement, normalised):\n")
  print(as.data.frame(utils::head(x, attr(x, "n_select"))))
  invisible(x)
}

# ---------------------------------------------------------------------------
# P9 x P5 -- Diffusion-posterior spread as AL priority
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# A conditional DDPM trained on labelled soil-map patches samples
# full maps from p(map | conditioning).  Regions where those
# samples differ most (high per-cell posterior SD) are the sites
# where a new label reduces most of the entropy the model is
# currently uncertain about.
#
# `al_query_diffusion()` draws N samples from the DDPM, computes
# per-cell posterior SD, and ranks candidate cells by a
# combination of SD and optional logistical cost.

#' Diffusion-posterior-driven AL (Pilar 9 x Pilar 5)
#'
#' Ranks candidate cells by the standard deviation of DDPM posterior
#' samples.  High-SD cells are the most uncertain map locations;
#' labelling there delivers the largest reduction in model entropy
#' per sample.
#'
#' @param dm_fit An `edaphos_dm_fit` from [`dm_fit()`].
#' @param conditioning Optional `(n_samples, cond_dim)` matrix (one
#'   row per posterior draw); when `NULL` the model is sampled
#'   unconditionally.
#' @param n_samples Integer; number of posterior draws.
#' @param candidate_cells Optional integer matrix with columns `row`,
#'   `col` restricting the candidate pool to accessible sites.
#'   Defaults to the full H x W grid.
#' @param n_select Integer; how many cells to return.
#' @param combine One of `"sd"` or `"sd_x_mean_abs"` to weight SD by
#'   the absolute expected value (prioritises cells where the model
#'   thinks the SOC is BOTH high and uncertain).
#' @param seed RNG seed.
#' @return A data frame of class `edaphos_al_diffusion_query`
#'   sorted by descending score.
#' @export
al_query_diffusion <- function(dm_fit, conditioning = NULL,
                                  n_samples = 16L,
                                  candidate_cells = NULL,
                                  n_select = 10L,
                                  combine = c("sd", "sd_x_mean_abs"),
                                  seed = NULL) {
  stopifnot(inherits(dm_fit, "edaphos_dm_fit"))
  combine <- match.arg(combine)
  H <- dm_fit$H; W <- dm_fit$W
  samps <- dm_sample(dm_fit, n_samples = n_samples,
                       conditioning = conditioning, seed = seed)
  # samps: (n_samples, H, W)
  post_mean <- apply(samps, c(2L, 3L), mean, na.rm = TRUE)
  post_sd   <- apply(samps, c(2L, 3L), stats::sd, na.rm = TRUE)

  if (is.null(candidate_cells)) {
    candidate_cells <- expand.grid(row = seq_len(H), col = seq_len(W))
  }
  stopifnot(all(c("row", "col") %in% names(candidate_cells)))
  sd_vals   <- post_sd[ cbind(candidate_cells$row, candidate_cells$col) ]
  mean_vals <- post_mean[cbind(candidate_cells$row, candidate_cells$col)]

  score <- switch(combine,
    sd              = sd_vals,
    sd_x_mean_abs   = sd_vals * abs(mean_vals)
  )
  out <- data.frame(
    row        = candidate_cells$row,
    col        = candidate_cells$col,
    posterior_mean = mean_vals,
    posterior_sd   = sd_vals,
    score          = score,
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$score), ]
  structure(out,
             class    = c("edaphos_al_diffusion_query", "data.frame"),
             n_select = n_select, combine = combine)
}

#' @export
print.edaphos_al_diffusion_query <- function(x, ...) {
  cat("<edaphos_al_diffusion_query>  (Pilar 9 x Pilar 5)\n")
  cat(sprintf("  pool size : %d\n", nrow(x)))
  cat(sprintf("  combine   : %s\n", attr(x, "combine")))
  cat(sprintf("  top-%d cells:\n", attr(x, "n_select")))
  print(as.data.frame(utils::head(x, attr(x, "n_select"))))
  invisible(x)
}

# ---------------------------------------------------------------------------
# P7 x P5 -- Bayesian Hierarchical AL (Settles 2009 posterior-sampling)
# ---------------------------------------------------------------------------
#
# Hypothesis
# ----------
# Posterior-sampling active learning (Thompson sampling for AL; cf.
# Settles 2009, Sec. 3.3) draws a parameter sample theta ~ p(theta |
# D), picks the candidate that maximises the predictive marginal
# variance UNDER that theta, and iterates.  Because we average
# across posterior draws, candidates selected are ones whose
# predictive uncertainty is HIGH for many plausible theta values,
# not just the posterior mean.
#
# `al_query_bhs()` implements this for a Pilar 7 `edaphos_bhs` fit.
# For each MCMC draw (beta, sigma^2, tau^2) we compute the
# predictive variance of a candidate site as
#
#     var_pred = sigma^2 (1 - k_cross' R_tr^-1 k_cross) + tau^2
#
# and average across draws.

#' Bayesian Hierarchical Active Learning (Pilar 7 x Pilar 5)
#'
#' Ranks candidate sites by their predictive variance averaged over
#' the BHS posterior MCMC draws -- Thompson-sampling-style AL in
#' the language of Settles (2009, Section 3.3).
#'
#' @param bhs_fit An `edaphos_bhs` from [`bhs_fit()`].
#' @param pool_data Data frame of candidate sites with covariates +
#'   coords.
#' @param n_select Integer; number of candidates to return.
#' @param n_draws Integer; number of posterior draws to average.
#' @return `edaphos_al_bhs_query` data frame sorted by descending
#'   average predictive variance.
#' @export
al_query_bhs <- function(bhs_fit, pool_data,
                           n_select = 5L, n_draws = 200L) {
  stopifnot(inherits(bhs_fit, "edaphos_bhs"))
  if (bhs_fit$backend != "gibbs")
    stop("al_query_bhs() currently supports backend = 'gibbs' only.",
          call. = FALSE)

  # Build X_new with the same column set used at training
  rhs_terms <- stats::delete.response(stats::terms(bhs_fit$formula))
  X_new <- stats::model.matrix(rhs_terms, data = pool_data)
  X_new <- X_new[, colnames(bhs_fit$X), drop = FALSE]
  coord_cols <- colnames(bhs_fit$coords)
  S_new <- as.matrix(pool_data[, coord_cols, drop = FALSE])

  # Precompute training kernel + cross-distance
  phi    <- bhs_fit$phi_hat %||% stats::median(bhs_fit$phi_draws)
  D_tr   <- as.matrix(stats::dist(bhs_fit$coords))
  R_tr   <- exp(-phi * D_tr); diag(R_tr) <- diag(R_tr) + 1e-8
  R_tr_inv <- solve(R_tr)
  n_tr <- nrow(bhs_fit$coords); n_pool <- nrow(S_new)
  D_cross <- as.matrix(stats::dist(rbind(bhs_fit$coords, S_new)))[
    seq_len(n_tr),
    seq(n_tr + 1L, n_tr + n_pool), drop = FALSE]
  R_cross <- exp(-phi * D_cross)

  # Posterior-draw variance-average
  idx <- sample.int(nrow(bhs_fit$beta_draws),
                     min(n_draws, nrow(bhs_fit$beta_draws)))
  pred_var <- numeric(n_pool)
  # k(x_new, x_new) = 1 by the exponential-correlation convention
  for (i in idx) {
    s2 <- bhs_fit$sigma2_draws[i]
    t2 <- bhs_fit$tau2_draws[i]
    # Per-candidate variance of the latent + noise:
    #   var_new = s2 (1 - k' R_inv k) + t2
    quadratic <- colSums((R_tr_inv %*% R_cross) * R_cross)
    var_draw  <- s2 * pmax(1 - quadratic, 0) + t2
    pred_var <- pred_var + var_draw / length(idx)
  }
  out <- data.frame(
    pool_index    = seq_len(n_pool),
    posterior_var = pred_var,
    posterior_sd  = sqrt(pred_var),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$posterior_var), ]
  structure(out,
             class    = c("edaphos_al_bhs_query", "data.frame"),
             n_select = n_select, n_draws = length(idx))
}

#' @export
print.edaphos_al_bhs_query <- function(x, ...) {
  cat("<edaphos_al_bhs_query>  (Pilar 7 x Pilar 5)\n")
  cat(sprintf("  pool size : %d\n", nrow(x)))
  cat(sprintf("  n_draws   : %d   n_select: %d\n",
               attr(x, "n_draws"), attr(x, "n_select")))
  cat("  top candidates by avg posterior variance:\n")
  print(as.data.frame(utils::head(x, attr(x, "n_select"))))
  invisible(x)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
