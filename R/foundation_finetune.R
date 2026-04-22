# Pillar 4 -- Downstream fine-tuning API.
#
# `foundation_moco_pretrain()` / `foundation_moco_pretrain_tiles()`
# produce self-supervised encoders that map raster patches to
# feature-dim-dimensional embeddings. Until v1.2.0, consuming those
# encoders for a concrete task (classify soil order, regress SOC from
# a patch of ancillary covariates) required the user to write their
# own torch head on top of `foundation_moco_embed()`. This file
# closes that gap with two dedicated entry points:
#
#   * foundation_fit_classifier()    classification head
#   * foundation_fit_regressor()     regression head
#
# Both accept an `edaphos_foundation_moco` / `_simclr` encoder and
# support two standard training regimes from the transfer-learning
# literature (He, Girshick and Dollar 2019):
#
#   * Linear probing (freeze_backbone = TRUE, head = "linear"):
#     the encoder weights are frozen; only a single linear layer is
#     trained on top of the embeddings. Benchmarks the quality of
#     the self-supervised representation as a fixed feature
#     extractor.
#
#   * Full fine-tuning (freeze_backbone = FALSE): the encoder and
#     head are trained jointly with a two-group learning rate
#     (typically 0.1 * lr for the backbone, 1.0 * lr for the head;
#     Kornblith, Shlens and Le 2019). Usually the better option when
#     the downstream dataset is large enough (>= ~500 labelled
#     patches).
#
# The returned objects `edaphos_foundation_classifier` /
# `_regressor` carry (i) the (possibly fine-tuned) encoder, (ii) the
# trained head, (iii) the class levels / regression target
# normalisation, and (iv) loss + validation-metric histories. A
# standard `predict()` method makes them drop-in compatible with
# every other supervised-learning workflow in `edaphos`.

# --- device / module utilities ----------------------------------------------

.ft_require_torch <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE) ||
      !requireNamespace("torch", quietly = TRUE)) {
    stop("Install the `torch` package (and its MPS / CUDA backend) to use ",
         "the fine-tuning API.", call. = FALSE)
  }
  invisible(TRUE)
}

.ft_resolve_device <- function(device = c("cpu", "mps", "cuda")) {
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
  torch::torch_device(device)
}

.ft_extract_encoder <- function(object) {
  # Accept either an edaphos_foundation_moco or edaphos_foundation_simclr
  # object, return its encoder `nn_module` (query encoder for MoCo).
  if (inherits(object, "edaphos_foundation_moco")) {
    return(object$encoder_q %||% object$encoder %||% object$model)
  }
  if (inherits(object, "edaphos_foundation_simclr")) {
    return(object$encoder %||% object$model)
  }
  # Allow a bare nn_module as a power-user escape hatch.
  if (inherits(object, "nn_module")) return(object)
  stop("`object` must be an edaphos_foundation_moco / _simclr fit ",
       "(from foundation_moco_pretrain_tiles / foundation_simclr_pretrain) ",
       "or a bare nn_module.", call. = FALSE)
}

.ft_feature_dim <- function(object) {
  object$feature_dim %||%
    stop("Could not determine encoder feature_dim; pass it explicitly.",
         call. = FALSE)
}

# Build a classification / regression head as a torch nn_module.
.ft_build_head <- function(feature_dim, out_dim,
                            head = c("linear", "mlp"),
                            hidden = c(64L, 32L),
                            dropout = 0) {
  head <- match.arg(head)
  if (head == "linear") {
    return(torch::nn_linear(feature_dim, out_dim))
  }
  # MLP head
  layers <- list()
  prev <- feature_dim
  for (h in hidden) {
    layers[[length(layers) + 1L]] <- torch::nn_linear(prev, as.integer(h))
    layers[[length(layers) + 1L]] <- torch::nn_relu()
    if (dropout > 0) {
      layers[[length(layers) + 1L]] <- torch::nn_dropout(p = dropout)
    }
    prev <- as.integer(h)
  }
  layers[[length(layers) + 1L]] <- torch::nn_linear(prev, out_dim)
  do.call(torch::nn_sequential, layers)
}

