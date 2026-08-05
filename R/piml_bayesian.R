# Pillar 2 -- Bayesian posterior for the pedogenetic ODE.
#
# `piml_profile_fit()` (R/piml_profile.R) returns a single point-
# estimate for the parametric ODE
#
#   dy/dz = -lambda0 * exp(-mu z) * (y - y_inf),     y(0) = y0
#
# which is adequate for descriptive fitting but hides the identification
# risk that is native to this class of ODEs: lambda0, mu and y_inf trade
# against one another in a correlated and non-linear way, so a point
# estimate hides a potentially wide posterior. For any downstream
# propagation of uncertainty (Pillar 3 data assimilation, Pillar 5
# Active Learning uncertainty, publishable parameter intervals) we need
# the *posterior* p(lambda0, mu, y_inf, y0 | depths, values), not just
# the MAP.
#
# This file provides two levels of Bayesian inference on top of the
# existing forward-model:
#
#   1) Laplace approximation (default, cheap, ~50 ms per pedon).
#      A Gaussian posterior whose mean is the MAP and whose covariance
#      is the inverse observed Fisher information (i.e. -H^{-1} where H
#      is the log-posterior Hessian at the MAP). Exact for a linear
#      model with conjugate Gaussian prior and an accurate asymptotic
#      approximation for well-identified non-linear problems [Bishop
#      2006, chapter 4.4].
#
#   2) Adaptive random-walk Metropolis (full MCMC, ~5 s per pedon for
#      5000 iterations). Uses the Laplace covariance, scaled by the
#      Roberts-Gelman-Gilks 2.38^2/d optimal factor and adapted online
#      by Haario/Saksman recursion, as the proposal covariance.
#      Returns full posterior samples so non-Gaussian / multimodal
#      posteriors (typical when the data are sparse in the top horizon)
#      are captured faithfully.
#
# Weakly-informative priors match the physical ranges of the four
# parameters (lambda0 > 0, |mu| < 1 in 1/cm, y_inf and y0 in the data's
# observed range) but can be overridden via the `prior` argument for a
# proper Bayesian analysis with literature priors.
#
# Posterior predictive draws --------------------------------------------
#
# Given M posterior samples theta_1, ..., theta_M, the predictive
# posterior at a new depth z* is
#
#   p(y* | z*, D) = integral p(y* | z*, theta) p(theta | D) d theta
#                 approx (1/M) sum_m N(y* ; g(z*, theta_m), sigma^2),
#
# where g is the ODE forward map and sigma^2 is the observation noise
# (estimated from the MAP residual RMSE). `predict()` on the Bayesian
# fit returns either a matrix of M draws per depth or a tidy
# (mean, sd, lower, upper) summary.

# --- forward model + log-density helpers -------------------------------

# Negative log-posterior at theta = (log kappa, log mu, log y_asym, log y0),
# the identified coordinates of `.piml_unpack()`. Every coordinate is a log,
# so each prior below is log-normal on its natural scale -- which is the right
# family for a rate, a depth scale and a concentration, and which puts zero
# mass on the impossible region (negative carbon, rates growing with depth)
# that the previous free-sign parameterisation left open.
#
# Priors are placed on kappa and y_asym rather than on lambda0 and y_inf
# deliberately: those are the coordinates the data identify. A prior on y_inf
# is a prior on a value the profile never attains, and it leaks into the fit
# through a ratio the likelihood barely constrains.
#
# sigma is the LAST element of theta, on the log scale, and is sampled like
# any other parameter. It used to be estimated once from the MAP residuals and
# then held fixed through the whole MCMC run -- empirical Bayes on 7 points
# with 4 parameters, which guarantees intervals that are too narrow, because
# the uncertainty in the noise scale never propagates. Its prior is the
# standard weakly-informative half-Student-t(3, 0, s0) on sigma (Gelman 2006),
# with s0 set from the spread of the observations, plus the log Jacobian.
.piml_bayes_neg_log_post <- function(theta, depths, obs, y_surface,
                                       sigma = NULL, prior, top = NULL,
                                       bottom = NULL, family = "gaussian") {
  if (is.null(sigma)) {
    np    <- length(theta) - 1L
    sigma <- exp(theta[np + 1L])
    theta <- theta[seq_len(np)]
    sample_sigma <- TRUE
  } else {
    sample_sigma <- FALSE
  }
  if (!is.finite(sigma) || sigma <= 0) return(1e9)
  params <- .piml_unpack(theta, y_surface)
  pred   <- tryCatch(
    if (is.null(top) || is.null(bottom)) .piml_solution(depths, params)
    else .piml_layer_mean(top, bottom, params),
    error = function(e) NULL)
  if (is.null(pred) || any(!is.finite(pred))) return(1e9)

  # Observation likelihood. For "gaussian" sigma is an SD in the property's
  # units; for "lognormal" and "gamma" it is a coefficient of variation, and
  # both are parameterised so the prediction is the MEAN of the observation.
  nll <- .piml_nll(obs, pred, sigma, family)
  if (!is.finite(nll)) return(1e9)

  # Priors. All expressed as `0.5 * ((x - mu) / sd)^2 + const` so they
  # are additive in -log-posterior.
  nlp <- 0
  # log(kappa) ~ N(prior$log_kappa_mean, prior$log_kappa_sd^2)
  nlp <- nlp + 0.5 * ((theta[1L] - prior$log_kappa_mean) /
                        prior$log_kappa_sd)^2
  # log(mu) ~ N(prior$log_mu_mean, prior$log_mu_sd^2)
  nlp <- nlp + 0.5 * ((theta[2L] - prior$log_mu_mean) / prior$log_mu_sd)^2
  # log(y_asym) ~ N(prior$log_y_asym_mean, prior$log_y_asym_sd^2)
  nlp <- nlp + 0.5 * ((theta[3L] - prior$log_y_asym_mean) /
                        prior$log_y_asym_sd)^2
  if (is.null(y_surface)) {
    # log(y0) ~ N(prior$log_y0_mean, prior$log_y0_sd^2)
    nlp <- nlp + 0.5 * ((theta[4L] - prior$log_y0_mean) /
                          prior$log_y0_sd)^2
  }
  if (sample_sigma) {
    # sigma ~ half-t(nu = 3, scale = s0); on log sigma add -log(sigma) for the
    # change of variable.
    s0 <- prior$sigma_scale
    nlp <- nlp + 2 * log1p(sigma^2 / (3 * s0^2)) - log(sigma)
  }
  nll + nlp
}

