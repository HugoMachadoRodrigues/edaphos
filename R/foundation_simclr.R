# Pillar 4 — Foundation Model (scaffold).
#
# SimCLR (Chen et al. 2020) adapted to soil covariate rasters.
# Training pretexts the encoder on raw covariate patches without any
# soil-property label: the model learns that two augmented views of the
# same patch should embed nearby, while views of different patches
# should repel. The resulting encoder is then reusable as a learned
# covariate-to-embedding map — usable as extra features for Pillars 2
# and 5 with no labelled data consumed during pre-training.
#
# This file ships a **scaffold** implementation sized for unit testing
# (tiny batches, tiny encoder) so that the Pillar 4 plumbing is in
# place and has regression coverage. Production-scale training on
# planetary covariate cubes (the real "SoilGPT" premise) needs GPU
# workflows, momentum encoders and larger backbones — scheduled for
# 0.1.0+.

.foundation_require_torch <- function() {
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("Install the `torch` package to use foundation_simclr_*().",
         call. = FALSE)
  }
  invisible(TRUE)
}

.foundation_build_encoder <- function() {
  torch::nn_module(
    "RasterEncoder",
    initialize = function(in_channels, feature_dim = 32L, proj_dim = 16L) {
      self$feature_dim <- as.integer(feature_dim)
      self$conv1 <- torch::nn_conv2d(as.integer(in_channels),
                                      16L, kernel_size = 3L, padding = 1L)
      self$conv2 <- torch::nn_conv2d(16L, self$feature_dim,
                                      kernel_size = 3L, padding = 1L)
      self$pool  <- torch::nn_adaptive_avg_pool2d(c(1L, 1L))
      self$proj  <- torch::nn_sequential(
        torch::nn_linear(self$feature_dim, self$feature_dim),
        torch::nn_relu(),
        torch::nn_linear(self$feature_dim, as.integer(proj_dim))
      )
    },
    backbone = function(x) {
      h <- torch::nnf_relu(self$conv1(x))
      h <- torch::nnf_relu(self$conv2(h))
      h <- self$pool(h)$reshape(c(x$size(1L), self$feature_dim))
      h
    },
    forward = function(x) {
      h <- self$backbone(x)
      z <- self$proj(h)
      z / torch::torch_sqrt(
        torch::torch_sum(z * z, dim = 2L, keepdim = TRUE) + 1e-9
      )
    }
  )
}

.foundation_augment <- function(x, noise_sd = 0.1) {
  # x: (B, C, H, W) torch tensor.
  # Per-sample random flips + additive Gaussian noise + channel dropout.
  B <- x$size(1L); C <- x$size(2L)
  out <- x$clone()
  for (i in seq_len(B)) {
    if (stats::runif(1) > 0.5) {
      out[i, , , ] <- torch::torch_flip(out[i, , , ], dims = c(2L))
    }
    if (stats::runif(1) > 0.5) {
      out[i, , , ] <- torch::torch_flip(out[i, , , ], dims = c(3L))
    }
    # Channel dropout (probability 0.2 per channel).
    if (C > 1L) {
      drop <- stats::runif(C) < 0.2
      if (any(drop)) {
        for (c in which(drop)) out[i, c, , ] <- 0
      }
    }
  }
  noise <- torch::torch_randn_like(out) * noise_sd
  out + noise
}

.foundation_nt_xent <- function(z1, z2, temperature = 0.2) {
  B <- z1$size(1L)
  z <- torch::torch_cat(list(z1, z2), dim = 1L)        # (2B, D)
  sim <- torch::torch_mm(z, z$t()) / temperature       # (2B, 2B)
  # Large negative on self-similarity so softmax ignores it.
  sim <- sim - 1e9 * torch::torch_eye(2L * B)
  # Positives: i <-> i+B (top half); j <-> j-B (bottom half).
  # R torch uses 1-based indexing for class labels.
  labels <- torch::torch_tensor(
    c(as.integer((B + 1L):(2L * B)), as.integer(1L:B)),
    dtype = torch::torch_long()
  )
  torch::nnf_cross_entropy(sim, labels)
}

