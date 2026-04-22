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

# Negative log-posterior at theta = (log lambda0, mu, y_inf, y0). The
# log-prior is weakly informative so that the Laplace approximation is
# stabilised against pathological optima.
.piml_bayes_neg_log_post <- function(theta, depths, obs, y_surface,
                                       sigma, prior) {
  params <- .piml_unpack(theta, y_surface)
  pred   <- tryCatch(piml_profile_predict(params, depths),
                      error = function(e) NULL)
  if (is.null(pred) || any(!is.finite(pred))) return(1e9)

  # Gaussian likelihood
  n     <- length(obs)
  nll   <- 0.5 * n * log(2 * pi * sigma^2) +
           sum((obs - pred)^2) / (2 * sigma^2)

  # Priors. All expressed as `0.5 * ((x - mu) / sd)^2 + const` so they
  # are additive in -log-posterior.
  nlp <- 0
  # log(lambda0) ~ N(prior$log_lambda0_mean, prior$log_lambda0_sd^2)
  nlp <- nlp + 0.5 * ((theta[1L] - prior$log_lambda0_mean) /
                        prior$log_lambda0_sd)^2
  # mu ~ N(0, prior$mu_sd^2) -- centred at 0 (depth-invariant by default)
  nlp <- nlp + 0.5 * (theta[2L] / prior$mu_sd)^2
  # y_inf ~ N(prior$y_inf_mean, prior$y_inf_sd^2)
  nlp <- nlp + 0.5 * ((theta[3L] - prior$y_inf_mean) /
                        prior$y_inf_sd)^2
  if (is.null(y_surface)) {
    # y0 ~ N(prior$y0_mean, prior$y0_sd^2)
    nlp <- nlp + 0.5 * ((theta[4L] - prior$y0_mean) /
                          prior$y0_sd)^2
  }
  nll + nlp
}

.piml_bayes_default_prior <- function(depths, obs, y_surface) {
  # Weakly informative, data-driven prior.
  o <- order(depths)
  list(
    log_lambda0_mean = log(1e-2),  # ~1% decay / cm default
    log_lambda0_sd   = 2,          # 2 orders of magnitude spread
    mu_sd            = 0.5,        # |mu| < ~1 / cm covers realistic rates
    y_inf_mean       = obs[o[length(o)]],
    y_inf_sd         = max(stats::sd(obs, na.rm = TRUE), 1),
    y0_mean          = if (is.null(y_surface)) obs[o[1L]] else y_surface,
    y0_sd            = max(stats::sd(obs, na.rm = TRUE), 1)
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
                                start, control) {
  # MAP by optim on -log posterior.
  fit <- stats::optim(
    par       = start,
    fn        = function(th, ...) .piml_bayes_neg_log_post(th, ...),
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    sigma     = 1.0,            # provisional; updated below
    prior     = prior,
    method    = "Nelder-Mead",
    control   = control
  )
  # Empirical sigma from the MAP residuals, then refit with that sigma
  # so the prior / likelihood balance uses the right noise scale.
  params0 <- .piml_unpack(fit$par, y_surface)
  pred0   <- piml_profile_predict(params0, depths)
  sigma   <- max(sqrt(mean((values - pred0)^2)), 1e-6)
  fit <- stats::optim(
    par       = fit$par,
    fn        = function(th, ...) .piml_bayes_neg_log_post(th, ...),
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    sigma     = sigma,
    prior     = prior,
    method    = "Nelder-Mead",
    control   = control
  )
  H <- .piml_numerical_hessian(
    fn        = .piml_bayes_neg_log_post,
    theta     = fit$par,
    depths    = depths,
    obs       = values,
    y_surface = y_surface,
    sigma     = sigma,
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
#' @param prior Named list of hyperparameters for the priors. See the
#'   source for the default structure (fields
#'   `log_lambda0_mean`, `log_lambda0_sd`, `mu_sd`, `y_inf_mean`,
#'   `y_inf_sd`, `y0_mean`, `y0_sd`).
#' @param start Optional starting vector. Defaults to
#'   [piml_profile_fit()]'s point-estimate theta for the MAP search.
#' @param control `optim` control list for the MAP step.
#' @param n_iter,n_burn,thin,seed MCMC settings. Only consulted when
#'   `method = "mcmc"`.
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
#' fit_bayes <- piml_profile_fit_bayesian(depths, values)
#' fit_bayes
#' summary(fit_bayes)
#' @export
piml_profile_fit_bayesian <- function(depths, values, y_surface = NULL,
                                        method  = c("laplace", "mcmc"),
                                        prior   = NULL,
                                        start   = NULL,
                                        control = list(maxit = 2000),
                                        n_iter  = 5000L,
                                        n_burn  = 2000L,
                                        thin    = 1L,
                                        seed    = NULL,
                                        verbose = FALSE) {
  stopifnot(length(depths) == length(values),
            length(depths) >= 2L,
            all(is.finite(depths)), all(is.finite(values)),
            all(depths >= 0))
  method <- match.arg(method)

  if (is.null(prior)) prior <- .piml_bayes_default_prior(depths, values,
                                                            y_surface)
  if (is.null(start)) {
    start <- piml_profile_fit(depths, values, y_surface = y_surface,
                                control = control)$theta
  }

  lap <- .piml_laplace_fit(depths, values, y_surface, prior, start,
                             control)

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
  } else {
    nlp_closure <- function(th) {
      .piml_bayes_neg_log_post(th, depths = depths, obs = values,
                                 y_surface = y_surface, sigma = lap$sigma,
                                 prior = prior)
    }
    mc <- .piml_mcmc_adaptive_rwm(
      neg_log_post_fn = nlp_closure,
      start           = lap$map,
      proposal_cov    = lap$cov,
      n_iter          = as.integer(n_iter),
      n_burn          = as.integer(n_burn),
      thin            = as.integer(thin),
      seed            = seed,
      verbose         = verbose
    )
    draws      <- mc$draws
    accept_rate <- mc$accept_rate
    post_cov   <- stats::cov(draws)
  }

  # Natural-scale posterior summaries.
  nat <- t(apply(draws, 1L, function(th) {
    p <- .piml_unpack(th, y_surface)
    c(lambda0 = p$lambda0, mu = p$mu, y_inf = p$y_inf, y0 = p$y0)
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

  structure(
    list(
      method      = method,
      map         = .piml_unpack(lap$map, y_surface),
      theta_map   = lap$map,
      sigma       = lap$sigma,
      cov         = post_cov,
      draws       = draws,
      summary     = summ,
      accept_rate = accept_rate,
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
    cat(sprintf("  accept rate: %.2f\n", x$accept_rate))
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
#' @param ... Unused; present for S3 `predict` generic compatibility.
#' @return Either a matrix (when `interval` is NULL) or a data frame
#'   with columns `depth`, `mean`, `sd`, `lower`, `upper`.
#' @examples
#' depths <- c(5, 15, 30, 60, 100)
#' values <- c(25, 18, 12, 8, 6.5)
#' fit <- piml_profile_fit_bayesian(depths, values)
#' predict(fit, newdepths = c(10, 20, 40, 80), interval = 0.95)
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
    params <- .piml_unpack(object$draws[ix[m], ], object$y_surface)
    yhat <- tryCatch(piml_profile_predict(params, newdepths),
                      error = function(e) rep(NA_real_, length(newdepths)))
    pred[m, ] <- yhat
  }
  if (isTRUE(include_obs_noise)) {
    pred <- pred + matrix(stats::rnorm(length(pred), sd = object$sigma),
                           nrow = nrow(pred), ncol = ncol(pred))
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
