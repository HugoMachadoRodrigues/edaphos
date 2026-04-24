# Pilar 7 -- Bayesian hierarchical spatial models (edaphos v2.3.0).
#
# Model
# -----
# For a response vector y at n geographically located sites we assume
#
#     y_i = x_i' beta + w_i + eps_i,      eps_i ~ N(0, tau^2)
#     w   ~ N_n(0, sigma^2 * R(phi))       latent spatial GP
#     R_{ij}(phi) = exp(-phi * d_ij)        exponential correlation
#
# Priors
#     beta  ~ N_p(0, prior_var_beta * I_p)
#     sigma^2, tau^2  ~ InverseGamma(a_prior, b_prior)
#     phi: fixed at a profile-likelihood estimate (empirical Bayes).
#     Treating phi as a hyperparameter via profile-MLE keeps every
#     posterior update closed-form and avoids slow Metropolis steps
#     -- the same strategy used by the "inla" family of approximations
#     (Rue, Martino and Chopin 2009) for the spatial hyperparameter.
#
# Gibbs sampler
# -------------
# Conjugate updates each iteration:
#   beta  | . ~ N( mu_beta, Sigma_beta )
#   sigma^2 | . ~ IG( a + n/2, b + (1/2) w' R^-1 w )
#   tau^2   | . ~ IG( a + n/2, b + (1/2) (y - X beta - w)' (y - X beta - w) )
#   w     | . ~ N( mu_w, Sigma_w )
#
# where mu_w = sigma^2 R * (sigma^2 R + tau^2 I)^-1 (y - X beta) and
# Sigma_w is the Woodbury-reduced form.  For scalability we use the
# profile-MLE of phi from `stats::optimise` over a user-supplied
# bracket.
#
# Posterior output is packaged as an `edaphos_bhs` S3 object with
# MCMC draws over beta, sigma^2, tau^2, plus `predict()` for Bayesian
# kriging and `as_edaphos_posterior()` for v1.6.0 integration.
#
# Alternative backends
# --------------------
#   backend = "gibbs"   : this pure-R Gibbs sampler (default).
#   backend = "spBayes" : dispatches to `spBayes::spLM` when the
#                          Suggests-only package is installed --
#                          runs the full Bayesian spatial linear
#                          model with phi MCMC.
#   backend = "stan"    : future v2.3.1 work.
#
# References
# ----------
# Finley, A. O., Banerjee, S. and Carlin, B. P. (2007).  spBayes: an
#   R package for univariate and multivariate hierarchical point-
#   referenced spatial models.  Journal of Statistical Software 19(4).
# Rue, H., Martino, S. and Chopin, N. (2009).  Approximate Bayesian
#   inference for latent Gaussian models using integrated nested
#   Laplace approximations.  JRSS B 71, 319-392.
# Poggio, L. et al. (2021).  SoilGrids 2.0.  SOIL 7, 217-240.

