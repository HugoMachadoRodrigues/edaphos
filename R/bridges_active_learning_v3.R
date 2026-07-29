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
# follow the `al_query_causal()` signature pattern so they
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
#' @examples
#' # br_cerrado is a surface grid and Pillar 8 needs depth curves, so
#' # each pixel is expanded into an exponential profile whose decay
#' # rate is driven by its own TWI.  The profiles are synthetic; what
#' # is being demonstrated is the hand-off, not a soil result.
#' set.seed(11)
#' sub  <- br_cerrado[sample(nrow(br_cerrado), 90L), ]
#' zz   <- c(5, 15, 30, 60, 100)                 # depths, cm
#' covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' Xc   <- scale(as.matrix(sub[, covs]))
#' rate <- 0.015 + 0.0015 * as.numeric(scale(sub$twi))
#' prof <- t(vapply(seq_len(nrow(sub)), function(i)
#'            4 + (sub$soc[i] - 4) * exp(-rate[i] * zz), numeric(5L)))
#' tr <- 1:60; po <- 61:90
#'
#' no <- no_deeponet_fit(zz, prof[tr, ], Xc[tr, ], branch_hidden = 12L,
#'                       trunk_hidden = 12L, output_dim = 6L,
#'                       epochs = 300L, lr = 0.02, seed = 1L)
#' # Worth checking before ranking anything by its disagreement: the
#' # operator is ahead of the regional mean profile, but only by 21 %.
#' c(deeponet = edaphos_rmse(prof[po, ], predict(no, Xc[po, ],
#'                                               newdepths = zz)),
#'   mean_profile = edaphos_rmse(prof[po, ],
#'     matrix(colMeans(prof[tr, ]), 30L, 5L, byrow = TRUE)))
#' # 2.72 vs 3.42 g/kg
#'
#' # Pillar 2 supplies the reference kinetics, fitted to the mean
#' # training profile.
#' ode <- piml_profile_fit(zz, colMeans(prof[tr, ]))
#' q <- al_query_neural_operator(no, ode, Xc[po, ], pool_depths = zz,
#'                               n_select = 5L, n_pert = 20L, seed = 1L)
#' q
#'
#' # First trap: `n_select` never subsets.  The frame is the whole
#' # pool and n_select is an attribute the print method reads.
#' c(rows = nrow(q), n_select = attr(q, "n_select"))          # 30 and 5
#'
#' # Second: the ODE contributes ONE curve, not one per site --
#' # predict.edaphos_piml_profile() is a function of depth alone.  So
#' # `no_ode_disagreement` measures each site against a single
#' # regional reference, and two candidates with the same operator
#' # profile score identically however different their soils are.
#' round(as.numeric(predict(ode, newdepths = zz)), 2)
#' # 17.92 15.89 13.43 9.98 7.19 g/kg -- the same for all 30 sites
#'
#' # Third: the denominator is a perturbation proxy, not a posterior,
#' # and it barely reorders anything.  Read the two together.
#' c(sd_cv = sd(q$no_uncertainty_sd) / mean(q$no_uncertainty_sd),
#'   rank_agreement = cor(rank(q$score),
#'                        rank(q$no_ode_disagreement)))   # 0.231, 0.960
#'
#' # It is also the only stochastic part and there is no default seed.
#' # Here the top five survive a change of seed but individual scores
#' # move by half; an unseeded call is not reproducible at all.
#' q2 <- al_query_neural_operator(no, ode, Xc[po, ], pool_depths = zz,
#'                                n_pert = 20L, seed = 2L)
#' identical(head(q$pool_index, 5L), head(q2$pool_index, 5L))   # TRUE
#' max(abs(q$score[order(q$pool_index)] /
#'         q2$score[order(q2$pool_index)] - 1))                 # 0.506
#'
#' # Trap for the other operator class: predict() for an FNO has no
#' # `newdepths` argument at all, so `pool_depths` is swallowed by
#' # `...` and the profile always comes back on the training grid.
#' names(formals(getS3method("predict", "edaphos_no_fno")))
#' # "object" "newcovariates" "..."
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
#' @examples
#' # Pillar 9 wants a bank of patches: cut the 45 x 45 Cerrado SOC
#' # grid into 25 non-overlapping 9 x 9 tiles.
#' soc_grid <- matrix(br_cerrado$soc, 45L, 45L)
#' stack <- array(0, c(25L, 9L, 9L))
#' k <- 0L
#' for (i in 0:4) for (j in 0:4) {
#'   k <- k + 1L
#'   stack[k, , ] <- soc_grid[(i * 9L + 1L):(i * 9L + 9L),
#'                            (j * 9L + 1L):(j * 9L + 9L)]
#' }
#' dm <- dm_fit(stack, T = 40L, epochs = 200L, hidden = 24L,
#'              lr = 0.01, seed = 1L)
#' c(first_epoch = dm$history[1L], last_epoch = dm$history[200L])
#' # 3.64 -> 1.02 on the score-matching loss
#'
#' q <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L, seed = 1L)
#' q
#'
#' # The number that decides whether this ranking means anything is
#' # not in the frame: the width of the posterior draws against the
#' # variability of the maps they are meant to model.
#' emp_sd <- apply(stack, c(2L, 3L), sd)      # per-cell sd over 25 tiles
#' c(ddpm = mean(q$posterior_sd), data = mean(emp_sd))     # 19.3 vs 6.5
#' # The pure-R denoiser trains a readout over frozen random features,
#' # so its ancestral samples are three times wider than the map they
#' # came from.  Most of "posterior SD" here is sampler noise.
#'
#' # Which the ranking shows directly.  Redraw with another seed: the
#' # SD map hardly correlates with itself and one of the eight chosen
#' # cells survives.
#' q2 <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L, seed = 2L)
#' a <- q[order(q$row, q$col), ]; b <- q2[order(q2$row, q2$col), ]
#' cor(a$posterior_sd, b$posterior_sd)                          # 0.070
#' length(intersect(paste(q$row[1:8],  q$col[1:8]),
#'                  paste(q2$row[1:8], q2$col[1:8])))           # 1 of 8
#'
#' # Four times the default draws lifts the seed-to-seed correlation
#' # to 0.30 and still does not settle which cells to visit.
#' c1 <- al_query_diffusion(dm, n_samples = 64L, n_select = 8L, seed = 1L)
#' c2 <- al_query_diffusion(dm, n_samples = 64L, n_select = 8L, seed = 2L)
#' cor(c1$posterior_sd[order(c1$row, c1$col)],
#'     c2$posterior_sd[order(c2$row, c2$col)])                  # 0.299
#'
#' # And the structure it does have is not the map's: the DDPM SD
#' # field is uncorrelated with where the real tiles actually differ.
#' cor(a$posterior_sd, as.numeric(emp_sd[cbind(a$row, a$col)]))  # -0.043
#'
#' # `combine` is not a tweak either -- weighting by the expected
#' # value keeps one of the same eight cells.
#' q3 <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L,
#'                          combine = "sd_x_mean_abs", seed = 1L)
#' length(intersect(paste(q$row[1:8],  q$col[1:8]),
#'                  paste(q3$row[1:8], q3$col[1:8])))           # 1 of 8
#'
#' # `candidate_cells` restricts the pool to the sites a field team
#' # can actually reach; `n_select`, as in the other AL bridges, is
#' # only an attribute and never subsets the frame.
#' reach <- expand.grid(row = 2:4, col = 2:4)
#' nrow(al_query_diffusion(dm, candidate_cells = reach,
#'                         n_samples = 8L, n_select = 3L, seed = 1L))  # 9
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
#' @examples
#' # A contiguous 15 x 15 block of the Cerrado grid, so the candidate
#' # spacing is the grid step and the GP range is resolvable at all.
#' gx <- sort(unique(br_cerrado$x)); gy <- sort(unique(br_cerrado$y))
#' blk <- br_cerrado[br_cerrado$x %in% gx[1:15] &
#'                   br_cerrado$y %in% gy[1:15], ]
#' names(blk)[names(blk) == "x"] <- "lon"
#' names(blk)[names(blk) == "y"] <- "lat"
#' set.seed(4)
#' tr   <- sort(sample(nrow(blk), 150L))
#' trn  <- blk[tr, ]; pool <- blk[-tr, ]     # 150 measured, 75 candidates
#'
#' bh <- bhs_fit(trn, soc ~ elev + twi + map_mm, coords = c("lon", "lat"),
#'               backend = "gibbs", nmcmc = 600L, burn = 300L,
#'               phi_range = c(0.1, 500), seed = 1L)
#'
#' # al_query_bhs() draws its MCMC subset from the ambient RNG and
#' # takes no seed of its own: set one, or the variances move between
#' # runs (the ORDER does not -- see below).
#' set.seed(7)
#' q <- al_query_bhs(bh, pool, n_select = 5L, n_draws = 50L)
#' q
#'
#' # Read the ranking against the diagnostic that says whether it can
#' # mean anything.  The profile-MLE correlation length is a third of
#' # the sampling interval, so no candidate is informed by its
#' # neighbours...
#' c(range_deg = 1 / bh$phi_hat, grid_step = gx[2L] - gx[1L])
#' # 0.0026 vs 0.0080 degrees
#'
#' # ...and every candidate's predictive variance therefore sits at
#' # sigma^2 + tau^2, the variance of a site the model knows nothing
#' # about.  The whole pool spans 1.3 % of that.
#' c(min = min(q$posterior_var), max = max(q$posterior_var),
#'   no_information = mean(bh$sigma2_draws) + mean(bh$tau2_draws))
#' # 29.52  29.92  29.60
#'
#' # What survives is geometry.  Averaging over posterior draws cannot
#' # reorder anything: var = sigma^2 (1 - k'R^-1k) + tau^2 is monotone
#' # in the kriging term for every draw, so the ranking is identical
#' # at 50 and at 400 draws (silently capped at the 300 stored).
#' set.seed(7)
#' q400 <- al_query_bhs(bh, pool, n_select = 5L, n_draws = 400L)
#' identical(q$pool_index, q400$pool_index)   # TRUE
#' attr(q400, "n_draws")                      # 300 -- silently capped
#'                                            # at the draws stored
#'
#' # Nor do the covariates: `pool_data` must carry every training
#' # column, but the design matrix built from them is never used --
#' # beta uncertainty is not in the formula.  Wreck them and nothing
#' # moves.
#' pw <- pool
#' pw$elev <- rev(pw$elev); pw$twi <- pw$twi * 100
#' pw$map_mm <- pw$map_mm + 5000
#' set.seed(7)
#' identical(q$posterior_var,
#'           al_query_bhs(bh, pw, n_draws = 50L)$posterior_var)   # TRUE
#'
#' # So what this returns is a distance-to-nearest-measurement
#' # ranking wearing a posterior's clothes.
#' D <- as.matrix(dist(rbind(as.matrix(trn[, c("lon", "lat")]),
#'                           as.matrix(pool[, c("lon", "lat")]))))
#' d_nn <- apply(D[151:225, 1:150, drop = FALSE], 1L, min)
#' cor(q$posterior_var[order(q$pool_index)], d_nn,
#'     method = "spearman")                                       # 0.561
#'
#' # Finally, the faster Pillar 7 backend is refused even though it
#' # stores the same draws -- refit with backend = "gibbs" for AL.
#' bhr <- bhs_fit(trn, soc ~ elev + twi + map_mm,
#'                coords = c("lon", "lat"), backend = "rcpp",
#'                nmcmc = 300L, burn = 150L, phi_range = c(0.1, 500),
#'                seed = 1L)
#' try(al_query_bhs(bhr, pool))
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
  # k(x_new, x_new) = 1 by the exponential-correlation convention.
  # The kriging quadratic form k' R_inv k is a function of the
  # coordinates and phi_hat only, so it is computed ONCE.  Inside the
  # loop it recomputed an (n_tr x n_tr) %*% (n_tr x n_pool) product
  # `n_draws` times for a bit-identical result, which at the default
  # n_draws = 200 is essentially the entire cost of the call.
  quadratic <- colSums((R_tr_inv %*% R_cross) * R_cross)
  for (i in idx) {
    s2 <- bhs_fit$sigma2_draws[i]
    t2 <- bhs_fit$tau2_draws[i]
    # Per-candidate variance of the latent + noise:
    #   var_new = s2 (1 - k' R_inv k) + t2
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