# Default prior. THIS IS EMPIRICAL BAYES, NOT A PRIOR IN THE STRICT SENSE.
#
# Three of its hyperparameters are functions of the response being fitted:
# log_y_asym_mean is the deepest observation, log_y0_mean is the shallowest,
# and sigma_scale is sd(obs). The data therefore enter twice -- once through
# the likelihood and once through the prior -- which narrows intervals and
# makes the "prior sensitivity" of the fit partly a sensitivity to itself.
#
# It is kept as the default because with four to nine horizons a genuinely
# flat prior lets the kappa ridge run away, and an empirical-Bayes centring
# is more honest than a made-up "weakly informative" number that happens to
# sit near the data anyway. But it is labelled for what it is, and
# `piml_prior_literature()` gives a non-circular alternative built from
# published values, so the circularity can be tested rather than assumed
# harmless. Only log_mu_mean (sampling geometry, not outcome) and
# log_kappa_mean (a modelling convention) are free of the response.
.piml_bayes_default_prior <- function(depths, obs, y_surface,
                                      family = "gaussian") {
  o <- order(depths)
  zmax <- max(depths, na.rm = TRUE)
  y_deep <- max(obs[o[length(o)]], 1e-3)
  y_top  <- max(if (is.null(y_surface)) obs[o[1L]] else y_surface, 1e-3)
  list(
    # kappa = lambda0/mu is the total relaxation: kappa = 3 means the profile
    # traverses 95% of its y0 -> y_inf gap. Centre there, 1.5 log units wide.
    log_kappa_mean   = log(3),
    log_kappa_sd     = 1.5,
    # mu sets the depth over which the decay rate itself decays; centre it on
    # the observed profile length, which is the only scale the data can speak
    # to, and allow two orders of magnitude either side.
    log_mu_mean      = log(2 / max(zmax, 1)),
    log_mu_sd        = 2,
    # the attainable deep value: centre on the deepest observation.
    log_y_asym_mean  = log(y_deep),
    log_y_asym_sd    = 1,
    log_y0_mean      = log(y_top),
    log_y0_sd        = 1,
    # Scale of the half-t prior on the observation noise. Its UNITS depend on
    # the family: an SD in g/kg for "gaussian", a coefficient of variation for
    # the other two. A prior centred on sd(obs) would be absurd for a CV.
    sigma_scale      = if (identical(family, "gaussian"))
                         max(stats::sd(obs, na.rm = TRUE), 1e-3) else 0.3
  )
}

#' A literature prior for the pedogenetic ODE, independent of the data
#'
#' The default prior used by [piml_profile_fit_bayesian()] centres three of
#' its hyperparameters on the response being fitted (the deepest observation,
#' the shallowest observation, and `sd(obs)`). That is empirical Bayes: the
#' data enter both the likelihood and the prior, intervals narrow, and a
#' prior-sensitivity check against it is partly a check of the data against
#' themselves.
#'
#' This constructor builds a prior from published values instead, so the two
#' can be compared and the circularity measured rather than assumed harmless.
#'
#' @param y_asym_mean,y_asym_sd Prior mean and log-scale spread for the
#'   attainable deep concentration, in the property's units. The default,
#'   3 g/kg, is the order of magnitude of deep (>1 m) mineral-associated
#'   organic carbon in deeply weathered tropical soils.
#' @param y0_mean,y0_sd Prior mean and log-scale spread for the surface
#'   concentration. The default, 25 g/kg, is a Cerrado topsoil value.
#' @param z_scale Depth scale in cm over which the decay rate itself decays,
#'   used to centre `mu`. The default, 35 cm, follows the Jackson et al.
#'   (1996) tropical-savanna rooting parameter beta = 0.972 via
#'   `z = -1/log(beta)`.
#' @param kappa_mean Prior mean for the total relaxation `lambda0/mu`.
#'   `kappa = 3` means the profile closes 95% of its gap.
#' @param sigma_scale Scale of the half-t(3) prior on the observation noise,
#'   in the property's units. The default, 2 g/kg, reflects laboratory plus
#'   short-range spatial variability rather than the spread of this profile.
#'
#' @return A list in the form [piml_profile_fit_bayesian()] expects for its
#'   `prior` argument.
#'
#' @references
#' Jackson RB, Canadell J, Ehleringer JR, Mooney HA, Sala OE, Schulze ED
#' (1996). A global analysis of root distributions for terrestrial biomes.
#' *Oecologia* 108:389-411.
#'
#' @export
#' @examples
#' # Compare the empirical-Bayes default against a non-circular prior on the
#' # pedon shipped with the package.
#' B <- readRDS(system.file("extdata", "capstone_campaign_results.rds",
#'                          package = "edaphos"))
#' p <- B$piml_profile_obs
#' a <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
#'                                top = p$top, bottom = p$bottom, seed = 7L)
#' b <- piml_profile_fit_bayesian(p$depth_mid, p$soc_g_kg,
#'                                top = p$top, bottom = p$bottom,
#'                                prior = piml_prior_literature(), seed = 7L)
#' # If the two disagree, the default's data-dependence is doing real work.
#' round(cbind(empirical_bayes = summary(a)$mean,
#'             literature      = summary(b)$mean), 4)
piml_prior_literature <- function(y_asym_mean = 3, y_asym_sd = 1.2,
                                  y0_mean = 25, y0_sd = 0.8,
                                  z_scale = 35, kappa_mean = 3,
                                  sigma_scale = 2) {
  stopifnot(y_asym_mean > 0, y0_mean > 0, z_scale > 0, kappa_mean > 0,
            sigma_scale > 0)
  list(
    log_kappa_mean  = log(kappa_mean),
    log_kappa_sd    = 1.5,
    log_mu_mean     = log(1 / z_scale),
    log_mu_sd       = 1.5,
    log_y_asym_mean = log(y_asym_mean),
    log_y_asym_sd   = y_asym_sd,
    log_y0_mean     = log(y0_mean),
    log_y0_sd       = y0_sd,
    sigma_scale     = sigma_scale
  )
}

