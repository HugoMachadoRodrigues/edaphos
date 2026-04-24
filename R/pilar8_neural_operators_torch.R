# Pilar 8 -- torch/autograd backend (edaphos v2.7.0).
#
# Full-gradient replacements for the v2.4.0 ELM-style FNO and
# DeepONet.  Activated by `backend = "torch"` on the existing fit
# functions; the pure-R implementations remain the default fallback
# so users without the torch runtime get a working baseline.
#
# Design contract
# ---------------
# * Identical public return-class (`edaphos_no_fno`, `edaphos_no_deeponet`)
#   so predict() dispatch keeps working.
# * `backend` is recorded in the object and routed through predict().
# * Training uses torch::optim_adam with cosine LR schedule;
#   standardisation is identical to the pure-R path so loss histories
#   are comparable.

# ---------------------------------------------------------------------------
# FNO torch module
# ---------------------------------------------------------------------------

.torch_fno_module <- function(C_in, n_depths, n_modes, width,
                                 n_blocks = 2L, out_dim = 1L) {
  torch::nn_module(
    "edaphos_fno_torch",
    initialize = function() {
      self$W_in  <- torch::nn_linear(C_in, width)
      self$out_head <- torch::nn_linear(width, out_dim)
      self$R <- torch::nn_parameter(
        torch::torch_randn(c(n_blocks, n_modes, width)) * 0.1
      )
      self$Wblk <- torch::nn_module_list(
        lapply(seq_len(n_blocks), function(i) torch::nn_linear(width, width))
      )
      self$n_blocks <- n_blocks
      self$n_modes  <- n_modes
      self$n_depths <- n_depths
      self$width    <- width
      self$out_dim  <- out_dim
    },
    forward = function(x) {
      # x: (batch, n_depths, C_in)
      h <- self$W_in(x)   # (batch, n_depths, width)
      for (i in seq_len(self$n_blocks)) {
        # FFT along depth axis
        h_perm <- h$permute(c(1L, 3L, 2L))      # (batch, width, n_depths)
        h_spec <- torch::torch_fft_rfft(h_perm, dim = 3L)
        # Truncated spectral multiplier: real magnitude on first n_modes
        mult <- self$R[i]$unsqueeze(1L)        # (1, n_modes, width)
        mult <- mult$permute(c(1L, 3L, 2L))    # (1, width, n_modes)
        n_freq <- h_spec$size(3L)
        keep_m <- min(self$n_modes, n_freq)
        # Zero-pad multiplier to full freq axis, then multiply
        pad_shape <- c(1L, self$width, n_freq - keep_m)
        mult_full <- torch::torch_cat(
          list(mult[, , 1:keep_m, drop = FALSE],
                torch::torch_ones(pad_shape)),
          dim = 3L
        )
        h_spec_new <- h_spec * mult_full
        h_spatial  <- torch::torch_fft_irfft(h_spec_new,
                                                n = self$n_depths,
                                                dim = 3L)
        h_new <- h_spatial$permute(c(1L, 3L, 2L))  # back to (batch, n_depths, width)
        # Residual pointwise linear + leaky-ReLU
        h_lin <- self$Wblk[[i]](h)
        h <- torch::nnf_leaky_relu(h_new + h_lin, negative_slope = 0.1)
      }
      y <- self$out_head(h)     # (batch, n_depths, out_dim)
      y$squeeze(3L)
    }
  )()
}

.torch_fno_fit <- function(depths, targets, covariates,
                              n_modes, width, n_blocks,
                              epochs, lr, seed, device_pref) {
  if (!is.null(seed)) {
    set.seed(seed); torch::torch_manual_seed(seed)
  }
  device_str <- if (identical(device_pref, "mps") &&
                      torch::backends_mps_is_available()) "mps"
                 else if (identical(device_pref, "cuda") &&
                             torch::cuda_is_available()) "cuda"
                 else "cpu"
  dev <- torch::torch_device(device_str)

  # Build arrays
  if (is.matrix(covariates))
    covariates <- array(covariates,
                         dim = c(nrow(covariates), ncol(covariates), 1L))
  n_obs <- dim(covariates)[1L]
  n_depths <- dim(covariates)[2L]; C_in <- dim(covariates)[3L]
  cov_flat <- matrix(covariates, nrow = n_obs * n_depths, ncol = C_in)
  cov_std  <- .no_standardise(cov_flat)
  cov_z    <- array(cov_std$X, dim = c(n_obs, n_depths, C_in))
  tgt_std  <- .no_standardise(matrix(targets, ncol = n_depths))
  tgt_z    <- matrix(tgt_std$X, nrow = n_obs, ncol = n_depths)

  # Torch tensors
  x_t <- torch::torch_tensor(cov_z, dtype = torch::torch_float(),
                                device = dev)
  y_t <- torch::torch_tensor(tgt_z, dtype = torch::torch_float(),
                                device = dev)

  mod <- .torch_fno_module(C_in = C_in, n_depths = n_depths,
                              n_modes = min(n_modes, n_depths %/% 2L),
                              width = width, n_blocks = n_blocks)
  mod$to(device = dev)
  opt <- torch::optim_adam(mod$parameters, lr = lr)
  history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    opt$zero_grad()
    pred <- mod(x_t)
    loss <- torch::nnf_mse_loss(pred, y_t)
    loss$backward()
    opt$step()
    history[ep] <- as.numeric(loss$detach()$to(device = "cpu"))
    if (is.finite(history[ep]) && history[ep] < 1e-6) break
  }

  structure(list(
    backend = "torch",
    depths = depths, targets = targets, covariates = covariates,
    n_modes = min(n_modes, n_depths %/% 2L),
    width = width, n_blocks = n_blocks,
    torch_module = mod, device = device_str,
    cov_std = cov_std, tgt_std = tgt_std,
    history = history[history > 0 | is.na(history)],
    n_obs = n_obs, C_in = C_in, n_depths = n_depths
  ), class = "edaphos_no_fno")
}

