# Pillar 4 adapter to the unified v1.6.0 uncertainty API.
#
# Pillar 4 has been deterministic through v1.5.0 -- a single encoder
# fine-tuned into a single classifier or regressor. The foundation-
# models literature already ships two cheap uncertainty recipes that
# work well at fine-tune time:
#
#   (A) Deep-ensemble head  -- fit K heads with different seeds on
#       top of the (frozen or unfrozen) encoder.  Deterministic at
#       predict time, variance estimated across members.
#       Lakshminarayanan, Pritzel, Blundell (2017).
#
#   (B) MC-dropout head    -- leave the dropout layers of the head
#       active at predict time and run N forward passes. Gal and
#       Ghahramani (2016).
#
# v1.6.0-e wires both, using the already-existing
# `foundation_fit_classifier()` / `foundation_fit_regressor()` entry
# points so the scientific content (SimCLR/MoCo encoder, linear
# probe vs full fine-tune, etc.) is untouched.

# ---------------------------------------------------------------------------
# (A) Deep-ensemble head
# ---------------------------------------------------------------------------

#' Deep-ensemble fine-tune of a Pillar 4 foundation encoder
#'
#' Trains `K_ens` independent heads on the same encoder with
#' different random seeds and collects them into a single object.
#' Each member is a full [`foundation_fit_classifier()`] or
#' [`foundation_fit_regressor()`] fit.
#'
#' @param encoder A MoCo/SimCLR encoder as returned by
#'   [`foundation_weights_load()`] (or an equivalent `nn_module`).
#' @param x,y Training data; same shape requirements as the base
#'   fine-tune functions (4-D array `(N, C, H, W)` + vector `y`).
#' @param task `"classification"` or `"regression"`.
#' @param K_ens Integer; number of ensemble heads. Defaults to `5L`.
#' @param base_seed Integer; each member uses `base_seed + k - 1L`.
#' @param ... Additional arguments forwarded verbatim to
#'   [`foundation_fit_classifier()`] or [`foundation_fit_regressor()`]
#'   (e.g. `epochs`, `batch_size`, `lr`, `dropout`, `hidden`,
#'   `freeze_backbone`, `device`, `verbose`).
#' @return A list with class `edaphos_foundation_ensemble` containing
#'   `members` (list of K fits), `task`, `K_ens`, `encoder` (a
#'   reference to the fit-time encoder), and `final_losses` /
#'   `loss_histories`.
#' @references
#' Lakshminarayanan, B., Pritzel, A. and Blundell, C. (2017). Simple
#' and scalable predictive uncertainty estimation using deep
#' ensembles. *NeurIPS 30*.
#' @export
foundation_finetune_ensemble <- function(encoder, x, y,
                                           task = c("classification",
                                                    "regression"),
                                           K_ens = 5L,
                                           base_seed = 301L, ...) {
  task  <- match.arg(task)
  K_ens <- as.integer(K_ens)
  stopifnot(K_ens >= 2L)
  fit_fn <- if (task == "classification") foundation_fit_classifier
              else foundation_fit_regressor

  members <- vector("list", K_ens)
  for (k in seq_len(K_ens)) {
    seed_k <- as.integer(base_seed + k - 1L)
    members[[k]] <- fit_fn(encoder = encoder, x = x, y = y,
                             seed = seed_k, ...)
  }
  structure(
    list(
      members        = members,
      encoder        = encoder,
      task           = task,
      K_ens          = K_ens,
      final_losses   = vapply(members,
                                function(m) utils::tail(m$loss_history, 1L),
                                numeric(1L)),
      loss_histories = lapply(members, `[[`, "loss_history"),
      config         = list(base_seed = base_seed, task = task)
    ),
    class = "edaphos_foundation_ensemble"
  )
}

#' @export
print.edaphos_foundation_ensemble <- function(x, ...) {
  cat("<edaphos_foundation_ensemble>\n")
  cat(sprintf("  task    : %s\n", x$task))
  cat(sprintf("  K_ens   : %d\n", x$K_ens))
  cat(sprintf("  final losses : min=%.4g  median=%.4g  max=%.4g\n",
              min(x$final_losses), stats::median(x$final_losses),
              max(x$final_losses)))
  invisible(x)
}

#' Predict with an edaphos_foundation_ensemble
#'
#' Returns the per-member prediction stack. For regression this is a
#' `(K_ens, N)` matrix; for classification this is a
#' `(K_ens, N, n_classes)` array of softmax probabilities.
#'
#' @param object An `edaphos_foundation_ensemble`.
#' @param x New patches `(N, C, H, W)`.
#' @param ... Forwarded to the member-wise `predict()` methods.
#' @return A per-member prediction array (see above).
#' @export
predict.edaphos_foundation_ensemble <- function(object, x, ...) {
  if (object$task == "regression") {
    out <- vapply(object$members,
                   function(m) as.numeric(stats::predict(m, x = x, ...)),
                   numeric(nrow(x) %||% dim(x)[1L]))
    # out is (N, K_ens); return (K_ens, N).
    t(out)
  } else {
    p_list <- lapply(object$members,
                       function(m) stats::predict(m, x = x,
                                                    type = "prob", ...))
    arr <- array(unlist(p_list, use.names = FALSE),
                  dim = c(dim(p_list[[1L]]), length(p_list)))
    # arr is (N, n_classes, K_ens); permute to (K_ens, N, n_classes).
    aperm(arr, c(3L, 1L, 2L))
  }
}