# Forward pass: encoder -> backbone embedding -> head. Used at
# training and inference time alike.
#
# `MoCoEncoder$forward()` returns the L2-normalised projection (used
# for the contrastive InfoNCE loss at pretraining time), which is a
# poor feature for downstream heads. We explicitly call the
# backbone-feature path when available. For encoders without a
# `backbone_features` slot we fall back to `forward()`.
.ft_embed <- function(encoder, x) {
  bf <- encoder$backbone_features %||% NULL
  if (is.function(bf)) return(bf(x))
  out <- encoder(x)
  # Some user-supplied encoders return a named list with a `feature`
  # slot -- support that for ergonomics.
  if (is.list(out)) {
    out$feature %||% out$embedding %||% out[[1L]]
  } else {
    out
  }
}

.ft_forward <- function(encoder, head, x) {
  head(.ft_embed(encoder, x))
}

# Simple train / val random split returning the index vectors.
.ft_train_val_split <- function(N, val_split, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  if (val_split <= 0) return(list(train = seq_len(N), val = integer(0)))
  n_val <- max(1L, floor(val_split * N))
  val_ix <- sample(N, n_val)
  list(train = setdiff(seq_len(N), val_ix), val = val_ix)
}

# --- classifier -------------------------------------------------------------

#' Fine-tune or linearly probe a Pillar 4 encoder for classification
#'
#' Attaches a classification head on top of a self-supervised encoder
#' produced by [foundation_moco_pretrain_tiles()],
#' [foundation_moco_pretrain()] or [foundation_simclr_pretrain()] and
#' trains it against a labelled patch set. Two standard regimes from
#' the transfer-learning literature are supported:
#'
#' \describe{
#'   \item{Linear probe (`freeze_backbone = TRUE`, `head = "linear"`)}{
#'     The encoder weights are frozen; only a single
#'     `nn_linear(feature_dim, n_classes)` head is trained. This is the
#'     canonical benchmark for evaluating self-supervised
#'     representations as fixed feature extractors
#'     (He, Girshick and Dollar 2019).}
#'   \item{Full fine-tuning (`freeze_backbone = FALSE`)}{The encoder
#'     and the head are trained jointly, with a two-group learning
#'     rate (`lr * backbone_lr_mult` for the backbone, `lr` for the
#'     head). Usually the better option when the downstream dataset is
#'     large enough (≥ ~500 patches per class).}
#' }
#'
#' @param encoder An `edaphos_foundation_moco` or
#'   `edaphos_foundation_simclr` fit, or a bare `nn_module` that
#'   accepts `(batch, C, H, W)` input and returns either an embedding
#'   tensor or a list with a `feature` field.
#' @param x A 4-dimensional R array `(N, C, H, W)` of labelled patches,
#'   of the same shape that was used to pretrain the encoder.
#' @param y A factor (or coercible character / integer) of length `N`
#'   with the patch-level class labels.
#' @param freeze_backbone Logical — `TRUE` for linear probing (default),
#'   `FALSE` for full fine-tuning. When `FALSE`, the encoder is put
#'   into training mode and its gradients flow back through the
#'   classification loss.
#' @param head `"linear"` (default) or `"mlp"`.
#' @param hidden Integer vector with MLP hidden-layer widths when
#'   `head = "mlp"`. Default `c(64L, 32L)`.
#' @param dropout Dropout probability in the MLP head (0 = disabled).
#' @param epochs,batch_size,lr Training hyperparameters.
#' @param weight_decay Adam weight decay (L2 regularisation).
#' @param backbone_lr_mult Multiplicative factor applied to `lr` for
#'   the encoder parameters when `freeze_backbone = FALSE`. Default
#'   `0.1`; set to `1.0` to train the backbone at full speed.
#' @param val_split Fraction of `x` held out for validation. `0`
#'   disables validation.
#' @param device `"cpu"` (default), `"mps"` or `"cuda"`. When the
#'   requested backend is unavailable the function falls back to
#'   `"cpu"` with a message.
#' @param seed Optional integer — seeds torch, NumPy and the
#'   train/val split.
#' @param verbose Logical — print loss / accuracy every 10 epochs.
#' @return An `edaphos_foundation_classifier` list with:
#' \describe{
#'   \item{encoder, head}{The trained torch modules.}
#'   \item{classes}{The character factor levels used for prediction.}
#'   \item{loss_history, val_accuracy_history}{Per-epoch training loss
#'     and validation accuracy (NA when `val_split = 0`).}
#'   \item{config}{List of the inputs to
#'     [foundation_fit_classifier()] for reproducibility.}
#' }
#' @seealso [predict.edaphos_foundation_classifier()],
#'   [foundation_fit_regressor()], [foundation_moco_pretrain_tiles()].
#' @references
#' He, K., Girshick, R. and Dollar, P. (2019). Rethinking ImageNet
#' pre-training. *ICCV 2019*.
#'
#' Kornblith, S., Shlens, J. and Le, Q. V. (2019). Do better ImageNet
#' models transfer better? *CVPR 2019*.
#' @examples
#' \dontrun{
#'   ds <- readRDS("tools/pretrain/cerrado_dataset.rds")
#'   moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
#'
#'   # Label a subset of patches by soil order (synthetic example).
#'   patches <- array(rnorm(200 * ds$n_channels * 16 * 16),
#'                    dim = c(200, ds$n_channels, 16, 16))
#'   soil_order <- factor(sample(c("Oxisol", "Ultisol", "Inceptisol"),
#'                                200, replace = TRUE))
#'
#'   fit <- foundation_fit_classifier(
#'     moco, patches, soil_order,
#'     freeze_backbone = TRUE, head = "linear",
#'     epochs = 40L, device = "mps", seed = 1L
#'   )
#'   pred <- predict(fit, patches, type = "class")
#' }
#' @export
foundation_fit_classifier <- function(encoder, x, y,
                                        freeze_backbone = TRUE,
                                        head    = c("linear", "mlp"),
                                        hidden  = c(64L, 32L),
                                        dropout = 0,
                                        epochs  = 30L,
                                        batch_size = 32L,
                                        lr = 1e-3,
                                        weight_decay = 0,
                                        backbone_lr_mult = 0.1,
                                        val_split = 0.2,
                                        device = c("cpu", "mps", "cuda"),
                                        seed    = NULL,
                                        verbose = FALSE) {
  .ft_require_torch()
  head <- match.arg(head)
  stopifnot(is.array(x), length(dim(x)) == 4L,
            length(y) == dim(x)[1L])

  y <- factor(y)
  classes <- levels(y)
  y_int <- as.integer(y)

  if (!is.null(seed)) {
    torch::torch_manual_seed(seed)
    set.seed(seed)
  }
  dev <- .ft_resolve_device(device)

  # Build the forward graph.
  enc <- .ft_extract_encoder(encoder)
  enc <- enc$to(device = dev)
  if (isTRUE(freeze_backbone)) {
    enc$eval()
    for (p in enc$parameters) p$requires_grad_(FALSE)
  } else {
    enc$train()
    for (p in enc$parameters) p$requires_grad_(TRUE)
  }
  feature_dim <- .ft_feature_dim(encoder)
  head_mod <- .ft_build_head(feature_dim, length(classes),
                               head = head, hidden = hidden,
                               dropout = dropout)$to(device = dev)

  # Parameter groups: head always at `lr`, backbone at
  # `lr * backbone_lr_mult` when unfrozen.
  param_groups <- list(
    list(params = head_mod$parameters, lr = lr)
  )
  if (!isTRUE(freeze_backbone)) {
    param_groups <- c(param_groups, list(
      list(params = enc$parameters, lr = lr * backbone_lr_mult)
    ))
  }
  optimizer <- torch::optim_adam(param_groups, weight_decay = weight_decay)

  split <- .ft_train_val_split(dim(x)[1L], val_split, seed = seed)
  x_train <- x[split$train, , , , drop = FALSE]
  y_train <- y_int[split$train]
  x_val   <- if (length(split$val) > 0L)
    x[split$val, , , , drop = FALSE] else NULL
  y_val   <- if (length(split$val) > 0L) y_int[split$val] else NULL

  # Convert to tensors and move to the target device.
  xt <- torch::torch_tensor(x_train)$to(dtype = torch::torch_float(),
                                          device = dev)
  yt <- torch::torch_tensor(y_train, dtype = torch::torch_long())$to(device = dev)

  loss_history <- numeric(epochs)
  val_acc_history <- rep(NA_real_, epochs)

  for (ep in seq_len(epochs)) {
    # Mini-batch shuffle.
    perm <- sample(nrow(x_train))
    ep_loss <- 0
    n_batches <- 0L
    for (start in seq(1L, nrow(x_train), by = batch_size)) {
      idx <- perm[seq(start,
                       min(start + batch_size - 1L, nrow(x_train)))]
      xb <- xt[idx, , , , drop = FALSE]
      yb <- yt[idx]
      optimizer$zero_grad()
      logits <- .ft_forward(enc, head_mod, xb)
      loss <- torch::nnf_cross_entropy(logits, yb)
      loss$backward()
      optimizer$step()
      ep_loss <- ep_loss + as.numeric(loss$item())
      n_batches <- n_batches + 1L
    }
    loss_history[ep] <- ep_loss / max(n_batches, 1L)

    if (!is.null(x_val)) {
      torch::with_no_grad({
        xv <- torch::torch_tensor(x_val)$to(dtype = torch::torch_float(),
                                              device = dev)
        yv <- torch::torch_tensor(y_val, dtype = torch::torch_long())$to(device = dev)
        logits_v <- .ft_forward(enc, head_mod, xv)
        pred_v   <- as.integer(torch::torch_argmax(logits_v, dim = 2L))
        val_acc_history[ep] <- mean(pred_v == y_val)
      })
    }

    if (isTRUE(verbose) && (ep == 1L || ep %% 10L == 0L || ep == epochs)) {
      message(sprintf("[classifier] ep %3d/%d  loss=%.4f  val_acc=%s",
                       ep, epochs, loss_history[ep],
                       if (is.na(val_acc_history[ep])) "-"
                       else sprintf("%.3f", val_acc_history[ep])))
    }
  }

  structure(
    list(
      encoder               = enc,
      head                  = head_mod,
      classes               = classes,
      feature_dim           = feature_dim,
      head_type             = head,
      freeze_backbone       = isTRUE(freeze_backbone),
      loss_history          = loss_history,
      val_accuracy_history  = val_acc_history,
      device                = as.character(dev),
      config = list(
        epochs = as.integer(epochs), batch_size = as.integer(batch_size),
        lr = lr, weight_decay = weight_decay,
        backbone_lr_mult = backbone_lr_mult,
        head = head, hidden = hidden, dropout = dropout,
        val_split = val_split, seed = seed
      )
    ),
    class = "edaphos_foundation_classifier"
  )
}

