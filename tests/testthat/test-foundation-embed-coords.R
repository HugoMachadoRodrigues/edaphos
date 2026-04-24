## Tests for foundation_embed_at_coords (v1.9.1).

test_that("foundation_embed_at_coords: patch extraction + encoder forward", {
  skip_if_not_installed("torch")
  skip_if_not_installed("terra")
  suppressMessages({
    library(torch); library(terra)
  })

  # Fake encoder: a tiny linear layer over flattened patches
  fake_moco <- function(C = 5L, feat = 8L, proj = 4L, patch = 16L) {
    blk <- torch::nn_module(
      initialize = function() {
        self$lin <- torch::nn_linear(C * patch * patch, feat)
      },
      forward = function(x) self$lin(torch::torch_flatten(x, start_dim = 2L)),
      backbone_features = function(x) {
        self$lin(torch::torch_flatten(x, start_dim = 2L))
      }
    )
    structure(list(
      encoder_q = blk(),
      feature_dim = feat, proj_dim = proj,
      patch_size = patch, n_channels = C
    ), class = "edaphos_foundation_moco")
  }
  moco <- fake_moco(C = 5L, feat = 8L, patch = 16L)

  # Small synthetic raster stack
  set.seed(1L)
  stk <- terra::rast(
    xmin = -50, xmax = -48, ymin = -16, ymax = -14,
    crs = "EPSG:4326", resolution = 0.02,
    nlyrs = moco$n_channels
  )
  for (k in seq_len(moco$n_channels))
    terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))

  coords <- data.frame(
    lon = stats::runif(10, -49.5, -48.5),
    lat = stats::runif(10, -15.5, -14.5)
  )
  dataset <- list(
    patch_size = 16L, n_channels = moco$n_channels,
    means = rep(0, moco$n_channels), sds = rep(1, moco$n_channels)
  )
  emb <- foundation_embed_at_coords(moco, coords, stk, dataset,
                                       patch_size = 16L, batch_size = 4L)
  expect_true(is.matrix(emb))
  expect_equal(nrow(emb), 10L)
  expect_equal(ncol(emb), 8L)
  # All coords are inside the raster with margin >= half, so all valid
  expect_equal(sum(stats::complete.cases(emb)), 10L)
})

test_that("foundation_embed_at_coords: out-of-extent coords produce NA rows", {
  skip_if_not_installed("torch")
  skip_if_not_installed("terra")
  suppressMessages({ library(torch); library(terra) })

  moco <- local({
    blk <- torch::nn_module(
      initialize = function() {
        self$lin <- torch::nn_linear(3L * 16L * 16L, 4L)
      },
      backbone_features = function(x) {
        self$lin(torch::torch_flatten(x, start_dim = 2L))
      },
      forward = function(x) self$backbone_features(x)
    )
    structure(list(
      encoder_q = blk(), feature_dim = 4L, proj_dim = 2L,
      patch_size = 16L, n_channels = 3L
    ), class = "edaphos_foundation_moco")
  })
  stk <- terra::rast(xmin = -50, xmax = -48, ymin = -16, ymax = -14,
                      crs = "EPSG:4326", resolution = 0.05, nlyrs = 3L)
  for (k in 1:3) terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))
  # Include a coord FAR outside the extent
  coords <- data.frame(
    lon = c(-49, 10),     # second is outside
    lat = c(-15, 50)
  )
  dataset <- list(patch_size = 16L, n_channels = 3L,
                   means = rep(0, 3), sds = rep(1, 3))
  emb <- foundation_embed_at_coords(moco, coords, stk, dataset,
                                       patch_size = 16L, batch_size = 2L)
  expect_equal(nrow(emb), 2L)
  # First row valid, second row all-NA
  expect_false(any(is.na(emb[1, ])))
  expect_true(all(is.na(emb[2, ])))
})

test_that("foundation_embed_at_coords: patch_size = NULL falls back to dataset", {
  skip_if_not_installed("torch")
  skip_if_not_installed("terra")
  suppressMessages({ library(torch); library(terra) })

  moco <- local({
    blk <- torch::nn_module(
      initialize = function() {
        self$lin <- torch::nn_linear(2L * 8L * 8L, 4L)
      },
      backbone_features = function(x) {
        self$lin(torch::torch_flatten(x, start_dim = 2L))
      },
      forward = function(x) self$backbone_features(x)
    )
    structure(list(
      encoder_q = blk(), feature_dim = 4L, proj_dim = 2L,
      patch_size = 8L, n_channels = 2L
    ), class = "edaphos_foundation_moco")
  })
  stk <- terra::rast(xmin = -50, xmax = -48, ymin = -16, ymax = -14,
                      crs = "EPSG:4326", resolution = 0.02, nlyrs = 2L)
  for (k in 1:2) terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))

  dataset <- list(patch_size = 8L, n_channels = 2L,
                   means = c(0, 0), sds = c(1, 1))
  emb <- foundation_embed_at_coords(
    moco, data.frame(lon = -49, lat = -15), stk, dataset,
    patch_size = NULL, batch_size = 1L
  )
  expect_equal(ncol(emb), 4L)
  expect_false(all(is.na(emb)))
})

test_that("foundation_embed_at_coords: errors on NULL patch_size without dataset fallback", {
  skip_if_not_installed("torch")
  skip_if_not_installed("terra")
  suppressMessages({ library(torch); library(terra) })

  moco <- local({
    blk <- torch::nn_module(
      initialize = function() {
        self$lin <- torch::nn_linear(2L * 8L * 8L, 4L)
      },
      backbone_features = function(x) {
        self$lin(torch::torch_flatten(x, start_dim = 2L))
      },
      forward = function(x) self$backbone_features(x)
    )
    structure(list(
      encoder_q = blk(), feature_dim = 4L, proj_dim = 2L,
      patch_size = 8L, n_channels = 2L
    ), class = "edaphos_foundation_moco")
  })
  stk <- terra::rast(xmin = -50, xmax = -48, ymin = -16, ymax = -14,
                      crs = "EPSG:4326", resolution = 0.02, nlyrs = 2L)
  for (k in 1:2) terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))
  dataset_bad <- list(patch_size = NULL, n_channels = 2L,
                        means = c(0, 0), sds = c(1, 1))
  expect_error(
    foundation_embed_at_coords(
      moco, data.frame(lon = -49, lat = -15), stk, dataset_bad,
      patch_size = NULL
    ),
    regexp = "patch_size"
  )
})
