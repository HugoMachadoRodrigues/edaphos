skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1), error = function(e) skip("torch runtime unavailable"))
}

make_patches <- function(N = 12L, C = 3L, H = 8L, W = 8L, seed = 1L) {
  set.seed(seed)
  # Make patches distinguishable: a spatial gradient + a random offset per
  # patch, so SimCLR has real structure to learn.
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

test_that("foundation_simclr_pretrain trains end-to-end and drops loss", {
  skip_if_no_torch()
  patches <- make_patches(N = 16L, C = 3L, H = 8L, W = 8L, seed = 7L)
  fit <- foundation_simclr_pretrain(
    patches, feature_dim = 16L, proj_dim = 8L,
    batch_size = 8L, epochs = 30L, lr = 0.01,
    seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_foundation_simclr")
  expect_lt(fit$final_loss, fit$loss_history[1])
})

test_that("foundation_simclr_embed returns correctly-shaped matrices", {
  skip_if_no_torch()
  patches <- make_patches(N = 10L, C = 2L, H = 6L, W = 6L, seed = 3L)
  fit <- foundation_simclr_pretrain(
    patches, feature_dim = 12L, proj_dim = 6L,
    batch_size = 4L, epochs = 10L, seed = 1L
  )
  emb <- foundation_simclr_embed(fit, patches)
  expect_equal(dim(emb), c(10L, 12L))
  proj <- foundation_simclr_embed(fit, patches, projection = TRUE)
  expect_equal(dim(proj), c(10L, 6L))
})

test_that("print.edaphos_foundation_simclr works", {
  skip_if_no_torch()
  patches <- make_patches(N = 6L, C = 2L, H = 6L, W = 6L, seed = 2L)
  fit <- foundation_simclr_pretrain(patches, epochs = 3L,
                                     batch_size = 4L, seed = 1L)
  expect_output(print(fit), "foundation_simclr")
})