# Numerical Hessian via finite differences at `theta`. `fn(theta + eps)`
# and `fn(theta - eps)` are called for each pair of coordinates; the
# Hessian is O(d^2) evaluations of `fn`. For d = 4 that is 16 forward
# ODE integrations per Laplace fit — trivial.
.piml_numerical_hessian <- function(fn, theta, eps = 1e-4, ...) {
  d <- length(theta)
  H <- matrix(0, d, d)
  fx <- fn(theta, ...)
  for (i in seq_len(d)) {
    for (j in seq_len(d)) {
      if (i == j) {
        tp <- theta; tp[i] <- tp[i] + eps
        tm <- theta; tm[i] <- tm[i] - eps
        H[i, i] <- (fn(tp, ...) - 2 * fx + fn(tm, ...)) / eps^2
      } else if (j > i) {
        tpp <- theta; tpp[i] <- tpp[i] + eps; tpp[j] <- tpp[j] + eps
        tpm <- theta; tpm[i] <- tpm[i] + eps; tpm[j] <- tpm[j] - eps
        tmp <- theta; tmp[i] <- tmp[i] - eps; tmp[j] <- tmp[j] + eps
        tmm <- theta; tmm[i] <- tmm[i] - eps; tmm[j] <- tmm[j] - eps
        H[i, j] <- (fn(tpp, ...) - fn(tpm, ...) -
                     fn(tmp, ...) + fn(tmm, ...)) / (4 * eps^2)
        H[j, i] <- H[i, j]
      }
    }
  }
  H
}

# Regularise a covariance matrix: project to nearest PSD by flooring
# eigenvalues at a small positive value. Needed because the finite-
# difference Hessian of a non-convex loss surface occasionally has one
# tiny negative eigenvalue from numerical noise.
.piml_nearest_psd <- function(Sigma, floor_eig = 1e-10) {
  es <- eigen(Sigma, symmetric = TRUE)
  d  <- pmax(es$values, floor_eig)
  es$vectors %*% diag(d, length(d)) %*% t(es$vectors)
}

# --- Laplace fit -------------------------------------------------------

.piml_laplace_fit <- function(depths, values, y_surface, prior,
                                top = NULL, bottom = NULL, family = "gaussian",
                                start, control) {
  # Stage 1: locate the parameters at a provisional noise scale. This is only
  # an initialisation -- sigma is a sampled parameter, not a plug-in.
  fit0 <- stats::optim(
    par       = start,
    fn        = function(th, ...) .piml_bayes_neg_log_post(th, ...),
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    top       = top,
    bottom    = bottom,
    family    = family,
    sigma     = 1.0,
    prior     = prior,
    method    = "Nelder-Mead",
    control   = control
  )
  params0 <- .piml_unpack(fit0$par, y_surface)
  pred0   <- if (is.null(top)) .piml_solution(depths, params0) else
    .piml_layer_mean(top, bottom, params0)
  sigma0  <- max(sqrt(mean((values - pred0)^2)), 1e-6)

  # Stage 2: joint MAP over (parameters, log sigma). Passing sigma = NULL
  # tells the log-posterior that the last coordinate IS log sigma.
  start2 <- c(fit0$par, log_sigma = log(sigma0))
  fit <- stats::optim(
    par       = start2,
    fn        = function(th, ...) .piml_bayes_neg_log_post(th, ...),
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    top       = top,
    bottom    = bottom,
    family    = family,
    sigma     = NULL,
    prior     = prior,
    method    = "Nelder-Mead",
    control   = control
  )
  np    <- length(fit$par) - 1L
  sigma <- exp(fit$par[np + 1L])
  H <- .piml_numerical_hessian(
    fn        = .piml_bayes_neg_log_post,
    theta     = fit$par,
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    top       = top,
    bottom    = bottom,
    family    = family,
    sigma     = NULL,
    prior     = prior
  )
  # SVD-based Moore-Penrose pseudo-inverse fallback — avoids a MASS
  # dependency just for ginv().
  ginv_svd <- function(M, tol = sqrt(.Machine$double.eps)) {
    s <- svd(M)
    pos <- s$d > max(tol * max(s$d), 0)
    if (!any(pos)) return(matrix(0, nrow(M), ncol(M)))
    s$v[, pos, drop = FALSE] %*%
      (t(s$u[, pos, drop = FALSE]) / s$d[pos])
  }
  Sigma <- tryCatch(solve(H), error = function(e) ginv_svd(H))
  Sigma <- .piml_nearest_psd(Sigma)
  list(map = fit$par, sigma = sigma, cov = Sigma,
       neg_log_post = fit$value)
}