# ---------------------------------------------------------------------------
# DeepONet torch module
# ---------------------------------------------------------------------------

.torch_deeponet_module <- function(p_in, branch_hidden, trunk_hidden,
                                       output_dim) {
  torch::nn_module(
    "edaphos_deeponet_torch",
    initialize = function() {
      self$branch <- torch::nn_sequential(
        torch::nn_linear(p_in, branch_hidden),
        torch::nn_tanh(),
        torch::nn_linear(branch_hidden, output_dim)
      )
      self$trunk <- torch::nn_sequential(
        torch::nn_linear(1L, trunk_hidden),
        torch::nn_tanh(),
        torch::nn_linear(trunk_hidden, output_dim)
      )
      self$bias <- torch::nn_parameter(torch::torch_zeros(1L))
    },
    forward = function(u, z) {
      # u: (n_obs, p_in); z: (n_depths, 1)
      b <- self$branch(u)    # (n_obs, output_dim)
      t <- self$trunk(z)     # (n_depths, output_dim)
      torch::torch_matmul(b, t$t()) + self$bias
    }
  )()
}

.torch_deeponet_fit <- function(depths, targets, covariates,
                                   branch_hidden, trunk_hidden,
                                   output_dim, epochs, lr, seed,
                                   device_pref) {
  if (!is.null(seed)) {
    set.seed(seed); torch::torch_manual_seed(seed)
  }
  device_str <- if (identical(device_pref, "mps") &&
                      torch::backends_mps_is_available()) "mps"
                 else if (identical(device_pref, "cuda") &&
                             torch::cuda_is_available()) "cuda"
                 else "cpu"
  dev <- torch::torch_device(device_str)

  n_obs    <- nrow(targets); n_depths <- length(depths)
  p_in     <- ncol(covariates)
  cov_std  <- .no_standardise(covariates)
  tgt_std  <- .no_standardise(matrix(targets, ncol = n_depths))
  tgt_z    <- matrix(tgt_std$X, nrow = n_obs, ncol = n_depths)
  depth_std <- .no_standardise(matrix(depths, ncol = 1L))

  u_t <- torch::torch_tensor(cov_std$X, dtype = torch::torch_float(),
                                device = dev)
  z_t <- torch::torch_tensor(depth_std$X, dtype = torch::torch_float(),
                                device = dev)
  y_t <- torch::torch_tensor(tgt_z, dtype = torch::torch_float(),
                                device = dev)

  mod <- .torch_deeponet_module(p_in, branch_hidden, trunk_hidden,
                                    output_dim)
  mod$to(device = dev)
  opt <- torch::optim_adam(mod$parameters, lr = lr)
  history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    opt$zero_grad()
    pred <- mod(u_t, z_t)
    loss <- torch::nnf_mse_loss(pred, y_t)
    loss$backward()
    opt$step()
    history[ep] <- as.numeric(loss$detach()$to(device = "cpu"))
    if (is.finite(history[ep]) && history[ep] < 1e-7) break
  }

  structure(list(
    backend = "torch",
    depths = depths, targets = targets, covariates = covariates,
    torch_module = mod, device = device_str,
    cov_std = cov_std, tgt_std = tgt_std, depth_std = depth_std,
    p_in = p_in, output_dim = output_dim,
    branch_hidden = branch_hidden, trunk_hidden = trunk_hidden,
    n_obs = n_obs, n_depths = n_depths,
    history = history[history > 0 | is.na(history)]
  ), class = "edaphos_no_deeponet")
}
