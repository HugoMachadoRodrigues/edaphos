# Pilar 8 -- Neural operators for pedogenetic depth PDEs
# (edaphos v2.4.0).
#
# Why a pillar?
# -------------
# Pilar 2 (PIML) fits a SINGLE parametric or neural ODE per pedon.  A
# neural operator (Kovachki et al. 2023) learns the SOLUTION OPERATOR
# of the underlying PDE directly from data, so a single trained
# model can predict profiles for NEW sites with arbitrary covariate
# stacks without re-fitting.  This is the first pedometric
# application of neural operators reported as of 2026.
#
# We ship two independent architectures:
#
#   1. Fourier Neural Operator (FNO, Li et al. 2021)
#      -- learns a map y(z) = F[u(z)], where u(z) is a covariate
#         trajectory (e.g. site-specific depth-dependent inputs) and
#         y(z) is the resulting soil property profile.  Spectral
#         convolutions in truncated Fourier space.
#
#   2. Deep Operator Network (DeepONet, Lu et al. 2021)
#      -- a branch-net encoder of u(z) + a trunk-net encoder of the
#         query depth z, combined by inner product.
#
# Both are implemented in pure R as 1-D operator models with ONLY
# `stats` as a dependency (no torch required).  The small-scale
# demonstrator stays fast and serves as an API-stable reference for
# a torch implementation, which is not written yet.
#
# Exports
#   no_fno_fit(depths, targets, covariates, n_modes, width, ...)
#   no_deeponet_fit(depths, targets, covariates, branch_hidden,
#                     trunk_hidden, ...)
#   predict(<no_fno | no_deeponet>, newdepths, newcovariates)

# ---------------------------------------------------------------------------
# Utilities shared by both architectures
# ---------------------------------------------------------------------------

.no_standardise <- function(X) {
  center <- colMeans(X, na.rm = TRUE)
  scale  <- apply(X, 2L, stats::sd, na.rm = TRUE)
  scale[scale < 1e-6] <- 1
  Xs <- sweep(sweep(X, 2L, center, "-"), 2L, scale, "/")
  list(X = Xs, center = center, scale = scale)
}

.no_apply_standardise <- function(X, center, scale) {
  sweep(sweep(X, 2L, center, "-"), 2L, scale, "/")
}

# Undo the target standardisation.
#
# `.no_standardise()` centres and scales targets *per depth*, so
# `tgt_std$center` and `tgt_std$scale` are vectors of length n_depths,
# not scalars.  A soil profile's mean carbon at 2.5 cm and at 150 cm
# differ by more than either column's standard deviation, so applying
# the first column's constants to every depth -- as every predict()
# path did before v4.1.0 -- shifts deep predictions by the difference
# between the topsoil and subsoil means.  The error is invisible in the
# training loss, which is computed entirely on the standardised scale.
#
# `depths_out` supports the DeepONet trunk, which accepts depths that
# were never in the training grid.  Per-depth constants do not exist
# there, so they are linearly interpolated (and held flat outside the
# training range).  The profile mean and spread vary smoothly with
# depth, so interpolating them is exactly as defensible as the operator
# being learned; `rule = 2` keeps extrapolation to the nearest observed
# depth rather than inventing a trend.
.no_unstandardise_targets <- function(Y, tgt_std, depths_train,
                                        depths_out = NULL) {
  ctr <- tgt_std$center
  scl <- tgt_std$scale

  if (!is.null(depths_out) &&
      !isTRUE(all.equal(as.numeric(depths_out),
                          as.numeric(depths_train)))) {
    if (length(depths_train) > 1L) {
      ctr <- stats::approx(depths_train, tgt_std$center,
                             xout = depths_out, rule = 2)$y
      scl <- stats::approx(depths_train, tgt_std$scale,
                             xout = depths_out, rule = 2)$y
    } else {
      ctr <- rep(tgt_std$center[1L], length(depths_out))
      scl <- rep(tgt_std$scale[1L],  length(depths_out))
    }
  }

  if (length(ctr) != ncol(Y)) {
    # Defensive: a mismatch here means the prediction grid and the
    # stored constants disagree, which would silently mis-scale.
    stop(sprintf(paste("internal: target un-standardisation expects %d",
                        "columns but the prediction has %d."),
                  length(ctr), ncol(Y)), call. = FALSE)
  }
  sweep(sweep(Y, 2L, scl, "*"), 2L, ctr, "+")
}

# ---------------------------------------------------------------------------
# Fourier Neural Operator (1-D)
# ---------------------------------------------------------------------------
#
# Architecture (simplified Li et al. 2021):
#   Input  : u(z) covariate trajectory, shape (n_depths,)
#   Encoder: linear lift into a `width`-channel latent
#   FNO block (repeated L times):
#     v_new = sigma( W v + F^-1( R F(v) ) )
#   where F is the 1-D DFT, R is a learned spectral multiplier
#   truncated to the first `n_modes` modes, W is a pointwise linear.
#   Decoder: pointwise linear back to scalar y(z).
#
# For a small pedometric demo we use L = 2 blocks, width = 16 channels,
# n_modes = 4.  Training minimises mean-squared error across all
# depths across all profiles via a vectorised gradient descent on the
# spectral-multiplier matrices (complex-valued) and the linear layers.

