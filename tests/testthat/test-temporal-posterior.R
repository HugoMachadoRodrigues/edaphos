# v1.6.0-d -- Pillar 3 adapters to edaphos_posterior.

skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  has_torch <- isTRUE(tryCatch(torch::torch_is_installed(),
                                 error = function(e) FALSE))
  if (!has_torch) skip("libtorch backend unavailable")
}

.mini_cube_tensors <- function() {
  # Tiny synthetic 4D cube identical in shape to the v1.5.0 real-data
  # runner but small enough to train a 3-member ensemble in a couple
  # seconds.
  set.seed(1L)
  T_total <- 12L; H <- 4L; W <- 4L
  seq_arr <- array(stats::rnorm(1 * T_total * 2 * H * W),
                    dim = c(1L, T_total, 2L, H, W))
  tgt_arr <- array(stats::rnorm(1 * T_total * H * W),
                    dim = c(1L, T_total, H, W))
  T_past <- 8L
  list(
    past_seq    = seq_arr[, 1L:T_past, , , , drop = FALSE],
    past_target = tgt_arr[, 1L:T_past, , , drop = FALSE],
    future_seq  = seq_arr[, (T_past + 1L):T_total, , , , drop = FALSE],
    T_past  = T_past,
    T_total = T_total,
    H = H, W = W
  )
}

test_that("temporal_convlstm_ensemble_fit() trains K members and caches their losses", {
  skip_if_no_torch()
  d <- .mini_cube_tensors()
  ens <- temporal_convlstm_ensemble_fit(
    sequence = d$past_seq, target = d$past_target,
    hidden_dims = c(4L), kernel_size = 3L,
    return_sequence = TRUE,
    epochs = 10L, lr = 0.02,
    K_ens = 3L, base_seed = 201L, verbose = FALSE
  )
  expect_s3_class(ens, "edaphos_temporal_convlstm_ensemble")
  expect_equal(ens$K_ens, 3L)
  expect_length(ens$final_losses, 3L)
  expect_length(ens$loss_histories, 3L)
  # print()
  expect_output(print(ens), "edaphos_temporal_convlstm_ensemble")
})

test_that("temporal_convlstm_ensemble_rollout() returns (K, T_future, H, W)", {
  skip_if_no_torch()
  d <- .mini_cube_tensors()
  ens <- temporal_convlstm_ensemble_fit(
    sequence = d$past_seq, target = d$past_target,
    hidden_dims = c(4L), kernel_size = 3L,
    return_sequence = TRUE,
    epochs = 10L, lr = 0.02,
    K_ens = 3L, base_seed = 201L, verbose = FALSE
  )
  rolls <- temporal_convlstm_ensemble_rollout(
    ens, past_sequence = d$past_seq, future_drivers = d$future_seq
  )
  expect_equal(dim(rolls), c(3L, d$T_total - d$T_past, d$H, d$W))
})

test_that("as_edaphos_posterior.edaphos_temporal_convlstm_ensemble wraps the rollout", {
  skip_if_no_torch()
  d <- .mini_cube_tensors()
  ens <- temporal_convlstm_ensemble_fit(
    sequence = d$past_seq, target = d$past_target,
    hidden_dims = c(4L), kernel_size = 3L,
    return_sequence = TRUE,
    epochs = 10L, lr = 0.02,
    K_ens = 3L, base_seed = 201L, verbose = FALSE
  )
  post <- as_edaphos_posterior(
    ens,
    past_sequence  = d$past_seq,
    future_drivers = d$future_seq,
    units = "NDVI z-units"
  )
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(post$method, "ensemble")
  expect_equal(post$query_type, "map")
  expect_equal(dim(post$samples), c(3L, d$H, d$W))
})

test_that("as_edaphos_posterior on a temporal_kalman_update result wraps the analysis ensemble", {
  set.seed(1L)
  fc <- array(stats::rnorm(30 * 6 * 6), dim = c(30, 6, 6))
  out <- temporal_kalman_update(
    forecast_ensemble   = fc,
    obs_value           = c(0.3, -0.2, 0.5),
    obs_row             = c(2L, 4L, 5L),
    obs_col             = c(3L, 5L, 2L),
    obs_sd              = 0.1,
    localization_radius = 2,
    seed                = 1L
  )
  expect_s3_class(out, "edaphos_temporal_kalman")
  post <- as_edaphos_posterior(out, units = "NDVI z-units")
  expect_s3_class(post, "edaphos_posterior")
  expect_equal(dim(post$samples), c(30L, 6L, 6L))
  expect_equal(post$query_type, "map")
  expect_equal(post$metadata$n_obs, 3L)
})

test_that("4-D temporal_kalman_update wraps to map of the chosen slice", {
  set.seed(1L)
  fc <- array(stats::rnorm(20 * 5 * 5 * 3), dim = c(20, 5, 5, 3))
  out <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value         = 1.0,
    obs_row = 3L, obs_col = 3L, obs_sd = 0.1,
    time_step = 2L,
    seed = 1L
  )
  post <- as_edaphos_posterior(out, time_step = 2L)
  expect_equal(dim(post$samples), c(20L, 5L, 5L))
})

test_that("temporal_convlstm_mcdropout_predict() returns a draws array (dropout off -> constant draws)", {
  skip_if_no_torch()
  d <- .mini_cube_tensors()
  fit <- temporal_convlstm_fit(
    sequence = d$past_seq, target = d$past_target,
    hidden_dims = c(4L), kernel_size = 3L,
    return_sequence = TRUE,
    epochs = 10L, lr = 0.02, seed = 501L, verbose = FALSE
  )
  draws <- temporal_convlstm_mcdropout_predict(
    fit, sequence = d$past_seq, n_draws = 4L, seed = 1L,
    return_sequence = TRUE
  )
  # shape: (n_draws, batch, T, H, W)
  expect_equal(length(dim(draws)), 5L)
  expect_equal(dim(draws)[1L], 4L)
  expect_equal(dim(draws)[2L], 1L)     # batch
  expect_equal(dim(draws)[3L], d$T_past)
  expect_equal(dim(draws)[4L], d$H)
  expect_equal(dim(draws)[5L], d$W)
  # Without dropout_p > 0 all draws are identical.
  d1 <- draws[1L, , , , ]
  d2 <- draws[2L, , , , ]
  expect_lt(max(abs(d1 - d2)), 1e-6)
})