#' Fit a Bayesian hierarchical spatial linear model (Pilar 7)
#'
#' The v2.3.0 activation of the Pilar 7 scaffold.  Fits a Bayesian
#' spatial linear model `y_i = x_i' beta + w_i + eps_i` with a latent
#' exponential-correlation Gaussian process on the residual field
#' and returns full posterior draws.
#'
#' @param data A data frame with the response + covariates + spatial
#'   coordinates.
#' @param formula A `response ~ covariates` formula.
#' @param coords Character length-2 (default `c("lon", "lat")`) giving
#'   the coordinate columns.
#' @param backend One of `"gibbs"` (pure-R Gibbs sampler, default,
#'   no external deps), `"spBayes"` (dispatches to `spBayes::spLM`
#'   when available).
#' @param nmcmc Integer; number of MCMC iterations.  Default `2000L`.
#' @param burn Integer; burn-in to discard.  Default `nmcmc %/% 2`.
#' @param thin Integer; keep every `thin`-th post-burn draw.  Default `1L`.
#' @param prior_var_beta Numeric; Gaussian prior variance on `beta`.
#' @param prior_ig_a,prior_ig_b Shape and scale of the inverse-Gamma
#'   priors on `sigma^2` and `tau^2`.
#' @param phi_range Numeric length-2; bracket for the profile-MLE of
#'   the GP rate parameter `phi`.  Default `c(0.01, 10)`.
#' @param seed Optional RNG seed.
#' @param verbose Logical.
#' @return An `edaphos_bhs` S3 object.
#' @export
bhs_fit <- function(data, formula, coords = c("lon", "lat"),
                      backend = c("gibbs", "spBayes"),
                      nmcmc = 2000L, burn = NULL, thin = 1L,
                      prior_var_beta = 1e3,
                      prior_ig_a = 2, prior_ig_b = 1,
                      phi_range = c(0.01, 10),
                      seed = NULL, verbose = FALSE) {
  backend <- match.arg(backend)
  stopifnot(is.data.frame(data),
             inherits(formula, "formula"),
             is.character(coords), length(coords) == 2L)
  if (is.null(burn)) burn <- nmcmc %/% 2L
  stopifnot(burn >= 0L, burn < nmcmc, thin >= 1L)

  # Build the model matrix and coordinate matrix.  Use an internal
  # integer row-id column to avoid the frequent dplyr-style rowname
  # reset bug that breaks `data[as.integer(rownames(mf)), ]`.
  data_ <- data
  data_$.row_id <- seq_len(nrow(data_))
  mf <- stats::model.frame(stats::update(formula, ~ . + .row_id),
                             data_, na.action = stats::na.omit)
  # Additionally require coord columns to be present and finite.
  coord_df <- data_[mf$.row_id, coords, drop = FALSE]
  keep_coord <- stats::complete.cases(coord_df) &
                  apply(coord_df, 1L, function(r) all(is.finite(r)))
  mf       <- mf[keep_coord, , drop = FALSE]
  coord_df <- coord_df[keep_coord, , drop = FALSE]
  if (nrow(mf) < nrow(data_)) {
    message("[bhs_fit] dropped ", nrow(data_) - nrow(mf),
             " rows with NAs in the model frame / coords.")
  }
  mf$.row_id <- NULL
  y <- stats::model.response(mf)
  X <- stats::model.matrix(formula, mf)
  S <- as.matrix(coord_df)
  n  <- length(y); p <- ncol(X)
  if (n < p + 5L) stop("Too few complete rows for BHS.", call. = FALSE)

  if (!is.null(seed)) set.seed(seed)

  if (backend == "spBayes") {
    if (!requireNamespace("spBayes", quietly = TRUE))
      stop("Install `spBayes` to use backend = 'spBayes'.", call. = FALSE)
    # Dispatch to spBayes::spLM
    fit <- spBayes::spLM(
      formula = formula, data = data, coords = S,
      starting = list(beta = rep(0, p), phi = mean(phi_range),
                       sigma.sq = 1, tau.sq = 0.5),
      tuning   = list(phi = 0.1, sigma.sq = 0.1, tau.sq = 0.1),
      priors   = list(
        beta.Norm       = list(rep(0, p), diag(prior_var_beta, p)),
        phi.Unif        = phi_range,
        sigma.sq.IG     = c(prior_ig_a, prior_ig_b),
        tau.sq.IG       = c(prior_ig_a, prior_ig_b)
      ),
      cov.model = "exponential",
      n.samples = nmcmc, verbose = verbose
    )
    fit_sp <- spBayes::spRecover(fit, start = burn + 1L, verbose = FALSE)
    beta_draws <- fit_sp$p.beta.recover.samples
    theta_draws <- fit_sp$p.theta.recover.samples
    out <- list(
      backend    = "spBayes",
      beta_draws = beta_draws,
      sigma2_draws = theta_draws[, "sigma.sq"],
      tau2_draws   = theta_draws[, "tau.sq"],
      phi_draws    = theta_draws[, "phi"],
      X = X, y = y, coords = S, formula = formula,
      raw = fit_sp
    )
    class(out) <- "edaphos_bhs"
    return(out)
  }

  # ---- Pure-R Gibbs sampler -------------------------------------------
  # Pre-compute distance matrix
  D <- as.matrix(stats::dist(S))

  # Profile log-likelihood for phi (integrating beta, sigma^2 out
  # analytically under flat priors).
  neg_loglik_phi <- function(phi) {
    R <- exp(-phi * D)
    diag(R) <- diag(R) + 1e-8  # nugget for numerical stability
    Rinv <- tryCatch(solve(R), error = function(e) return(NULL))
    if (is.null(Rinv)) return(1e10)
    XtRinvX <- crossprod(X, Rinv %*% X)
    XtRinvy <- crossprod(X, Rinv %*% y)
    beta_hat <- solve(XtRinvX, XtRinvy)
    resid <- as.numeric(y - X %*% beta_hat)
    RSS  <- as.numeric(crossprod(resid, Rinv %*% resid))
    sigma2_hat <- RSS / (n - p)
    ldet <- determinant(R, logarithm = TRUE)$modulus
    as.numeric(
      0.5 * ldet + 0.5 * (n - p) * log(sigma2_hat) +
        0.5 * determinant(XtRinvX, logarithm = TRUE)$modulus
    )
  }
  phi_hat <- tryCatch(
    stats::optimise(neg_loglik_phi,
                      interval = phi_range)$minimum,
    error = function(e) mean(phi_range)
  )
  if (verbose) message(sprintf("[bhs_fit] profile-MLE phi = %.4f", phi_hat))

  # Gibbs sampler conditional on phi_hat
  R <- exp(-phi_hat * D)
  diag(R) <- diag(R) + 1e-8
  Rinv <- solve(R)

  beta_draws <- matrix(NA_real_, nmcmc, p,
                        dimnames = list(NULL, colnames(X)))
  sigma2_draws <- numeric(nmcmc)
  tau2_draws   <- numeric(nmcmc)
  w_mean       <- numeric(n)   # running mean of latent w for predictions

  # Initial values
  beta <- as.numeric(stats::lm.fit(X, y)$coefficients)
  sigma2 <- stats::var(y) / 2
  tau2   <- stats::var(y) / 2
  w_cur  <- rep(0, n)

  prior_prec <- 1 / prior_var_beta

  # Robust Cholesky with jitter
  .chol_jitter <- function(M, tries = 8L) {
    jit <- 0
    for (k in seq_len(tries)) {
      L <- tryCatch(chol(M + diag(jit, nrow(M))),
                     error = function(e) NULL)
      if (!is.null(L)) return(L)
      jit <- if (jit == 0) 1e-8 else jit * 10
    }
    # Final fallback: ridge-regularise heavily
    chol(M + diag(1e-2 * mean(diag(M)), nrow(M)))
  }

  for (iter in seq_len(nmcmc)) {
    # Update w | beta, sigma2, tau2
    # w ~ N(mu_w, V_w) where
    #   V_w = (Rinv/sigma2 + I/tau2)^-1
    #   mu_w = V_w (y - X beta) / tau2
    prec_w <- Rinv / sigma2 + diag(1 / tau2, n)
    L_w <- .chol_jitter(prec_w)
    V_w <- chol2inv(L_w)
    mu_w <- as.numeric(V_w %*% ((y - as.numeric(X %*% beta)) / tau2))
    L_Vw <- .chol_jitter(V_w)
    w_cur <- as.numeric(mu_w + t(L_Vw) %*% stats::rnorm(n))

    # Update beta | w, tau2
    prec_beta <- crossprod(X) / tau2 + prior_prec * diag(p)
    V_beta    <- chol2inv(.chol_jitter(prec_beta))
    mu_beta   <- as.numeric(V_beta %*% crossprod(X, y - w_cur) / tau2)
    beta      <- as.numeric(mu_beta + t(.chol_jitter(V_beta)) %*% stats::rnorm(p))

    # Update sigma^2 | w
    shape_s <- prior_ig_a + n / 2
    rate_s  <- prior_ig_b + 0.5 * as.numeric(crossprod(w_cur, Rinv %*% w_cur))
    sigma2  <- 1 / stats::rgamma(1, shape = shape_s, rate = rate_s)

    # Update tau^2 | beta, w
    resid <- y - as.numeric(X %*% beta) - w_cur
    shape_t <- prior_ig_a + n / 2
    rate_t  <- prior_ig_b + 0.5 * sum(resid^2)
    tau2    <- 1 / stats::rgamma(1, shape = shape_t, rate = rate_t)

    beta_draws[iter, ]  <- beta
    sigma2_draws[iter]  <- sigma2
    tau2_draws[iter]    <- tau2
    if (iter > burn) w_mean <- w_mean + w_cur / (nmcmc - burn)
  }

  # Thin post-burn
  keep <- seq(burn + 1L, nmcmc, by = thin)
  out <- structure(list(
    backend      = "gibbs",
    beta_draws   = beta_draws[keep, , drop = FALSE],
    sigma2_draws = sigma2_draws[keep],
    tau2_draws   = tau2_draws[keep],
    phi_hat      = phi_hat,
    w_post_mean  = w_mean,
    X = X, y = y, coords = S,
    formula = formula,
    nmcmc = nmcmc, burn = burn, thin = thin,
    prior_var_beta = prior_var_beta,
    prior_ig_a = prior_ig_a, prior_ig_b = prior_ig_b
  ), class = "edaphos_bhs")
  out
}