#' @export
print.edaphos_foundation_classifier <- function(x, ...) {
  cat("<edaphos_foundation_classifier>\n")
  cat(sprintf("  n classes     : %d  (%s)\n",
              length(x$classes), paste(utils::head(x$classes, 5L),
                                        collapse = ", ")))
  cat(sprintf("  feature_dim   : %d   head: %s\n",
              x$feature_dim, x$head_type))
  cat(sprintf("  regime        : %s\n",
              if (x$freeze_backbone) "linear probe (backbone frozen)"
              else "full fine-tuning"))
  cat(sprintf("  device        : %s\n", x$device))
  cat(sprintf("  final loss    : %.4g\n",
              utils::tail(x$loss_history, 1L)))
  if (any(!is.na(x$val_accuracy_history))) {
    cat(sprintf("  best val_acc  : %.3f\n",
                max(x$val_accuracy_history, na.rm = TRUE)))
  }
  invisible(x)
}

#' Predict class probabilities / labels from a fine-tuned classifier
#'
#' @param object An `edaphos_foundation_classifier`.
#' @param x A 4-D array `(N, C, H, W)` of new patches.
#' @param type `"class"` (default — factor of predicted labels) or
#'   `"prob"` (N-by-n_classes matrix of softmax probabilities).
#' @param device Optional override — defaults to the fit-time device.
#' @param ... Unused; S3 predict compatibility.
#' @return A factor (type = "class") or a numeric matrix (type = "prob").
#' @export
predict.edaphos_foundation_classifier <- function(object, x,
                                                     type = c("class",
                                                               "prob"),
                                                     device = NULL, ...) {
  .ft_require_torch()
  stopifnot(is.array(x), length(dim(x)) == 4L)
  type <- match.arg(type)
  dev <- if (is.null(device)) {
    torch::torch_device(object$device)
  } else {
    .ft_resolve_device(device)
  }
  object$encoder <- object$encoder$to(device = dev)
  object$encoder$eval()
  object$head    <- object$head$to(device = dev)
  object$head$eval()
  xt <- torch::torch_tensor(x)$to(dtype = torch::torch_float(),
                                    device = dev)
  logits <- torch::with_no_grad({
    .ft_forward(object$encoder, object$head, xt)
  })
  if (type == "prob") {
    probs <- as.matrix(torch::nnf_softmax(logits, dim = 2L)$to(device = "cpu"))
    colnames(probs) <- object$classes
    return(probs)
  }
  cls_ix <- as.integer(torch::torch_argmax(logits, dim = 2L))
  factor(object$classes[cls_ix], levels = object$classes)
}

