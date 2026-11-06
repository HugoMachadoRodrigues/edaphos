## piml_neural_ode_predict() and temporal_convlstm_predict() are exported but
## were reached only through predict() methods, never called by name. Their
## help pages each make a checkable promise; these tests hold them to it.

test_that("piml_neural_ode_predict() reproduces $fitted on the training depths", {
  skip_if_no_torch()
  depths <- c(5, 15, 30, 50, 80)
  soc    <- c(22, 9, 16, 14, 11)
  fit <- piml_neural_ode_fit(depths, soc, hidden = c(8L, 8L), epochs = 20L,
                             n_steps = 2L, seed = 1L)
  # Same RK4 grid, same answer -- to the last bit, as documented.
  expect_equal(piml_neural_ode_predict(fit, depths), fit$fitted,
               tolerance = 1e-6)
  expect_identical(predict(fit, depths), piml_neural_ode_predict(fit, depths))
  expect_length(piml_neural_ode_predict(fit, c(1, 2, 3, 200)), 4L)
  expect_error(piml_neural_ode_predict(fit, -1))
  expect_error(piml_neural_ode_predict(list(), depths))
})

test_that("temporal_convlstm_predict(): return_sequence reads the same head", {
  skip_if_no_torch()
  cube <- temporal_synth_soc_cube(H = 6, W = 6, T_total = 4, seed = 42)
  tt   <- temporal_cube_to_tensor(cube)
  y4   <- array(tt$target[1, 4, , ], dim = c(1, 6, 6))
  fit  <- temporal_convlstm_fit(tt$sequence, y4, hidden_dims = 4L,
                                epochs = 10L, lr = 0.05, seed = 1L)

  p1 <- temporal_convlstm_predict(fit, tt$sequence)
  expect_equal(dim(p1), c(1L, 6L, 6L))
  # Deterministic: no dropout or noise at prediction time.
  expect_identical(p1, temporal_convlstm_predict(fit, tt$sequence))
  expect_identical(p1, predict(fit, tt$sequence))

  # return_sequence = TRUE is an override, not a second model: its last step
  # is bit-identical to the sequence-to-one output.
  ps <- temporal_convlstm_predict(fit, tt$sequence, return_sequence = TRUE)
  expect_equal(dim(ps), c(1L, 4L, 6L, 6L))
  expect_identical(ps[1, 4, , ], p1[1, , ])
})