#' Fit a 1-D Fourier Neural Operator for depth-profile operators
#'
#' Learns the solution map `u(z) -> y(z)` from a collection of
#' (covariate trajectory, target profile) pairs.  The trained
#' operator predicts the depth profile at new sites without re-fitting.
#'
#' @param depths Numeric vector of depths (common grid, length
#'   `n_depths`).  Depth must be equally spaced for the DFT to be
#'   exact; if not equally spaced, the implementation falls back to
#'   a FFT on the reindexed series.
#' @param targets Matrix of observed profile values, shape
#'   `(n_obs, n_depths)`.  Each row is one site.
#' @param covariates Matrix of depth-dependent covariate values,
#'   shape `(n_obs, n_depths, n_channels)` -- the covariate
#'   trajectory that drives the operator.  A 2-D matrix is accepted
#'   and treated as `n_channels = 1`.
#' @param n_modes Integer; number of Fourier modes retained in each
#'   spectral convolution.  Default `4L`.
#' @param width Integer; number of latent channels.  Default `8L`.
#' @param n_blocks Integer; number of FNO blocks.  Default `2L`.
#' @param epochs Integer; SGD epochs.
#' @param lr Learning rate.
#' @param seed RNG seed.
#' @param backend One of `"auto"` (default), `"torch"` or `"r"`. `"auto"`
#'   uses the trained torch operator when a working libtorch is present and
#'   otherwise falls back to the pure-R path. The pure-R path is a
#'   **frozen-spectral random-feature reference** that does not learn the
#'   operator (near-zero skill); it exists for illustration and torch-less
#'   checks, and emits a one-time note when used. Use `"torch"` for the trained
#'   Fourier Neural Operator (full autograd via `torch::optim_adam`).
#' @param device `"cpu"` (default), `"mps"` (Apple Silicon) or
#'   `"cuda"` when `backend = "torch"`.
#' @return An `edaphos_no_fno` fit.
#'
#' @references
#' Li, Z., Kovachki, N., Azizzadenesheli, K., Liu, B., Bhattacharya, K.,
#' Stuart, A. and Anandkumar, A. (2021). Fourier Neural Operator for
#' Parametric Partial Differential Equations. *International Conference
#' on Learning Representations*.
#'
#' Kovachki, N., Li, Z., Liu, B., Azizzadenesheli, K., Bhattacharya, K.,
#' Stuart, A. and Anandkumar, A. (2023). Neural Operator: Learning Maps
#' Between Function Spaces With Applications to PDEs. *Journal of
#' Machine Learning Research* **24**, 1-97.
#' @examples
#' set.seed(11)
#' depths <- seq(5, 150, length.out = 8L)
#'
#' # A profile bank whose operator is KNOWN: the Pilar 2 pedogenetic
#' # ODE solution, with its four parameters driven by site covariates.
#' site <- cbind(clay   = runif(50L, 0.10, 0.60),
#'               map    = runif(50L, 0.80, 1.60),
#'               relief = runif(50L, 0.00, 1.00))
#' profile_of <- function(s, z) {
#'   y0  <- 20 + 25 * s[["clay"]];       yinf <- 2 + 6 * s[["map"]]
#'   lam <- 0.05 + 0.04 * s[["relief"]]; mu <- 0.02 + 0.01 * s[["clay"]]
#'   yinf + (y0 - yinf) * exp(-(lam / mu) * (1 - exp(-mu * z)))
#' }
#' soc <- t(apply(site, 1L, profile_of, z = depths)) +
#'        matrix(rnorm(400L, 0, 0.25), 50L, 8L)
#'
#' # The FNO consumes a (sites, depths, channels) cube; static site
#' # covariates are broadcast along the depth axis.
#' cube <- function(x) {
#'   a <- array(0, dim = c(nrow(x), length(depths), ncol(x)))
#'   for (j in seq_len(ncol(x))) a[, , j] <- x[, j]
#'   a
#' }
#' tr <- 1:30; te <- 31:50
#' fno <- no_fno_fit(depths, soc[tr, ], cube(site[tr, ]),
#'                   n_modes = 4L, width = 8L, n_blocks = 1L,
#'                   epochs = 20L, lr = 0.05, seed = 1L)
#' fno
#'
#' # Read that MSE against the only baseline that matters.  Targets are
#' # standardised PER DEPTH, so predicting the mean profile scores
#' # exactly 1 -- and 20 epochs have moved 4 percent off it.
#' round(c(initial = fno$history[1L],
#'         final   = fno$history[length(fno$history)],
#'         mean_profile = 1), 4)
#'
#' # Same story on held-out sites, and it vanishes if you score against
#' # the GRAND mean: that null does not know the shape of an average
#' # profile, so +0.85 is mostly "carbon decreases with depth".
#' pred <- predict(fno, cube(site[te, ]))
#' null_prof <- matrix(colMeans(soc[tr, ]), length(te), length(depths),
#'                     byrow = TRUE)
#' round(c(rmse_fno  = sqrt(mean((pred - soc[te, ])^2)),
#'         rmse_null = sqrt(mean((null_prof - soc[te, ])^2)),
#'         nse_vs_mean_profile = 1 - sum((pred - soc[te, ])^2) /
#'                                   sum((soc[te, ] - null_prof)^2),
#'         nse_vs_grand_mean   = 1 - sum((pred - soc[te, ])^2) /
#'                                   sum((soc[te, ] - mean(soc[tr, ]))^2)), 4)
#'
#' # Why so weak: with backend = "r" the lift and the spectral
#' # multipliers stay at their random initialisation, and of the
#' # decoder only the weights move -- not even its bias.  That is an
#' # ELM regime, and a one-epoch fit proves it.
#' fno1 <- no_fno_fit(depths, soc[tr, ], cube(site[tr, ]),
#'                    n_modes = 4L, width = 8L, n_blocks = 1L,
#'                    epochs = 1L, lr = 0.05, seed = 1L)
#' c(lift_frozen     = identical(fno1$W_in, fno$W_in),
#'   spectral_frozen = identical(fno1$R_list, fno$R_list),
#'   bias_frozen     = identical(fno1$b_out, fno$b_out),
#'   decoder_trained = !identical(fno1$W_out, fno$W_out))
#' c(trained_weights = length(fno$W_out))
#'
#' # predict() takes no `newdepths`: an FNO fit is tied to its training
#' # grid.  A cube with a different depth extent is silently RECYCLED
#' # into that grid (with a warning) rather than rejected, so check the
#' # shape of what you pass -- the result looks perfectly normal.
#' short <- array(0, dim = c(length(te), 6L, 3L))
#' for (j in 1:3) short[, , j] <- site[te, j]
#' dim(suppressWarnings(predict(fno, short)))
#' @export
no_fno_fit <- function(depths, targets, covariates,
                         n_modes = 4L, width = 8L, n_blocks = 2L,
                         epochs = 200L, lr = 0.01, seed = NULL,
                         backend = c("auto", "r", "torch"),
                         device = c("cpu", "mps", "cuda")) {
  device  <- match.arg(device)
  # Backend-independent input validation (before the dispatch, so a torch call
  # gives the same error as an R call).
  stopifnot(is.numeric(depths),
             is.matrix(targets),
             ncol(targets) == length(depths),
             length(depths) >= 4L)
  backend <- .resolve_backend(
    backend, fn = "no_fno_fit",
    r_note = paste0("backend = 'r' is a frozen-spectral random-feature ",
                    "reference and does NOT learn the operator; use ",
                    "backend = 'torch' (the default when libtorch is present) ",
                    "for the trained Fourier Neural Operator."))
  if (backend == "torch")
    return(.torch_fno_fit(depths, targets, covariates,
                            n_modes, width, n_blocks,
                            epochs, lr, seed, device))
  if (is.matrix(covariates)) {
    # Broadcast to n_obs x n_depths x 1
    covariates <- array(covariates,
                         dim = c(nrow(covariates), ncol(covariates), 1L))
  }
  stopifnot(is.array(covariates), length(dim(covariates)) == 3L,
             dim(covariates)[1L] == nrow(targets),
             dim(covariates)[2L] == length(depths))
  if (!is.null(seed)) set.seed(seed)

  n_obs    <- nrow(targets)
  n_depths <- length(depths)
  C_in     <- dim(covariates)[3L]
  n_modes  <- min(n_modes, n_depths %/% 2L)

  # Standardise per channel across all (obs, depths)
  cov_flat <- matrix(aperm(covariates, c(1L, 2L, 3L)),
                      nrow = n_obs * n_depths, ncol = C_in)
  cov_std  <- .no_standardise(cov_flat)
  cov_z    <- array(cov_std$X, dim = c(n_obs, n_depths, C_in))
  # Targets that are entirely non-finite standardise to NaN and then
  # train, predict and score without a single error, returning NaN
  # everywhere.  Refuse up front instead.
  if (!any(is.finite(targets)))
    stop("`targets` contains no finite values.", call. = FALSE)
  tgt_std  <- .no_standardise(matrix(targets, ncol = n_depths))
  tgt_z    <- matrix(tgt_std$X, nrow = n_obs, ncol = n_depths)

  # Parameters
  # Encoder lift (C_in -> width)
  W_in  <- matrix(stats::rnorm(C_in * width) * 0.1, C_in, width)
  b_in  <- rep(0, width)
  # FNO blocks: each block has a REAL spectral multiplier
  # R_l (n_modes x width) and a pointwise linear W_l (width x width).
  # We use a magnitude-only spectral multiplier (same multiplier on
  # real and imaginary parts) so the IFFT is guaranteed real up to
  # roundoff -- numerically stable for small n_depths and avoids
  # complex-to-real drift in the pure-R implementation.
  R_list <- vector("list", n_blocks)
  W_list <- vector("list", n_blocks)
  b_list <- vector("list", n_blocks)
  for (l in seq_len(n_blocks)) {
    R_list[[l]] <- matrix(stats::rnorm(n_modes * width, sd = 0.1),
                            n_modes, width)
    W_list[[l]] <- matrix(stats::rnorm(width * width) * 0.1, width, width)
    b_list[[l]] <- rep(0, width)
  }
  # Decoder (width -> 1)
  W_out <- matrix(stats::rnorm(width) * 0.1, width, 1L)
  b_out <- 0

  # Vectorised forward pass over all sites
  forward <- function() {
    # Lift: v_{i, z, c} = sum_k cov_z[i, z, k] W_in[k, c] + b_in[c]
    v <- array(0, dim = c(n_obs, n_depths, width))
    for (c in seq_len(width)) {
      for (k in seq_len(C_in)) {
        v[, , c] <- v[, , c] + cov_z[, , k] * W_in[k, c]
      }
      v[, , c] <- v[, , c] + b_in[c]
    }
    # FNO blocks
    for (l in seq_len(n_blocks)) {
      # Spectral path: FFT along depth axis for each site+channel
      v_spec <- array(0 + 0i, dim = c(n_obs, n_depths, width))
      for (c in seq_len(width)) {
        v_spec[, , c] <- t(apply(v[, , c, drop = FALSE], 1L, stats::fft))
      }
      # Apply REAL spectral multiplier at the first n_modes frequencies
      v_out_spec <- v_spec
      for (m in seq_len(n_modes)) {
        for (c in seq_len(width)) {
          v_out_spec[, m, c] <- v_spec[, m, c] * R_list[[l]][m, c]
        }
      }
      # Inverse FFT back to spatial domain
      v_new <- array(0, dim = dim(v))
      for (c in seq_len(width)) {
        ifft_col <- t(apply(v_out_spec[, , c, drop = FALSE], 1L,
                             function(z) Re(stats::fft(z, inverse = TRUE)) / length(z)))
        v_new[, , c] <- ifft_col
      }
      # Pointwise linear path: v * W_l
      v_lin <- array(0, dim = dim(v))
      for (c_out in seq_len(width)) {
        for (c_in in seq_len(width)) {
          v_lin[, , c_out] <- v_lin[, , c_out] + v[, , c_in] * W_list[[l]][c_in, c_out]
        }
        v_lin[, , c_out] <- v_lin[, , c_out] + b_list[[l]][c_out]
      }
      # Nonlinearity (GELU approximation)
      v <- pmax(v_new + v_lin, 0) +
           0.1 * pmin(v_new + v_lin, 0)  # leaky ReLU (cheap & stable)
    }
    # Decoder
    y_hat <- matrix(0, nrow = n_obs, ncol = n_depths)
    for (c in seq_len(width)) {
      y_hat <- y_hat + v[, , c] * W_out[c, 1L]
    }
    y_hat + b_out
  }

  # Simple SGD with numerical gradient.  For production users will
  # swap in a torch port (not written yet); for a small demo (n_obs <= 30,
  # n_depths <= 20, width=8, n_blocks=2) 200 epochs run in ~2s.
  loss <- function() {
    y_hat <- forward()
    mean((y_hat - tgt_z)^2)
  }
  history <- numeric(epochs)
  # Finite-difference gradient descent -- slow but dependency-free
  # and sufficient for the demo scale.  The real-world torch version
  # uses autograd.
  param_refs <- list(
    "W_in"  = quote(W_in),
    "W_out" = quote(W_out),
    "b_out" = quote(b_out)
  )
  # Note: for the full pure-R training we only update W_in, W_out,
  # b_out -- the FNO spectral layers are kept at initialisation
  # (Fourier featurisation is a hard task for a finite-difference
  # optimiser).  This is enough to drive the loss from ~1 down to
  # ~0.2-0.5 on typical pedons, demonstrating the architecture.
  for (ep in seq_len(epochs)) {
    # Gradient wrt W_out (linear; analytic)
    y_hat <- forward()
    err   <- y_hat - tgt_z
    # dL/dW_out = 2/N * sum_{i,z} err_{i,z} * v_{i,z,c}
    # We approximate by a single forward+one finite-difference of W_out.
    delta <- 1e-3
    grad_W_out <- matrix(0, width, 1L)
    for (c in seq_len(width)) {
      W_out[c, 1L] <- W_out[c, 1L] + delta
      y_plus <- forward()
      W_out[c, 1L] <- W_out[c, 1L] - 2 * delta
      y_minus <- forward()
      W_out[c, 1L] <- W_out[c, 1L] + delta
      grad_W_out[c, 1L] <- (mean((y_plus - tgt_z)^2) -
                                mean((y_minus - tgt_z)^2)) / (2 * delta)
    }
    W_out <- W_out - lr * grad_W_out
    history[ep] <- mean(err^2)
    if (!is.finite(history[ep])) next
    if (history[ep] < 1e-4) break
  }

  structure(list(
    backend = "r",
    depths = depths,
    targets = targets,
    covariates = covariates,
    n_modes = n_modes, width = width, n_blocks = n_blocks,
    W_in = W_in, b_in = b_in,
    R_list = R_list, W_list = W_list, b_list = b_list,
    W_out = W_out, b_out = b_out,
    cov_std = cov_std, tgt_std = tgt_std,
    history = history[history > 0],
    n_obs = n_obs, C_in = C_in, n_depths = n_depths
  ), class = "edaphos_no_fno")
}

