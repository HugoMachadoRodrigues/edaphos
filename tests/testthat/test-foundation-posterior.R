# v1.6.0-e -- Pillar 4 ensemble + MC-dropout adapter tests.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  if (!torch::torch_is_installed()) skip("torch backend not installed")
}

.ft_fixture_patches <- function(N = 32L, C = 4L, P = 8L, seed = 1L) {
  set.seed(seed)
  array(stats::rnorm(N * C * P * P), dim = c(N, C, P, P))
}

.ft_mock_encoder <- function(C = 4L, P = 8L, feature_dim = 8L) {
  # Tiny mock MoCo encoder; its forward path is irrelevant to these
  # tests (we only exercise the head ensemble + predict pipeline).
  patches <- .ft_fixture_patches(N = 32L, C = C, P = P)
  ds <- structure(
    list(stack = NULL, patch_size = P, n_patches = 32L,
          n_channels = C, means = rep(0, C), sds = rep(1, C),
          valid_cells = seq_len(32L),
          sample = function(b) patches[sample(32L, b), , , , drop = FALSE]),
    class = "edaphos_tile_dataset"
  )
  foundation_moco_pretrain_tiles(
    ds, feature_dim = feature_dim, proj_dim = 4L,
    queue_size = 16L, batch_size = 8L, epochs = 3L,
    device = "cpu", seed = 1L
  )
}

test_that("foundation_finetune_ensemble() fits K regressor heads", {
  skip_if_no_torch()
  enc <- .ft_mock_encoder()
  x   <- .ft_fixture_patches(N = 40L, C = 4L, P = 8L, seed = 2L)
  y   <- stats::rnorm(40L)
  ens <- foundation_finetune_ensemble(
    enc, x = x, y = y, task = "regression",
    K_ens = 3L, base_seed = 301L,
    epochs = 2L, batch_size = 8L, hidden = c(8L),
    dropout = 0.2, device = "cpu"
  )
  expect_s3_class(ens, "edaphos_foundation_ensemble")
  expect_equal(ens$K_ens, 3L)
  expect_equal(ens$task, "regression")
  expect_length(ens$final_losses, 3L)
})

test_that("predict() on the ensemble returns (K, N) for regression", {
  skip_if_no_torch()
  enc <- .ft_mock_encoder()
  x   <- .ft_fixture_patches(N = 40L, C = 4L, P = 8L, seed = 2L)
  y   <- stats::rnorm(40L)
  ens <- foundation_finetune_ensemble(
    enc, x = x, y = y, task = "regression",
    K_ens = 3L, base_seed = 301L,
    epochs = 2L, batch_size = 8L, device = "cpu"
  )
  newx  <- .ft_fixture_patches(N = 10L, C = 4L, P = 8L, seed = 10L)
  preds <- stats::predict(ens, x = newx)
  expect_equal(dim(preds), c(3L, 10L))
})

test_that("as_edaphos_posterior.edaphos_foundation_ensemble wraps regression output", {
  skip_if_no_torch()
  enc <- .ft_mock_encoder()
  x   <- .ft_fixture_patches(N = 40L, C = 4L, P = 8L, seed = 2L)
  y   <- stats::rnorm(40L)
  ens <- foundation_finetune_ensemble(
    enc, x = x, y = y, task = "regression",
    K_ens = 3L, base_seed = 301L,
    epochs = 2L, batch_size = 8L, device = "cpu"
  )
  newx <- .ft_fixture_patches(N = 10L, C = 4L, P = 8L, seed = 10L)
  post <- as_edaphos_posterior(ens, newx = newx, units = "y-units")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$query_type, "sample")
  expect_equal(dim(post$samples), c(3L, 10L))
})

test_that("foundation_mcdropout_predict() returns (n_draws, N) for regression", {
  skip_if_no_torch()
  enc <- .ft_mock_encoder()
  x   <- .ft_fixture_patches(N = 40L, C = 4L, P = 8L, seed = 2L)
  y   <- stats::rnorm(40L)
  fit <- foundation_fit_regressor(
    enc, x = x, y = y,
    head = "mlp", hidden = c(8L), dropout = 0.3,
    epochs = 2L, batch_size = 8L, device = "cpu", seed = 1L
  )
  newx <- .ft_fixture_patches(N = 10L, C = 4L, P = 8L, seed = 10L)
  draws <- foundation_mcdropout_predict(fit, x = newx, n_draws = 5L,
                                           seed = 1L)
  expect_equal(dim(draws), c(5L, 10L))
  # With dropout = 0.3, the MC draws should be non-degenerate.
  sdcol <- apply(draws, 2L, stats::sd)
  expect_gt(max(sdcol), 1e-6)
})

test_that("as_edaphos_posterior requires newx", {
  skip_if_no_torch()
  enc <- .ft_mock_encoder()
  x   <- .ft_fixture_patches(N = 20L, C = 4L, P = 8L, seed = 2L)
  y   <- stats::rnorm(20L)
  ens <- foundation_finetune_ensemble(
    enc, x = x, y = y, task = "regression",
    K_ens = 2L, base_seed = 1L,
    epochs = 1L, batch_size = 8L, device = "cpu"
  )
  expect_error(as_edaphos_posterior(ens), regexp = "newx")
})
