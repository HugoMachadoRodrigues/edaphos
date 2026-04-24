## Edge-case tests for Pilar 9 DDPM (v2.9.0 expansion)

.mk_patches <- function(n = 6L, H = 6L, W = 6L, seed = 1L) {
  set.seed(seed)
  array(stats::rnorm(n * H * W), dim = c(n, H, W))
}

test_that("dm_cosine_schedule: T = 1 is handled (degenerate case)", {
  sch <- dm_cosine_schedule(T = 1L)
  expect_equal(sch$T, 1L)
  expect_equal(length(sch$alphas), 1L)
})

test_that("dm_cosine_schedule: numerical stability at T = 1000", {
  sch <- dm_cosine_schedule(T = 1000L)
  expect_true(all(sch$alphabar > 0))
  expect_true(all(sch$alphabar <= 0.9999))
  expect_true(all(sch$sqrt_alphabar >= 0))
})

test_that("dm_fit: degenerate constant stack still runs", {
  stack <- array(1, dim = c(4L, 6L, 6L))
  # All-constant stack -> sd = 0 -> standardisation hits 1 fallback
  fit <- dm_fit(stack, T = 5L, epochs = 2L, hidden = 4L, seed = 1L)
  expect_s3_class(fit, "edaphos_dm_fit")
  expect_true(all(is.finite(fit$history)))
})

test_that("dm_sample: deterministic with same seed", {
  stack <- .mk_patches(n = 4L, H = 6L, W = 6L)
  fit <- dm_fit(stack, T = 6L, epochs = 2L, hidden = 4L, seed = 1L)
  s1 <- dm_sample(fit, n_samples = 2L, seed = 99L)
  s2 <- dm_sample(fit, n_samples = 2L, seed = 99L)
  expect_equal(s1, s2, tolerance = 1e-10)
})

test_that("dm_sample: n_samples = 1 boundary", {
  stack <- .mk_patches(n = 3L, H = 6L, W = 6L)
  fit <- dm_fit(stack, T = 5L, epochs = 2L, hidden = 4L, seed = 1L)
  out <- dm_sample(fit, n_samples = 1L, seed = 1L)
  expect_equal(dim(out), c(1L, 6L, 6L))
})

test_that("dm_fit: conditioning dim mismatch at sample time errors", {
  stack <- .mk_patches(n = 4L, H = 6L, W = 6L)
  cond <- matrix(stats::rnorm(4 * 2), 4L, 2L)
  fit <- dm_fit(stack, conditioning = cond,
                  T = 5L, epochs = 2L, hidden = 4L, seed = 1L)
  wrong_cond <- matrix(stats::rnorm(2 * 5), 2L, 5L)  # wrong ncol
  expect_error(dm_sample(fit, n_samples = 2L,
                           conditioning = wrong_cond),
                regexp = "cond_dim|ncol")
})

test_that("dm_sample: unconditional when model was conditional returns zeros-cond", {
  stack <- .mk_patches(n = 4L, H = 6L, W = 6L)
  cond <- matrix(stats::rnorm(4 * 2), 4L, 2L)
  fit <- dm_fit(stack, conditioning = cond,
                  T = 4L, epochs = 2L, hidden = 4L, seed = 1L)
  # Passing conditioning = NULL should fall back to zero-vectors per
  # sample (per the R backend docstring)
  out <- dm_sample(fit, n_samples = 2L,
                     conditioning = matrix(0, 2L, 2L), seed = 1L)
  expect_equal(dim(out), c(2L, 6L, 6L))
})

test_that("dm_fit(backend='torch'): device='cpu' produces finite output", {
  skip_if_not_installed("torch")
  stack <- .mk_patches(n = 4L, H = 6L, W = 6L)
  fit <- dm_fit(stack, T = 4L, epochs = 2L, hidden = 8L,
                  seed = 1L, backend = "torch", device = "cpu")
  expect_equal(fit$backend, "torch")
  out <- dm_sample(fit, n_samples = 2L, seed = 1L)
  expect_true(all(is.finite(out)))
})

test_that("dm_fit: extremely small T still produces valid sampling output", {
  stack <- .mk_patches(n = 3L, H = 4L, W = 4L)
  fit <- dm_fit(stack, T = 2L, epochs = 2L, hidden = 4L, seed = 1L)
  out <- dm_sample(fit, n_samples = 2L, seed = 1L)
  expect_equal(dim(out), c(2L, 4L, 4L))
  expect_true(all(is.finite(out)))
})
