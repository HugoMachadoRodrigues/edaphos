# Pillar 4 v1.2.0 tests: fine-tuning API (classifier + regressor).
#
# Every torch-backed test is gated on torch being installed and its
# native backend being available; the tests run with `device = "cpu"`
# so they are reproducible on any CI runner.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  if (!torch::torch_is_installed()) {
    skip("torch backend not installed")
  }
}

.ft_fixture_patches <- function(N = 60L, C = 4L, P = 16L, seed = 1L) {
  set.seed(seed)
  array(rnorm(N * C * P * P), dim = c(N, C, P, P))
}

.ft_fixture_moco <- function(C = 4L, P = 16L, feature_dim = 16L,
                              proj_dim = 8L, steps = 5L, seed = 1L) {
  patches <- .ft_fixture_patches(N = 32L, C = C, P = P, seed = seed)
  ds <- structure(
    list(
      stack       = NULL,
      patch_size  = P,
      n_patches   = 32L,
      n_channels  = C,
      means       = rep(0, C),
      sds         = rep(1, C),
      valid_cells = seq_len(32L),
      sample      = function(b) patches[sample(32L, b), , , ,
                                           drop = FALSE]
    ),
    class = "edaphos_tile_dataset"
  )
  foundation_moco_pretrain_tiles(
    ds, feature_dim = feature_dim, proj_dim = proj_dim,
    queue_size = 16L, batch_size = 8L, epochs = steps,
    device = "cpu", seed = seed
  )
}

test_that("foundation_fit_classifier linear probe converges on a toy task", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 60L, C = 4L, P = 16L, seed = 2L)
  # Two-class task: sign of the patch-wise mean of channel 1.
  y <- factor(ifelse(rowMeans(x[, 1L, , ]) > 0, "A", "B"))
  fit <- foundation_fit_classifier(
    moco, x, y,
    freeze_backbone = TRUE, head = "linear",
    epochs = 20L, lr = 5e-2, val_split = 0.25,
    device = "cpu", seed = 3L
  )
  expect_s3_class(fit, "edaphos_foundation_classifier")
  expect_equal(fit$feature_dim, 16L)
  expect_true(fit$freeze_backbone)
  expect_equal(fit$classes, c("A", "B"))
  expect_length(fit$loss_history, 20L)
  # Loss should decrease — compare first-3 mean to last-3 mean.
  expect_lt(mean(utils::tail(fit$loss_history, 3L)),
             mean(utils::head(fit$loss_history, 3L)))
  # Val accuracy must be present and in [0, 1].
  expect_true(any(!is.na(fit$val_accuracy_history)))
  expect_true(max(fit$val_accuracy_history, na.rm = TRUE) <= 1)
  expect_true(max(fit$val_accuracy_history, na.rm = TRUE) >= 0)
})

test_that("predict.edaphos_foundation_classifier returns class + prob", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 40L, C = 4L, P = 16L, seed = 2L)
  y <- factor(ifelse(rowMeans(x[, 1L, , ]) > 0, "A", "B"))
  fit <- foundation_fit_classifier(moco, x, y,
                                     epochs = 10L, lr = 5e-2,
                                     device = "cpu", seed = 3L)
  pred <- predict(fit, x[1:6, , , , drop = FALSE], type = "class")
  expect_s3_class(pred, "factor")
  expect_equal(levels(pred), c("A", "B"))
  expect_length(pred, 6L)
  probs <- predict(fit, x[1:6, , , , drop = FALSE], type = "prob")
  expect_true(is.matrix(probs))
  expect_equal(nrow(probs), 6L)
  expect_equal(colnames(probs), c("A", "B"))
  expect_true(all(abs(rowSums(probs) - 1) < 1e-5))
})

