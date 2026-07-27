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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   # 8 x 8 covariate patches cut on a stride-6 grid over the 45 x 45
#'   # br_cerrado raster; the label is mean SOC inside the patch.
#'   g <- 45L; p <- 8L
#'   cov4 <- lapply(br_cerrado[c("elev", "slope", "twi", "ndvi")],
#'                  function(v) matrix(scale(v)[, 1L], g, g))
#'   soc_m <- matrix(br_cerrado$soc, g, g)
#'   ij <- expand.grid(i = seq(1L, g - p + 1L, by = 6L),
#'                     j = seq(1L, g - p + 1L, by = 6L))
#'   x <- array(0, dim = c(nrow(ij), 4L, p, p))
#'   y <- numeric(nrow(ij))
#'   for (k in seq_len(nrow(ij))) {
#'     rr <- ij$i[k] + 0:(p - 1L); cc <- ij$j[k] + 0:(p - 1L)
#'     for (ch in 1:4) x[k, ch, , ] <- cov4[[ch]][rr, cc]
#'     y[k] <- mean(soc_m[rr, cc])
#'   }
#'   set.seed(2024)
#'   test  <- sample(nrow(ij), 12L)
#'   train <- setdiff(seq_len(nrow(ij)), test)
#'
#'   # A MoCo fit exposes backbone_features(), which is what the
#'   # fine-tune heads read. A SimCLR fit does not: its heads are fed
#'   # the projection output instead, so there proj_dim must equal
#'   # feature_dim or the head is built at the wrong width.
#'   enc <- foundation_moco_pretrain(
#'     x[train, , , , drop = FALSE], feature_dim = 16L, proj_dim = 8L,
#'     queue_size = 16L, batch_size = 8L, epochs = 5L, seed = 42L)
#'
#'   # READ THIS BEFORE READING ANY NUMBER BELOW. In
#'   # foundation_moco_pretrain(), `epochs` counts optimiser steps and
#'   # not passes over the data: one mini-batch is drawn per epoch. So
#'   # `enc` above is five gradient steps on batches of 8 -- 40 patch
#'   # presentations drawn from 37 patches. Its own diagnostic says
#'   # what that buys: the InfoNCE loss of an encoder whose logits are
#'   # all equal, i.e. one that cannot pick the positive key out of its
#'   # queue_size negatives, is log1p(queue_size). The trace below is
#'   # noise around that line rather than a descent: it is not
#'   # monotone, and which side of the baseline its last value lands on
#'   # is not stable.
#'   print(round(enc$loss_history, 3))
#'   print(round(c(final_infonce    = enc$final_loss,
#'                 all_logits_equal = log1p(enc$queue_size),
#'                 patch_draws      = length(enc$loss_history) *
#'                                      enc$batch_size), 3))
#'   print(c(monotone = all(diff(enc$loss_history) < 0)))
#'   # Do not read the exact figures as a property of `seed = 42L`
#'   # either: that argument fixes only the torch RNG, while the batch
#'   # draw and the augmentations come from R's RNG, so the whole trace
#'   # -- final value included -- moves with the ambient R seed.
#'
#'   # `enc` is therefore, for practical purposes, a random
#'   # convolutional feature map -- and the fine-tune keeps it that
#'   # way, because freeze_backbone defaults to TRUE and only the head
#'   # is trained. Everything below is a demonstration of the ENSEMBLE
#'   # MACHINERY -- the fitting loop, the (K_ens, N) predict contract,
#'   # how to aggregate it, how to score it -- and none of it is
#'   # evidence about soil carbon. A representation worth fine-tuning
#'   # needs patches by the 1e4-1e6 and thousands of steps;
#'   # foundation_moco_pretrain_tiles() is the entry point that
#'   # streams a corpus that size.
#'
#'   # K_ens = 3 and 20 epochs keep this example short; an ensemble you
#'   # would report wants 5-10 members. With K = 3 the member sd below
#'   # has two degrees of freedom.
#'   ens <- foundation_finetune_ensemble(
#'     enc, x = x[train, , , , drop = FALSE], y = y[train],
#'     task = "regression", K_ens = 3L, base_seed = 301L,
#'     head = "mlp", hidden = 8L, dropout = 0.2,
#'     epochs = 20L, batch_size = 16L, lr = 0.01, device = "cpu")
#'   print(ens)
#'
#'   # Member k is fit with seed = base_seed + k - 1, and that seed
#'   # drives the head initialisation, the mini-batch order AND the
#'   # internal val_split holdout -- so no two members train on exactly
#'   # the same patches, and they do not converge to the same loss.
#'   print(round(ens$final_losses, 3))
#'
#'   # predict() returns the raw (K_ens, N) member stack, never a
#'   # summary; aggregating it is the caller's job.
#'   newx  <- x[test, , , , drop = FALSE]
#'   preds <- predict(ens, x = newx)
#'   print(dim(preds))
#'   mu   <- colMeans(preds)
#'   sd_k <- apply(preds, 2L, stats::sd)
#'   print(round(rbind(mean = mu, sd = sd_k)[, 1:4], 2))
#'
#'   # Averaging is not cosmetic, and this part survives the useless
#'   # backbone: in squared error the ensemble mean is at least as good
#'   # as the average member for ANY collection of members, good or
#'   # garbage (the ambiguity decomposition). It is not guaranteed to
#'   # beat the best member, and it still has to beat an achievable
#'   # null -- the training mean.
#'   sq_err <- function(z) mean((y[test] - z)^2)
#'   print(round(c(member         = apply(preds, 1L, sq_err),
#'                 ensemble_mean  = sq_err(mu),
#'                 average_member = mean(apply(preds, 1L, sq_err)),
#'                 train_mean     = sq_err(rep(mean(y[train]),
#'                                             length(test)))), 3))
#'
#'   # Beating that null is no verdict on the pretraining either. With
#'   # the backbone frozen this is random-feature regression, and a
#'   # trained head on random features is already a real (weak)
#'   # predictor. The matched control: same head, same seed 301, on an
#'   # encoder given ONE gradient step instead of five.
#'   enc1 <- foundation_moco_pretrain(
#'     x[train, , , , drop = FALSE], feature_dim = 16L, proj_dim = 8L,
#'     queue_size = 16L, batch_size = 8L, epochs = 1L, seed = 42L)
#'   fit1 <- foundation_fit_regressor(
#'     enc1, x = x[train, , , , drop = FALSE], y = y[train],
#'     head = "mlp", hidden = 8L, dropout = 0.2, epochs = 20L,
#'     batch_size = 16L, lr = 0.01, device = "cpu", seed = 301L)
#'   print(round(c(
#'     member1_enc_5ep   = sq_err(preds[1L, ]),
#'     same_head_enc_1ep = sq_err(as.numeric(predict(fit1, x = newx))),
#'     member_spread     = diff(range(apply(preds, 1L, sq_err)))), 3))
#'   # That contrast would have to come out decisively for the 5-step
#'   # encoder before any accuracy above could be credited to the
#'   # pretraining, and 12 test patches cannot settle it whichever way
#'   # it lands on your machine -- compare the gap between the two
#'   # against member_spread, which is pure head-seed noise.
#'
#'   # The member spread is not a posterior: it covers initialisation
#'   # and optimisation, not the noise in y. Score the band rather than
#'   # trust it -- PICP against the nominal 0.95, read next to the
#'   # interval score, which also charges for width.
#'   lo <- mu - 1.96 * sd_k; up <- mu + 1.96 * sd_k
#'   print(round(c(picp           = edaphos_picp(y[test], lo, up),
#'                 mean_width     = mean(up - lo),
#'                 interval_score = edaphos_interval_score(y[test],
#'                                                          lo, up)), 3))
#'   # With length(test) = 12, PICP moves in steps of 1/12 and carries
#'   # a standard error near 0.1: a smoke test that the plumbing runs,
#'   # not a calibration result for this or any encoder.
#' }
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
#' @examples
#' if (requireNamespace("torch", quietly = TRUE) &&
#'     isTRUE(torch::torch_is_installed())) {
#'   # Same 8 x 8 br_cerrado patches as foundation_finetune_ensemble().
#'   g <- 45L; p <- 8L
#'   cov4 <- lapply(br_cerrado[c("elev", "slope", "twi", "ndvi")],
#'                  function(v) matrix(scale(v)[, 1L], g, g))
#'   soc_m <- matrix(br_cerrado$soc, g, g)
#'   ij <- expand.grid(i = seq(1L, g - p + 1L, by = 6L),
#'                     j = seq(1L, g - p + 1L, by = 6L))
#'   x <- array(0, dim = c(nrow(ij), 4L, p, p))
#'   y <- numeric(nrow(ij))
#'   for (k in seq_len(nrow(ij))) {
#'     rr <- ij$i[k] + 0:(p - 1L); cc <- ij$j[k] + 0:(p - 1L)
#'     for (ch in 1:4) x[k, ch, , ] <- cov4[[ch]][rr, cc]
#'     y[k] <- mean(soc_m[rr, cc])
#'   }
#'   set.seed(2024)
#'   test  <- sample(nrow(ij), 12L)
#'   train <- setdiff(seq_len(nrow(ij)), test)
#'   enc <- foundation_moco_pretrain(
#'     x[train, , , , drop = FALSE], feature_dim = 16L, proj_dim = 8L,
#'     queue_size = 16L, batch_size = 8L, epochs = 5L, seed = 42L)
#'
#'   # Same warning as in foundation_finetune_ensemble(). `epochs`
#'   # counts optimiser steps, not passes over the data, so `enc` is
#'   # five gradient steps on batches of 8. Read its final InfoNCE loss
#'   # against log1p(queue_size), the loss of an encoder whose logits
#'   # are all equal -- one that cannot pick the positive key out of
#'   # its queue_size negatives. The trace is noise around that line
#'   # rather than a descent, and it moves with the ambient R seed:
#'   # `seed=` fixes only the torch RNG.
#'   print(round(enc$loss_history, 3))
#'   print(round(c(final_infonce    = enc$final_loss,
#'                 all_logits_equal = log1p(enc$queue_size),
#'                 patch_draws      = length(enc$loss_history) *
#'                                      enc$batch_size), 3))
#'
#'   # freeze_backbone defaults to TRUE, so the head below is fit on
#'   # that frozen, effectively random feature map. Read the rest as a
#'   # demonstration of the MC-DROPOUT MACHINERY -- what `seed`
#'   # controls, how the draws differ from predict(), and when the
#'   # "posterior" is secretly a point mass -- not as an uncertainty
#'   # statement about soil carbon.
#'
#'   # MC-dropout can only sample if the head carries a stochastic
#'   # layer: head = "mlp" with dropout > 0. See the trap below.
#'   fit <- foundation_fit_regressor(
#'     enc, x = x[train, , , , drop = FALSE], y = y[train],
#'     head = "mlp", hidden = 8L, dropout = 0.2,
#'     epochs = 20L, batch_size = 16L, lr = 0.01,
#'     device = "cpu", seed = 301L)
#'
#'   # n_draws = 20 is small for speed; a draw sd you report wants 100+.
#'   newx  <- x[test, , , , drop = FALSE]
#'   draws <- foundation_mcdropout_predict(fit, x = newx, n_draws = 20L,
#'                                         seed = 7L)
#'   print(dim(draws))
#'
#'   # The dropout masks are resampled on every call, so `seed` is what
#'   # makes a reported posterior reproducible.
#'   print(c(seeded_same = isTRUE(all.equal(
#'             draws, foundation_mcdropout_predict(fit, x = newx,
#'                                                 n_draws = 20L,
#'                                                 seed = 7L))),
#'           unseeded_differs = !isTRUE(all.equal(
#'             draws, foundation_mcdropout_predict(fit, x = newx,
#'                                                 n_draws = 20L)))))
#'
#'   # The MC mean is not predict(): predict() switches dropout off and
#'   # runs the whole head, while the draws average thinned copies.
#'   point <- as.numeric(predict(fit, x = newx))
#'   print(round(c(predict_1    = point[1L],
#'                 mc_mean_1    = colMeans(draws)[1L],
#'                 mean_abs_gap = mean(abs(point - colMeans(draws)))), 3))
#'
#'   # TRAP: with no dropout layer the "posterior" silently collapses
#'   # to a point. A linear head -- and equally head = "mlp" with
#'   # dropout = 0 -- still returns n_draws rows, but they are
#'   # identical and their sd is exactly 0.
#'   fit_lin <- foundation_fit_regressor(
#'     enc, x = x[train, , , , drop = FALSE], y = y[train],
#'     head = "linear", epochs = 20L, batch_size = 16L, lr = 0.01,
#'     device = "cpu", seed = 301L)
#'   print(max(apply(foundation_mcdropout_predict(fit_lin, x = newx,
#'                                                n_draws = 5L, seed = 7L),
#'                   2L, stats::sd)))
#'
#'   # What the spread does not contain: it is the variation of ONE
#'   # network's units, conditional on the single optimisation run that
#'   # produced `fit`. Refit under another seed and it moves. That
#'   # second source of variance is what foundation_finetune_ensemble()
#'   # covers instead -- the two are not estimates of the same thing.
#'   # This point does not depend on the backbone being any good: it is
#'   # a statement about which sources of variation each estimator
#'   # integrates over, and it would hold identically for an encoder
#'   # pretrained on a million patches.
#'   fit2 <- foundation_fit_regressor(
#'     enc, x = x[train, , , , drop = FALSE], y = y[train],
#'     head = "mlp", hidden = 8L, dropout = 0.2,
#'     epochs = 20L, batch_size = 16L, lr = 0.01,
#'     device = "cpu", seed = 302L)
#'   draws2 <- foundation_mcdropout_predict(fit2, x = newx,
#'                                          n_draws = 20L, seed = 7L)
#'   print(round(c(
#'     median_sd_seed301 = stats::median(apply(draws,  2L, stats::sd)),
#'     median_sd_seed302 = stats::median(apply(draws2, 2L, stats::sd))), 3))
#'
#'   # And neither route is calibrated by construction: score the band
#'   # before reporting it. Nominal coverage here is 0.95. Print the
#'   # mean half-width next to the RMSE the band would have to span.
#'   # The dropout masks are the only thing that varies across draws,
#'   # so the interval is centred on a point estimate whose own error
#'   # it cannot see. Read the three numbers together: the mean
#'   # half-width (1.53) is WIDER than the RMSE (1.29), and coverage is
#'   # still only 0.58 against a nominal 0.95. A wide interval that
#'   # under-covers is the signature of a centre that is off, not of a
#'   # spread that is too small -- widening it further would not fix
#'   # the problem, because MC-dropout never samples the bias of the
#'   # frozen backbone it sits on. At length(test) = 12, and on a
#'   # backbone this untrained, read the direction and not the digits.
#'   mu <- colMeans(draws); s <- apply(draws, 2L, stats::sd)
#'   print(round(c(
#'     picp = edaphos_picp(y[test], mu - 1.96 * s, mu + 1.96 * s),
#'     mean_half_width = mean(1.96 * s),
#'     rmse            = sqrt(mean((y[test] - point)^2)),
#'     interval_score = edaphos_interval_score(y[test], mu - 1.96 * s,
#'                                             mu + 1.96 * s)), 3))
#' }
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
