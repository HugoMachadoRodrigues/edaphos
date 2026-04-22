# Pillar 4 -- MoCo v2 upgrade.
#
# Implements Momentum Contrast v2 (He et al. 2020; Chen et al. 2020,
# "Improved Baselines with MoCo") on top of `torch`, with a
# raster-specific augmentation stack. Compared to the SimCLR scaffold
# (R/foundation_simclr.R), MoCo v2 brings three features that matter
# at planetary scale:
#
#   1. Momentum encoder.  Keys are embedded by a second copy of the
#      backbone whose parameters track the query network by EMA:
#        theta_k <- m * theta_k + (1 - m) * theta_q.
#      The key side is therefore stable across updates even though the
#      query side changes every batch.
#
#   2. Dictionary queue.  A FIFO buffer of past keys decouples the
#      number of negatives from the mini-batch size: the contrastive
#      loss compares every anchor against K >> B queued negatives.
#
#   3. Wider backbone + 2-layer projection head.  Moves the encoder
#      from the SimCLR scaffold's 2-conv feature extractor to a
#      BatchNorm CNN capable of learning stronger representations.
#
# The raster-specific augmentation stack (spatial crop / flip /
# rotation, additive sensor noise, per-channel brightness jitter,
# channel dropout, spatial cutout) makes the objective meaningful for
# soil-covariate stacks rather than natural photographs.

.moco_require_torch <- function() {
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("Install the `torch` package to use foundation_moco_*().",
         call. = FALSE)
  }
  invisible(TRUE)
}

# ---- Backbone + projection head ---------------------------------------------

.moco_build_backbone <- function() {
  torch::nn_module(
    "MoCoBackbone",
    initialize = function(in_channels, feature_dim = 64L) {
      self$feature_dim <- as.integer(feature_dim)
      # Block 1: in_channels -> 32
      self$conv1 <- torch::nn_conv2d(in_channels, 32L, 3L, padding = 1L)
      self$bn1   <- torch::nn_batch_norm2d(32L)
      # Block 2: 32 -> 32 (residual)
      self$conv2 <- torch::nn_conv2d(32L, 32L, 3L, padding = 1L)
      self$bn2   <- torch::nn_batch_norm2d(32L)
      # Block 3: 32 -> 64 with stride-2 downsample
      self$conv3 <- torch::nn_conv2d(32L, 64L, 3L, stride = 2L, padding = 1L)
      self$bn3   <- torch::nn_batch_norm2d(64L)
      # Block 4: 64 -> 64 (residual on downsampled)
      self$conv4 <- torch::nn_conv2d(64L, 64L, 3L, padding = 1L)
      self$bn4   <- torch::nn_batch_norm2d(64L)
      # Block 5: 64 -> feature_dim
      self$conv5 <- torch::nn_conv2d(64L, self$feature_dim, 3L,
                                      padding = 1L)
      self$bn5   <- torch::nn_batch_norm2d(self$feature_dim)
      self$pool  <- torch::nn_adaptive_avg_pool2d(c(1L, 1L))
    },
    forward = function(x) {
      h <- torch::nnf_relu(self$bn1(self$conv1(x)))
      r <- torch::nnf_relu(self$bn2(self$conv2(h)))
      h <- r + h   # residual shortcut inside block 1/2
      h <- torch::nnf_relu(self$bn3(self$conv3(h)))
      r <- torch::nnf_relu(self$bn4(self$conv4(h)))
      h <- r + h   # residual shortcut inside block 3/4
      h <- torch::nnf_relu(self$bn5(self$conv5(h)))
      h <- self$pool(h)$reshape(c(x$size(1L), self$feature_dim))
      h
    }
  )
}

.moco_build_projection <- function() {
  torch::nn_module(
    "MoCoProjection",
    initialize = function(feature_dim, proj_dim = 32L) {
      self$fc1 <- torch::nn_linear(feature_dim, feature_dim)
      self$bn1 <- torch::nn_batch_norm1d(feature_dim)
      self$fc2 <- torch::nn_linear(feature_dim, as.integer(proj_dim))
    },
    forward = function(x) {
      h <- torch::nnf_relu(self$bn1(self$fc1(x)))
      z <- self$fc2(h)
      # L2 normalise -- InfoNCE expects unit-length embeddings.
      norm <- torch::torch_sqrt(
        torch::torch_sum(z * z, dim = 2L, keepdim = TRUE) + 1e-9
      )
      z / norm
    }
  )
}

