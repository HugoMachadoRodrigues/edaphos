skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1),
           error = function(e) skip("torch runtime unavailable"))
}

make_patches <- function(N = 24L, C = 3L, H = 8L, W = 8L, seed = 1L) {
  set.seed(seed)
  arr <- array(0, dim = c(N, C, H, W))
  for (i in seq_len(N)) {
    offset <- stats::rnorm(C, 0, 2)
    for (c in seq_len(C)) {
      xg <- matrix(seq(-1, 1, length.out = W), H, W, byrow = TRUE)
      yg <- matrix(seq(-1, 1, length.out = H), H, W, byrow = FALSE)
      arr[i, c, , ] <- offset[c] + 0.5 * xg + 0.3 * yg +
                       matrix(stats::rnorm(H * W, 0, 0.1), H, W)
    }
  }
  arr
}

# ---- Augmentation primitives ---------------------------------------------

test_that("flip + rot90 augmentations preserve shape", {
  skip_if_no_torch()
  x <- torch::torch_randn(2L, 3L, 8L, 8L)
  expect_equal(as.integer(edaphos:::.moco_aug_flip(x, 1)$size()),
               c(2L, 3L, 8L, 8L))
  expect_equal(as.integer(edaphos:::.moco_aug_rot90(x, 1)$size()),
               c(2L, 3L, 8L, 8L))
})

test_that("crop-resize augmentation returns a same-shape tensor", {
  skip_if_no_torch()
  x <- torch::torch_randn(4L, 2L, 10L, 10L)
  out <- edaphos:::.moco_aug_crop_resize(x, crop_ratio = c(0.5, 0.9))
  expect_equal(as.integer(out$size()), c(4L, 2L, 10L, 10L))
})

test_that("channel-dropout actually zeros whole channels", {
  skip_if_no_torch()
  x <- torch::torch_ones(8L, 5L, 6L, 6L)
  set.seed(1)
  out <- edaphos:::.moco_aug_channel_drop(x, drop_prob = 1)  # drop all
  expect_lt(as.numeric(out$sum()$item()), 1e-6)
})

test_that("spatial cutout creates zero regions", {
  skip_if_no_torch()
  x <- torch::torch_ones(4L, 2L, 10L, 10L)
  set.seed(1)
  out <- edaphos:::.moco_aug_cutout(x, prob = 1, size_ratio = 0.5)
  # Total sum < original (zeros introduced)
  expect_lt(as.numeric(out$sum()$item()),
            as.numeric(x$sum()$item()))
})

test_that("additive noise shifts the tensor stochastically", {
  skip_if_no_torch()
  x <- torch::torch_zeros(3L, 2L, 6L, 6L)
  set.seed(1)
  out <- edaphos:::.moco_aug_noise(x, sd = 1)
  expect_gt(as.numeric(out$abs()$sum()$item()), 0)
})

# ---- End-to-end training -------------------------------------------------

test_that("foundation_moco_pretrain trains and returns the right object", {
  skip_if_no_torch()
  patches <- make_patches(N = 24L, C = 3L, H = 8L, W = 8L, seed = 1L)
  fit <- foundation_moco_pretrain(
    patches,
    feature_dim = 16L, proj_dim = 8L,
    queue_size  = 32L, batch_size = 8L,
    momentum    = 0.95,
    temperature = 0.1,
    epochs = 15L, lr = 0.02,
    seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_foundation_moco")
  expect_equal(fit$in_channels, 3L)
  expect_equal(fit$feature_dim, 16L)
  expect_equal(fit$proj_dim,    8L)
  # Queue is auto-clamped to at most (N - batch_size) so it can be
  # populated without overlapping the current batch.
  expect_true(fit$queue_size >= 2L)
  expect_true(fit$queue_size <= nrow(patches) - fit$batch_size)
  expect_equal(length(fit$loss_history), 15L)
  # Loss mean in the second half should be below the first half (net
  # downward trend even though contrastive loss is noisy).
  first  <- mean(fit$loss_history[1:7])
  second <- mean(fit$loss_history[8:15])
  expect_lt(second, first)
})

test_that("foundation_moco_embed returns a numeric matrix of the right shape", {
  skip_if_no_torch()
  patches <- make_patches(N = 12L, C = 2L, H = 8L, W = 8L, seed = 2L)
  fit <- foundation_moco_pretrain(patches,
                                   feature_dim = 12L, proj_dim = 6L,
                                   queue_size  = 16L, batch_size = 4L,
                                   epochs = 5L, seed = 1L)
  emb_bb <- foundation_moco_embed(fit, patches)
  emb_pj <- foundation_moco_embed(fit, patches, projection = TRUE)
  expect_equal(dim(emb_bb), c(12L, 12L))
  expect_equal(dim(emb_pj), c(12L, 6L))
  # Projection-head output is L2-normalised.
  norms <- sqrt(rowSums(emb_pj ^ 2))
  expect_true(all(abs(norms - 1) < 1e-3))
})

test_that("key encoder gradients are disabled (momentum-only update)", {
  skip_if_no_torch()
  patches <- make_patches(N = 8L, C = 2L, H = 6L, W = 6L, seed = 3L)
  fit <- foundation_moco_pretrain(patches,
                                   feature_dim = 8L, proj_dim = 4L,
                                   queue_size  = 8L, batch_size = 4L,
                                   epochs = 2L, seed = 1L)
  # Every parameter of the key encoder has requires_grad = FALSE.
  rg <- vapply(fit$encoder_k$parameters,
               function(p) as.logical(p$requires_grad), logical(1L))
  expect_true(all(!rg))
})

test_that("print.edaphos_foundation_moco does not error", {
  skip_if_no_torch()
  patches <- make_patches(N = 6L, C = 2L, H = 6L, W = 6L, seed = 4L)
  fit <- foundation_moco_pretrain(patches,
                                   feature_dim = 8L, proj_dim = 4L,
                                   queue_size  = 8L, batch_size = 3L,
                                   epochs = 2L, seed = 1L)
  expect_output(print(fit), "MoCo v2")
})
