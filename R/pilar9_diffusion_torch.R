# Pilar 9 -- torch/autograd DDPM with a 2-D U-Net denoiser
# (edaphos v2.7.0).
#
# Replaces the v2.5.0 ELM-style MLP with a real conv-U-Net that
# respects the spatial structure of soil-map patches.
#
# Architecture
# ------------
#   Encoder:
#     Conv2d(1 -> 16, 3x3) -> GELU -> Conv2d(16 -> 16, 3x3) -> GELU
#     MaxPool(2)  (skip1)
#     Conv2d(16 -> 32, 3x3) -> GELU -> Conv2d(32 -> 32, 3x3) -> GELU
#     MaxPool(2)  (skip2)
#   Bottleneck:
#     Conv2d(32 -> 64, 3x3) -> GELU + time-embedding bias
#   Decoder:
#     UpsampleNN(2) -> Conv2d(64 -> 32) -> cat(skip2) -> Conv2d(64 -> 32)
#     UpsampleNN(2) -> Conv2d(32 -> 16) -> cat(skip1) -> Conv2d(32 -> 16)
#     Conv2d(16 -> 1, 1x1)
#   Time embedding:
#     sinusoidal(time_dim) -> MLP(time_dim, 32)  broadcast add to
#     bottleneck feature map.
#   Conditioning:
#     Linear(cond_dim -> 16) -> broadcast add to the first encoder
#     block (classifier-free style; dropout to 0 with prob 0.1 during
#     training to enable unconditional sampling at inference).

# ---------------------------------------------------------------------------
# Time embedding
# ---------------------------------------------------------------------------

.torch_sinusoidal_embed <- function(t_scalar, dim) {
  half <- dim %/% 2L
  freqs <- torch::torch_exp(
    -log(10000) * torch::torch_arange(0, half - 1L) / half
  )
  args <- t_scalar * freqs
  torch::torch_cat(list(torch::torch_sin(args), torch::torch_cos(args)),
                     dim = 1L)
}

# ---------------------------------------------------------------------------
# U-Net module
# ---------------------------------------------------------------------------

.torch_ddpm_unet <- function(H, W, cond_dim = 0L, time_dim = 16L,
                                base_ch = 8L) {
  torch::nn_module(
    "edaphos_ddpm_unet",
    initialize = function() {
      self$time_dim <- time_dim
      self$cond_dim <- cond_dim
      # Time MLP
      self$time_mlp <- torch::nn_sequential(
        torch::nn_linear(time_dim, 4L * time_dim),
        torch::nn_gelu(),
        torch::nn_linear(4L * time_dim, 4L * base_ch)
      )
      # Optional conditioning projection (cond_dim -> base_ch)
      if (cond_dim > 0L) {
        self$cond_proj <- torch::nn_linear(cond_dim, base_ch)
      }
      # Encoder
      self$enc1a <- torch::nn_conv2d(1L,         base_ch,      3L, padding = 1L)
      self$enc1b <- torch::nn_conv2d(base_ch,    base_ch,      3L, padding = 1L)
      self$enc2a <- torch::nn_conv2d(base_ch,    2L * base_ch, 3L, padding = 1L)
      self$enc2b <- torch::nn_conv2d(2L*base_ch, 2L * base_ch, 3L, padding = 1L)
      # Bottleneck
      self$bot_a <- torch::nn_conv2d(2L*base_ch, 4L * base_ch, 3L, padding = 1L)
      # Decoder
      self$up2   <- torch::nn_conv2d(4L*base_ch, 2L * base_ch, 3L, padding = 1L)
      self$up2b  <- torch::nn_conv2d(4L*base_ch, 2L * base_ch, 3L, padding = 1L)
      self$up1   <- torch::nn_conv2d(2L*base_ch, base_ch,      3L, padding = 1L)
      self$up1b  <- torch::nn_conv2d(2L*base_ch, base_ch,      3L, padding = 1L)
      self$out   <- torch::nn_conv2d(base_ch,    1L,           1L)

      self$pool  <- torch::nn_avg_pool2d(2L)
      self$H <- H;  self$W <- W
      self$base_ch <- base_ch
    },
    forward = function(x, t_scalar, cond = NULL) {
      # x: (batch, 1, H, W); t_scalar: scalar (timestep normalised)
      # cond: (batch, cond_dim) or NULL
      temb <- .torch_sinusoidal_embed(t_scalar, self$time_dim)
      temb <- self$time_mlp(temb$unsqueeze(1L))  # (1, 4*base_ch)
      # Inject conditioning by adding cond_proj to the first encoder
      if (!is.null(cond) && self$cond_dim > 0L) {
        c_emb <- self$cond_proj(cond)            # (batch, base_ch)
      }

      h1 <- torch::nnf_gelu(self$enc1a(x))
      if (!is.null(cond) && self$cond_dim > 0L) {
        h1 <- h1 + c_emb$unsqueeze(3L)$unsqueeze(4L)
      }
      h1 <- torch::nnf_gelu(self$enc1b(h1))     # (batch, base_ch, H, W)
      p1 <- self$pool(h1)                         # (batch, base_ch, H/2, W/2)
      h2 <- torch::nnf_gelu(self$enc2a(p1))
      h2 <- torch::nnf_gelu(self$enc2b(h2))
      p2 <- self$pool(h2)
      b  <- torch::nnf_gelu(self$bot_a(p2))
      # Add time embedding (broadcast across spatial dims)
      temb_b <- temb$unsqueeze(3L)$unsqueeze(4L)  # (1, 4*base_ch, 1, 1)
      b <- b + temb_b
      # Decoder with skip connections
      u2 <- torch::nnf_interpolate(b, size = h2$shape[3:4],
                                      mode = "nearest")
      u2 <- torch::nnf_gelu(self$up2(u2))
      u2 <- torch::torch_cat(list(u2, h2), dim = 2L)
      u2 <- torch::nnf_gelu(self$up2b(u2))
      u1 <- torch::nnf_interpolate(u2, size = h1$shape[3:4],
                                      mode = "nearest")
      u1 <- torch::nnf_gelu(self$up1(u1))
      u1 <- torch::torch_cat(list(u1, h1), dim = 2L)
      u1 <- torch::nnf_gelu(self$up1b(u1))
      self$out(u1)  # (batch, 1, H, W) -- predicted noise
    }
  )()
}