#' SimCLR pre-training on raster covariate patches (Pillar 4 scaffold)
#'
#' Trains a small CNN encoder on unlabeled raster patches via the SimCLR
#' contrastive objective. Each forward pass draws two independent
#' augmented views of every patch in the mini-batch and enforces high
#' embedding similarity between views of the same patch and low
#' similarity otherwise.
#'
#' @param patches A 4-D R array shaped `(N, C, H, W)`: `N` patches, `C`
#'   covariate channels, spatial `H x W`.
#' @param feature_dim,proj_dim Integer; backbone and projection head
#'   widths.
#' @param batch_size Integer; SimCLR mini-batch size. Each batch
#'   contributes `2 * batch_size - 2` negatives per anchor.
#' @param epochs,lr Training hyperparameters for Adam.
#' @param temperature Numeric; NT-Xent temperature.
#' @param noise_sd Numeric; additive-noise strength during augmentation.
#' @param seed,verbose As elsewhere.
#'
#' @return A `edaphos_foundation_simclr` object (S3).
#' @export
foundation_simclr_pretrain <- function(patches,
                                        feature_dim = 32L, proj_dim = 16L,
                                        batch_size = 8L,
                                        epochs = 30L, lr = 0.005,
                                        temperature = 0.2,
                                        noise_sd = 0.1,
                                        seed = NULL, verbose = FALSE) {
  .foundation_require_torch()
  stopifnot(length(dim(patches)) == 4L)
  if (!is.null(seed)) torch::torch_manual_seed(seed)

  N <- dim(patches)[1L]
  C <- dim(patches)[2L]
  batch_size <- as.integer(min(batch_size, N))

  patches_t <- torch::torch_tensor(patches)$to(dtype = torch::torch_float())

  EncCtor <- .foundation_build_encoder()
  model   <- EncCtor(in_channels = C,
                     feature_dim = as.integer(feature_dim),
                     proj_dim    = as.integer(proj_dim))
  optimizer <- torch::optim_adam(model$parameters, lr = lr)

  loss_history <- numeric(epochs)
  for (ep in seq_len(epochs)) {
    # Random mini-batch of patch indices.
    idx <- sample.int(N, batch_size)
    batch <- patches_t[idx, , , ]
    view1 <- .foundation_augment(batch, noise_sd = noise_sd)
    view2 <- .foundation_augment(batch, noise_sd = noise_sd)

    optimizer$zero_grad()
    z1 <- model(view1)
    z2 <- model(view2)
    loss <- .foundation_nt_xent(z1, z2, temperature = temperature)
    loss$backward()
    optimizer$step()
    loss_history[ep] <- as.numeric(loss$item())
    if (verbose && (ep %% 5L == 0L || ep == 1L || ep == epochs)) {
      message(sprintf("[ep %3d/%d] contrastive loss = %.4f",
                      ep, epochs, loss_history[ep]))
    }
  }

  structure(
    list(
      model        = model,
      in_channels  = C,
      feature_dim  = as.integer(feature_dim),
      proj_dim     = as.integer(proj_dim),
      batch_size   = batch_size,
      temperature  = temperature,
      loss_history = loss_history,
      final_loss   = loss_history[epochs]
    ),
    class = "edaphos_foundation_simclr"
  )
}

#' Extract embeddings from a pretrained SimCLR encoder
#'
#' Returns the **backbone** features (before the projection head) —
#' these are the reusable vectors to feed into downstream DSM models. If
#' you wanted the contrastive-projection vectors instead, pass
#' `projection = TRUE`.
#'
#' @param object A `edaphos_foundation_simclr`.
#' @param patches Array `(N, C, H, W)`.
#' @param projection Logical; return L2-normalised projection-head
#'   outputs instead of backbone features.
#' @return Numeric matrix `N x D` with `D = feature_dim` (or `proj_dim`).
#' @export
foundation_simclr_embed <- function(object, patches, projection = FALSE) {
  .foundation_require_torch()
  stopifnot(inherits(object, "edaphos_foundation_simclr"),
            length(dim(patches)) == 4L)
  patches_t <- torch::torch_tensor(patches)$to(dtype = torch::torch_float())
  emb <- torch::with_no_grad({
    if (projection) {
      z <- object$model(patches_t)
    } else {
      z <- object$model$backbone(patches_t)
    }
    as.array(z$cpu())
  })
  emb
}

#' @export
print.edaphos_foundation_simclr <- function(x, ...) {
  cat("<edaphos_foundation_simclr> (experimental; Pillar 4 scaffold)\n")
  cat(sprintf("  in_channels = %d  feature_dim = %d  proj_dim = %d\n",
              x$in_channels, x$feature_dim, x$proj_dim))
  cat(sprintf("  batch = %d  temperature = %.3g\n",
              x$batch_size, x$temperature))
  cat(sprintf("  epochs = %d  final loss = %.4g\n",
              length(x$loss_history), x$final_loss))
  invisible(x)
}