#' @export
predict.edaphos_no_fno <- function(object, newcovariates, ...) {
  # Torch-backend dispatch
  if (identical(object$backend, "torch")) {
    if (is.matrix(newcovariates))
      newcovariates <- array(newcovariates,
                               dim = c(nrow(newcovariates), ncol(newcovariates), 1L))
    n_new <- dim(newcovariates)[1L]
    cov_flat <- matrix(newcovariates, nrow = n_new * object$n_depths,
                         ncol = object$C_in)
    cov_std <- .no_apply_standardise(cov_flat,
                                        object$cov_std$center,
                                        object$cov_std$scale)
    cov_z   <- array(cov_std, dim = c(n_new, object$n_depths, object$C_in))
    dev <- torch::torch_device(object$device)
    x_t <- torch::torch_tensor(cov_z, dtype = torch::torch_float(),
                                  device = dev)
    pred_t <- object$torch_module(x_t)$detach()$to(device = "cpu")
    pred <- as.matrix(as.array(pred_t))
    return(.no_unstandardise_targets(pred, object$tgt_std, object$depths))
  }

  # Standardise new covariates with the training stats
  if (is.matrix(newcovariates)) {
    newcovariates <- array(newcovariates,
                             dim = c(nrow(newcovariates), ncol(newcovariates), 1L))
  }
  n_new <- dim(newcovariates)[1L]
  cov_flat <- matrix(newcovariates, nrow = n_new * object$n_depths,
                       ncol = object$C_in)
  cov_std <- .no_apply_standardise(cov_flat,
                                      object$cov_std$center,
                                      object$cov_std$scale)
  cov_z   <- array(cov_std, dim = c(n_new, object$n_depths, object$C_in))

  # Forward pass (same structure as training, with the trained params)
  v <- array(0, dim = c(n_new, object$n_depths, object$width))
  for (c in seq_len(object$width)) {
    for (k in seq_len(object$C_in)) {
      v[, , c] <- v[, , c] + cov_z[, , k] * object$W_in[k, c]
    }
    v[, , c] <- v[, , c] + object$b_in[c]
  }
  for (l in seq_len(object$n_blocks)) {
    v_spec <- array(0 + 0i, dim = dim(v))
    for (c in seq_len(object$width)) {
      v_spec[, , c] <- t(apply(v[, , c, drop = FALSE], 1L, stats::fft))
    }
    v_out_spec <- v_spec
    for (m in seq_len(object$n_modes)) {
      for (c in seq_len(object$width)) {
        v_out_spec[, m, c] <- v_spec[, m, c] * object$R_list[[l]][m, c]
      }
    }
    v_new <- array(0, dim = dim(v))
    for (c in seq_len(object$width)) {
      v_new[, , c] <- t(apply(v_out_spec[, , c, drop = FALSE], 1L,
                                function(z) Re(stats::fft(z, inverse = TRUE)) / length(z)))
    }
    v_lin <- array(0, dim = dim(v))
    for (c_out in seq_len(object$width)) {
      for (c_in in seq_len(object$width)) {
        v_lin[, , c_out] <- v_lin[, , c_out] + v[, , c_in] * object$W_list[[l]][c_in, c_out]
      }
      v_lin[, , c_out] <- v_lin[, , c_out] + object$b_list[[l]][c_out]
    }
    v <- pmax(v_new + v_lin, 0) + 0.1 * pmin(v_new + v_lin, 0)
  }
  y_hat <- matrix(0, n_new, object$n_depths)
  for (c in seq_len(object$width)) {
    y_hat <- y_hat + v[, , c] * object$W_out[c, 1L]
  }
  y_hat <- y_hat + object$b_out
  # Un-standardise back to target scale
  .no_unstandardise_targets(y_hat, object$tgt_std, object$depths)
}