.moco_build_encoder <- function() {
  torch::nn_module(
    "MoCoEncoder",
    initialize = function(in_channels, feature_dim = 64L, proj_dim = 32L) {
      BB <- .moco_build_backbone()
      PH <- .moco_build_projection()
      self$backbone <- BB(in_channels = in_channels,
                          feature_dim = feature_dim)
      self$proj     <- PH(feature_dim = feature_dim,
                          proj_dim    = proj_dim)
    },
    backbone_features = function(x) self$backbone(x),
    forward = function(x) self$proj(self$backbone(x))
  )
}

# ---- Raster-specific augmentations ------------------------------------------

# Each augmentation operates on a (B, C, H, W) torch tensor and returns
# a tensor of the same shape. The functions are pure -- they return new
# tensors rather than mutating inputs.

.moco_aug_flip <- function(x, flip_prob = 0.5) {
  if (stats::runif(1) < flip_prob) x <- torch::torch_flip(x, dims = c(3L))
  if (stats::runif(1) < flip_prob) x <- torch::torch_flip(x, dims = c(4L))
  x
}

.moco_aug_rot90 <- function(x, prob = 0.75) {
  if (stats::runif(1) < prob) {
    k <- sample(1:3, 1L)
    x <- torch::torch_rot90(x, k = as.integer(k), dims = c(3L, 4L))
  }
  x
}

.moco_aug_crop_resize <- function(x, crop_ratio = c(0.6, 1.0)) {
  # Random resized crop: pick a crop size between crop_ratio * H, then
  # resize back up to (H, W) via bilinear interpolation.
  dims <- x$size()
  H <- dims[3L]; W <- dims[4L]
  ratio <- stats::runif(1, crop_ratio[1L], crop_ratio[2L])
  crop_h <- max(2L, as.integer(round(H * ratio)))
  crop_w <- max(2L, as.integer(round(W * ratio)))
  top  <- sample(seq_len(max(1L, H - crop_h + 1L)), 1L)
  left <- sample(seq_len(max(1L, W - crop_w + 1L)), 1L)
  cropped <- x[, , top:(top + crop_h - 1L), left:(left + crop_w - 1L)]
  torch::nnf_interpolate(cropped, size = c(H, W), mode = "bilinear",
                          align_corners = FALSE)
}

.moco_aug_channel_drop <- function(x, drop_prob = 0.2) {
  # Per-sample, per-channel Bernoulli drop. Simulates a missing /
  # corrupt band (e.g. SAR during rain, cloudy optical).
  B <- x$size(1L); C <- x$size(2L)
  mask <- stats::rbinom(B * C, 1L, 1 - drop_prob)
  mask_t <- torch::torch_tensor(matrix(mask, B, C),
                                 dtype = torch::torch_float())
  mask_t <- mask_t$reshape(c(B, C, 1L, 1L))
  x * mask_t
}

.moco_aug_cutout <- function(x, prob = 0.3, size_ratio = 0.2) {
  # Zero out a random spatial rectangle per sample. Simulates a cloud
  # mask over an optical patch.
  if (stats::runif(1) > prob) return(x)
  dims <- x$size()
  B <- dims[1L]; H <- dims[3L]; W <- dims[4L]
  cut_h <- max(1L, as.integer(round(H * size_ratio)))
  cut_w <- max(1L, as.integer(round(W * size_ratio)))
  out <- x$clone()
  for (b in seq_len(B)) {
    top  <- sample(seq_len(max(1L, H - cut_h + 1L)), 1L)
    left <- sample(seq_len(max(1L, W - cut_w + 1L)), 1L)
    out[b, , top:(top + cut_h - 1L), left:(left + cut_w - 1L)] <- 0
  }
  out
}