# ---------------------------------------------------------------------------
# Torch DDPM fit
# ---------------------------------------------------------------------------

.torch_ddpm_fit <- function(stack, conditioning, T, epochs, hidden,
                                lr, seed, device_pref, cond_drop = 0.1) {
  if (!is.null(seed)) {
    set.seed(seed); torch::torch_manual_seed(seed)
  }
  device_str <- if (identical(device_pref, "mps") &&
                      torch::backends_mps_is_available()) "mps"
                 else if (identical(device_pref, "cuda") &&
                             torch::cuda_is_available()) "cuda"
                 else "cpu"
  dev <- torch::torch_device(device_str)

  n_patches <- dim(stack)[1L]; H <- dim(stack)[2L]; W <- dim(stack)[3L]
  cond_dim <- if (is.null(conditioning)) 0L else ncol(conditioning)
  if (is.null(conditioning)) conditioning <- matrix(0, n_patches, 0L)

  # Standardise patches
  patches_flat <- matrix(stack, nrow = n_patches, ncol = H * W)
  mu <- mean(patches_flat); sd_ <- stats::sd(patches_flat)
  if (sd_ < 1e-6) sd_ <- 1
  patches_z <- (patches_flat - mu) / sd_
  patches_arr <- array(patches_z, dim = c(n_patches, 1L, H, W))

  x_t_full <- torch::torch_tensor(patches_arr, dtype = torch::torch_float(),
                                      device = dev)
  cond_t <- if (cond_dim > 0L)
    torch::torch_tensor(conditioning, dtype = torch::torch_float(),
                          device = dev)
  else NULL

  sched <- dm_cosine_schedule(T = T)
  sqrt_ab  <- torch::torch_tensor(sched$sqrt_alphabar,
                                     dtype = torch::torch_float(),
                                     device = dev)
  sqrt_1ab <- torch::torch_tensor(sched$sqrt_one_minus_alphabar,
                                      dtype = torch::torch_float(),
                                      device = dev)

  net <- .torch_ddpm_unet(H, W, cond_dim = cond_dim,
                             time_dim = hidden, base_ch = 8L)
  net$to(device = dev)
  opt <- torch::optim_adam(net$parameters, lr = lr)
  history <- numeric(epochs)

  for (ep in seq_len(epochs)) {
    opt$zero_grad()
    # Sample t uniformly
    t_ix <- sample.int(T, n_patches, replace = TRUE)
    # Sample noise
    eps  <- torch::torch_randn(c(n_patches, 1L, H, W), device = dev)
    # Build x_t for each sample using its own t
    # Vectorise via gather
    t_idx_t <- torch::torch_tensor(t_ix, dtype = torch::torch_long(),
                                       device = dev)
    sqrt_ab_i  <- sqrt_ab[t_idx_t]$reshape(c(n_patches, 1L, 1L, 1L))
    sqrt_1ab_i <- sqrt_1ab[t_idx_t]$reshape(c(n_patches, 1L, 1L, 1L))
    x_t_batch <- sqrt_ab_i * x_t_full + sqrt_1ab_i * eps

    # Time scalar normalised in [0, 1] -- here we use per-sample
    # embeddings by looping (small batch sizes only).  For patch
    # counts < 64, the loop overhead is negligible compared to the
    # conv cost.
    pred_eps <- torch::torch_empty_like(eps)
    cond_drop_mask <- if (cond_dim > 0L)
      stats::rbinom(n_patches, 1L, prob = 1 - cond_drop)
    else rep(1L, n_patches)
    for (i in seq_len(n_patches)) {
      t_norm <- torch::torch_tensor(t_ix[i] / T,
                                        dtype = torch::torch_float(),
                                        device = dev)
      cond_i <- if (!is.null(cond_t) && cond_drop_mask[i] == 1L)
        cond_t[i, , drop = FALSE] else NULL
      pred_eps[i, , , ] <- net(x_t_batch[i, , , , drop = FALSE],
                                  t_scalar = t_norm,
                                  cond = cond_i)$squeeze(1L)
    }
    loss <- torch::nnf_mse_loss(pred_eps, eps)
    loss$backward()
    opt$step()
    history[ep] <- as.numeric(loss$detach()$to(device = "cpu"))
    if (is.finite(history[ep]) && history[ep] < 1e-6) break
  }

  structure(list(
    backend = "torch",
    net = net, schedule = sched,
    H = H, W = W, n_patches = n_patches, cond_dim = cond_dim,
    mu = mu, sd = sd_, device = device_str,
    history = history[history > 0 | is.na(history)],
    T = T, hidden = hidden, lr = lr
  ), class = "edaphos_dm_fit")
}