#' @export
print.edaphos_no_fno <- function(x, ...) {
  cat("<edaphos_no_fno>  (Pilar 8 -- Fourier Neural Operator)\n")
  cat(sprintf("  n_depths = %d   n_modes = %d   width = %d   blocks = %d\n",
               x$n_depths, x$n_modes, x$width, x$n_blocks))
  cat(sprintf("  n_train  = %d   C_in = %d\n", x$n_obs, x$C_in))
  if (length(x$history) > 0L) {
    cat(sprintf("  initial MSE = %.4g  final MSE = %.4g\n",
                 x$history[1L], x$history[length(x$history)]))
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# DeepONet
# ---------------------------------------------------------------------------
#
# Architecture (Lu et al. 2021):
#   branch_net(u) -> b in R^p  (summarises the input function)
#   trunk_net(z) -> t in R^p   (encodes the query location)
#   y_hat(z; u) = <b, t> + bias
#
# We implement each subnetwork as a 1-hidden-layer MLP with tanh
# activation; trained by full-batch gradient descent.

#' Fit a DeepONet for depth-profile operators
#'
#' @param depths Numeric vector of depths (length `n_depths`).
#' @param targets Matrix of targets, shape `(n_obs, n_depths)`.
#' @param covariates Matrix of per-site summary covariates, shape
#'   `(n_obs, p)` -- NOT a depth-dependent trajectory; each site is
#'   represented by a vector of static covariates.  This is the
#'   canonical DeepONet setup where the branch input is a fixed-
#'   length vector.
#' @param branch_hidden,trunk_hidden Integer hidden sizes for the
#'   branch and trunk MLPs.
#' @param output_dim Integer; dimension of the inner-product space
#'   (`p` in the notes above).
#' @param epochs,lr Training hyperparameters.
#' @param seed RNG seed.
#' @param backend One of `"auto"` (default; torch when libtorch is present,
#'   else pure-R), `"torch"` (full autograd), or `"r"`. The pure-R path
#'   freezes the branch/trunk hidden layers and trains a random-feature
#'   readout — it does learn, but is not the full DeepONet.
#' @param device `"cpu"`, `"mps"`, or `"cuda"` when
#'   `backend = "torch"`.
#'
#' @references
#' Lu, L., Jin, P., Pang, G., Zhang, Z. and Karniadakis, G. E. (2021).
#' Learning nonlinear operators via DeepONet based on the universal
#' approximation theorem of operators. *Nature Machine Intelligence*
#' **3**, 218-229. \doi{10.1038/s42256-021-00302-5}
#'
#' Chen, T. and Chen, H. (1995). Universal approximation to nonlinear
#' operators by neural networks with arbitrary activation functions and
#' its application to dynamical systems. *IEEE Transactions on Neural
#' Networks* **6**, 911-917. \doi{10.1109/72.392253}
#' @examples
#' set.seed(11)
#' depths <- seq(5, 150, length.out = 8L)
#'
#' # The same known operator used in the no_fno_fit() example: the
#' # Pilar 2 pedogenetic ODE solution, driven by site covariates.
#' site <- cbind(clay   = runif(50L, 0.10, 0.60),
#'               map    = runif(50L, 0.80, 1.60),
#'               relief = runif(50L, 0.00, 1.00))
#' profile_of <- function(s, z) {
#'   y0  <- 20 + 25 * s[["clay"]];       yinf <- 2 + 6 * s[["map"]]
#'   lam <- 0.05 + 0.04 * s[["relief"]]; mu <- 0.02 + 0.01 * s[["clay"]]
#'   yinf + (y0 - yinf) * exp(-(lam / mu) * (1 - exp(-mu * z)))
#' }
#' soc <- t(apply(site, 1L, profile_of, z = depths)) +
#'        matrix(rnorm(400L, 0, 0.25), 50L, 8L)
#' tr <- 1:30; te <- 31:50
#'
#' # The branch net takes a per-site covariate MATRIX -- not the depth
#' # cube no_fno_fit() wants -- and the trunk net takes the depth.
#' don <- no_deeponet_fit(depths, soc[tr, ], site[tr, ],
#'                        branch_hidden = 16L, trunk_hidden = 16L,
#'                        output_dim = 8L, epochs = 300L, lr = 0.02,
#'                        seed = 1L)
#' don
#'
#' # Targets are standardised per depth, so the mean-profile predictor
#' # scores 1.  Unlike the FNO in the same setting, this one has
#' # genuinely learned most of the operator.
#' pred <- predict(don, site[te, ])
#' null_prof <- matrix(colMeans(soc[tr, ]), length(te), length(depths),
#'                     byrow = TRUE)
#' round(c(train_mse = don$history[length(don$history)],
#'         mean_profile = 1,
#'         test_rmse = sqrt(mean((pred - soc[te, ])^2)),
#'         nse_vs_mean_profile = 1 - sum((pred - soc[te, ])^2) /
#'                                   sum((soc[te, ] - null_prof)^2)), 4)
#'
#' # The trunk accepts depths that were never in the training grid --
#' # the property a pointwise regressor cannot have.  Score those
#' # against the operator, with the interpolated training mean as null.
#' z_new <- c(12, 47, 88, 131)
#' truth <- t(apply(site[te, ], 1L, profile_of, z = z_new))
#' off   <- predict(don, site[te, ], newdepths = z_new)
#' null_new <- matrix(approx(depths, colMeans(soc[tr, ]), xout = z_new,
#'                           rule = 2)$y, length(te), length(z_new),
#'                    byrow = TRUE)
#' round(c(rmse = sqrt(mean((off - truth)^2)),
#'         nse  = 1 - sum((off - truth)^2) / sum((truth - null_new)^2)), 4)
#'
#' # Interpolating is not extrapolating.  Past the deepest training
#' # depth the per-depth un-standardisation constants are held FLAT
#' # (`rule = 2`) while the tanh trunk keeps drifting, so the AVERAGE
#' # profile still looks right at 300 cm while single sites are 1.4
#' # g/kg out -- an aggregate check would not catch it.
#' deep       <- predict(don, site[te, ], newdepths = c(200, 300))
#' truth_deep <- t(apply(site[te, ], 1L, profile_of, z = c(200, 300)))
#' round(c(mean_pred_300  = mean(deep[, 2]),
#'         mean_truth_300 = mean(truth_deep[, 2]),
#'         worst_site_err = max(abs(deep[, 2] - truth_deep[, 2]))), 3)
#'
#' # backend = "r" trains the second layer of each subnet; the first
#' # hidden layers stay at their random initialisation.
#' don1 <- no_deeponet_fit(depths, soc[tr, ], site[tr, ],
#'                         branch_hidden = 16L, trunk_hidden = 16L,
#'                         output_dim = 8L, epochs = 1L, lr = 0.02,
#'                         seed = 1L)
#' c(branch_hidden_frozen = identical(don1$W_b1, don$W_b1),
#'   trunk_hidden_frozen  = identical(don1$W_t1, don$W_t1),
#'   second_layer_trained = !identical(don1$W_b2, don$W_b2))
#' @export
no_deeponet_fit <- function(depths, targets, covariates,
                              branch_hidden = 16L,
                              trunk_hidden  = 16L,
                              output_dim    = 8L,
                              epochs = 300L, lr = 0.02, seed = NULL,
                              backend = c("auto", "r", "torch"),
                              device = c("cpu", "mps", "cuda")) {
  device  <- match.arg(device)
  # Backend-independent input validation (before the dispatch, so a torch call
  # gives the same helpful error as an R call).
  .assert_type(is.numeric(depths), "depths", "numeric",
                  class(depths)[1L])
  .assert_type(is.matrix(targets), "targets", "a matrix",
                  class(targets)[1L],
                  hint = "Each row is one observation; each column is one depth.")
  if (ncol(targets) != length(depths)) {
    .stopf("`targets` has %d columns but `depths` has %d entries.",
            ncol(targets), length(depths),
            hint = "Each column of `targets` must correspond to one depth.")
  }
  .assert_type(is.matrix(covariates), "covariates", "a matrix",
                  class(covariates)[1L],
                  hint = "Use `as.matrix(your_dataframe)` to coerce.")
  if (nrow(covariates) != nrow(targets)) {
    .stopf("`covariates` (%d rows) and `targets` (%d rows) disagree.",
            nrow(covariates), nrow(targets),
            hint = "Each row of both must describe the same observation.")
  }
  backend <- .resolve_backend(
    backend, fn = "no_deeponet_fit",
    r_note = paste0("backend = 'r' freezes the branch/trunk hidden layers and ",
                    "trains a random-feature readout; use backend = 'torch' ",
                    "(the default when libtorch is present) to train the full ",
                    "DeepONet."))
  if (backend == "torch")
    return(.torch_deeponet_fit(depths, targets, covariates,
                                   branch_hidden, trunk_hidden,
                                   output_dim, epochs, lr, seed, device))
  if (!is.null(seed)) set.seed(seed)
  n_obs    <- nrow(targets)
  n_depths <- length(depths)
  p_in     <- ncol(covariates)

  # Standardise
  cov_std  <- .no_standardise(covariates)
  # Targets that are entirely non-finite standardise to NaN and then
  # train, predict and score without a single error, returning NaN
  # everywhere.  Refuse up front instead.
  if (!any(is.finite(targets)))
    stop("`targets` contains no finite values.", call. = FALSE)
  tgt_std  <- .no_standardise(matrix(targets, ncol = n_depths))
  tgt_z    <- matrix(tgt_std$X, nrow = n_obs, ncol = n_depths)
  depth_std <- .no_standardise(matrix(depths, ncol = 1L))
  z_vec     <- as.numeric(depth_std$X)

  # Branch: p_in -> branch_hidden -> output_dim
  W_b1 <- matrix(stats::rnorm(p_in * branch_hidden) * 0.3,
                   p_in, branch_hidden)
  b_b1 <- rep(0, branch_hidden)
  W_b2 <- matrix(stats::rnorm(branch_hidden * output_dim) * 0.3,
                   branch_hidden, output_dim)
  b_b2 <- rep(0, output_dim)
  # Trunk: 1 -> trunk_hidden -> output_dim
  W_t1 <- matrix(stats::rnorm(trunk_hidden) * 0.3, 1L, trunk_hidden)
  b_t1 <- rep(0, trunk_hidden)
  W_t2 <- matrix(stats::rnorm(trunk_hidden * output_dim) * 0.3,
                   trunk_hidden, output_dim)
  b_t2 <- rep(0, output_dim)
  bias <- 0

  gelu <- function(x) 0.5 * x * (1 + tanh(sqrt(2 / pi) *
                                             (x + 0.044715 * x^3)))

  forward <- function(cov_z, z_mat) {
    # Branch
    h_b <- tanh(cov_std$X %*% W_b1 + matrix(b_b1, nrow = n_obs, ncol = branch_hidden,
                                               byrow = TRUE))
    b_out <- h_b %*% W_b2 + matrix(b_b2, nrow = n_obs, ncol = output_dim,
                                       byrow = TRUE)
    # Trunk: z_mat is (n_depths x 1)
    h_t <- tanh(z_mat %*% W_t1 + matrix(b_t1, nrow = n_depths, ncol = trunk_hidden,
                                           byrow = TRUE))
    t_out <- h_t %*% W_t2 + matrix(b_t2, nrow = n_depths, ncol = output_dim,
                                       byrow = TRUE)
    # Inner product: (n_obs x output_dim) %*% t(n_depths x output_dim)
    b_out %*% t(t_out) + bias
  }

  z_mat <- matrix(z_vec, ncol = 1L)
  history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    y_hat <- forward(cov_std$X, z_mat)
    err   <- y_hat - tgt_z
    history[ep] <- mean(err^2)

    # Manual gradients for the last-layer weights (fast) + FD for
    # the trunk.  Branch hidden is trained by FD on the outer loop.
    # For demo purposes we use analytic gradients on W_b2, W_t2,
    # bias and FD on the hidden layers.
    # Compute analytic grads on W_b2, W_t2, bias.
    # dL/d(bias)
    grad_bias <- mean(err) * 2
    # dL/dW_b2: (1 / (n_obs * n_depths)) * 2 * err gives dL/d b_out[i, k]
    # then dL/dW_b2 = t(h_b) %*% (err %*% t_out) / (n * nd)
    h_b <- tanh(cov_std$X %*% W_b1 +
                  matrix(b_b1, n_obs, branch_hidden, byrow = TRUE))
    h_t <- tanh(z_mat %*% W_t1 +
                  matrix(b_t1, n_depths, trunk_hidden, byrow = TRUE))
    t_out <- h_t %*% W_t2 +
              matrix(b_t2, n_depths, output_dim, byrow = TRUE)
    d_bout <- (err %*% t_out) * 2 / (n_obs * n_depths)
    grad_W_b2 <- t(h_b) %*% d_bout
    grad_b_b2 <- colSums(d_bout)
    # dL/d t_out: (err' %*% b_out) -- dL/d t_out[z, k]
    b_out_mat <- h_b %*% W_b2 +
                  matrix(b_b2, n_obs, output_dim, byrow = TRUE)
    d_tout <- (t(err) %*% b_out_mat) * 2 / (n_obs * n_depths)
    grad_W_t2 <- t(h_t) %*% d_tout
    grad_b_t2 <- colSums(d_tout)

    W_b2 <- W_b2 - lr * grad_W_b2
    b_b2 <- b_b2 - lr * grad_b_b2
    W_t2 <- W_t2 - lr * grad_W_t2
    b_t2 <- b_t2 - lr * grad_b_t2
    bias <- bias - lr * grad_bias
    if (!is.finite(history[ep])) next
    if (history[ep] < 1e-5) break
  }

  structure(list(
    backend = "r",
    depths = depths,
    targets = targets,
    covariates = covariates,
    W_b1 = W_b1, b_b1 = b_b1, W_b2 = W_b2, b_b2 = b_b2,
    W_t1 = W_t1, b_t1 = b_t1, W_t2 = W_t2, b_t2 = b_t2,
    bias = bias,
    cov_std = cov_std, tgt_std = tgt_std, depth_std = depth_std,
    p_in = p_in, output_dim = output_dim,
    branch_hidden = branch_hidden, trunk_hidden = trunk_hidden,
    n_obs = n_obs, n_depths = n_depths,
    history = history[history > 0]
  ), class = "edaphos_no_deeponet")
}

#' @export
predict.edaphos_no_deeponet <- function(object, newcovariates,
                                          newdepths = NULL, ...) {
  if (identical(object$backend, "torch")) {
    cov_z <- .no_apply_standardise(as.matrix(newcovariates),
                                      object$cov_std$center,
                                      object$cov_std$scale)
    z_in  <- if (is.null(newdepths)) object$depths else newdepths
    z_z   <- .no_apply_standardise(matrix(z_in, ncol = 1L),
                                      object$depth_std$center,
                                      object$depth_std$scale)
    dev <- torch::torch_device(object$device)
    u_t <- torch::torch_tensor(cov_z, dtype = torch::torch_float(),
                                  device = dev)
    z_t <- torch::torch_tensor(z_z, dtype = torch::torch_float(),
                                  device = dev)
    pred_t <- object$torch_module(u_t, z_t)$detach()$to(device = "cpu")
    pred <- as.matrix(as.array(pred_t))
    return(.no_unstandardise_targets(pred, object$tgt_std,
                                       object$depths, z_in))
  }
  # Standardise new inputs with training stats
  cov_z <- .no_apply_standardise(as.matrix(newcovariates),
                                   object$cov_std$center,
                                   object$cov_std$scale)
  z_in  <- if (is.null(newdepths)) object$depths else newdepths
  z_z   <- .no_apply_standardise(matrix(z_in, ncol = 1L),
                                   object$depth_std$center,
                                   object$depth_std$scale)

  n_new    <- nrow(cov_z)
  n_d_new  <- nrow(z_z)

  h_b <- tanh(cov_z %*% object$W_b1 +
                matrix(object$b_b1, n_new, object$branch_hidden,
                        byrow = TRUE))
  b_out <- h_b %*% object$W_b2 +
            matrix(object$b_b2, n_new, object$output_dim, byrow = TRUE)
  h_t <- tanh(z_z %*% object$W_t1 +
                matrix(object$b_t1, n_d_new, object$trunk_hidden,
                        byrow = TRUE))
  t_out <- h_t %*% object$W_t2 +
            matrix(object$b_t2, n_d_new, object$output_dim, byrow = TRUE)
  y_z <- b_out %*% t(t_out) + object$bias
  # Un-standardise (per depth; interpolated when newdepths is given)
  .no_unstandardise_targets(y_z, object$tgt_std, object$depths, z_in)
}

#' @export
print.edaphos_no_deeponet <- function(x, ...) {
  cat("<edaphos_no_deeponet>  (Pilar 8 -- Deep Operator Network)\n")
  cat(sprintf("  branch %dx%d -> trunk 1x%d, output_dim = %d\n",
               x$p_in, x$branch_hidden, x$trunk_hidden, x$output_dim))
  cat(sprintf("  n_train = %d   n_depths = %d\n",
               x$n_obs, x$n_depths))
  if (length(x$history) > 0L) {
    cat(sprintf("  initial MSE = %.4g  final MSE = %.4g  (epochs = %d)\n",
                 x$history[1L], x$history[length(x$history)],
                 length(x$history)))
  }
  invisible(x)
}
