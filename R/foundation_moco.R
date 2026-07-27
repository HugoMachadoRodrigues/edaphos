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
  mask_t <- mask_t$reshape(c(B, C, 1L, 1L))$to(device = x$device)
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
  f_t <- f_t$reshape(c(B, C, 1L, 1L))$to(device = x$device)
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
  labels <- torch::torch_tensor(rep(1L, B),
                                  dtype = torch::torch_long())$to(device = logits$device)
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
#' @examples
#' # `requireNamespace("torch")` is TRUE as soon as the R package is
#' # installed, but the libtorch/lantern shared libraries are a separate
#' # separate binary download that CI and CRAN machines routinely lack
#' # (about 0.45 GB installed here). Both halves
#' # of the guard are needed.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'
#' # MoCo v2 consumes (N, C, H, W). `br_cerrado` is a complete 45 x 45
#' # grid, so every covariate reshapes into a surface and the 8 x 8
#' # windows cut out of it are genuine soil-landscape patches.
#' # Standardise the surfaces first: the augmentation stack adds noise
#' # of a fixed sd and jitters brightness multiplicatively, so map_mm
#' # (millimetres) and ndvi (a unitless index) would otherwise be
#' # perturbed by wildly different relative amounts.
#' g <- 45L
#' cube <- vapply(c("elev", "slope", "twi", "map_mm", "ndvi"),
#'                function(v) {
#'                  m <- matrix(br_cerrado[[v]], g, g)
#'                  (m - mean(m)) / stats::sd(m)
#'                }, matrix(0, g, g))
#' set.seed(42)
#' top  <- sample(g - 7L, 24L, replace = TRUE)
#' left <- sample(g - 7L, 24L, replace = TRUE)
#' patches <- array(0, dim = c(24L, 5L, 8L, 8L))
#' for (i in 1:24) {
#'   patches[i, , , ] <- aperm(cube[top[i]:(top[i] + 7L),
#'                                  left[i]:(left[i] + 7L), ], c(3, 1, 2))
#' }
#'
#' set.seed(1)
#' fit <- foundation_moco_pretrain(patches, feature_dim = 16L,
#'                                 proj_dim = 8L, queue_size = 1024L,
#'                                 batch_size = 8L, epochs = 8L,
#'                                 seed = 1L)
#' print(fit)
#'
#' # `queue_size` is a request, not a setting: it is silently clamped
#' # to N - batch_size, so the 1024-key dictionary asked for above is
#' # 16 keys wide over 24 patches. Always read it back off the object.
#' print(c(requested = 1024, actual = fit$queue_size))
#'
#' # Worse, the loss at step t is computed against the queue as it stood
#' # at the END of step t - 1, and the FIFO first drops the oldest
#' # batch_size rows, then appends the current keys. Halve the corpus and
#' # the clamp leaves queue_size equal to batch_size, so the drop empties
#' # the queue and the append refills it: the dictionary in force at step
#' # t is exactly the keys of step t - 1. Every negative is then a key of
#' # the PREVIOUS mini-batch under the previous momentum encoder, none
#' # come from the current one (the current batch supplies only the
#' # positive), and no key older than a single step ever survives --
#' # which is MoCo's whole advantage over SimCLR. `retained` is how many
#' # pre-existing keys outlive a step; keep N well above 2 * batch_size
#' # to make it positive.
#' tiny <- foundation_moco_pretrain(patches[1:16, , , , drop = FALSE],
#'                                  feature_dim = 8L, proj_dim = 4L,
#'                                  batch_size = 8L, epochs = 2L,
#'                                  seed = 1L)
#' print(c(queue = tiny$queue_size, batch = tiny$batch_size,
#'         retained = tiny$queue_size - tiny$batch_size))
#'
#' # `epochs` counts optimiser steps, not passes over `patches`: one
#' # mini-batch is drawn per epoch, so a short trace reports which
#' # patches were sampled at least as much as it reports learning.
#' # Read its tail next to log1p(queue_size) -- the InfoNCE value of a
#' # model whose logits are all equal -- before concluding anything.
#' print(round(fit$loss_history, 3))
#' print(c(final = fit$final_loss,
#'         all_logits_equal = log1p(fit$queue_size)))
#'
#' # Reproducibility needs BOTH generators. `seed=` only sets the torch
#' # RNG (weight init, additive sensor noise); the mini-batch draw and
#' # the crop / flip / rotation / channel-drop / cutout / brightness
#' # augmentations are all drawn from R's RNG. The same `seed=` under a
#' # different R seed is a different run.
#' set.seed(99)
#' a <- foundation_moco_pretrain(patches, feature_dim = 8L, proj_dim = 4L,
#'                               batch_size = 8L, epochs = 3L, seed = 1L)
#' set.seed(123)
#' b <- foundation_moco_pretrain(patches, feature_dim = 8L, proj_dim = 4L,
#'                               batch_size = 8L, epochs = 3L, seed = 1L)
#' set.seed(99)
#' d <- foundation_moco_pretrain(patches, feature_dim = 8L, proj_dim = 4L,
#'                               batch_size = 8L, epochs = 3L, seed = 1L)
#' print(c(other_R_seed = identical(a$loss_history, b$loss_history),
#'         same_R_seed  = identical(a$loss_history, d$loss_history)))
#' }
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
#' @examples
#' # The installed-package check is not enough on its own: libtorch /
#' # lantern is a separate binary download, and torch_is_installed() is
#' # what tells you it is actually there.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'
#' # The same 8 x 8 Cerrado patch corpus used by
#' # foundation_moco_pretrain().
#' g <- 45L
#' cube <- vapply(c("elev", "slope", "twi", "map_mm", "ndvi"),
#'                function(v) {
#'                  m <- matrix(br_cerrado[[v]], g, g)
#'                  (m - mean(m)) / stats::sd(m)
#'                }, matrix(0, g, g))
#' set.seed(42)
#' top  <- sample(g - 7L, 24L, replace = TRUE)
#' left <- sample(g - 7L, 24L, replace = TRUE)
#' patches <- array(0, dim = c(24L, 5L, 8L, 8L))
#' for (i in 1:24) {
#'   patches[i, , , ] <- aperm(cube[top[i]:(top[i] + 7L),
#'                                  left[i]:(left[i] + 7L), ], c(3, 1, 2))
#' }
#' set.seed(1)
#' fit <- foundation_moco_pretrain(patches, feature_dim = 16L,
#'                                 proj_dim = 8L, batch_size = 8L,
#'                                 epochs = 8L, seed = 1L)
#'
#' # Default: the reusable backbone representation, feature_dim wide.
#' emb <- foundation_moco_embed(fit, patches)
#' print(dim(emb))
#'
#' # The two outputs live in different spaces and must never be mixed
#' # in one distance calculation. Backbone features leave a ReLU, so
#' # they are non-negative and of arbitrary length; the projection head
#' # L2-normalises, so its rows sit on the unit sphere and may be
#' # negative. Regress on the backbone, do cosine geometry on the
#' # projection.
#' z <- foundation_moco_embed(fit, patches, projection = TRUE)
#' print(c(backbone_cols = ncol(emb), proj_cols = ncol(z),
#'         backbone_min = min(emb), proj_min = min(z)))
#' print(range(round(sqrt(rowSums(z^2)), 6)))
#'
#' # The encoder is switched to eval() inside, so BatchNorm uses its
#' # stored running statistics rather than the statistics of whatever
#' # you happened to pass. That is what makes an embedding a property
#' # of the patch instead of a property of the batch: encoding three
#' # patches alone reproduces the corresponding rows of the full run
#' # (to float32 precision), and a repeated call is bit-identical.
#' chunk <- foundation_moco_embed(fit, patches[1:3, , , , drop = FALSE])
#' print(c(chunked  = isTRUE(all.equal(chunk, emb[1:3, , drop = FALSE],
#'                                     tolerance = 1e-4)),
#'         repeated = identical(foundation_moco_embed(fit, patches),
#'                              emb)))
#'
#' # Only the query encoder is read here. `fit$encoder_k` is the
#' # momentum copy that built the dictionary during training and is
#' # never consulted by this function.
#' }
#' @export
foundation_moco_embed <- function(object, patches, projection = FALSE) {
  .moco_require_torch()
  stopifnot(inherits(object, "edaphos_foundation_moco"),
            length(dim(patches)) == 4L)
  patches_t <- torch::torch_tensor(patches)$to(dtype = torch::torch_float())
  enc <- object$encoder_q
  # Force eval mode so BatchNorm uses the saved `running_mean` /
  # `running_var` rather than the per-batch statistics of `patches_t`.
  # Without this the embedding is non-deterministic (depends on the
  # current mini-batch composition) and inconsistent across re-loaded
  # copies of the same encoder — the bug that would otherwise make
  # `foundation_weights_load()` disagree with its source object.
  enc$eval()
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

#' Dataset-backed MoCo v2 pre-training for planetary-scale corpora
#'
#' Drop-in streaming variant of [foundation_moco_pretrain()] that
#' reads patches on the fly from an `edaphos_tile_dataset`
#' (see [foundation_tile_dataset()]). The point is to train on real
#' multi-source raster mosaics -- SoilGrids, WorldClim, SRTM, MODIS,
#' ERA5 -- that do not fit in RAM as a single `(N, C, H, W)` array.
#'
#' Checkpointing is optional but recommended for long runs: every
#' `checkpoint_every` epochs the encoder state dicts, the dictionary
#' queue, the loss history and the configuration are written to
#' `checkpoint_dir`. Pass `resume = path` to restart from that
#' checkpoint.
#'
#' @param dataset An `edaphos_tile_dataset`.
#' @param feature_dim,proj_dim,queue_size,momentum,temperature,batch_size,epochs,lr,crop_ratio,flip_prob,rot90_prob,channel_drop_prob,cutout_prob,cutout_size_ratio,brightness_jitter,noise_sd,seed,verbose As in [foundation_moco_pretrain()].
#' @param device Backend for the training loop. One of `"cpu"`
#'   (default), `"mps"` (Apple Silicon GPU via Metal) or `"cuda"`
#'   (NVIDIA). Requested-but-unavailable backends fall back to `"cpu"`
#'   with a message. Added in v1.2.0.
#' @param checkpoint_dir Optional directory for periodic checkpoints.
#' @param checkpoint_every Integer -- save a checkpoint every `k`
#'   epochs.
#' @param resume Optional path to a checkpoint directory to restart
#'   from.
#' @return An `edaphos_foundation_moco` (identical structure to
#'   [foundation_moco_pretrain()]).
#' @examples
#' # torch_is_installed() is the half of the guard that matters on a
#' # fresh machine: the R package installs in seconds, the libtorch /
#' # lantern binaries behind it are a separate download.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed()) &&
#'     requireNamespace("terra", quietly = TRUE)) {
#'
#' # A tile dataset streams patches out of a raster instead of holding
#' # an (N, C, H, W) array in RAM. The mosaic here is small enough to
#' # build in memory from `br_cerrado`, but the call sequence is the
#' # one you use for a SoilGrids + WorldClim + SRTM stack that is not.
#' covs <- terra::rast(br_cerrado[, c("x", "y", "elev", "slope", "twi",
#'                                    "map_mm", "ndvi")], type = "xyz")
#' ds <- foundation_tile_dataset(covs, patch_size = 8L, n_patches = 64L,
#'                               seed = 7L)
#'
#' set.seed(11)
#' mt <- foundation_moco_pretrain_tiles(ds, feature_dim = 16L,
#'                                      proj_dim = 8L, queue_size = 32L,
#'                                      batch_size = 8L, epochs = 6L,
#'                                      seed = 11L, device = "cpu")
#' print(mt)
#'
#' # Unlike foundation_moco_pretrain(), `queue_size` is honoured here
#' # rather than clamped to the corpus size. The FIFO still only
#' # retains queue_size - batch_size old keys per step, so this is the
#' # knob that decides how much of a dictionary you actually have.
#' print(c(queue = mt$queue_size, batch = mt$batch_size,
#'         retained = mt$queue_size - mt$batch_size))
#'
#' # The queue is warmed by drawing min(queue_size, 4 * batch_size)
#' # patches in a single call, and foundation_tile_dataset() refuses a
#' # draw larger than `n_patches`. So the dataset must satisfy
#' # n_patches >= min(queue_size, 4 * batch_size); below, min(256, 32)
#' # is 32 and the dataset only holds 20.
#' small <- foundation_tile_dataset(covs, patch_size = 8L,
#'                                  n_patches = 20L, seed = 3L)
#' try(foundation_moco_pretrain_tiles(small, feature_dim = 8L,
#'                                    proj_dim = 4L, queue_size = 256L,
#'                                    batch_size = 8L, epochs = 2L,
#'                                    seed = 3L))
#'
#' # `device` is resolved, not obeyed: an unavailable backend prints a
#' # note and the run silently continues on CPU. Read the resolved
#' # value back rather than trusting the argument you passed -- a
#' # "GPU run" that took CPU wall-clock is usually this.
#' set.seed(11)
#' gpu <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
#'                                       proj_dim = 4L, queue_size = 32L,
#'                                       batch_size = 8L, epochs = 2L,
#'                                       seed = 11L, device = "cuda")
#' print(identical(gpu$device,
#'                 if (torch::cuda_is_available()) "cuda" else "cpu"))
#'
#' # Checkpointing is what makes a multi-day run restartable. Four
#' # epochs at checkpoint_every = 2 leave both encoders, the dictionary
#' # queue and the loss history on disk; `resume=` restores them and
#' # carries on at the stored next_epoch, so run2 holds run1's four
#' # losses verbatim plus the two new ones.
#' ck <- file.path(tempdir(), "moco_ck")
#' set.seed(21)
#' run1 <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
#'                                        proj_dim = 4L, queue_size = 32L,
#'                                        batch_size = 8L, epochs = 4L,
#'                                        seed = 21L, checkpoint_dir = ck,
#'                                        checkpoint_every = 2L)
#' print(list.files(ck))
#' set.seed(22)
#' run2 <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
#'                                        proj_dim = 4L, queue_size = 32L,
#'                                        batch_size = 8L, epochs = 6L,
#'                                        seed = 22L, resume = ck)
#' print(length(run2$loss_history))
#' print(identical(run2$loss_history[1:4], run1$loss_history))
#' unlink(ck, recursive = TRUE)
#' }
#'
#' \dontrun{
#' # The real target: a multi-source mosaic that does not fit in RAM.
#' # Every source below downloads, so this block is never run by
#' # examples -- but it is the working pipeline.
#' aoi  <- c(-48.5, -47.0, -16.5, -15.0)   # xmin, xmax, ymin, ymax
#' srtm <- foundation_tile_source_srtm(aoi, derive = c("slope", "TPI"),
#'                                     country = "BRA")
#' clim <- foundation_tile_source_worldclim(c("prec", "tavg"),
#'                                          country = "BRA", aoi = aoi)
#' soil <- foundation_tile_source_soilgrids(c("soc", "clay"),
#'                                          depth = "0-5cm", aoi = aoi)
#' mosaic <- foundation_tile_align(
#'   list(srtm = srtm, clim = clim, soil = soil),
#'   target_res = 0.005, aoi = aoi)
#' ds_big <- foundation_tile_dataset(mosaic, patch_size = 32L,
#'                                   n_patches = 20000L, seed = 1L)
#' moco <- foundation_moco_pretrain_tiles(
#'   ds_big, queue_size = 4096L, batch_size = 64L, epochs = 20000L,
#'   device = "mps", checkpoint_dir = "moco_ck", checkpoint_every = 500L,
#'   verbose = TRUE)
#' }
#' @export
foundation_moco_pretrain_tiles <- function(dataset,
                                             feature_dim = 64L,
                                             proj_dim    = 32L,
                                             queue_size  = 1024L,
                                             momentum    = 0.999,
                                             temperature = 0.07,
                                             batch_size  = 16L,
                                             epochs      = 100L,
                                             lr          = 0.03,
                                             crop_ratio  = c(0.6, 1.0),
                                             flip_prob   = 0.5,
                                             rot90_prob  = 0.75,
                                             channel_drop_prob = 0.2,
                                             cutout_prob       = 0.3,
                                             cutout_size_ratio = 0.2,
                                             brightness_jitter = 0.2,
                                             noise_sd          = 0.1,
                                             device      = c("cpu", "mps",
                                                              "cuda"),
                                             seed = NULL, verbose = FALSE,
                                             checkpoint_dir = NULL,
                                             checkpoint_every = 10L,
                                             resume = NULL) {
  .moco_require_torch()
  stopifnot(inherits(dataset, "edaphos_tile_dataset"))
  device <- match.arg(device)
  if (device == "mps" && !torch::backends_mps_is_available()) {
    message("note: 'mps' backend requested but not available; ",
             "falling back to 'cpu'.")
    device <- "cpu"
  }
  if (device == "cuda" && !torch::cuda_is_available()) {
    message("note: 'cuda' backend requested but not available; ",
             "falling back to 'cpu'.")
    device <- "cpu"
  }
  dev <- torch::torch_device(device)
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  C  <- dataset$n_channels
  batch_size <- as.integer(min(batch_size, dataset$n_patches))
  queue_size <- as.integer(queue_size)

  EncCtor <- .moco_build_encoder()
  enc_q   <- EncCtor(in_channels = C,
                      feature_dim = as.integer(feature_dim),
                      proj_dim    = as.integer(proj_dim))$to(device = dev)
  enc_k   <- EncCtor(in_channels = C,
                      feature_dim = as.integer(feature_dim),
                      proj_dim    = as.integer(proj_dim))$to(device = dev)
  torch::with_no_grad({
    params_q <- enc_q$parameters; params_k <- enc_k$parameters
    for (nm in names(params_q)) params_k[[nm]]$copy_(params_q[[nm]])
  })
  for (p in enc_k$parameters) p$requires_grad_(FALSE)
  optimizer <- torch::optim_adam(enc_q$parameters, lr = lr)

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

  loss_history <- numeric(0)
  start_epoch  <- 1L

  # Resume from checkpoint if requested.
  if (!is.null(resume)) {
    ck <- readRDS(file.path(resume, "state.rds"))
    loss_history <- ck$loss_history
    start_epoch  <- ck$next_epoch
    enc_q$load_state_dict(torch::torch_load(file.path(resume, "encoder_q.pt")))
    enc_k$load_state_dict(torch::torch_load(file.path(resume, "encoder_k.pt")))
    queue <- torch::torch_load(file.path(resume, "queue.pt"))
    # `torch_load()` materialises tensors on CPU regardless of where
    # they were saved.  When resuming on MPS / CUDA, every parameter
    # of both encoders + the queue must be moved to the training
    # device, otherwise the first matmul in .moco_info_nce() raises:
    #   "Tensor for argument #2 'mat2' is on CPU, but expected to be on GPU"
    enc_q$to(device = dev)
    enc_k$to(device = dev)
    queue <- queue$to(device = dev)
    # Re-freeze key encoder grads (load_state_dict re-enables them).
    for (p in enc_k$parameters) p$requires_grad_(FALSE)
    # Rebuild the optimizer over the device-moved parameters of enc_q
    # so its internal state tensors live on `dev` too.
    optimizer <- torch::optim_adam(enc_q$parameters, lr = lr)
    if (verbose) message("Resumed from checkpoint at epoch ", start_epoch)
  } else {
    init_batch <- dataset$sample(min(queue_size, batch_size * 4L))
    init_t <- torch::torch_tensor(init_batch)$to(dtype = torch::torch_float(),
                                                    device = dev)
    # If queue > init_batch, tile it.
    reps <- ceiling(queue_size / nrow(init_batch))
    init_t <- torch::with_no_grad(enc_k(init_t))$detach()
    if (init_t$size(1L) < queue_size) {
      init_t <- init_t$repeat_interleave(reps, dim = 1L)[seq_len(queue_size), ,
                                                           drop = FALSE]
    } else {
      init_t <- init_t[seq_len(queue_size), , drop = FALSE]
    }
    queue <- init_t
  }

  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, showWarnings = FALSE, recursive = TRUE)
  }

  for (ep in seq.int(start_epoch, epochs)) {
    batch_arr <- dataset$sample(batch_size)
    batch <- torch::torch_tensor(batch_arr)$to(dtype = torch::torch_float(),
                                                 device = dev)

    xq <- .moco_augment(batch, aug_params)
    xk <- .moco_augment(batch, aug_params)

    optimizer$zero_grad()
    z_q <- enc_q(xq)
    z_k <- torch::with_no_grad(enc_k(xk))$detach()

    loss <- .moco_info_nce(z_q, z_k, queue, temperature = temperature)
    loss$backward()
    optimizer$step()
    .moco_momentum_update(enc_q, enc_k, m = momentum)

    torch::with_no_grad({
      new_k <- z_k$detach()
      n_new <- new_k$size(1L)
      queue <- torch::torch_cat(
        list(queue[(n_new + 1L):queue$size(1L), , drop = FALSE], new_k),
        dim = 1L
      )
    })

    loss_history <- c(loss_history, as.numeric(loss$item()))
    if (verbose && (ep %% 5L == 0L || ep == start_epoch || ep == epochs)) {
      message(sprintf("[ep %4d/%d] InfoNCE loss = %.4f",
                      ep, epochs, loss_history[length(loss_history)]))
    }

    if (!is.null(checkpoint_dir) && (ep %% checkpoint_every == 0L ||
                                      ep == epochs)) {
      torch::torch_save(enc_q$state_dict(),
                         file.path(checkpoint_dir, "encoder_q.pt"))
      torch::torch_save(enc_k$state_dict(),
                         file.path(checkpoint_dir, "encoder_k.pt"))
      torch::torch_save(queue, file.path(checkpoint_dir, "queue.pt"))
      saveRDS(list(loss_history = loss_history,
                    next_epoch   = ep + 1L,
                    aug_params   = aug_params,
                    feature_dim  = feature_dim,
                    proj_dim     = proj_dim),
               file.path(checkpoint_dir, "state.rds"))
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
      device       = device,
      loss_history = loss_history,
      final_loss   = loss_history[length(loss_history)],
      aug_params   = aug_params
    ),
    class = "edaphos_foundation_moco"
  )
}