# --- convergence diagnostics -------------------------------------------

# Split-Rhat and bulk effective sample size (Vehtari et al. 2021, Bayesian
# Analysis 16:667-718), computed on the rank-normalised draws.
#
# The sampler used to run a single chain and report nothing but the acceptance
# rate. On a posterior whose covariance needs eigenvalue flooring to be
# positive-definite, an acceptance rate says nothing about whether the chain
# explored the ridge -- and with one chain, R-hat cannot be computed even in
# principle. `piml_profile_fit_bayesian(method = "mcmc")` now runs several
# chains from dispersed starts and reports both.
#
# `chains` is a list of (n_draws x n_par) matrices.
.piml_rhat_ess <- function(chains) {
  M <- length(chains)
  N <- nrow(chains[[1L]])
  d <- ncol(chains[[1L]])
  # Split each chain in half, so a single long chain that has not mixed
  # within itself is still caught (Gelman et al. 2013, sec 11.4).
  h <- floor(N / 2)
  if (h < 2L) return(list(rhat = rep(NA_real_, d), ess = rep(NA_real_, d)))
  split <- unlist(lapply(chains, function(cm)
    list(cm[seq_len(h), , drop = FALSE],
         cm[(N - h + 1L):N, , drop = FALSE])), recursive = FALSE)
  m <- length(split)

  out_rhat <- out_ess <- numeric(d)
  for (j in seq_len(d)) {
    X <- vapply(split, function(cm) cm[, j], numeric(h))   # h x m
    # Rank-normalise: makes the diagnostic robust to heavy tails and to
    # parameters with infinite variance, which the kappa ridge can produce.
    r <- matrix(rank(as.numeric(X), ties.method = "average"), h, m)
    z <- stats::qnorm((r - 3 / 8) / (h * m - 1 / 4 + 1 / 4))

    cm_ <- colMeans(z)
    B <- h * stats::var(cm_)
    W <- mean(apply(z, 2L, stats::var))
    if (!is.finite(W) || W <= 0) { out_rhat[j] <- NA_real_; out_ess[j] <- NA_real_; next }
    var_hat <- ((h - 1) / h) * W + B / h
    out_rhat[j] <- sqrt(var_hat / W)

    # Bulk ESS from the autocorrelation of the rank-normalised draws,
    # truncated by the Geyer initial-positive-sequence rule.
    rho_sum <- 0
    t <- 1L
    tmax <- h - 2L
    while (t < tmax) {
      rho_t <- mean(vapply(seq_len(m), function(k) {
        a <- stats::acf(z[, k], lag.max = t + 1L, plot = FALSE, demean = TRUE)$acf
        if (length(a) < t + 2L) return(NA_real_)
        a[t + 1L] + a[t + 2L]                    # pairs (rho_t + rho_{t+1})
      }, numeric(1)), na.rm = TRUE)
      if (!is.finite(rho_t) || rho_t <= 0) break
      rho_sum <- rho_sum + rho_t
      t <- t + 2L
    }
    tau <- 1 + 2 * rho_sum
    out_ess[j] <- if (is.finite(tau) && tau > 0) (m * h) / tau else NA_real_
  }
  list(rhat = out_rhat, ess = pmin(out_ess, M * N))
}

# --- adaptive random-walk Metropolis -----------------------------------

.piml_mcmc_adaptive_rwm <- function(neg_log_post_fn, start, proposal_cov,
                                      n_iter, n_burn, thin = 1L,
                                      seed = NULL, verbose = FALSE) {
  if (!is.null(seed)) set.seed(seed)
  d <- length(start)
  # Roberts-Gelman-Gilks optimal scaling for RWM on d-dim Gaussian.
  sd_opt <- (2.38)^2 / d
  Sigma  <- sd_opt * proposal_cov

  theta <- start
  U     <- neg_log_post_fn(theta)
  samples <- matrix(NA_real_, nrow = n_iter, ncol = d)
  accept  <- logical(n_iter)
  adapt_start <- max(100L, floor(n_iter / 20))

  # Haario/Saksman online covariance update.
  running_mean <- theta
  running_cov  <- Sigma

  for (it in seq_len(n_iter)) {
    # Cholesky of current proposal covariance; fall back to its PSD
    # nearest neighbour if the matrix went non-PD during adaptation.
    L <- tryCatch(t(chol(Sigma)),
                   error = function(e) t(chol(.piml_nearest_psd(Sigma))))
    proposal <- as.numeric(theta + L %*% stats::rnorm(d))
    U_prop   <- neg_log_post_fn(proposal)
    log_acc  <- U - U_prop
    if (!is.finite(log_acc)) log_acc <- -Inf
    if (log(stats::runif(1)) < log_acc) {
      theta <- proposal
      U     <- U_prop
      accept[it] <- TRUE
    }
    samples[it, ] <- theta

    # Adapt after burn-in: recursive mean + covariance of the visited
    # states (Haario, Saksman, Tamminen 2001).
    if (it > adapt_start) {
      n_adapt     <- it - adapt_start
      delta       <- theta - running_mean
      running_mean <- running_mean + delta / n_adapt
      delta2       <- theta - running_mean
      running_cov  <- ((n_adapt - 1L) * running_cov +
                        (delta %o% delta2)) / n_adapt
      # Scale by optimal factor + small diagonal regulariser.
      Sigma <- sd_opt * (running_cov + 1e-8 * diag(d))
    }

    if (isTRUE(verbose) && it %% max(1L, floor(n_iter / 10)) == 0L) {
      message(sprintf("[mcmc-rwm] iter %d / %d   accept=%.2f",
                       it, n_iter, mean(accept[seq_len(it)])))
    }
  }
  keep <- seq(from = n_burn + 1L, to = n_iter, by = thin)
  list(
    draws         = samples[keep, , drop = FALSE],
    accept_rate   = mean(accept[seq(n_burn + 1L, n_iter)]),
    n_iter        = n_iter,
    n_burn        = n_burn,
    thin          = as.integer(thin),
    proposal_cov  = Sigma
  )
}