# ---------------------------------------------------------------------------
# (B) MC-dropout predict
# ---------------------------------------------------------------------------

#' MC-dropout predictive draws from a fine-tuned Pillar 4 fit
#'
#' Runs `n_draws` forward passes through a fitted
#' `edaphos_foundation_classifier` or `edaphos_foundation_regressor`
#' with the MLP head's dropout kept in train mode, producing a
#' Monte-Carlo sample of the predictive posterior (Gal & Ghahramani
#' 2016). The fit must have been trained with an MLP head and a
#' non-zero `dropout` for the draws to be non-degenerate.
#'
#' @param object An `edaphos_foundation_classifier` or
#'   `edaphos_foundation_regressor` fit.
#' @param x New patches `(N, C, H, W)`.
#' @param n_draws Integer; number of MC forward passes.
#' @param seed Optional integer seed.
#' @return For regression, a `(n_draws, N)` numeric matrix. For
#'   classification, a `(n_draws, N, n_classes)` array of softmax
#'   probabilities.
#' @references
#' Gal, Y. and Ghahramani, Z. (2016). Dropout as a Bayesian
#' approximation: representing model uncertainty in deep learning.
#' *ICML 33*, 1050-1059.
#' @export
foundation_mcdropout_predict <- function(object, x,
                                            n_draws = 50L,
                                            seed = NULL) {
  stopifnot(inherits(object, c("edaphos_foundation_classifier",
                                 "edaphos_foundation_regressor")))
  if (!requireNamespace("torch", quietly = TRUE)) {
    stop("torch is required for foundation_mcdropout_predict().",
         call. = FALSE)
  }
  if (!is.null(seed)) torch::torch_manual_seed(seed)
  n_draws <- as.integer(n_draws)
  stopifnot(n_draws >= 1L)

  is_classifier <- inherits(object, "edaphos_foundation_classifier")
  # We cannot call `predict()` here because both regressor and
  # classifier predict methods force `head$eval()`, which disables
  # dropout. Instead we run the underlying encoder + head graph by
  # hand so the head can stay in train mode.
  dev <- torch::torch_device(object$device)
  object$encoder <- object$encoder$to(device = dev)
  object$head    <- object$head$to(device = dev)
  object$encoder$eval()      # encoder stays deterministic
  object$head$train()        # dropout active
  on.exit(object$head$eval(), add = TRUE)

  xt <- torch::torch_tensor(x)$to(dtype = torch::torch_float(),
                                    device = dev)

  draws <- vector("list", n_draws)
  for (m in seq_len(n_draws)) {
    logits <- torch::with_no_grad({
      .ft_forward(object$encoder, object$head, xt)
    })
    if (is_classifier) {
      prob <- as.matrix(torch::nnf_softmax(logits, dim = 2L)$to(device = "cpu"))
      colnames(prob) <- object$classes
      draws[[m]] <- prob
    } else {
      pred_n <- as.numeric(logits$squeeze(-1L)$to(device = "cpu"))
      draws[[m]] <- pred_n * object$y_sd + object$y_mean
    }
  }
  if (is_classifier) {
    arr <- array(unlist(draws, use.names = FALSE),
                  dim = c(dim(draws[[1L]]), n_draws))
    aperm(arr, c(3L, 1L, 2L))
  } else {
    do.call(rbind, draws)
  }
}

# ---------------------------------------------------------------------------
# Adapters
# ---------------------------------------------------------------------------

#' @export
as_edaphos_posterior.edaphos_foundation_ensemble <- function(x,
                                                               newx = NULL,
                                                               units = NULL,
                                                               ...) {
  if (is.null(newx)) {
    stop("Supply `newx = ...` (a 4-D patch tensor) to adapt a foundation ensemble.",
         call. = FALSE)
  }
  preds <- stats::predict(x, x = newx, ...)
  # For regression: preds is (K, N) already.
  # For classification: preds is (K, N, n_classes); marginalise to
  # the probability of the first class? or flatten. To keep a scalar
  # posterior per query, we take p(y = class_argmax_over_members)
  # by averaging. But the uniform recipe is: treat every
  # class-probability as an independent scalar posterior.
  if (x$task == "regression") {
    edaphos_posterior(
      samples    = preds,                       # (K, N)
      method     = "ensemble",
      query_type = "sample",
      units      = units,
      metadata   = list(task = "regression", K_ens = x$K_ens)
    )
  } else {
    # Keep samples 3-D so the query shape is (N, n_classes).
    edaphos_posterior(
      samples    = preds,                       # (K, N, n_classes)
      method     = "ensemble",
      query_type = "feature",
      units      = units,
      metadata   = list(task = "classification", K_ens = x$K_ens,
                         classes = x$members[[1L]]$classes)
    )
  }
}
