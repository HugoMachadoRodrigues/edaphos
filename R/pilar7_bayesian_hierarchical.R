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
#   backend = "stan"    : not implemented.
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
#'   the GP rate parameter `phi`.  Default `c(0.01, 10)`.  Note that
#'   `phi` is a **rate**, entering the correlation as
#'   \eqn{\rho(d) = \exp(-\phi d)}, so its units are 1/distance and the
#'   usable bracket depends on whether `coords` are in degrees, metres
#'   or kilometres.  If the profile-MLE lands on an endpoint,
#'   `bhs_fit()` warns: the bracket rather than the data is then
#'   determining the correlation rate, and the spatial variance
#'   fraction can be off by an order of magnitude.
#' @param seed Optional RNG seed.
#' @param verbose Logical.
#' @return An `edaphos_bhs` S3 object.
#'
#' @references
#' Banerjee, S., Carlin, B. P. and Gelfand, A. E. (2014). *Hierarchical
#' Modeling and Analysis for Spatial Data*, 2nd edition. Chapman and
#' Hall/CRC, Boca Raton. \doi{10.1201/b17115}
#'
#' Rue, H., Martino, S. and Chopin, N. (2009). Approximate Bayesian
#' inference for latent Gaussian models by using integrated nested
#' Laplace approximations. *Journal of the Royal Statistical Society:
#' Series B* **71**, 319-392. \doi{10.1111/j.1467-9868.2008.00700.x}
#'
#' Cressie, N. and Wikle, C. K. (2011). *Statistics for Spatio-Temporal
#' Data*. Wiley, Hoboken.
#' @export
bhs_fit <- function(data, formula, coords = c("lon", "lat"),
                      backend = c("gibbs", "rcpp", "spBayes"),
                      nmcmc = 2000L, burn = NULL, thin = 1L,
                      prior_var_beta = 1e3,
                      prior_ig_a = 2, prior_ig_b = 1,
                      phi_range = c(0.01, 10),
                      seed = NULL, verbose = FALSE) {
  backend <- match.arg(backend)
  .assert_type(is.data.frame(data), "data", "a data frame",
                  paste0("an object of class '", class(data)[1L], "'"),
                  hint = "Convert with `as.data.frame(your_object)`.")
  .assert_type(inherits(formula, "formula"), "formula",
                  "a formula", class(formula)[1L],
                  hint = "Use the standard `response ~ x1 + x2 + ...` form.")
  .assert_type(is.character(coords) && length(coords) == 2L,
                  "coords", "a length-2 character vector",
                  paste0(class(coords)[1L], " of length ", length(coords)),
                  hint = "e.g. `c(\"lon\", \"lat\")` matching column names in `data`.")
  .assert_coords(data, coords)
  if (is.null(burn)) burn <- nmcmc %/% 2L
  if (!(burn >= 0L && burn < nmcmc && thin >= 1L)) {
    .stopf("MCMC schedule invalid: burn=%d, nmcmc=%d, thin=%d.",
            burn, nmcmc, thin,
            hint = "Need 0 <= burn < nmcmc and thin >= 1.")
  }

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

  # Reject a rank-deficient design before the sampler starts.
  #
  # The Gibbs chain seeds beta from stats::lm.fit(), which returns NA for
  # aliased columns.  That NA reaches the inverse-gamma rate parameters, so
  # rgamma() warns "NAs produced" and returns NaN, and the next iteration dies
  # inside chol() with "the leading minor of order 1 is not positive" -- a
  # message that tells the caller nothing about the actual problem, which is a
  # constant or collinear covariate.  Name the offending columns instead.
  qr_X <- qr(X)
  if (qr_X$rank < p) {
    aliased <- colnames(X)[is.na(stats::lm.fit(X, y)$coefficients)]
    if (!length(aliased))
      aliased <- setdiff(colnames(X), colnames(X)[qr_X$pivot[seq_len(qr_X$rank)]])
    .stopf(paste("design matrix is rank-deficient: rank %d for %d columns.",
                 "Aliased column(s): %s."),
           qr_X$rank, p, paste(aliased, collapse = ", "),
           hint = paste("A covariate is constant or an exact linear",
                        "combination of the others. Drop it, or check for a",
                        "factor level that no retained row uses."))
  }

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
  # The profile MLE is only meaningful if it is interior to the
  # bracket.  When it lands on an endpoint the likelihood is still
  # climbing and `phi_range` -- not the data -- is what determined the
  # answer.  This is not cosmetic: on a bracket that is too narrow the
  # implied sigma^2 / (sigma^2 + tau^2) can differ by an order of
  # magnitude from its value at the true optimum, which silently
  # reverses the conclusion about whether any spatial structure is
  # present.  phi is a *rate* with units of 1/distance, so the usable
  # bracket depends on the units of `coords` (degrees, metres, km).
  tol <- 1e-3 * max(1, diff(range(phi_range)))
  if (isTRUE(abs(phi_hat - phi_range[1L]) < tol) ||
      isTRUE(abs(phi_hat - phi_range[2L]) < tol)) {
    edge <- if (abs(phi_hat - phi_range[1L]) < tol) "lower" else "upper"
    warning(sprintf(paste(
      "bhs_fit(): the profile-MLE of phi (%.4g) is at the %s end of",
      "phi_range = c(%.4g, %.4g), so the bracket -- not the data --",
      "is setting the correlation rate. Widen phi_range and refit;",
      "the spatial variance fraction is not trustworthy until phi is",
      "interior. phi is a rate (1/distance) in the units of `coords`."),
      phi_hat, edge, phi_range[1L], phi_range[2L]), call. = FALSE)
  }
  if (verbose) message(sprintf("[bhs_fit] profile-MLE phi = %.4f", phi_hat))

  # Gibbs sampler conditional on phi_hat
  R <- exp(-phi_hat * D)
  diag(R) <- diag(R) + 1e-8
  Rinv <- solve(R)

  # v3.5.0 RcppArmadillo fast path -- a self-contained C++ Gibbs
  # sweep that produces statistically equivalent draws to the v3.2.0
  # R fast path with a 5-15x wall-time reduction.
  if (backend == "rcpp") {
    out_rcpp <- bhs_gibbs_rcpp(
      y, X, Rinv, as.integer(nmcmc), as.integer(burn),
      as.integer(thin), prior_var_beta, prior_ig_a, prior_ig_b,
      seed_ = if (is.null(seed)) NULL else as.numeric(seed)
    )
    beta_kept <- out_rcpp$beta_draws
    colnames(beta_kept) <- colnames(X)
    out <- structure(list(
      backend      = "rcpp",
      beta_draws   = beta_kept,
      sigma2_draws = as.numeric(out_rcpp$sigma2_draws),
      tau2_draws   = as.numeric(out_rcpp$tau2_draws),
      phi_hat      = phi_hat,
      w_post_mean  = as.numeric(out_rcpp$w_post_mean),
      X = X, y = y, coords = S,
      formula = formula,
      nmcmc = nmcmc, burn = burn, thin = thin,
      prior_var_beta = prior_var_beta,
      prior_ig_a = prior_ig_a, prior_ig_b = prior_ig_b
    ), class = "edaphos_bhs")
    return(out)
  }

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

  # v3.2.0 fast path: avoid `chol2inv(...)` entirely by drawing from
  # N(mu, V) via a single upper-triangular Cholesky of the PRECISION
  # matrix and two `backsolve` calls.  With `L = chol(P)` (upper
  # triangular) and `z ~ N(0, I)`, the sample
  #
  #     x = mu + backsolve(L, z)
  #
  # has covariance  solve(L) %*% solve(L)^T = (L^T L)^-1 = P^-1 = V,
  # without ever forming V explicitly.  The mean is also recovered
  # from two triangular solves instead of a dense matrix-vector
  # multiply with V.  This replaces 3 (dense inverse + extra Cholesky)
  # calls per iteration with 1 Cholesky + 3 triangular solves.
  # Correctness: the beta and sigma2 / tau2 marginals are bit-for-bit
  # identical (up to RNG-draw order) to the v2.3.0 path; see
  # tests/testthat/test-pilar7-bhs-fastpath.R.
  pre_Ip <- diag(p)  # hoist prior precision
  Rinv_sigma_scaled_cached <- NULL
  last_sigma <- NA_real_
  for (iter in seq_len(nmcmc)) {
    # Update w | beta, sigma2, tau2
    # w ~ N(mu_w, V_w) where   V_w = (Rinv/sigma2 + I/tau2)^-1
    # Precision matrix: P_w = Rinv/sigma2 + (1/tau2)*I
    prec_w <- Rinv * (1 / sigma2)
    diag(prec_w) <- diag(prec_w) + (1 / tau2)
    L_w <- .chol_jitter(prec_w)                     # upper triangular
    rhs_w <- (y - as.numeric(X %*% beta)) / tau2
    # mu_w = solve(P_w, rhs_w) via two triangular solves
    tmp   <- backsolve(L_w, rhs_w, transpose = TRUE)
    mu_w  <- backsolve(L_w, tmp)
    z_w   <- stats::rnorm(n)
    w_cur <- as.numeric(mu_w + backsolve(L_w, z_w))

    # Update beta | w, tau2.  P_b = X'X / tau2 + prior_prec * I
    prec_beta <- crossprod(X) * (1 / tau2)
    diag(prec_beta) <- diag(prec_beta) + prior_prec
    L_b    <- .chol_jitter(prec_beta)
    rhs_b  <- crossprod(X, y - w_cur) / tau2        # column matrix
    tmp_b  <- backsolve(L_b, rhs_b, transpose = TRUE)
    mu_b   <- as.numeric(backsolve(L_b, tmp_b))
    z_b    <- stats::rnorm(p)
    beta   <- as.numeric(mu_b + backsolve(L_b, z_b))

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

  D_cross <- as.matrix(stats::dist(rbind(object$coords,
                                            S_new)))[
    seq_len(n_tr),
    seq(n_tr + 1L, n_tr + n_te), drop = FALSE]
  R_cross <- exp(-phi * D_cross)

  # Exact conditional predictive, per posterior draw.
  #
  # Marginalising the latent field out of the hierarchy leaves
  #   y  ~ N(X beta, Sigma),  Sigma = sigma^2 R + tau^2 I
  # and, for a new site s0 with cross-correlation vector r0,
  #   cov(y0, y) = sigma^2 r0,   var(y0) = sigma^2 + tau^2.
  # The Gaussian conditional is therefore
  #   E[y0 | y] = x0' beta + sigma^2 r0' Sigma^{-1} (y - X beta)
  #   V[y0 | y] = sigma^2 + tau^2 - sigma^4 r0' Sigma^{-1} r0.
  #
  # The second term of the variance is the kriging variance.  It
  # vanishes only when s0 coincides with a training site; as s0 moves
  # away r0 -> 0 and the predictive variance correctly relaxes to the
  # full marginal sigma^2 + tau^2.  Omitting it -- i.e. adding only the
  # nugget -- makes every interval too narrow by exactly the share of
  # residual variance that is spatially structured, which is severe
  # precisely when the spatial model is doing the most work.
  #
  # One symmetric eigendecomposition of R serves every draw:
  #   Sigma^{-1} = U diag(1 / (sigma^2 lambda + tau^2)) U'
  # so each draw costs O(n_tr * n_te) instead of an O(n_tr^3) solve.
  eg   <- eigen(R_tr, symmetric = TRUE)
  U    <- eg$vectors
  lam  <- pmax(eg$values, 0)
  Ut_y <- crossprod(U, object$y)
  Ut_X <- crossprod(U, object$X)
  Ut_r <- crossprod(U, R_cross)          # n_tr x n_te, draw-independent
  Ut_r2 <- Ut_r^2

  idx <- sample.int(nrow(object$beta_draws),
                     min(n_draws, nrow(object$beta_draws)))
  draws <- matrix(NA_real_, length(idx), n_te)
  for (i in seq_along(idx)) {
    b  <- object$beta_draws[idx[i], ]
    s2 <- object$sigma2_draws[idx[i]]
    t2 <- object$tau2_draws[idx[i]]

    dinv  <- 1 / (s2 * lam + t2)
    Ut_e  <- Ut_y - Ut_X %*% b           # U' (y - X beta)

    mu_new <- as.numeric(X_new %*% b) +
      s2 * as.numeric(crossprod(Ut_r, dinv * Ut_e))
    v_new  <- s2 + t2 - s2^2 * as.numeric(colSums(dinv * Ut_r2))
    v_new  <- pmax(v_new, .Machine$double.eps)

    draws[i, ] <- mu_new + stats::rnorm(n_te, 0, sqrt(v_new))
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