#' Predict at new sites from a fitted Bayesian hierarchical spatial model
#'
#' Bayesian kriging: for each posterior draw of `(beta, sigma^2,
#' tau^2)` we sample the latent GP at new locations conditional on
#' the observed latent field, then add iid noise.  Returns posterior
#' mean and quantiles at each `newdata` row.
#'
#' @param object An `edaphos_bhs` fit.
#' @param newdata A data frame with covariates + coordinates matching
#'   the training schema.
#' @param quantiles Quantile levels to return.  Default
#'   `c(0.025, 0.5, 0.975)`.
#' @param n_draws Integer; how many posterior samples to use (capped
#'   by the actual number available in the fit).  Default `500L`.
#' @param ... Unused.
#' @return A data frame with `newdata` rows plus columns `mean`,
#'   `sd`, and one column per quantile.
#' @export
predict.edaphos_bhs <- function(object, newdata, quantiles = c(0.025, 0.5, 0.975),
                                  n_draws = 500L, ...) {
  if (object$backend == "spBayes")
    stop("predict() for spBayes backend is not yet implemented; ",
          "use the pure-R gibbs backend for v2.3.0.", call. = FALSE)
  # Strip the response side of the formula before building X_new
  # (newdata typically has no response column).
  rhs_terms <- stats::delete.response(stats::terms(object$formula))
  X_new <- stats::model.matrix(rhs_terms, data = newdata)
  if (!all(colnames(X_new) %in% colnames(object$X)))
    stop("newdata matrix does not match training columns.", call. = FALSE)
  X_new <- X_new[, colnames(object$X), drop = FALSE]
  coord_cols <- colnames(object$coords)
  S_new <- as.matrix(newdata[, coord_cols, drop = FALSE])

  # Cross-distance + new-new distance
  n_tr  <- nrow(object$coords); n_te <- nrow(S_new)
  D_tr  <- as.matrix(stats::dist(object$coords))
  phi   <- object$phi_hat %||% stats::median(object$phi_draws)
  R_tr  <- exp(-phi * D_tr);  diag(R_tr) <- diag(R_tr) + 1e-8
  R_tr_inv <- solve(R_tr)

  D_cross <- as.matrix(stats::dist(rbind(object$coords,
                                            S_new)))[
    seq_len(n_tr),
    seq(n_tr + 1L, n_tr + n_te), drop = FALSE]
  R_cross <- exp(-phi * D_cross)

  # Posterior draws
  idx <- sample.int(nrow(object$beta_draws),
                     min(n_draws, nrow(object$beta_draws)))
  draws <- matrix(NA_real_, length(idx), n_te)
  for (i in seq_along(idx)) {
    b  <- object$beta_draws[idx[i], ]
    s2 <- object$sigma2_draws[idx[i]]
    t2 <- object$tau2_draws[idx[i]]
    # Posterior mean of latent w at new sites
    w_new_mean <- as.numeric(
      t(R_cross) %*% R_tr_inv %*% object$w_post_mean
    )
    # Mean prediction
    mu_new <- as.numeric(X_new %*% b) + w_new_mean
    # Draw observational noise
    draws[i, ] <- mu_new + stats::rnorm(n_te, 0, sqrt(t2))
  }
  mu  <- colMeans(draws)
  sd_ <- apply(draws, 2L, stats::sd)
  qmat <- apply(draws, 2L, stats::quantile, probs = quantiles,
                 names = FALSE)
  res <- data.frame(mean = mu, sd = sd_)
  for (i in seq_along(quantiles)) {
    qn <- sprintf("q%03.0f",  round(quantiles[i] * 1000))
    res[[qn]] <- qmat[i, ]
  }
  res
}