.moco_aug_noise <- function(x, sd = 0.1) {
  x + torch::torch_randn_like(x) * sd
}

.moco_aug_brightness <- function(x, jitter = 0.2) {
  # Per-sample, per-channel multiplicative brightness (analogue to
  # SimCLR colour jitter, but per-band since rasters have no RGB).
  B <- x$size(1L); C <- x$size(2L)
  f <- 1 + stats::runif(B * C, -jitter, jitter)
  f_t <- torch::torch_tensor(matrix(f, B, C),
                              dtype = torch::torch_float())
  f_t <- f_t$reshape(c(B, C, 1L, 1L))
  x * f_t
}

.moco_augment <- function(x, p) {
  # Composite augmentation. `p` is a list of probabilities /
  # parameters configured by foundation_moco_pretrain().
  x <- .moco_aug_crop_resize(x, crop_ratio = p$crop_ratio)
  x <- .moco_aug_flip(x, flip_prob = p$flip_prob)
  x <- .moco_aug_rot90(x, prob = p$rot90_prob)
  x <- .moco_aug_channel_drop(x, drop_prob = p$channel_drop_prob)
  x <- .moco_aug_cutout(x, prob = p$cutout_prob,
                        size_ratio = p$cutout_size_ratio)
  x <- .moco_aug_brightness(x, jitter = p$brightness_jitter)
  x <- .moco_aug_noise(x, sd = p$noise_sd)
  x
}

# ---- Momentum update + loss -------------------------------------------------

# EMA-update every parameter of `enc_k` toward `enc_q`: theta_k <- m *
# theta_k + (1-m) * theta_q. Called with no_grad so the update graph
# is not attached to the autograd tape.
.moco_momentum_update <- function(enc_q, enc_k, m) {
  params_q <- enc_q$parameters
  params_k <- enc_k$parameters
  torch::with_no_grad({
    for (nm in names(params_q)) {
      pk <- params_k[[nm]]
      pq <- params_q[[nm]]
      pk$copy_(m * pk + (1 - m) * pq)
    }
  })
  invisible(NULL)
}

# InfoNCE with a queue of negatives. `z_q` and `z_k` are L2-normalised
# (B, D) projections. `queue` is a (K, D) buffer (oldest first).
.moco_info_nce <- function(z_q, z_k, queue, temperature) {
  # Positive logit: elementwise dot product along D.
  l_pos <- (z_q * z_k)$sum(dim = 2L)$unsqueeze(2L)   # (B, 1)
  l_neg <- torch::torch_mm(z_q, queue$t())           # (B, K)
  logits <- torch::torch_cat(list(l_pos, l_neg), dim = 2L) / temperature
  B <- z_q$size(1L)
  # Positive is at column index 1 (R torch is 1-based for cross_entropy).
  labels <- torch::torch_tensor(rep(1L, B), dtype = torch::torch_long())
  torch::nnf_cross_entropy(logits, labels)
}

# ---- Public API -------------------------------------------------------------

