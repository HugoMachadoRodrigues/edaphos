## Tests for Pilar 9 -- DDPM (v2.5.0).

.mk_soil_patches <- function(n = 8L, H = 6L, W = 6L, seed = 1L) {
  set.seed(seed)
  # Gaussian-smooth random fields
  patches <- array(0, dim = c(n, H, W))
  for (i in seq_len(n)) {
    a <- matrix(stats::rnorm(H * W), H, W)
    # Simple 3-point local averaging for spatial smoothness
    b <- a
    for (r in 2:(H - 1)) for (c in 2:(W - 1)) {
      b[r, c] <- mean(a[(r - 1):(r + 1), (c - 1):(c + 1)])
    }
    patches[i, , ] <- b
  }
  patches
}

test_that("dm_cosine_schedule: returns well-formed arrays", {
  sch <- dm_cosine_schedule(T = 20L)
  expect_equal(sch$T, 20L)
  expect_length(sch$alphas,   20L)
  expect_length(sch$betas,    20L)
  expect_length(sch$alphabar, 20L)
  expect_true(all(sch$alphas  > 0 & sch$alphas  <= 1))
  expect_true(all(sch$betas   >= 0 & sch$betas   <= 1))
  expect_true(all(sch$alphabar > 0 & sch$alphabar <= 1))
  # alphabar should be monotone decreasing
  expect_true(all(diff(sch$alphabar) <= 0))
})

test_that("dm_fit: produces a fitted object with the expected schema", {
  p <- .mk_soil_patches(n = 6L, H = 6L, W = 6L)
  fit <- dm_fit(p, T = 10L, epochs = 5L, hidden = 8L,
                  lr = 0.05, seed = 1L)
  expect_s3_class(fit, "edaphos_dm_fit")
  expect_equal(fit$H, 6L); expect_equal(fit$W, 6L)
  expect_equal(fit$n_patches, 6L)
  expect_true(length(fit$history) > 0L)
  expect_true(all(is.finite(fit$history)))
})

test_that("dm_sample: returns an array of the expected shape", {
  p <- .mk_soil_patches(n = 6L, H = 6L, W = 6L)
  fit <- dm_fit(p, T = 8L, epochs = 3L, hidden = 8L,
                  lr = 0.05, seed = 1L)
  out <- dm_sample(fit, n_samples = 4L, seed = 1L)
  expect_true(is.array(out))
  expect_equal(dim(out), c(4L, 6L, 6L))
  expect_true(all(is.finite(out)))
})

test_that("dm_fit: conditioning vector of correct dim is accepted", {
  p <- .mk_soil_patches(n = 8L, H = 4L, W = 4L)
  cond <- matrix(stats::rnorm(8 * 3), 8L, 3L)
  fit <- dm_fit(p, conditioning = cond,
                  T = 6L, epochs = 3L, hidden = 8L,
                  lr = 0.05, seed = 1L)
  expect_equal(fit$cond_dim, 3L)
  new_cond <- matrix(stats::rnorm(2 * 3), 2L, 3L)
  out <- dm_sample(fit, n_samples = 2L, conditioning = new_cond,
                     seed = 1L)
  expect_equal(dim(out), c(2L, 4L, 4L))
})

test_that("dm_fit: print method emits a readable header", {
  p <- .mk_soil_patches(n = 4L, H = 4L, W = 4L)
  fit <- dm_fit(p, T = 6L, epochs = 2L, hidden = 8L, seed = 1L)
  out <- utils::capture.output(print(fit))
  expect_true(any(grepl("edaphos_dm_fit", out)))
  expect_true(any(grepl("Pilar 9", out)))
  expect_true(any(grepl("DDPM|Denoising", out)))
})