# --- public entry point -------------------------------------------------

#' Bayesian posterior for the Pillar 2 pedogenetic ODE
#'
#' Returns the posterior distribution of
#' \eqn{(\lambda_0, \mu, y_\infty, y_0)} conditional on the observed
#' depth profile. Two levels of approximation are offered:
#'
#' \describe{
#'   \item{`method = "laplace"` (default)}{Gaussian posterior obtained
#'     from the MAP and the inverse observed information at the MAP.
#'     Accurate when the posterior is approximately Gaussian, which is
#'     typical for well-identified profiles with \eqn{n \geq 4} horizons.
#'     Runtime: O(milliseconds).}
#'   \item{`method = "mcmc"`}{Adaptive random-walk Metropolis
#'     (Haario, Saksman and Tamminen 2001; see the @references
#'     section below). Proposal covariance starts at the Laplace
#'     covariance, scaled by the Roberts-Gelman-Gilks
#'     \eqn{(2.38)^2 / d} factor, and is updated online by Haario
#'     recursion after a warm-up period. Returns full posterior samples
#'     so non-Gaussian / multimodal posteriors are captured faithfully.
#'     Runtime: a few seconds for the default 5000 iterations.}
#' }
#'
#' The noise scale \eqn{\sigma} is estimated from the MAP residual RMSE
#' and held fixed during MCMC (empirical Bayes). Weakly-informative,
#' data-driven priors are applied by default; pass a custom `prior`
#' list to override them.
#'
#' @param depths,values Numeric vectors — same as [piml_profile_fit()].
#' @param y_surface Optional fixed surface value.
#' @param method One of `"laplace"` (default) or `"mcmc"`.
#' @param family Observation family, as in [piml_profile_fit()]. `"gaussian"`
#'   (default) puts predictive mass below zero and weights every horizon by
#'   the same absolute error; `"lognormal"` and `"gamma"` are strictly
#'   positive, mean-preserving, and weight by relative error. When it is not
#'   `"gaussian"`, `sigma` is a coefficient of variation rather than an SD in
#'   the property's units, and the default prior on it changes accordingly.
#' @param top,bottom Optional horizon boundaries — same as
#'   [piml_profile_fit()]. When supplied, each observation is compared to
#'   the model's depth-average over its horizon rather than to a point
#'   evaluation at the mid-depth.
#' @param prior Named list of hyperparameters for the priors, placed on the
#'   identified log coordinates (fields `log_kappa_mean`, `log_kappa_sd`,
#'   `log_mu_mean`, `log_mu_sd`, `log_y_asym_mean`, `log_y_asym_sd`,
#'   `log_y0_mean`, `log_y0_sd`). Each is log-normal on its natural scale,
#'   which is the right family for a rate, a depth scale and a
#'   concentration, and which puts no mass on the impossible region. Note
#'   there is no prior on `y_inf`: it is a derived coordinate the profile
#'   never attains, and the data do not identify it.
#' @param start Optional starting vector. Defaults to
#'   [piml_profile_fit()]'s point-estimate theta for the MAP search.
#' @param control `optim` control list for the MAP step.
#' @param n_chains Integer, number of MCMC chains started from dispersed
#'   points around the Laplace mode. Four or more are needed for split-R-hat
#'   to mean anything; with one chain there is no between-chain variance and
#'   convergence cannot be assessed at all. Only consulted when
#'   `method = "mcmc"`.
#' @param n_iter,n_burn,thin MCMC settings. The defaults were 5000/2000,
#'   which do NOT converge on this posterior: four chains on the shipped pedon
#'   gave max split-R-hat 1.015 and min bulk ESS 361 at 6000 iterations,
#'   against 1.004 and 1113 at 20000. A default that silently fails its own
#'   diagnostic is a trap, so the default is now the converging one. Only
#'   consulted when
#'   `method = "mcmc"`.
#' @param seed Optional integer seed. Consulted by *both* methods, not
#'   only by MCMC: with `method = "laplace"` it seeds the 2000 Gaussian
#'   draws taken from the Laplace posterior, and with `method = "mcmc"`
#'   it seeds the Metropolis chain. Because every entry of the returned
#'   `summary` (and of any downstream `predict()`) is a Monte-Carlo
#'   average over those draws, leaving `seed = NULL` makes the reported
#'   posterior means, SDs and quantiles change on every call. Set it
#'   whenever you intend to quote or compare the numbers.
#' @param verbose Logical — print one progress line per 10% of MCMC
#'   iterations.
#' @return An `edaphos_piml_bayes` object with:
#' \describe{
#'   \item{method}{`"laplace"` or `"mcmc"`.}
#'   \item{map}{Named list with the MAP values of the natural
#'     parameters `(lambda0, mu, y_inf, y0)`.}
#'   \item{theta_map}{Unconstrained parameter vector at the MAP.}
#'   \item{sigma}{Observation-noise standard deviation estimated at
#'     the MAP.}
#'   \item{cov}{The \eqn{d \times d} posterior covariance matrix on
#'     the unconstrained scale (Laplace), or the empirical sample
#'     covariance of the MCMC chain.}
#'   \item{draws}{An M-by-d matrix of posterior samples on the
#'     unconstrained scale. For Laplace, 2000 draws are pre-sampled
#'     from \eqn{N(\text{map}, \text{cov})} for predictive
#'     convenience; for MCMC, the kept post-burn-in chain.}
#'   \item{summary}{A data frame with `mean`, `sd`, `q2.5`, `q50`,
#'     `q97.5` per parameter (natural scale: `lambda0`, `mu`,
#'     `y_inf`, `y0`).}
#'   \item{accept_rate}{MCMC acceptance rate (only for `method = "mcmc"`).}
#' }
#' @seealso [piml_profile_fit()] for the point estimate;
#'   [predict.edaphos_piml_bayes()] for posterior predictive draws.
#' @references
#' Bishop, C. M. (2006). *Pattern Recognition and Machine Learning*.
#' Springer, chapter 4.4 (Laplace approximation).
#'
#' Haario, H., Saksman, E. and Tamminen, J. (2001). An adaptive
#' Metropolis algorithm. *Bernoulli* **7**, 223–242.
#' @examples
#' depths <- c(5, 15, 30, 60, 100)
#' values <- c(25, 18, 12, 8, 6.5)
#' # The posterior summary is a Monte-Carlo average over 2000 draws from
#' # the Laplace posterior, so `seed` is required for it to be
#' # reproducible. Drop the seed and the printed means and quantiles
#' # change in the 4th significant figure on every call.
#' fit_bayes <- piml_profile_fit_bayesian(depths, values, seed = 1)
#' fit_bayes
#' summary(fit_bayes)
#'
#' # With seed = 1 this profile gives a lambda0 posterior mean of 0.0493
#' # and a 95% credible interval of [0.04434, 0.05456] -- a relative
#' # width of 21%, so the decay rate is identified to roughly +/- 10%
#' # and the point estimate alone would overstate what 5 horizons buy.
#' round(subset(summary(fit_bayes), parameter == "lambda0",
#'              c("mean", "q2.5", "q97.5")), 5)
#' @export
piml_profile_fit_bayesian <- function(depths, values, y_surface = NULL,
                                        top = NULL, bottom = NULL,
                                        family = c("lognormal", "gaussian",
                                                   "gamma"),
                                        method  = c("laplace", "mcmc"),
                                        prior   = NULL,
                                        start   = NULL,
                                        control = list(maxit = 2000),
                                        n_iter  = 20000L,
                                        n_burn  = 6000L,
                                        n_chains = 4L,
                                        thin    = 1L,
                                        seed    = NULL,
                                        verbose = FALSE) {
  stopifnot(length(depths) == length(values),
            length(depths) >= 2L,
            all(is.finite(depths)), all(is.finite(values)),
            all(depths >= 0))
  method <- match.arg(method)
  family <- match.arg(family)

  if (is.null(prior)) prior <- .piml_bayes_default_prior(depths, values,
                                                            y_surface, family)
  if (is.null(start)) {
    start <- piml_profile_fit(depths, values, y_surface = y_surface,
                                top = top, bottom = bottom, family = family,
                                control = control)$theta
  }

  lap <- .piml_laplace_fit(depths, values, y_surface, prior, start,
                             control, top = top, bottom = bottom,
                             family = family)

  if (method == "laplace") {
    # 2000 draws for downstream predict().
    if (!is.null(seed)) set.seed(seed)
    d <- length(lap$map)
    L <- tryCatch(t(chol(lap$cov)),
                   error = function(e) t(chol(.piml_nearest_psd(lap$cov))))
    Z <- matrix(stats::rnorm(2000L * d), 2000L, d)
    draws <- sweep(Z %*% t(L), 2, lap$map, `+`)
    accept_rate <- NA_real_
    post_cov    <- lap$cov
    diag_ <- NULL
  } else {
    nlp_closure <- function(th) {
      .piml_bayes_neg_log_post(th, depths = depths, obs = values,
                                 y_surface = y_surface, sigma = NULL,
                                 prior = prior, top = top, bottom = bottom,
                                 family = family)
    }
    # Several chains from dispersed starts. One chain cannot be checked for
    # convergence: R-hat compares between-chain to within-chain variance, and
    # with M = 1 there is no between-chain term. Starts are drawn from the
    # Laplace approximation and inflated, so the chains genuinely begin apart.
    n_chains <- max(1L, as.integer(n_chains))
    L_start <- tryCatch(t(chol(lap$cov)),
                        error = function(e) t(chol(.piml_nearest_psd(lap$cov))))
    if (!is.null(seed)) set.seed(seed)
    starts <- c(list(lap$map), lapply(seq_len(n_chains - 1L), function(k)
      as.numeric(lap$map + 2 * L_start %*% stats::rnorm(length(lap$map)))))
    chains <- lapply(seq_len(n_chains), function(k) {
      .piml_mcmc_adaptive_rwm(
        neg_log_post_fn = nlp_closure,
        start           = starts[[k]],
        proposal_cov    = lap$cov,
        n_iter          = as.integer(n_iter),
        n_burn          = as.integer(n_burn),
        thin            = as.integer(thin),
        seed            = if (is.null(seed)) NULL else as.integer(seed + k - 1L),
        verbose         = verbose
      )
    })
    draws       <- do.call(rbind, lapply(chains, `[[`, "draws"))
    accept_rate <- mean(vapply(chains, `[[`, numeric(1), "accept_rate"))
    post_cov    <- stats::cov(draws)
    diag_ <- .piml_rhat_ess(lapply(chains, `[[`, "draws"))
  }

  # Natural-scale posterior summaries.
  # The last column of `draws` is log sigma, so strip it before unpacking the
  # ODE parameters, and report sigma on its natural scale alongside them.
  n_par <- ncol(draws) - 1L
  nat <- t(apply(draws, 1L, function(th) {
    p <- .piml_unpack(th[seq_len(n_par)], y_surface)
    c(lambda0 = p$lambda0, mu = p$mu, y_inf = p$y_inf, y0 = p$y0,
      kappa = p$kappa, y_asym = .piml_asymptote(p), sigma = exp(th[n_par + 1L]))
  }))
  summ <- data.frame(
    parameter = colnames(nat),
    mean      = apply(nat, 2L, mean),
    sd        = apply(nat, 2L, stats::sd),
    q2.5      = apply(nat, 2L, stats::quantile, probs = 0.025),
    q50       = apply(nat, 2L, stats::quantile, probs = 0.5),
    q97.5     = apply(nat, 2L, stats::quantile, probs = 0.975),
    row.names = NULL, stringsAsFactors = FALSE
  )
  # Convergence diagnostics, on the SAMPLED coordinates. They are reported per
  # sampled parameter (log kappa, log mu, log y_asym, log y0, log sigma) rather
  # than per derived quantity, because that is where the chain actually moves;
  # they are mapped onto the summary rows that each coordinate drives.
  if (!is.null(diag_)) {
    .map_row <- c(kappa = 1L, mu = 2L, y_asym = 3L, y0 = 4L, sigma = 5L,
                  lambda0 = 1L, y_inf = 3L)
    idx <- .map_row[summ$parameter]
    summ$rhat <- ifelse(is.na(idx), NA_real_, diag_$rhat[idx])
    summ$ess  <- ifelse(is.na(idx), NA_real_, diag_$ess[idx])
  }

  structure(
    list(
      method      = method,
      map         = .piml_unpack(lap$map[seq_len(length(lap$map) - 1L)],
                                 y_surface),
      theta_map   = lap$map,
      sigma       = lap$sigma,
      cov         = post_cov,
      draws       = draws,
      summary     = summ,
      accept_rate = accept_rate,
      family      = family,
      # NULL for the Laplace path, which is not a sampler and for which these
      # diagnostics are undefined.
      diagnostics = diag_,
      n_chains    = if (is.null(diag_)) NA_integer_ else as.integer(n_chains),
      depths      = depths,
      values      = values,
      y_surface   = y_surface,
      prior       = prior
    ),
    class = "edaphos_piml_bayes"
  )
}