# --- regressor --------------------------------------------------------------

#' Fine-tune or linearly probe a Pillar 4 encoder for regression
#'
#' Regression counterpart of [foundation_fit_classifier()]. Attaches
#' a scalar-output head (linear or MLP) on top of a self-supervised
#' encoder and trains it against a numeric target `y`. Supports the
#' same two regimes — linear probing with a frozen backbone or full
#' fine-tuning with a two-group learning rate — and the same
#' `device ∈ {"cpu", "mps", "cuda"}` dispatch.
#'
#' Target normalisation is handled internally: `y` is centred and
#' scaled before training and un-scaled at `predict()` time so the
#' user never has to think about the numerical range of the head.
#'
#' @param encoder See [foundation_fit_classifier()].
#' @param x A 4-D array `(N, C, H, W)` of patches.
#' @param y Numeric vector of length `N` with the target values.
#' @param freeze_backbone,head,hidden,dropout,epochs,batch_size,lr,weight_decay,backbone_lr_mult,val_split,device,seed,verbose
#'   See [foundation_fit_classifier()].
#' @param loss One of `"mse"` (default) or `"huber"`. Huber is more
#'   robust to outlier pedons with extreme SOC / clay contents.
#' @return An `edaphos_foundation_regressor` list with the same slots
#'   as the classifier counterpart plus `y_mean`, `y_sd` (target
#'   normalisation constants) and `val_rmse_history`.
#' @seealso [predict.edaphos_foundation_regressor()].
#' @examples
#' \dontrun{
#'   moco <- foundation_weights_load("edaphos-cerrado-moco-v1")
#'   ds   <- readRDS("tools/pretrain/cerrado_dataset.rds")
#'   patches <- array(rnorm(300 * ds$n_channels * 16 * 16),
#'                    dim = c(300, ds$n_channels, 16, 16))
#'   soc <- rnorm(300, mean = 15, sd = 6)
#'   fit <- foundation_fit_regressor(
#'     moco, patches, soc,
#'     freeze_backbone = TRUE, head = "linear",
#'     epochs = 40L, device = "mps", seed = 1L
#'   )
#'   predict(fit, patches[1:10, , , , drop = FALSE])
#' }
#' @export
foundation_fit_regressor <- function(encoder, x, y,
                                       freeze_backbone = TRUE,
                                       head    = c("linear", "mlp"),
                                       hidden  = c(64L, 32L),
                                       dropout = 0,
                                       epochs  = 30L,
                                       batch_size = 32L,
                                       lr = 1e-3,
                                       weight_decay = 0,
                                       backbone_lr_mult = 0.1,
                                       loss = c("mse", "huber"),
                                       val_split = 0.2,
                                       device = c("cpu", "mps", "cuda"),
                                       seed    = NULL,
                                       verbose = FALSE) {
  .ft_require_torch()
  head <- match.arg(head)
  loss_fn_name <- match.arg(loss)
  stopifnot(is.array(x), length(dim(x)) == 4L,
            is.numeric(y), length(y) == dim(x)[1L])

  y_mean <- mean(y, na.rm = TRUE)
  y_sd   <- max(stats::sd(y, na.rm = TRUE), 1e-6)
  y_n    <- (y - y_mean) / y_sd

  if (!is.null(seed)) {
    torch::torch_manual_seed(seed); set.seed(seed)
  }
  dev <- .ft_resolve_device(device)

  enc <- .ft_extract_encoder(encoder)
  enc <- enc$to(device = dev)
  if (isTRUE(freeze_backbone)) {
    enc$eval()
    for (p in enc$parameters) p$requires_grad_(FALSE)
  } else {
    enc$train()
    for (p in enc$parameters) p$requires_grad_(TRUE)
  }
  feature_dim <- .ft_feature_dim(encoder)
  head_mod <- .ft_build_head(feature_dim, 1L, head = head,
                               hidden = hidden, dropout = dropout)$to(device = dev)

  param_groups <- list(list(params = head_mod$parameters, lr = lr))
  if (!isTRUE(freeze_backbone)) {
    param_groups <- c(param_groups, list(
      list(params = enc$parameters, lr = lr * backbone_lr_mult)
    ))
  }
  optimizer <- torch::optim_adam(param_groups, weight_decay = weight_decay)

  split <- .ft_train_val_split(dim(x)[1L], val_split, seed = seed)
  x_train <- x[split$train, , , , drop = FALSE]
  y_train <- y_n[split$train]
  x_val   <- if (length(split$val) > 0L)
    x[split$val, , , , drop = FALSE] else NULL
  y_val_raw <- if (length(split$val) > 0L) y[split$val] else NULL

  xt <- torch::torch_tensor(x_train)$to(dtype = torch::torch_float(),
                                          device = dev)
  yt <- torch::torch_tensor(y_train, dtype = torch::torch_float())$to(device = dev)

  loss_history     <- numeric(epochs)
  val_rmse_history <- rep(NA_real_, epochs)

  loss_fn <- switch(loss_fn_name,
                     mse   = torch::nnf_mse_loss,
                     huber = torch::nnf_smooth_l1_loss)

  for (ep in seq_len(epochs)) {
    perm <- sample(nrow(x_train))
    ep_loss <- 0; n_batches <- 0L
    for (start in seq(1L, nrow(x_train), by = batch_size)) {
      idx <- perm[seq(start,
                       min(start + batch_size - 1L, nrow(x_train)))]
      xb <- xt[idx, , , , drop = FALSE]
      yb <- yt[idx]
      optimizer$zero_grad()
      pred <- .ft_forward(enc, head_mod, xb)$squeeze(-1L)
      l    <- loss_fn(pred, yb)
      l$backward()
      optimizer$step()
      ep_loss <- ep_loss + as.numeric(l$item())
      n_batches <- n_batches + 1L
    }
    loss_history[ep] <- ep_loss / max(n_batches, 1L)

    if (!is.null(x_val)) {
      torch::with_no_grad({
        xv <- torch::torch_tensor(x_val)$to(dtype = torch::torch_float(),
                                              device = dev)
        pred_v_n <- as.numeric(
          .ft_forward(enc, head_mod, xv)$squeeze(-1L)$to(device = "cpu")
        )
        pred_v <- pred_v_n * y_sd + y_mean
        val_rmse_history[ep] <- sqrt(mean((pred_v - y_val_raw)^2,
                                            na.rm = TRUE))
      })
    }

    if (isTRUE(verbose) && (ep == 1L || ep %% 10L == 0L || ep == epochs)) {
      message(sprintf("[regressor] ep %3d/%d  loss=%.4f  val_rmse=%s",
                       ep, epochs, loss_history[ep],
                       if (is.na(val_rmse_history[ep])) "-"
                       else sprintf("%.4f", val_rmse_history[ep])))
    }
  }

  structure(
    list(
      encoder          = enc,
      head             = head_mod,
      feature_dim      = feature_dim,
      head_type        = head,
      freeze_backbone  = isTRUE(freeze_backbone),
      y_mean           = y_mean,
      y_sd             = y_sd,
      loss_fn          = loss_fn_name,
      loss_history     = loss_history,
      val_rmse_history = val_rmse_history,
      device           = as.character(dev),
      config = list(
        epochs = as.integer(epochs), batch_size = as.integer(batch_size),
        lr = lr, weight_decay = weight_decay,
        backbone_lr_mult = backbone_lr_mult,
        head = head, hidden = hidden, dropout = dropout,
        loss = loss_fn_name,
        val_split = val_split, seed = seed
      )
    ),
    class = "edaphos_foundation_regressor"
  )
}

