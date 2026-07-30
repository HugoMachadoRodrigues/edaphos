# Pilar 9 -- Denoising-Diffusion Probabilistic Models for soil maps
# (edaphos v2.5.0).
#
# Why a pillar?
# -------------
# No classical DSM method samples ENTIRE plausible soil maps
# conditional on covariates.  Ensemble kriging does (in a Gaussian
# sense) but struggles on non-Gaussian distributions like SOC.  A
# DDPM (Ho et al. 2020) samples from p(map | covariates) via an
# iterative denoising process:
#
#     forward :  x_t = sqrt(alphabar_t) x_0 + sqrt(1 - alphabar_t) eps
#     reverse :  x_{t-1} = f_theta(x_t, t, conditioning)
#
# Trained with the score-matching surrogate:
#
#     L = E_{x_0, t, eps} [|| eps - eps_theta(x_t, t, c) ||^2]
#
# Pedometric contribution (novel as of 2026):
# Soil maps are natively 2-D; our pure-R DDPM is a TINY 2-D model
# with a single-level U-Net (downscale -> time embedding -> upscale)
# that can be trained on 16 x 16 SOC patches in seconds, sufficient
# to demonstrate the full pipeline:
#   (a) forward noising trajectory
#   (b) denoising-network training via score matching
#   (c) conditional ancestral sampling
#
# The point is the API + scientific machinery; a production-grade
# version ported to torch is not written yet.
#
# References
# ----------
# Ho, J., Jain, A. and Abbeel, P. (2020).  Denoising Diffusion
#   Probabilistic Models.  NeurIPS 33.
# Nichol, A. and Dhariwal, P. (2021).  Improved Denoising Diffusion
#   Probabilistic Models.  ICML.

# ---------------------------------------------------------------------------
# Diffusion schedule
# ---------------------------------------------------------------------------

#' Build a DDPM noise schedule
#'
#' Cosine schedule of Nichol & Dhariwal (2021).  Returns per-step
#' `alphas`, `betas`, `alphabar`, `sqrt_alphabar`, `sqrt_one_minus_alphabar`.
#' @param T Integer; number of diffusion steps.
#' @param s Numeric; small offset to avoid alphabar = 0 at t = T.
#' @return Named list.
#'
#' @references
#' Nichol, A. Q. and Dhariwal, P. (2021). Improved Denoising Diffusion
#' Probabilistic Models. *Proceedings of the 38th International
#' Conference on Machine Learning* **139**, 8162-8171.
#' @examples
#' sch <- dm_cosine_schedule(T = 100L)
#'
#' # alphabar is the fraction of the original signal surviving to step
#' # t: it starts near 1 and decays monotonically to ~0.
#' round(sch$alphabar[c(1, 25, 50, 75, 100)], 4)
#'
#' # The three arrays are mutually consistent -- alphabar is the
#' # running product of alphas -- which is what makes the reverse step
#' # algebraically valid.
#' c(complementary = isTRUE(all.equal(sch$alphas + sch$betas, rep(1, 100))),
#'   running_prod  = isTRUE(all.equal(sch$alphabar, cumprod(sch$alphas))))
#'
#' # beta is clipped at 0.999 (Nichol and Dhariwal 2021) to keep the
#' # 1/sqrt(alpha_t) factor of the reverse step finite near t = T.
#' max(sch$betas)
#' @export
dm_cosine_schedule <- function(T = 50L, s = 0.008) {
  t <- seq(0, T)
  f <- cos((t / T + s) / (1 + s) * pi / 2)^2
  alphabar <- f / f[1]
  alphabar <- pmax(pmin(alphabar, 0.9999), 1e-8)
  alphas <- alphabar[-1] / alphabar[-(T + 1)]

  # Nichol and Dhariwal (2021), sec. 3.2: clip beta_t at 0.999 "to
  # prevent singularities near t = T".  Without it the cosine schedule
  # drives alpha_T towards 1e-5, and the reverse step
  #   mu = (1 / sqrt(alpha_t)) (x_t - ...)
  # multiplies the iterate by 1/sqrt(alpha_T) ~ 150 in a single step.
  # With an exact denoiser the bracket cancels and this is harmless;
  # with any approximate one the residual is amplified and ancestral
  # sampling diverges -- observed at ~1e4 times the data scale, while
  # the training loss (computed only on the forward process) looks
  # perfectly healthy.
  betas  <- pmin(1 - alphas, 0.999)
  alphas <- 1 - betas

  # Re-derive alphabar from the clipped alphas so that the three arrays
  # remain mutually consistent: the reverse step is only valid when
  # alphabar_t == prod(alphas_1..t).
  alphabar_c <- cumprod(alphas)

  list(
    T = as.integer(T),
    alphas = alphas,
    betas  = betas,
    alphabar = alphabar_c,
    sqrt_alphabar         = sqrt(alphabar_c),
    sqrt_one_minus_alphabar = sqrt(1 - alphabar_c)
  )
}