#' Apply a fitted MoCo v2 encoder over a full raster mosaic
#'
#' Slides a `patch_size x patch_size` window over the input raster at
#' stride `stride`, extracts each patch, encodes it with the
#' backbone of `moco$encoder_q`, and writes the resulting embedding
#' vector back as a multi-layer `terra::SpatRaster` whose layer count
#' equals `moco$feature_dim`. Patches whose centre cell is NA in the
#' input produce an NA row in the output.
#'
#' Normalisation uses the global per-layer mean and sd stored in
#' `dataset`, so the embedding pipeline is consistent between
#' pretraining and inference.
#'
#' @param moco An `edaphos_foundation_moco` returned by
#'   [foundation_moco_pretrain_tiles()].
#' @param stack A `terra::SpatRaster` with the **same channel order**
#'   as the one used at training time.
#' @param dataset The `edaphos_tile_dataset` used at training time
#'   (provides the per-channel normalisation statistics).
#' @param patch_size Integer -- must equal `dataset$patch_size`.
#' @param stride Integer step size of the sliding window (default
#'   half of `patch_size`).
#' @param projection Logical -- if `TRUE` return the L2-normalised
#'   projection-head outputs instead of the backbone features.
#' @return A `terra::SpatRaster` with `feature_dim` (or `proj_dim`)
#'   layers.
#' @examples
#' # Guard on the libtorch binaries as well as on the R package --
#' # requireNamespace() alone is TRUE on machines that cannot run a
#' # single tensor operation.
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed()) &&
#'     requireNamespace("terra", quietly = TRUE)) {
#'
#' covs <- terra::rast(br_cerrado[, c("x", "y", "elev", "slope", "twi",
#'                                    "map_mm", "ndvi")], type = "xyz")
#' ds <- foundation_tile_dataset(covs, patch_size = 8L, n_patches = 64L,
#'                               seed = 7L)
#' set.seed(11)
#' moco <- foundation_moco_pretrain_tiles(ds, feature_dim = 8L,
#'                                        proj_dim = 4L, queue_size = 32L,
#'                                        batch_size = 8L, epochs = 6L,
#'                                        seed = 11L)
#'
#' # One output layer per backbone feature, on a grid coarsened by
#' # `stride`. Pass the same `dataset` you trained on: its per-channel
#' # means and sds are the normalisation, and a different dataset would
#' # feed the encoder a differently-scaled raster.
#' emb <- foundation_moco_embed_raster(moco, covs, ds, stride = 8L)
#' print(c(layers = terra::nlyr(emb), feature_dim = moco$feature_dim))
#' print(terra::res(emb) / terra::res(covs))
#'
#' # TRAP: the output is not co-registered with the input. The grid is
#' # anchored at the input's top-left corner and is ncol(emb) * stride
#' # input columns wide, so with 45 columns and stride 8 the last five
#' # columns -- and the last five rows -- of `covs` are not covered.
#' print(terra::ncol(covs) - 8L * terra::ncol(emb))
#' print(rbind(covs = as.vector(terra::ext(covs)),
#'             emb  = as.vector(terra::ext(emb))))
#'
#' # It overshoots just as happily in the other direction: stride 24
#' # gives two columns of 24 cells, i.e. 48 > 45, and the embedding
#' # raster sticks out past the input. Always crop or resample to a
#' # reference grid before overlaying anything on it.
#' emb24 <- foundation_moco_embed_raster(moco, covs, ds, stride = 24L)
#' print(c(covered = 24L * terra::ncol(emb24),
#'         input = terra::ncol(covs),
#'         overshoots = terra::xmax(emb24) > terra::xmax(covs)))
#'
#' # TRAP: missing data is imputed, not propagated. NA cells are set to
#' # the channel mean before encoding, so a patch that is entirely
#' # no-data -- all five channels blank, below -- still gets a finite
#' # embedding. The output cannot be used to find gaps: carry a separate
#' # mask.
#' blank <- terra::cellFromRowCol(covs, rep(1:8, each = 8), rep(1:8, 8))
#' gap <- terra::deepcopy(covs)
#' for (k in 1:5) gap[[k]][blank] <- NA
#' emb_gap <- foundation_moco_embed_raster(moco, gap, ds, stride = 24L)
#' print(colSums(is.na(terra::values(gap))))
#' print(c(na_in_output = sum(is.na(terra::values(emb_gap)))))
#'
#' # Rows 1:8 / columns 1:8 are exactly the window of the first stride-24
#' # patch, so row 1 of the gapped output is the all-NA patch. Finite it
#' # is; "close to an average patch" it is not, and nothing in the
#' # encoder pulls it there. The line below prints its distance to the
#' # mean of the four real embeddings, then how far the real patches
#' # themselves sit from that same mean, on average and at worst. The
#' # blank patch comes out FARTHER from the average than the average
#' # real patch is -- the opposite of reassuring. Read the printed
#' # values, do not quote a number from this comment: they move with the
#' # fit, and this one is 6 optimiser steps on 64 patches. Nor is the
#' # gap recoverable this way in general; the load-bearing number is the
#' # NA count above -- zero NA reaches the output, so carry a mask.
#' real <- terra::values(emb24)
#' ctr  <- colMeans(real)
#' print(round(c(blank_to_mean = sqrt(sum((terra::values(emb_gap)[1, ] -
#'                                           ctr)^2)),
#'               real_to_mean_mean = mean(sqrt(rowSums(sweep(real, 2,
#'                                                           ctr)^2))),
#'               real_to_mean_max  = max(sqrt(rowSums(sweep(real, 2,
#'                                                          ctr)^2)))), 3))
#'
#' # `projection = TRUE` swaps in the L2-normalised head, so each cell
#' # of the output has unit length across layers: a ready-made cosine
#' # similarity space, and a useless magnitude map.
#' embp <- foundation_moco_embed_raster(moco, covs, ds, stride = 24L,
#'                                      projection = TRUE)
#' print(c(layers = terra::nlyr(embp), proj_dim = moco$proj_dim))
#' print(range(round(sqrt(rowSums(terra::values(embp)^2)), 6)))
#' }
#' @export
foundation_moco_embed_raster <- function(moco, stack, dataset,
                                           patch_size = NULL,
                                           stride = NULL,
                                           projection = FALSE) {
  .moco_require_torch()
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Install `terra` to embed a raster.", call. = FALSE)
  }
  stopifnot(inherits(moco, "edaphos_foundation_moco"),
            inherits(stack, "SpatRaster"),
            inherits(dataset, "edaphos_tile_dataset"))
  if (is.null(patch_size)) patch_size <- dataset$patch_size
  if (is.null(stride))     stride     <- max(1L, patch_size %/% 2L)
  patch_size <- as.integer(patch_size)
  stride     <- as.integer(stride)
  C <- terra::nlyr(stack)
  stopifnot(C == dataset$n_channels)

  half <- patch_size %/% 2L
  nrow_r <- terra::nrow(stack); ncol_r <- terra::ncol(stack)
  centres_r <- seq(half + 1L, nrow_r - half, by = stride)
  centres_c <- seq(half + 1L, ncol_r - half, by = stride)
  n_cent    <- length(centres_r) * length(centres_c)

  # Prepare output: same extent and CRS, but `feature_dim` layers and
  # resolution scaled by stride.
  out_rows <- length(centres_r)
  out_cols <- length(centres_c)
  out_res <- c(terra::xres(stack) * stride, terra::yres(stack) * stride)
  out_ext <- terra::ext(stack)
  out_template <- terra::rast(
    nrows = out_rows, ncols = out_cols,
    xmin = out_ext$xmin, xmax = out_ext$xmin + out_cols * out_res[1L],
    ymin = out_ext$ymax - out_rows * out_res[2L], ymax = out_ext$ymax,
    crs  = terra::crs(stack)
  )
  D <- if (projection) moco$proj_dim else moco$feature_dim
  out <- terra::rast(replicate(D, out_template, simplify = FALSE))
  names(out) <- paste0("emb_", sprintf("%03d", seq_len(D)))

  means <- dataset$means; sds <- dataset$sds
  enc <- moco$encoder_q
  i_out <- 1L
  for (rc in centres_r) {
    for (cc in centres_c) {
      r0 <- rc - half; c0 <- cc - half
      blk <- terra::values(
        stack, row = r0, nrows = patch_size,
        col = c0, ncols = patch_size, mat = TRUE
      )
      arr <- aperm(
        array(blk, dim = c(patch_size, patch_size, C)),
        c(3L, 1L, 2L)
      )
      for (k in seq_len(C)) {
        v <- (arr[k, , ] - means[k]) / sds[k]
        v[is.na(v)] <- 0
        arr[k, , ] <- v
      }
      x <- torch::torch_tensor(array(arr, dim = c(1L, C, patch_size,
                                                    patch_size)))$to(
        dtype = torch::torch_float()
      )
      emb_vec <- torch::with_no_grad({
        if (projection) enc(x) else enc$backbone_features(x)
      })$cpu()
      emb_r <- as.array(emb_vec)[1L, ]
      cell_idx <- terra::cellFromRowCol(out, match(rc, centres_r),
                                          match(cc, centres_c))
      for (d in seq_len(D)) {
        out[[d]][cell_idx] <- emb_r[d]
      }
      i_out <- i_out + 1L
    }
  }
  out
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