# ---------------------------------------------------------------------------
# Torch DDPM ancestral sampling
# ---------------------------------------------------------------------------

.torch_ddpm_sample <- function(fit, n_samples, conditioning, seed) {
  if (!is.null(seed)) {
    set.seed(seed); torch::torch_manual_seed(seed)
  }
  dev <- torch::torch_device(fit$device)
  H <- fit$H; W <- fit$W; T <- fit$schedule$T
  if (is.null(conditioning) || fit$cond_dim == 0L) {
    cond_t <- NULL
  } else {
    stopifnot(nrow(conditioning) == n_samples,
               ncol(conditioning) == fit$cond_dim)
    cond_t <- torch::torch_tensor(conditioning,
                                      dtype = torch::torch_float(),
                                      device = dev)
  }

  x <- torch::torch_randn(c(n_samples, 1L, H, W), device = dev)
  for (t in seq(T, 1, by = -1L)) {
    at   <- fit$schedule$alphas[t]
    abt  <- fit$schedule$alphabar[t]
    beta_t <- fit$schedule$betas[t]
    sigma_t <- sqrt(beta_t)
    t_norm <- torch::torch_tensor(t / T, dtype = torch::torch_float(),
                                      device = dev)
    eps_hat <- torch::torch_empty_like(x)
    for (i in seq_len(n_samples)) {
      ci <- if (!is.null(cond_t)) cond_t[i, , drop = FALSE] else NULL
      eps_hat[i, , , ] <- fit$net(x[i, , , , drop = FALSE],
                                      t_scalar = t_norm,
                                      cond = ci)$squeeze(1L)
    }
    mu_t <- (1 / sqrt(at)) *
      (x - ((1 - at) / sqrt(1 - abt)) * eps_hat)
    if (t > 1L) {
      x <- mu_t + sigma_t * torch::torch_randn_like(x)
    } else {
      x <- mu_t
    }
  }
  out_arr <- as.array(x$detach()$to(device = "cpu"))
  out_arr <- out_arr[, 1L, , , drop = FALSE]       # drop channel axis
  out_arr <- array(out_arr, dim = c(n_samples, H, W))
  # Un-standardise
  out_arr * fit$sd + fit$mu
}