#' Pillar 4 -- MoCo v2 pre-training on raster covariate patches
#'
#' Self-supervised momentum-contrastive pre-training (He et al. 2020;
#' Chen et al. 2020) with a raster-specific augmentation stack. Compared
#' to the SimCLR scaffold in [foundation_simclr_pretrain()], MoCo v2
#' introduces three architectural upgrades:
#'
#' \itemize{
#'   \item A **momentum key encoder** updated by exponential moving
#'     average: \eqn{\theta_k \leftarrow m\,\theta_k + (1-m)\,\theta_q}.
#'   \item A **dictionary queue** of past keys, so every mini-batch
#'     sees `K` negatives rather than `2B - 2`.
#'   \item A wider residual CNN backbone (~feature_dim = 64 by default)
#'     followed by a 2-layer projection head with BatchNorm, matching
#'     the MoCo v2 recipe.
#' }
#'
#' The augmentation stack is tuned for multi-channel raster patches
#' rather than natural photographs: spatial random resized crop,
#' horizontal / vertical flip, 90-degree rotations, per-channel
#' Bernoulli dropout (missing-band simulation), spatial cutout
#' (cloud-mask simulation), per-channel multiplicative brightness
#' jitter, and additive Gaussian sensor noise.
#'
#' @param patches A 4-D array shaped `(N, C, H, W)` -- `N` patches,
#'   `C` covariate channels, spatial `H x W`.
#' @param feature_dim,proj_dim Integer widths of the backbone output
#'   and the contrastive projection head.
#' @param queue_size Integer `K` -- number of negatives stored in the
#'   FIFO dictionary queue.
#' @param momentum Numeric in `(0, 1)` -- EMA coefficient for the key
#'   encoder (MoCo paper default is 0.999).
#' @param temperature Numeric `> 0` -- InfoNCE temperature (MoCo v2
#'   default is 0.07).
#' @param batch_size,epochs,lr Integer / numeric -- Adam optimiser
#'   hyperparameters.
#' @param crop_ratio Numeric length-2 vector -- random-resized-crop
#'   ratio range.
#' @param flip_prob,rot90_prob Probabilities of horizontal / vertical
#'   flip and 90-deg rotation.
#' @param channel_drop_prob Probability of zeroing any given channel
#'   independently.
#' @param cutout_prob,cutout_size_ratio Probability of spatial cutout
#'   and its size ratio.
#' @param brightness_jitter Numeric `[0, 1)` -- per-channel
#'   multiplicative brightness range.
#' @param noise_sd Numeric `>= 0` -- additive-noise standard deviation.
#' @param seed,verbose As elsewhere in the package.
#'
#' @return An `edaphos_foundation_moco` S3 object containing the
#'   fitted query encoder (use [foundation_moco_embed()] to extract
#'   embeddings), the key encoder, the training loss history and the
#'   configuration.
#' @export
foundation_moco_pretrain <- function(patches,
                                      feature_dim = 64L,
                                      proj_dim    = 32L,
                                      queue_size  = 1024L,
                                      momentum    = 0.999,
                                      temperature = 0.07,
                                      batch_size  = 16L,
                                      epochs      = 30L,
                                      lr          = 0.03,
                                      crop_ratio  = c(0.6, 1.0),
                                      flip_prob   = 0.5,
                                      rot90_prob  = 0.75,
                                      channel_drop_prob    = 0.2,
                                      cutout_prob          = 0.3,
                                      cutout_size_ratio    = 0.2,
                                      brightness_jitter    = 0.2,
                                      noise_sd             = 0.1,
                                      seed = NULL, verbose = FALSE) {
  .moco_require_torch()
  stopifnot(length(dim(patches)) == 4L,
            is.numeric(momentum), momentum > 0, momentum < 1,
            is.numeric(temperature), temperature > 0)
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  N  <- dim(patches)[1L]
  C  <- dim(patches)[2L]
  batch_size <- as.integer(min(batch_size, N))
  queue_size <- as.integer(min(queue_size, max(2L, N - batch_size)))

  patches_t <- torch::torch_tensor(patches)$to(dtype = torch::torch_float())

  EncCtor <- .moco_build_encoder()
  enc_q   <- EncCtor(in_channels = C,
                      feature_dim = as.integer(feature_dim),
                      proj_dim    = as.integer(proj_dim))
  enc_k   <- EncCtor(in_channels = C,
                      feature_dim = as.integer(feature_dim),
                      proj_dim    = as.integer(proj_dim))
  # Initialise key encoder as an exact copy of the query encoder.
  torch::with_no_grad({
    params_q <- enc_q$parameters; params_k <- enc_k$parameters
    for (nm in names(params_q)) params_k[[nm]]$copy_(params_q[[nm]])
  })
  # Freeze gradient flow on the key encoder -- it is only updated by EMA.
  for (p in enc_k$parameters) p$requires_grad_(FALSE)

  optimizer <- torch::optim_adam(enc_q$parameters, lr = lr)

  # Warm the queue with keys computed on random anchors before training.
  init_idx <- sample.int(N, min(queue_size, N), replace = queue_size > N)
  with_queue_init <- torch::with_no_grad({
    init_x <- patches_t[init_idx, , , ]
    enc_k(init_x)
  })
  queue <- with_queue_init$detach()   # (queue_size, proj_dim)

  aug_params <- list(
    crop_ratio        = crop_ratio,
    flip_prob         = flip_prob,
    rot90_prob        = rot90_prob,
    channel_drop_prob = channel_drop_prob,
    cutout_prob       = cutout_prob,
    cutout_size_ratio = cutout_size_ratio,
    brightness_jitter = brightness_jitter,
    noise_sd          = noise_sd
  )

  loss_history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    idx <- sample.int(N, batch_size)
    batch <- patches_t[idx, , , ]

    xq <- .moco_augment(batch, aug_params)
    xk <- .moco_augment(batch, aug_params)

    optimizer$zero_grad()
    z_q <- enc_q(xq)
    z_k <- torch::with_no_grad(enc_k(xk))$detach()

    loss <- .moco_info_nce(z_q, z_k, queue, temperature = temperature)
    loss$backward()
    optimizer$step()

    # Key side: EMA update after the optimiser step.
    .moco_momentum_update(enc_q, enc_k, m = momentum)

    # Dictionary queue FIFO update (oldest batch_size rows drop out).
    torch::with_no_grad({
      queue <- torch::torch_cat(
        list(queue[(batch_size + 1L):queue$size(1L), , drop = FALSE],
             z_k$detach()),
        dim = 1L
      )
    })

    loss_history[ep] <- as.numeric(loss$item())
    if (verbose && (ep %% 5L == 0L || ep == 1L || ep == epochs)) {
      message(sprintf("[ep %3d/%d] InfoNCE loss = %.4f",
                      ep, epochs, loss_history[ep]))
    }
  }

  structure(
    list(
      encoder_q    = enc_q,
      encoder_k    = enc_k,
      in_channels  = C,
      feature_dim  = as.integer(feature_dim),
      proj_dim     = as.integer(proj_dim),
      queue_size   = queue_size,
      momentum     = momentum,
      temperature  = temperature,
      batch_size   = batch_size,
      loss_history = loss_history,
      final_loss   = loss_history[epochs],
      aug_params   = aug_params
    ),
    class = "edaphos_foundation_moco"
  )
}