#' @export
print.edaphos_foundation_regressor <- function(x, ...) {
  cat("<edaphos_foundation_regressor>\n")
  cat(sprintf("  feature_dim   : %d   head: %s   loss: %s\n",
              x$feature_dim, x$head_type, x$loss_fn))
  cat(sprintf("  regime        : %s\n",
              if (x$freeze_backbone) "linear probe (backbone frozen)"
              else "full fine-tuning"))
  cat(sprintf("  device        : %s\n", x$device))
  cat(sprintf("  y_mean / y_sd : %.4g  /  %.4g\n", x$y_mean, x$y_sd))
  cat(sprintf("  final loss    : %.4g\n",
              utils::tail(x$loss_history, 1L)))
  if (any(!is.na(x$val_rmse_history))) {
    cat(sprintf("  best val_rmse : %.4g\n",
                min(x$val_rmse_history, na.rm = TRUE)))
  }
  invisible(x)
}

#' Predict numeric targets from a fine-tuned regressor
#'
#' @param object An `edaphos_foundation_regressor`.
#' @param x A 4-D array `(N, C, H, W)` of new patches.
#' @param device Optional override — defaults to the fit-time device.
#' @param ... Unused.
#' @return Numeric vector of predicted targets, back-transformed to
#'   the original scale of `y`.
#' @export
predict.edaphos_foundation_regressor <- function(object, x,
                                                    device = NULL, ...) {
  .ft_require_torch()
  stopifnot(is.array(x), length(dim(x)) == 4L)
  dev <- if (is.null(device)) torch::torch_device(object$device)
         else .ft_resolve_device(device)
  object$encoder <- object$encoder$to(device = dev)
  object$encoder$eval()
  object$head    <- object$head$to(device = dev)
  object$head$eval()
  xt <- torch::torch_tensor(x)$to(dtype = torch::torch_float(),
                                    device = dev)
  pred_n <- torch::with_no_grad({
    as.numeric(.ft_forward(object$encoder, object$head, xt)$squeeze(-1L)$to(device = "cpu"))
  })
  pred_n * object$y_sd + object$y_mean
}