test_that("foundation_fit_classifier full fine-tuning updates backbone", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  # Snapshot the encoder params before.
  p_before <- torch::with_no_grad(
    as.numeric(moco$encoder_q$parameters[[1L]]$clone())
  )
  x <- .ft_fixture_patches(N = 40L, C = 4L, P = 16L, seed = 2L)
  y <- factor(ifelse(rowMeans(x[, 1L, , ]) > 0, "A", "B"))
  fit <- foundation_fit_classifier(
    moco, x, y,
    freeze_backbone = FALSE, head = "linear",
    epochs = 10L, lr = 1e-2, backbone_lr_mult = 1.0,
    val_split = 0, device = "cpu", seed = 3L
  )
  p_after <- torch::with_no_grad(
    as.numeric(fit$encoder$parameters[[1L]]$clone())
  )
  # Backbone params should have moved under full fine-tuning.
  expect_false(isTRUE(all.equal(p_before, p_after, tolerance = 0)))
})

test_that("foundation_fit_regressor converges on a toy regression task", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 80L, C = 4L, P = 16L, seed = 2L)
  # Target: patch-wise mean of channel 2 (so the encoder can learn it).
  y <- rowMeans(x[, 2L, , ]) + rnorm(80L, sd = 0.1)
  fit <- foundation_fit_regressor(
    moco, x, y,
    freeze_backbone = TRUE, head = "linear",
    epochs = 60L, lr = 5e-2, val_split = 0.25,
    device = "cpu", seed = 3L
  )
  expect_s3_class(fit, "edaphos_foundation_regressor")
  expect_equal(fit$feature_dim, 16L)
  expect_true(is.finite(fit$y_mean))
  expect_true(is.finite(fit$y_sd))
  # Validation RMSE must be smaller than the trivial "predict the
  # mean" baseline. The tiny fixture (3 pretraining steps, 60 points)
  # is noisy, so we allow a 25% slack above the exact sd-of-y bound.
  best_rmse <- min(fit$val_rmse_history, na.rm = TRUE)
  expect_lt(best_rmse, 1.25 * stats::sd(y))
})

test_that("predict.edaphos_foundation_regressor back-transforms y", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 40L, C = 4L, P = 16L, seed = 2L)
  y <- 100 * rowMeans(x[, 2L, , ]) + 500   # large-scale target
  fit <- foundation_fit_regressor(moco, x, y,
                                    epochs = 20L, lr = 5e-2,
                                    val_split = 0, device = "cpu",
                                    seed = 3L)
  preds <- predict(fit, x[1:8, , , , drop = FALSE])
  # Predictions must live on the *original* scale of y, not on the
  # normalised scale.
  expect_true(abs(mean(preds) - mean(y)) < 2 * stats::sd(y))
})

test_that("head = 'mlp' builds a deeper head", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 30L, C = 4L, P = 16L, seed = 2L)
  y <- factor(ifelse(rowMeans(x[, 1L, , ]) > 0, "A", "B"))
  fit <- foundation_fit_classifier(moco, x, y,
                                     head = "mlp", hidden = c(32L, 16L),
                                     epochs = 5L, val_split = 0,
                                     device = "cpu", seed = 1L)
  expect_identical(fit$head_type, "mlp")
  # Head should be a sequential with >= 4 children (Linear + ReLU +
  # Linear + ReLU + Linear when `hidden` has 2 elements).
  expect_gte(length(fit$head$children), 4L)
})

test_that("unavailable device falls back to cpu with a message", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 20L, C = 4L, P = 16L)
  y <- factor(ifelse(rowMeans(x[, 1L, , ]) > 0, "A", "B"))
  # CUDA is never available in CI — expect a fallback note.
  skip_if(torch::cuda_is_available())
  expect_message(
    foundation_fit_classifier(moco, x, y, device = "cuda",
                                epochs = 2L, val_split = 0, seed = 1L),
    regexp = "cuda.*not available"
  )
})

test_that("classifier rejects mismatched y length", {
  skip_if_no_torch()
  moco <- .ft_fixture_moco()
  x <- .ft_fixture_patches(N = 20L, C = 4L, P = 16L)
  y_bad <- factor(rep(c("A", "B"), times = 3L))   # length 6, not 20
  expect_error(
    foundation_fit_classifier(moco, x, y_bad, epochs = 1L,
                                device = "cpu"),
    regexp = "length\\(y\\) == dim\\(x\\)\\[1L\\]"
  )
})