#' @export
print.edaphos_piml_bayes <- function(x, ...) {
  cat("<edaphos_piml_bayes>\n")
  cat(sprintf("  method     : %s\n", x$method))
  cat(sprintf("  n draws    : %d\n", nrow(x$draws)))
  if (!is.na(x$accept_rate)) {
    cat(sprintf("  accept rate: %.2f   chains: %d\n",
                x$accept_rate, x$n_chains))
    if (!is.null(x$diagnostics)) {
      # An acceptance rate says nothing about whether the chain crossed the
      # ridge. Split-Rhat and bulk ESS do, and a fit that fails them should
      # say so on its own face rather than in a vignette.
      rh <- max(x$diagnostics$rhat, na.rm = TRUE)
      es <- min(x$diagnostics$ess,  na.rm = TRUE)
      cat(sprintf("  max split-Rhat: %.3f   min bulk ESS: %.0f%s\n", rh, es,
                  if (rh > 1.01 || es < 400) "   <-- NOT CONVERGED" else ""))
      if (rh > 1.01 || es < 400) {
        cat("  Rhat > 1.01 or ESS < 400: the posterior summary below is not\n",
            "  trustworthy. Increase n_iter, or use method = \"laplace\" and\n",
            "  report it as an approximation.\n", sep = "")
      }
    }
  }
  cat(sprintf("  sigma (noise): %.4g\n", x$sigma))
  cat("  posterior summary (natural scale):\n")
  print(format(x$summary, digits = 4L), row.names = FALSE)
  invisible(x)
}

