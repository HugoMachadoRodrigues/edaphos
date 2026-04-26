## Tests for the v2.7.0 torch backend of Pilar 9 (DDPM U-Net).

.mk_torch_patches <- function(n = 6L, H = 8L, W = 8L, seed = 1L) {
  set.seed(seed)
  stack <- array(stats::rnorm(n * H * W), dim = c(n, H, W))
  # Add some spatial smoothness by 3x3 averaging (once)
  for (i in seq_len(n)) {
    m <- stack[i, , ]
    for (r in 2:(H - 1)) for (c in 2:(W - 1)) {
      m[r, c] <- mean(stack[i, (r - 1):(r + 1), (c - 1):(c + 1)])
    }
    stack[i, , ] <- m
  }
  stack
}

test_that("dm_fit(backend='torch'): fits U-Net and returns valid schema", {
  .skip_if_no_torch()
  stack <- .mk_torch_patches(n = 4L, H = 8L, W = 8L)
  fit <- dm_fit(stack, T = 10L, epochs = 3L, hidden = 8L,
                  lr = 0.01, seed = 1L,
                  backend = "torch", device = "cpu")
  expect_s3_class(fit, "edaphos_dm_fit")
  expect_equal(fit$backend, "torch")
  expect_equal(fit$H, 8L); expect_equal(fit$W, 8L)
  expect_true(length(fit$history) > 0L)
  expect_true(all(is.finite(fit$history)))
})

test_that("dm_sample(backend='torch'): returns the expected shape", {
  .skip_if_no_torch()
  stack <- .mk_torch_patches(n = 4L, H = 8L, W = 8L)
  fit <- dm_fit(stack, T = 6L, epochs = 2L, hidden = 8L,
                  lr = 0.01, seed = 1L, backend = "torch")
  out <- dm_sample(fit, n_samples = 2L, seed = 1L)
  expect_equal(dim(out), c(2L, 8L, 8L))
  expect_true(all(is.finite(out)))
})

test_that("torch DDPM: conditioning vector is accepted end-to-end", {
  .skip_if_no_torch()
  stack <- .mk_torch_patches(n = 4L, H = 8L, W = 8L)
  cond <- matrix(stats::rnorm(4 * 3), 4L, 3L)
  fit <- dm_fit(stack, conditioning = cond,
                  T = 6L, epochs = 2L, hidden = 8L,
                  lr = 0.01, seed = 1L, backend = "torch")
  expect_equal(fit$cond_dim, 3L)
  out <- dm_sample(fit, n_samples = 2L,
                     conditioning = matrix(stats::rnorm(6), 2L, 3L),
                     seed = 1L)
  expect_equal(dim(out), c(2L, 8L, 8L))
})