# ---------------------------------------------------------------------------
# Denoising network (tiny 2-D MLP with sinusoidal time embedding)
# ---------------------------------------------------------------------------
#
# For a minimal pedometric demo we flatten the H x W patch + the
# (optional) conditioning covariate channel, concatenate a sinusoidal
# time embedding, and run a 2-hidden-layer MLP that predicts the
# noise eps that was added at time t.  This architecture is known
# to underperform a proper 2-D U-Net (cf. Ho et al. 2020) but is
# sufficient to demonstrate the score-matching objective on patches
# up to 8 x 8.  A U-Net port is not written yet.

.dm_time_embed <- function(t_norm, dim = 8L) {
  # Sinusoidal embedding: dim/2 frequencies
  half <- dim %/% 2L
  freqs <- 10000 ^ ((0:(half - 1)) / half)
  emb <- c(sin(t_norm / freqs),
            cos(t_norm / freqs))
  emb[seq_len(dim)]
}

.dm_init_net <- function(H, W, cond_dim = 0L, hidden = 64L,
                            time_dim = 8L) {
  input_dim <- H * W + cond_dim + time_dim
  list(
    W1 = matrix(stats::rnorm(input_dim * hidden, sd = sqrt(2 / input_dim)),
                  input_dim, hidden),
    b1 = rep(0, hidden),
    W2 = matrix(stats::rnorm(hidden * hidden, sd = sqrt(2 / hidden)),
                  hidden, hidden),
    b2 = rep(0, hidden),
    W3 = matrix(stats::rnorm(hidden * (H * W), sd = sqrt(2 / hidden)),
                  hidden, H * W),
    b3 = rep(0, H * W),
    H = H, W = W, cond_dim = cond_dim,
    hidden = hidden, time_dim = time_dim
  )
}

.dm_forward <- function(net, x_flat, cond_flat, t_norm) {
  t_emb <- .dm_time_embed(t_norm, dim = net$time_dim)
  z <- c(x_flat, cond_flat, t_emb)
  h1 <- pmax(z %*% net$W1 + net$b1, 0)          # ReLU
  h2 <- pmax(h1 %*% net$W2 + net$b2, 0)
  eps_hat <- as.numeric(h2 %*% net$W3 + net$b3)
  list(eps_hat = eps_hat, h1 = h1, h2 = h2)
}

# Batched time-embedding: t_norms is a length-n_batch vector, returns
# an (n_batch, dim) matrix.
.dm_time_embed_batch <- function(t_norms, dim = 8L) {
  half  <- dim %/% 2L
  freqs <- 10000 ^ ((0:(half - 1)) / half)     # length half
  ang   <- outer(as.numeric(t_norms), 1 / freqs)   # (n, half)
  emb   <- cbind(sin(ang), cos(ang))           # (n, 2*half)
  emb[, seq_len(dim), drop = FALSE]
}