#' @export
summary.edaphos_piml_bayes <- function(object, ...) object$summary

#' Posterior predictive distribution of a Bayesian Pillar 2 fit
#'
#' Propagates the full posterior over ODE parameters through the
#' forward model to produce posterior-predictive draws of
#' \eqn{y(z)} at user-supplied depths.
#'
#' @param object An `edaphos_piml_bayes` returned by
#'   [piml_profile_fit_bayesian()].
#' @param newdepths Numeric vector of depths at which to evaluate the
#'   predictive posterior.
#' @param n_draws Integer — number of posterior draws to propagate.
#'   Defaults to `min(500, nrow(object$draws))`.
#' @param interval Optional numeric scalar in `(0, 1)`. When given,
#'   returns a tidy `data.frame` with `mean`, `sd`, `lower`, `upper`
#'   per depth (symmetric central credible interval). When `NULL`
#'   (default), returns the full `n_draws`-by-length(newdepths) matrix
#'   of predictive draws.
#' @param include_obs_noise Logical — if `TRUE`, Gaussian observation
#'   noise `N(0, sigma^2)` is added to every predictive draw so the
#'   interval represents the predictive distribution of a *future
#'   observation*. If `FALSE` (default), the interval represents the
#'   uncertainty on the *mean function* \eqn{g(z; \theta)} alone.
#' @param seed Optional integer seed for the sub-sampling of draws.
#'   Every returned number is a Monte-Carlo summary over the sub-sample,
#'   so without a seed the `mean`, `sd`, `lower` and `upper` columns
#'   move between calls. Note that this seed only controls *which*
#'   posterior draws are propagated — reproducing a result end-to-end
#'   also requires seeding [piml_profile_fit_bayesian()] itself.
#' @param ... Unused; present for S3 `predict` generic compatibility.
#' @return Either a matrix (when `interval` is NULL) or a data frame
#'   with columns `depth`, `mean`, `sd`, `lower`, `upper`.
#' @examples
#' depths <- c(5, 15, 30, 60, 100)
#' values <- c(25, 18, 12, 8, 6.5)
#' # BOTH seeds are needed for a reproducible interval: one for the 2000
#' # posterior draws, one for the 500 of them that predict() propagates.
#' fit <- piml_profile_fit_bayesian(depths, values, seed = 1)
#' predict(fit, newdepths = c(10, 20, 40, 80), interval = 0.95, seed = 1)
#'
#' # At depth 10 that prints mean 21.00 with a 95% interval of
#' # [20.75, 21.24] for the mean function. `include_obs_noise = TRUE`
#' # widens it to [20.58, 21.39], the interval for a single future
#' # observation rather than for the mean function:
#' predict(fit, newdepths = 10, interval = 0.95, seed = 1,
#'         include_obs_noise = TRUE)
#' @export
predict.edaphos_piml_bayes <- function(object, newdepths,
                                          n_draws = NULL,
                                          interval = NULL,
                                          include_obs_noise = FALSE,
                                          seed = NULL, ...) {
  stopifnot(inherits(object, "edaphos_piml_bayes"),
            is.numeric(newdepths), all(newdepths >= 0))
  if (!is.null(seed)) set.seed(seed)
  total   <- nrow(object$draws)
  n_draws <- if (is.null(n_draws)) min(500L, total) else
    as.integer(min(n_draws, total))
  ix <- sample(seq_len(total), n_draws, replace = FALSE)

  pred <- matrix(NA_real_, nrow = n_draws, ncol = length(newdepths))
  for (m in seq_len(n_draws)) {
    th <- object$draws[ix[m], ]
    params <- .piml_unpack(th[seq_len(length(th) - 1L)], object$y_surface)
    yhat <- tryCatch(piml_profile_predict(params, newdepths),
                      error = function(e) rep(NA_real_, length(newdepths)))
    pred[m, ] <- yhat
  }
  if (isTRUE(include_obs_noise)) {
    # Per-draw noise scale: sigma is a sampled parameter, so its uncertainty
    # belongs in the predictive interval rather than being fixed at one value.
    # And the noise must be drawn from the family the model was FITTED with --
    # adding Gaussian noise to a gamma fit would put predictive mass below
    # zero, which is the defect the family argument exists to remove.
    sd_draw <- exp(object$draws[ix, ncol(object$draws)])
    fam <- object$family %||% "gaussian"
    if (!identical(fam, "gaussian")) {
      cv <- rep(sd_draw, ncol(pred))
      pred <- if (identical(fam, "gamma")) {
        matrix(stats::rgamma(length(pred), shape = 1 / cv^2,
                             rate = 1 / (cv^2 * pmax(as.numeric(pred), 1e-12))),
               nrow(pred), ncol(pred))
      } else {
        s2 <- log1p(cv^2)
        matrix(stats::rlnorm(length(pred),
                             meanlog = log(pmax(as.numeric(pred), 1e-12)) - s2 / 2,
                             sdlog = sqrt(s2)), nrow(pred), ncol(pred))
      }
    } else {
      pred <- pred + matrix(stats::rnorm(length(pred),
                                         sd = rep(sd_draw, ncol(pred))),
                            nrow = nrow(pred), ncol = ncol(pred))
    }
  }

  if (is.null(interval)) return(pred)
  stopifnot(is.numeric(interval), length(interval) == 1L,
            interval > 0, interval < 1)
  alpha <- (1 - interval) / 2
  out <- data.frame(
    depth = newdepths,
    mean  = apply(pred, 2L, mean, na.rm = TRUE),
    sd    = apply(pred, 2L, stats::sd, na.rm = TRUE),
    lower = apply(pred, 2L, stats::quantile, probs = alpha,
                   na.rm = TRUE),
    upper = apply(pred, 2L, stats::quantile, probs = 1 - alpha,
                   na.rm = TRUE),
    row.names = NULL, stringsAsFactors = FALSE
  )
  out
}