#' @export
as_edaphos_posterior.edaphos_bhs <- function(x, units = NULL, ...) {
  # Return a posterior over the prediction at an implicit grid:
  # we expose the MARGINAL posterior over the first fitted value
  # (useful for passing to uncertainty_calibrate).  For a full
  # grid posterior use `predict()` directly.
  n_draws <- nrow(x$beta_draws)
  # Fitted values per draw
  fitted_mat <- x$beta_draws %*% t(x$X)
  fitted_mat <- sweep(fitted_mat, 2L, x$w_post_mean, "+")
  edaphos_posterior(
    samples    = fitted_mat,
    method     = "bayesian",
    query_type = "map",
    units      = units,
    metadata   = list(
      backend = x$backend, nmcmc = x$nmcmc, burn = x$burn,
      thin = x$thin, phi_hat = x$phi_hat
    )
  )
}

#' @export
print.edaphos_bhs <- function(x, ...) {
  cat("<edaphos_bhs>  (Pilar 7 -- Bayesian Hierarchical Spatial)\n")
  cat(sprintf("  backend : %s\n", x$backend))
  cat(sprintf("  n_obs   : %d\n", length(x$y)))
  cat(sprintf("  p (covariates + intercept) : %d\n", ncol(x$X)))
  cat(sprintf("  MCMC draws kept : %d\n", nrow(x$beta_draws)))
  if (!is.null(x$phi_hat))
    cat(sprintf("  phi (profile-MLE) : %.4f\n", x$phi_hat))
  # Posterior summaries
  beta_mean <- colMeans(x$beta_draws)
  beta_sd   <- apply(x$beta_draws, 2L, stats::sd)
  cat(sprintf("  beta posterior means:\n"))
  for (i in seq_along(beta_mean)) {
    cat(sprintf("    %-20s %.4f (sd %.4f)\n",
                 names(beta_mean)[i] %||% paste0("beta", i - 1L),
                 beta_mean[i], beta_sd[i]))
  }
  cat(sprintf("  sigma^2 posterior mean : %.4f\n",
               mean(x$sigma2_draws)))
  cat(sprintf("  tau^2   posterior mean : %.4f\n",
               mean(x$tau2_draws)))
  invisible(x)
}