# Batched forward pass -- processes a full minibatch with a single
# GEMM per layer instead of one call per row.  Returns `eps_hat` and
# `h2` as `(n_batch, H*W)` and `(n_batch, hidden)` matrices.
# Numerically matches the per-row `.dm_forward()` to 1e-15 on
# gradient components (tested in v3.2.0 test-pilar9-ddpm-batched.R),
# with a 4-6x wall-time speedup on n_patches in [64, 512].
.dm_forward_batch <- function(net, X_flat, Cond_flat, t_norms) {
  T_emb <- .dm_time_embed_batch(t_norms, dim = net$time_dim)  # (n, time_dim)
  Z <- cbind(X_flat, Cond_flat, T_emb)
  # H1 = ReLU(Z W1 + b1)   -- matmul + row-broadcast of b1
  H1 <- pmax(sweep(Z %*% net$W1, 2L, net$b1, "+"), 0)
  H2 <- pmax(sweep(H1 %*% net$W2, 2L, net$b2, "+"), 0)
  Eps_hat <- sweep(H2 %*% net$W3, 2L, net$b3, "+")
  list(eps_hat = Eps_hat, h2 = H2)
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Train a tiny DDPM on a collection of soil-map patches
#'
#' @param stack A 3-D array of shape `(n_patches, H, W)` of soil-
#'   property patches (e.g. SOC at each pixel, already standardised
#'   to zero mean / unit variance).
#' @param conditioning Optional matrix of shape `(n_patches, cond_dim)`
#'   giving a per-patch covariate summary fed to the denoising
#'   network as conditioning.  Default `NULL`.
#' @param T Integer; number of diffusion timesteps.
#' @param epochs Integer; training epochs.
#' @param hidden Integer; hidden width of the denoising MLP.
#' @param lr Numeric; learning rate.
#' @param seed Optional RNG seed.
#' @param backend One of `"auto"` (default), `"torch"` or `"r"`. `"auto"`
#'   uses the torch U-Net denoiser when a working libtorch is present and
#'   otherwise falls back to the pure-R path. The pure-R denoiser is an
#'   **uncalibrated reference**: its samples are over-dispersed and spatially
#'   incoherent (see the Pillar 9 vignette), so publication figures must use
#'   `"torch"`. The R path emits a one-time note when used.
#' @param device `"cpu"` (default), `"mps"`, or `"cuda"` when
#'   `backend = "torch"`.
#' @return An `edaphos_dm_fit` fit.
#'
#' @references
#' Ho, J., Jain, A. and Abbeel, P. (2020). Denoising Diffusion
#' Probabilistic Models. *Advances in Neural Information Processing
#' Systems* **33**, 6840-6851.
#'
#' Nichol, A. Q. and Dhariwal, P. (2021). Improved Denoising Diffusion
#' Probabilistic Models. *Proceedings of the 38th International
#' Conference on Machine Learning* **139**, 8162-8171.
#'
#' Huang, G.-B., Zhu, Q.-Y. and Siew, C.-K. (2006). Extreme learning
#' machine: Theory and applications. *Neurocomputing* **70**, 489-501.
#' \doi{10.1016/j.neucom.2005.12.126} (the random-hidden-layer regime
#' the `backend = "r"` trainer operates in).
#' @examples
#' data(br_cerrado)
#'
#' # br_cerrado is a 45 x 45 grid, so it reshapes into an image.  Model
#' # `twi`: a generative model can only learn structure the field
#' # actually has, and `soc` in this grid carries far less short-range
#' # structure than `twi` does.
#' as_grid <- function(v) {
#'   ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
#'   m <- matrix(NA_real_, 45L, 45L)
#'   m[cbind(match(br_cerrado$x, ux), match(br_cerrado$y, uy))] <- v
#'   m
#' }
#' lag1 <- function(z) (cor(as.vector(z[, -ncol(z)]), as.vector(z[, -1])) +
#'                      cor(as.vector(z[-nrow(z), ]), as.vector(z[-1, ]))) / 2
#' round(c(soc = lag1(as_grid(br_cerrado$soc)),
#'         twi = lag1(as_grid(br_cerrado$twi))), 3)
#'
#' field  <- as_grid(br_cerrado$twi)
#' field  <- (field - mean(field)) / sd(field)
#' starts <- seq(1L, 38L, by = 5L)
#' cells  <- expand.grid(r = starts, c = starts)
#' stack  <- array(0, dim = c(nrow(cells), 8L, 8L))
#' for (i in seq_len(nrow(cells)))
#'   stack[i, , ] <- field[cells$r[i]:(cells$r[i] + 7L),
#'                         cells$c[i]:(cells$c[i] + 7L)]
#'
#' fit <- dm_fit(stack, T = 50L, epochs = 150L, hidden = 32L,
#'               lr = 0.02, seed = 1L)
#' fit
#'
#' # The score-matching target is standard normal, so a denoiser that
#' # predicts nothing at all -- eps_theta == 0 -- scores exactly 1.
#' # That is what the training loss must be read against, and the gap
#' # here is small.
#' round(c(initial = fit$history[1L],
#'         final   = fit$history[length(fit$history)],
#'         eps_hat_zero = 1), 4)
#'
#' # Nor does the gap close with training: `backend = "r"` fits a
#' # readout over frozen random features (an ELM), and that readout has
#' # already converged.  2.7 times the epochs buys 0.05.
#' fit_long <- dm_fit(stack, T = 50L, epochs = 400L, hidden = 32L,
#'                    lr = 0.02, seed = 1L)
#' round(c(epochs_150 = fit$history[150L],
#'         epochs_400 = fit_long$history[400L]), 4)
#'
#' # And the patches overlap by construction (stride 5, window 8), so
#' # these 64 are nowhere near 64 independent training examples.
#' c(n_patches = dim(stack)[1L], H = dim(stack)[2L], W = dim(stack)[3L])
#' @export
dm_fit <- function(stack, conditioning = NULL,
                     T = 50L, epochs = 100L,
                     hidden = 32L, lr = 0.01, seed = NULL,
                     backend = c("auto", "r", "torch"),
                     device = c("cpu", "mps", "cuda")) {
  device  <- match.arg(device)
  backend <- .resolve_backend(
    backend, fn = "dm_fit",
    r_note = paste0("backend = 'r' is a reference sampler whose draws are ",
                    "over-dispersed and spatially incoherent (not calibrated ",
                    "to the field's spatial statistics); use backend = 'torch' ",
                    "(the default when libtorch is present) for coherent ",
                    "samples."))
  if (backend == "torch")
    return(.torch_ddpm_fit(stack, conditioning, T, epochs, hidden,
                              lr, seed, device))
  if (!is.array(stack) || length(dim(stack)) != 3L) {
    .stopf("`stack` must be a 3-D array (n_patches, H, W), got %s of dim %s.",
            class(stack)[1L],
            if (is.null(dim(stack))) "NULL"
            else paste(dim(stack), collapse = " x "),
            hint = "Use `array(your_data, dim = c(n_patches, H, W))`.")
  }
  n_patches <- dim(stack)[1L]; H <- dim(stack)[2L]; W <- dim(stack)[3L]
  if (!is.null(conditioning)) {
    if (!is.matrix(conditioning)) {
      .stopf("`conditioning` must be a matrix when supplied, got %s.",
              class(conditioning)[1L],
              hint = "Wrap your data with `as.matrix(...)`.")
    }
    if (nrow(conditioning) != n_patches) {
      .stopf("`conditioning` must have one row per patch (n=%d), got %d.",
              n_patches, nrow(conditioning),
              hint = "The order of `conditioning` rows must match the first dim of `stack`.")
    }
    cond_dim <- ncol(conditioning)
  } else {
    conditioning <- matrix(0, n_patches, 0L)
    cond_dim <- 0L
  }
  if (!is.null(seed)) set.seed(seed)

  sched <- dm_cosine_schedule(T = T)
  net   <- .dm_init_net(H, W, cond_dim = cond_dim, hidden = hidden)

  patches_flat <- matrix(stack, nrow = n_patches, ncol = H * W)
  # Standardise patches across the whole bank -> zero mean, unit var
  mu <- mean(patches_flat); sd_ <- stats::sd(patches_flat)
  if (sd_ < 1e-6) sd_ <- 1
  patches_z <- (patches_flat - mu) / sd_

  history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    loss_acc <- 0
    # Random t per patch
    t_ix  <- sample.int(T, n_patches, replace = TRUE)
    eps   <- matrix(stats::rnorm(n_patches * H * W),
                      n_patches, H * W)
    x_t   <- sweep(patches_z, 1L,
                     sched$sqrt_alphabar[t_ix], "*") +
              sweep(eps, 1L,
                     sched$sqrt_one_minus_alphabar[t_ix], "*")
    # Simple SGD on last layer only (W3, b3) using analytic gradient.
    # This is enough to minimise the score-matching loss when the
    # hidden layers are randomly initialised (akin to ELM-style
    # training; Huang et al. 2006).  v3.2.0 swaps the per-patch
    # for-loop for a batched forward + gradient accumulation:
    #
    #   * Resid  = Eps_hat - eps            (n_patches, H*W)
    #   * grad_W3 = (2 / n) * t(H2) %*% Resid
    #   * grad_b3 = (2 / n) * colSums(Resid)
    #
    # Numerically identical to the per-row path (max |diff| < 1e-15
    # on gradients); empirically ~4-6x faster on n_patches in [64, 512].
    fwd   <- .dm_forward_batch(net,
                                 X_flat    = x_t,
                                 Cond_flat = conditioning,
                                 t_norms   = t_ix / T)
    resid <- fwd$eps_hat - eps
    loss_acc <- sum(resid * resid) / H / W
    grad_W3  <- (2 / n_patches) * crossprod(fwd$h2, resid)
    grad_b3  <- (2 / n_patches) * colSums(resid)
    net$W3   <- net$W3 - lr * grad_W3
    net$b3   <- net$b3 - lr * grad_b3
    history[ep] <- loss_acc / n_patches
  }

  structure(list(
    backend = "r",
    net = net, schedule = sched,
    H = H, W = W, n_patches = n_patches, cond_dim = cond_dim,
    mu = mu, sd = sd_,
    history = history,
    T = T, hidden = hidden, lr = lr
  ), class = "edaphos_dm_fit")
}

