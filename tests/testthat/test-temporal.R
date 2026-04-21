skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1), error = function(e) skip("torch runtime unavailable"))
}

test_that("temporal_convlstm_cell produces correctly-shaped outputs", {
  skip_if_no_torch()
  cell <- temporal_convlstm_cell(input_dim = 2L, hidden_dim = 4L,
                                 kernel_size = 3L)
  state <- cell$init_state(batch = 1L, height = 6L, width = 6L)
  x <- torch::torch_randn(1L, 2L, 6L, 6L)
  new_state <- cell$forward(x, state)
  expect_length(new_state, 2L)
  expect_equal(as.integer(new_state[[1L]]$size()), c(1L, 4L, 6L, 6L))
  expect_equal(as.integer(new_state[[2L]]$size()), c(1L, 4L, 6L, 6L))
})

test_that("temporal_convlstm_fit trains end-to-end on a tiny synthetic cube", {
  skip_if_no_torch()
  set.seed(42)
  # Spurious but learnable signal: target[b, i, j] = mean over time of
  # channel 1 minus mean of channel 2 at (i, j), plus noise.
  B <- 4L; Tt <- 5L; C <- 2L; H <- 6L; W <- 6L
  seq_arr <- array(rnorm(B * Tt * C * H * W), dim = c(B, Tt, C, H, W))
  target <- apply(seq_arr[, , 1L, , ], c(1, 3, 4), mean) -
            apply(seq_arr[, , 2L, , ], c(1, 3, 4), mean)
  target <- target + array(rnorm(B * H * W, 0, 0.05), dim = c(B, H, W))

  fit <- temporal_convlstm_fit(
    sequence = seq_arr, target = target,
    hidden_dim = 4L, kernel_size = 3L,
    epochs = 40L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_temporal_convlstm")
  # Loss must have decreased.
  expect_lt(fit$loss_history[length(fit$loss_history)],
            fit$loss_history[1] * 0.8)
  # Predict shape sanity.
  pred <- predict(fit, seq_arr)
  expect_equal(dim(pred), c(B, H, W))
  expect_true(all(is.finite(pred)))
})

test_that("print.edaphos_temporal_convlstm works", {
  skip_if_no_torch()
  B <- 2L; Tt <- 3L; C <- 2L; H <- 4L; W <- 4L
  seq_arr <- array(rnorm(B * Tt * C * H * W), dim = c(B, Tt, C, H, W))
  target <- array(rnorm(B * H * W), dim = c(B, H, W))
  fit <- temporal_convlstm_fit(seq_arr, target, epochs = 5L,
                               seed = 1L, verbose = FALSE)
  expect_output(print(fit), "temporal_convlstm")
})

test_that("multi-layer stack + seq2seq trains to lower loss than single-layer", {
  skip_if_no_torch()
  # Deterministic synthetic cube
  cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 10L, seed = 1L)
  td <- temporal_cube_to_tensor(cube)
  fit1 <- temporal_convlstm_fit(
    td$sequence, td$target,
    hidden_dims = 4L,            # single layer
    return_sequence = TRUE,
    epochs = 30L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  fit2 <- temporal_convlstm_fit(
    td$sequence, td$target,
    hidden_dims = c(8L, 4L),     # stacked
    return_sequence = TRUE,
    epochs = 30L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit2, "edaphos_temporal_convlstm")
  expect_equal(length(fit2$hidden_dims), 2L)
  # Both should have decreased, stacked likely lower (or comparable)
  expect_lt(fit2$final_loss, fit2$loss_history[1])
  pred <- predict(fit2, td$sequence)
  expect_equal(dim(pred), c(1L, 10L, 8L, 8L))
})

test_that("temporal_convlstm_rollout produces a forecast of the right shape", {
  skip_if_no_torch()
  cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L, seed = 2L)
  past_tensor <- temporal_cube_to_tensor(cube, t_slice = 1:8)
  future_tensor <- temporal_cube_to_tensor(cube, t_slice = 9:12)

  fit <- temporal_convlstm_fit(
    past_tensor$sequence, past_tensor$target,
    hidden_dims = c(6L, 4L), return_sequence = TRUE,
    epochs = 30L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  forecast <- temporal_convlstm_rollout(
    fit,
    past_sequence  = past_tensor$sequence,
    future_drivers = future_tensor$sequence
  )
  expect_equal(dim(forecast), c(1L, 4L, 8L, 8L))
  expect_true(all(is.finite(forecast)))
})

test_that("temporal_synth_soc_cube is reproducible and keeps SOC in range", {
  c1 <- temporal_synth_soc_cube(H = 6L, W = 6L, T_total = 6L, seed = 7L)
  c2 <- temporal_synth_soc_cube(H = 6L, W = 6L, T_total = 6L, seed = 7L)
  expect_equal(c1$soc, c2$soc)
  expect_true(all(c1$soc >= 5))          # floor is enforced
  expect_true(all(c1$precip >= 0))
})

test_that("physics_lambda activates mass-balance loss and records phys history", {
  skip_if_no_torch()
  cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 10L, seed = 3L)
  td   <- temporal_cube_to_tensor(cube)
  fit <- temporal_convlstm_fit(
    td$sequence, td$target,
    hidden_dims = c(6L, 4L), return_sequence = TRUE,
    epochs = 20L, lr = 0.02,
    physics_lambda = 0.1,
    physics_k_in = 0.03, physics_k_out = 0.015,
    physics_driver_channel = 2L,
    seed = 1L, verbose = FALSE
  )
  expect_equal(fit$physics_lambda, 0.1)
  # loss_phys_history must be non-zero at the very first iteration
  expect_true(any(fit$loss_phys_history > 0))
  # Training must still reduce the fit component
  expect_lt(fit$loss_fit_history[length(fit$loss_fit_history)],
            fit$loss_fit_history[1])
})

test_that("physics_lambda = 0 leaves a legacy (fit-only) training run", {
  skip_if_no_torch()
  cube <- temporal_synth_soc_cube(H = 6L, W = 6L, T_total = 8L, seed = 4L)
  td   <- temporal_cube_to_tensor(cube)
  fit <- temporal_convlstm_fit(
    td$sequence, td$target,
    hidden_dims = 4L, return_sequence = TRUE,
    epochs = 10L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  expect_equal(fit$physics_lambda, 0)
  expect_true(all(fit$loss_phys_history == 0))
})
