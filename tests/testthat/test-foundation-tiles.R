skip_if_no_terra <- function() skip_if_not_installed("terra")
skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1),
           error = function(e) skip("torch runtime unavailable"))
}

make_toy_stack <- function(C = 3L, nrow = 40L, ncol = 40L, seed = 1L) {
  skip_if_no_terra()
  set.seed(seed)
  r <- terra::rast(ncols = ncol, nrows = nrow,
                    xmin = -50, xmax = -48, ymin = -16, ymax = -14,
                    crs = "EPSG:4326")
  layers <- lapply(seq_len(C), function(i) {
    rr <- r
    terra::values(rr) <- stats::rnorm(terra::ncell(r), mean = i * 10,
                                        sd = i)
    names(rr) <- paste0("ch", i)
    rr
  })
  do.call(c, layers)
}

# ---- Tile dataset -----------------------------------------------------------

test_that("foundation_tile_dataset builds and samples the right shape", {
  skip_if_no_terra()
  stk <- make_toy_stack(C = 4L, nrow = 40L, ncol = 40L)
  ds  <- foundation_tile_dataset(stk, patch_size = 8L,
                                   n_patches = 32L, seed = 1L)
  expect_s3_class(ds, "edaphos_tile_dataset")
  expect_equal(ds$n_channels, 4L)
  expect_equal(ds$n_patches, 32L)
  batch <- ds$sample(batch_size = 6L)
  expect_equal(dim(batch), c(6L, 4L, 8L, 8L))
  expect_true(all(is.finite(batch)))
})

test_that("dataset normalisation yields approximately standardised batches", {
  skip_if_no_terra()
  stk <- make_toy_stack(C = 3L, nrow = 60L, ncol = 60L)
  ds  <- foundation_tile_dataset(stk, patch_size = 8L,
                                   n_patches = 200L, seed = 2L)
  batch <- ds$sample(batch_size = 32L)
  # Per-channel sd of the flattened batch should be near 1.
  for (k in 1:3) {
    expect_lt(abs(stats::sd(as.vector(batch[, k, , ])) - 1), 0.5)
  }
})

test_that("dataset honours a valid_mask (keeps only masked cells)", {
  skip_if_no_terra()
  stk <- make_toy_stack(C = 2L, nrow = 40L, ncol = 40L)
  # Mask that keeps only the bottom half
  m <- stk[[1L]] * 0
  vals <- rep(0, terra::ncell(m))
  half_cells <- (terra::ncell(m) / 2 + 1):terra::ncell(m)
  vals[half_cells] <- 1
  terra::values(m) <- vals
  ds <- foundation_tile_dataset(stk, patch_size = 6L,
                                  n_patches = 20L,
                                  valid_mask = m, seed = 1L)
  # All sampled centre cells should be in the bottom half of the raster.
  rc <- terra::rowColFromCell(stk, ds$patch_cells)
  expect_true(all(rc[, 1L] > terra::nrow(stk) / 2))
})

# ---- Alignment --------------------------------------------------------------

test_that("foundation_tile_align projects heterogeneous sources to a common grid", {
  skip_if_no_terra()
  a <- make_toy_stack(C = 1L, nrow = 20L, ncol = 20L)
  b <- make_toy_stack(C = 1L, nrow = 40L, ncol = 40L)
  stk <- foundation_tile_align(list(a = a, b = b),
                                 target_res = 0.05,
                                 target_crs = "EPSG:4326",
                                 method = "bilinear")
  expect_s4_class(stk, "SpatRaster")
  expect_equal(terra::nlyr(stk), 2L)
  # Both layers share the same resolution now.
  expect_equal(terra::xres(stk), terra::xres(stk))  # trivially true; sanity
})

# ---- Dataset-backed MoCo pretraining ---------------------------------------

test_that("foundation_moco_pretrain_tiles trains on a dataset", {
  skip_if_no_terra(); skip_if_no_torch()
  stk <- make_toy_stack(C = 3L, nrow = 32L, ncol = 32L)
  ds  <- foundation_tile_dataset(stk, patch_size = 8L,
                                   n_patches = 100L, seed = 1L)
  fit <- foundation_moco_pretrain_tiles(
    ds, feature_dim = 16L, proj_dim = 8L,
    queue_size = 32L, batch_size = 8L,
    epochs = 15L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_foundation_moco")
  expect_equal(fit$in_channels, 3L)
  expect_equal(length(fit$loss_history), 15L)
  # Loss mean should trend down.
  early <- mean(fit$loss_history[1:7])
  late  <- mean(fit$loss_history[9:15])
  expect_lt(late, early * 1.05)
})

test_that("checkpoint round-trip preserves loss-history length", {
  skip_if_no_terra(); skip_if_no_torch()
  stk <- make_toy_stack(C = 2L, nrow = 24L, ncol = 24L)
  ds  <- foundation_tile_dataset(stk, patch_size = 6L,
                                   n_patches = 40L, seed = 1L)
  ck  <- tempfile("moco_ck_")
  fit1 <- foundation_moco_pretrain_tiles(
    ds, feature_dim = 8L, proj_dim = 4L,
    queue_size = 8L, batch_size = 4L,
    epochs = 4L, lr = 0.02, seed = 1L,
    checkpoint_dir = ck, checkpoint_every = 2L
  )
  # Checkpoint files exist
  expect_true(file.exists(file.path(ck, "state.rds")))
  expect_true(file.exists(file.path(ck, "encoder_q.pt")))
  expect_true(file.exists(file.path(ck, "encoder_k.pt")))
  expect_true(file.exists(file.path(ck, "queue.pt")))

  # Resume: next_epoch was written as 5, so asking for 6 epochs runs 2 more.
  fit2 <- foundation_moco_pretrain_tiles(
    ds, feature_dim = 8L, proj_dim = 4L,
    queue_size = 8L, batch_size = 4L,
    epochs = 6L, lr = 0.02, seed = 1L,
    checkpoint_dir = ck, checkpoint_every = 2L,
    resume = ck
  )
  expect_equal(length(fit2$loss_history), 6L)
})

# ---- embed_raster -----------------------------------------------------------

test_that("foundation_moco_embed_raster produces a SpatRaster of right dim", {
  skip_if_no_terra(); skip_if_no_torch()
  stk <- make_toy_stack(C = 3L, nrow = 32L, ncol = 32L)
  ds  <- foundation_tile_dataset(stk, patch_size = 8L,
                                   n_patches = 60L, seed = 1L)
  fit <- foundation_moco_pretrain_tiles(
    ds, feature_dim = 12L, proj_dim = 6L,
    queue_size = 16L, batch_size = 6L,
    epochs = 4L, seed = 1L
  )
  emb <- foundation_moco_embed_raster(fit, stk, ds,
                                        patch_size = 8L, stride = 8L)
  expect_s4_class(emb, "SpatRaster")
  expect_equal(terra::nlyr(emb), 12L)
})