#' Extract backbone embeddings from a fitted MoCo v2 encoder
#'
#' Returns the `feature_dim` backbone output of the **query** encoder
#' (the projection head is by design discarded after pre-training, so
#' the returned embedding is the reusable representation suitable for
#' downstream DSM tasks). Set `projection = TRUE` to obtain the
#' normalised projection-head output instead, which is useful when
#' visualising the contrastive space.
#'
#' @param object A `edaphos_foundation_moco`.
#' @param patches Array `(N, C, H, W)`.
#' @param projection Logical; return L2-normalised projection outputs
#'   rather than backbone features.
#' @return Numeric matrix `(N, D)` where `D = feature_dim` (or
#'   `proj_dim` if `projection = TRUE`).
#' @export
foundation_moco_embed <- function(object, patches, projection = FALSE) {
  .moco_require_torch()
  stopifnot(inherits(object, "edaphos_foundation_moco"),
            length(dim(patches)) == 4L)
  patches_t <- torch::torch_tensor(patches)$to(dtype = torch::torch_float())
  enc <- object$encoder_q
  emb <- torch::with_no_grad({
    if (projection) {
      z <- enc(patches_t)
    } else {
      z <- enc$backbone_features(patches_t)
    }
    as.array(z$cpu())
  })
  emb
}

#' @export
print.edaphos_foundation_moco <- function(x, ...) {
  cat("<edaphos_foundation_moco>  (MoCo v2 -- Pillar 4)\n")
  cat(sprintf("  in_channels = %d  feature_dim = %d  proj_dim = %d\n",
              x$in_channels, x$feature_dim, x$proj_dim))
  cat(sprintf("  queue_size = %d  momentum = %.4f  tau = %.3g  batch = %d\n",
              x$queue_size, x$momentum, x$temperature, x$batch_size))
  cat(sprintf("  epochs = %d  final InfoNCE loss = %.4g\n",
              length(x$loss_history), x$final_loss))
  invisible(x)
}
