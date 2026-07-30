## Regressions for two Pilar 9 defects, both of which made ancestral
## sampling diverge while the training loss looked healthy.  The loss is
## computed on the forward process only, so neither was visible from it.
##
##  (a) dm_cosine_schedule() did not clip beta_t.  Nichol and Dhariwal
##      (2021, sec. 3.2) clip at 0.999 "to prevent singularities near
##      t = T"; without it alpha_T reaches ~1e-5 and the reverse step
##      multiplies the iterate by 1/sqrt(alpha_T) ~ 150 in one step.
##  (b) dm_sample() used the compact reverse step with no x_0 clipping.
##      Ho et al. (2020, sec. 3.3) clip x_0 to the data range and
##      rebuild the posterior mean from it; without that, an imperfect
##      denoiser (the pure-R backend trains a readout over frozen
##      random features) has its error amplified every step.
##
## On the v4.0.0 code the two together produced samples at ~1e4 times
## the scale of the standardised training data.

.mk_field_patches <- function(n = 40L, P = 8L, seed = 3L) {
  set.seed(seed)
  # Smooth random fields: 3-point local averaging over white noise.
  a <- array(stats::rnorm(n * (P + 4L) * (P + 4L)), c(n, P + 4L, P + 4L))
  out <- array(0, dim = c(n, P, P))
  for (i in seq_len(n)) {
    m <- a[i, , ]
    for (pass in 1:2) {
      s <- m
      for (r in 2:(nrow(m) - 1L)) for (cc in 2:(ncol(m) - 1L))
        s[r, cc] <- mean(m[(r - 1):(r + 1), (cc - 1):(cc + 1)])
      m <- s
    }
    out[i, , ] <- m[3:(P + 2L), 3:(P + 2L)]
  }
  (out - mean(out)) / stats::sd(out)
}

test_that("dm_cosine_schedule clips beta and stays self-consistent", {
  for (Tt in c(20L, 100L, 400L)) {
    s <- dm_cosine_schedule(T = Tt)

    expect_lte(max(s$betas), 0.999 + 1e-12)
    expect_gte(min(s$alphas), 1 - 0.999 - 1e-12)

    # alphas and betas must be complements of each other ...
    expect_equal(s$alphas + s$betas, rep(1, Tt), tolerance = 1e-12)
    # ... and alphabar must be their running product, or the reverse
    # step is algebraically invalid.
    expect_equal(s$alphabar, cumprod(s$alphas), tolerance = 1e-12)

    expect_equal(s$sqrt_alphabar, sqrt(s$alphabar), tolerance = 1e-12)
    expect_equal(s$sqrt_one_minus_alphabar, sqrt(1 - s$alphabar),
                 tolerance = 1e-12)
    expect_true(all(diff(s$alphabar) <= 0))
  }
})

test_that("the unclipped schedule would have produced a singular final step", {
  # Reconstruct the pre-fix schedule to show the clip is load-bearing:
  # without it 1/sqrt(alpha_T) is a three-figure amplification.
  Tt <- 100L
  t  <- seq(0, Tt)
  f  <- cos((t / Tt + 0.008) / 1.008 * pi / 2)^2
  ab <- pmax(pmin(f / f[1], 0.9999), 1e-8)
  raw_alphas <- ab[-1] / ab[-(Tt + 1)]

  expect_gt(1 / sqrt(min(raw_alphas)), 100)          # the singularity
  expect_lt(1 / sqrt(min(dm_cosine_schedule(T = Tt)$alphas)), 35)
})

test_that("dm_sample stays on the scale of the training data", {
  stack <- .mk_field_patches()
  fit   <- dm_fit(stack, backend = "r", T = 100L, epochs = 150L, hidden = 32L,
                  lr = 0.02, seed = 1L)
  s <- dm_sample(fit, n_samples = 12L, seed = 7L)

  expect_equal(dim(s), c(12L, dim(stack)[2], dim(stack)[3]))
  expect_true(all(is.finite(s)))

  # Pre-fix this ran to ~1e4 x the data scale.  The bar is deliberately
  # loose -- the pure-R denoiser is weak and over-disperses (see the
  # vignette) -- but bounded within an order of magnitude.
  expect_lt(max(abs(s)), 10 * max(abs(stack)))
  expect_lt(mean(apply(s, 1L, stats::sd)),
            10 * mean(apply(stack, 1L, stats::sd)))
})

test_that("dm_sample does not blow up as the number of steps grows", {
  stack <- .mk_field_patches()

  scale_at <- function(Tt) {
    fit <- dm_fit(stack, backend = "r", T = Tt, epochs = 120L, hidden = 32L,
                  lr = 0.02, seed = 1L)
    mean(apply(dm_sample(fit, n_samples = 8L, seed = 7L), 1L, stats::sd))
  }

  s50  <- scale_at(50L)
  s200 <- scale_at(200L)

  # The divergent recursion grew linearly in T (measured: 875 -> 3611
  # for T = 50 -> 200).  A stable sampler must not.
  expect_lt(s200, 2 * s50)
  expect_true(is.finite(s50) && is.finite(s200))
})

test_that("dm_sample respects the x_0 clip bound", {
  stack <- .mk_field_patches()
  fit   <- dm_fit(stack, backend = "r", T = 100L, epochs = 100L, hidden = 32L,
                  lr = 0.02, seed = 1L)
  s <- dm_sample(fit, n_samples = 20L, seed = 5L)

  # Samples are un-standardised on the way out, so the bound maps to
  # clip * sd + mu.  Allow the final step's posterior noise on top.
  lim <- 4 * fit$sd + abs(fit$mu) + 4 * fit$sd
  expect_lt(max(abs(s)), lim)
})

test_that("the torch sampler is also bounded and keeps spatial structure", {
  skip_on_cran()
  skip_if_not_installed("torch")
  skip_if_not(tryCatch({ torch::torch_tensor(1); TRUE },
                       error = function(e) FALSE),
              "torch runtime unavailable")

  lag1 <- function(p) {
    h <- stats::cor(as.vector(p[, -ncol(p)]), as.vector(p[, -1]))
    v <- stats::cor(as.vector(p[-nrow(p), ]), as.vector(p[-1, ]))
    (h + v) / 2
  }

  stack <- .mk_field_patches(n = 24L)
  fit <- dm_fit(stack, T = 100L, epochs = 300L, hidden = 64L, lr = 1e-3,
                backend = "torch", device = "cpu", seed = 1L)
  s <- dm_sample(fit, n_samples = 20L, seed = 99L)

  expect_true(all(is.finite(s)))

  # `.torch_ddpm_sample()` is a separate code path from the pure-R
  # sampler and carried the same unclipped recursion: it produced
  # correctly *shaped* fields at ~250x the data scale, which is exactly
  # the failure a visual check would pass.
  expect_lt(mean(apply(s, 1L, stats::sd)),
            5 * mean(apply(stack, 1L, stats::sd)))

  # Unlike the pure-R backend, this one does learn the spatial score,
  # so the structure check is a real bar here rather than a formality.
  expect_gt(mean(apply(s, 1L, lag1)), 0.4)
})