#' Sample new soil-map patches from a trained DDPM
#'
#' Ancestral sampling (Ho et al. 2020 Algorithm 2): start from
#' Gaussian noise at t=T, iteratively apply the denoising network to
#' walk back to t=0.  Optional conditioning vector c is passed in at
#' every step.
#'
#' @param fit An `edaphos_dm_fit` from [`dm_fit()`].
#' @param n_samples Integer; number of independent map draws.
#' @param conditioning Optional `(n_samples, cond_dim)` matrix.
#'   Default: zero vector for every sample (unconditional).
#' @param seed Optional RNG seed.
#' @return 3-D array `(n_samples, H, W)` of generated patches.
#' @examples
#' data(br_cerrado)
#'
#' as_grid <- function(v) {
#'   ux <- sort(unique(br_cerrado$x)); uy <- sort(unique(br_cerrado$y))
#'   m <- matrix(NA_real_, 45L, 45L)
#'   m[cbind(match(br_cerrado$x, ux), match(br_cerrado$y, uy))] <- v
#'   m
#' }
#' lag1 <- function(z) (cor(as.vector(z[, -ncol(z)]), as.vector(z[, -1])) +
#'                      cor(as.vector(z[-nrow(z), ]), as.vector(z[-1, ]))) / 2
#'
#' field  <- as_grid(br_cerrado$twi)
#' field  <- (field - mean(field)) / sd(field)
#' starts <- seq(1L, 38L, by = 5L)
#' cells  <- expand.grid(r = starts, c = starts)
#' stack  <- array(0, dim = c(nrow(cells), 8L, 8L))
#' for (i in seq_len(nrow(cells)))
#'   stack[i, , ] <- field[cells$r[i]:(cells$r[i] + 7L),
#'                         cells$c[i]:(cells$c[i] + 7L)]
#'
#' fit <- dm_fit(stack, T = 50L, epochs = 150L, hidden = 32L,
#'               lr = 0.02, seed = 1L)
#' gen <- dm_sample(fit, n_samples = 8L, seed = 7L)
#' dim(gen)
#'
#' # "They look plausible" is not a result.  A generative model of a
#' # spatial field makes a checkable promise: the SPATIAL STATISTICS of
#' # its draws should match the data's.  Two numbers catch the usual
#' # failure modes, and they have to be read together.
#' stat <- function(a) c(sd = mean(apply(a, 1L, sd)),
#'                       lag1 = mean(apply(a, 1L, lag1)))
#' round(rbind(real = stat(stack), generated = stat(gen)), 3)
#'
#' # The draws are five times over-dispersed AND spatially incoherent
#' # (lag-1 near zero against 0.32 in the data).  With `backend = "r"`
#' # the denoiser is a readout over frozen random features and has
#' # learned a marginal scale, not a landscape: these are not soil
#' # maps.  Use `backend = "torch"` for anything you would publish --
#' # and run this same two-number check on it rather than trusting it.
#'
#' # `conditioning` is silently IGNORED when the fit was
#' # unconditional: cond_dim is 0, so there is no input for it to
#' # enter through, and the draws are bit-identical to the ones above.
#' same <- dm_sample(fit, n_samples = 8L,
#'                   conditioning = matrix(99, 8L, 1L), seed = 7L)
#' identical(same, gen)
#'
#' # Conditioning has to be supplied at fit time, and its effect judged
#' # against the signal available.  Patch-mean elevation is nearly
#' # perfectly anti-correlated with patch-mean twi in this grid:
#' elev <- as_grid(br_cerrado$elev)
#' cond <- matrix(0, nrow(cells), 1L)
#' for (i in seq_len(nrow(cells)))
#'   cond[i, 1L] <- mean(elev[cells$r[i]:(cells$r[i] + 7L),
#'                            cells$c[i]:(cells$c[i] + 7L)])
#' cond[, 1L] <- as.vector(scale(cond[, 1L]))
#' round(cor(cond[, 1L], apply(stack, 1L, mean)), 3)
#'
#' # ... and yet swinging the conditioner across 3 sd moves the sample
#' # mean by an eighth of the draw-to-draw spread, in the wrong
#' # direction.  Read it as a demonstration of the interface, not of a
#' # calibrated conditional simulator.
#' fit_c <- dm_fit(stack, conditioning = cond, T = 50L, epochs = 150L,
#'                 hidden = 32L, lr = 0.02, seed = 1L)
#' lo <- dm_sample(fit_c, n_samples = 8L,
#'                 conditioning = matrix(-1.5, 8L, 1L), seed = 3L)
#' hi <- dm_sample(fit_c, n_samples = 8L,
#'                 conditioning = matrix(1.5, 8L, 1L), seed = 3L)
#' round(c(mean_low = mean(lo), mean_high = mean(hi),
#'         response = mean(hi) - mean(lo),
#'         draw_sd  = sd(apply(lo, 1L, mean))), 3)
#' @export
dm_sample <- function(fit, n_samples = 4L,
                        conditioning = NULL, seed = NULL) {
  stopifnot(inherits(fit, "edaphos_dm_fit"))
  if (identical(fit$backend, "torch")) {
    return(.torch_ddpm_sample(fit, n_samples, conditioning, seed))
  }
  if (!is.null(seed)) set.seed(seed)
  H <- fit$H; W <- fit$W
  T <- fit$schedule$T
  if (is.null(conditioning) || fit$cond_dim == 0L) {
    conditioning <- matrix(0, n_samples, fit$cond_dim)
  } else {
    stopifnot(nrow(conditioning) == n_samples,
               ncol(conditioning) == fit$cond_dim)
  }

  # Ancestral sampling with x_0 clipping (Ho et al. 2020, sec. 3.3).
  #
  # The compact form of the reverse step,
  #   mu = (1 / sqrt(a_t)) (x_t - ((1 - a_t) / sqrt(1 - abar_t)) eps_hat),
  # multiplies the iterate by 1 / sqrt(a_t) at every step.  Only an
  # accurate eps_hat makes the bracket cancel that growth: with
  # eps_hat == 0 the total gain over the trajectory is
  # 1 / sqrt(alphabar_T), which the cosine schedule drives past 1e4.
  # The pure-R denoiser trains a readout over frozen random features
  # (an ELM regime) and explains only a modest share of the noise, so
  # the unclipped recursion diverges -- silently, because the training
  # loss is computed on the forward process and never sees it.
  #
  # The standard remedy is to route the step through x_0: invert the
  # forward process for x_0, clip it to the range the data actually
  # occupy, and rebuild the posterior mean from the clipped value via
  #   mu = (sqrt(abar_{t-1}) b_t / (1 - abar_t)) x0
  #      + (sqrt(a_t) (1 - abar_{t-1}) / (1 - abar_t)) x_t   (eq. 7).
  # This is algebraically identical when x_0 is in range and bounded
  # otherwise, so it costs nothing when the denoiser is good.
  #
  # Patches are standardised at fit time, so the bound is set in
  # standard deviations of the training data.
  clip <- 4
  x <- matrix(stats::rnorm(n_samples * H * W), n_samples, H * W)
  for (t in seq(T, 1, by = -1L)) {
    at   <- fit$schedule$alphas[t]
    abt  <- fit$schedule$alphabar[t]
    abtm <- if (t > 1L) fit$schedule$alphabar[t - 1L] else 1
    bt   <- fit$schedule$betas[t]
    # Posterior variance of q(x_{t-1} | x_t, x_0) (eq. 7), which is
    # smaller than the beta_t used by the compact form.
    sigma_t <- if (t > 1L) sqrt(bt * (1 - abtm) / (1 - abt)) else 0
    for (i in seq_len(n_samples)) {
      fwd <- .dm_forward(fit$net,
                          x_flat    = x[i, ],
                          cond_flat = conditioning[i, ],
                          t_norm    = t / T)
      x0 <- (x[i, ] - sqrt(1 - abt) * fwd$eps_hat) / sqrt(abt)
      x0 <- pmin(pmax(x0, -clip), clip)

      mu <- (sqrt(abtm) * bt / (1 - abt)) * x0 +
            (sqrt(at) * (1 - abtm) / (1 - abt)) * x[i, ]

      x[i, ] <- if (t > 1L) mu + sigma_t * stats::rnorm(H * W) else mu
    }
  }
  # Un-standardise
  x_un <- x * fit$sd + fit$mu
  array(x_un, dim = c(n_samples, H, W))
}

#' @export
print.edaphos_dm_fit <- function(x, ...) {
  cat("<edaphos_dm_fit>  (Pilar 9 -- Denoising Diffusion Probabilistic Model)\n")
  cat(sprintf("  patch shape : %d x %d\n", x$H, x$W))
  cat(sprintf("  n_train     : %d   cond_dim = %d\n",
               x$n_patches, x$cond_dim))
  cat(sprintf("  T (steps)   : %d   hidden = %d\n", x$T, x$hidden))
  if (length(x$history) > 0L) {
    cat(sprintf("  initial loss = %.4g  final loss = %.4g\n",
                 x$history[1L], x$history[length(x$history)]))
  }
  invisible(x)
}
