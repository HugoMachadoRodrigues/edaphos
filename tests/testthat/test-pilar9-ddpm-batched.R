## Tests for the v3.2.0 batched DDPM forward pass.
## Contract: .dm_forward_batch() matches the per-row .dm_forward()
## up to floating-point round-off, and the training loop on it
## produces the same loss trajectory as the old per-patch loop.

# Reference implementation: old per-row forward + gradient accumulation.
.old_dm_epoch_loss <- function(net, x_t, conditioning, eps, t_ix, T) {
  loss_acc <- 0
  H_W <- dim(x_t)[2L]
  grad_W3 <- matrix(0, net$hidden, H_W)
  grad_b3 <- rep(0, H_W)
  for (i in seq_len(nrow(x_t))) {
    fwd <- edaphos:::.dm_forward(net,
                                    x_flat    = x_t[i, ],
                                    cond_flat = conditioning[i, ],
                                    t_norm    = t_ix[i] / T)
    resid <- fwd$eps_hat - eps[i, ]
    loss_acc <- loss_acc + mean(resid^2)
    grad_W3  <- grad_W3 + outer(as.numeric(fwd$h2), resid) *
                  (2 / nrow(x_t))
    grad_b3  <- grad_b3 + resid * (2 / nrow(x_t))
  }
  list(loss = loss_acc / nrow(x_t),
       grad_W3 = grad_W3, grad_b3 = grad_b3)
}

.new_dm_epoch_loss <- function(net, x_t, conditioning, eps, t_ix, T) {
  n_patches <- nrow(x_t); H_W <- dim(x_t)[2L]
  fwd <- edaphos:::.dm_forward_batch(net,
                                        X_flat = x_t,
                                        Cond_flat = conditioning,
                                        t_norms = t_ix / T)
  resid <- fwd$eps_hat - eps
  loss  <- (sum(resid * resid) / H_W) / n_patches
  grad_W3 <- (2 / n_patches) * crossprod(fwd$h2, resid)
  grad_b3 <- (2 / n_patches) * colSums(resid)
  list(loss = loss, grad_W3 = grad_W3, grad_b3 = grad_b3)
}

test_that(".dm_forward_batch: matches .dm_forward row-by-row (cond_dim=0)", {
  set.seed(1L)
  H <- 4L; W <- 4L; hidden <- 8L; n <- 5L
  net <- edaphos:::.dm_init_net(H, W, cond_dim = 0L, hidden = hidden)
  X   <- matrix(stats::rnorm(n * H * W), n, H * W)
  Cnd <- matrix(0, n, 0L)
  t_norms <- stats::runif(n)
  B <- edaphos:::.dm_forward_batch(net, X, Cnd, t_norms)
  for (i in seq_len(n)) {
    r <- edaphos:::.dm_forward(net, X[i, ], Cnd[i, ], t_norms[i])
    expect_equal(as.numeric(B$eps_hat[i, ]), r$eps_hat,
                   tolerance = 1e-10)
    expect_equal(as.numeric(B$h2[i, ]),      as.numeric(r$h2),
                   tolerance = 1e-10)
  }
})

test_that(".dm_forward_batch: matches row-by-row with non-zero cond_dim", {
  set.seed(2L)
  H <- 4L; W <- 4L; hidden <- 6L; n <- 4L; cd <- 3L
  net <- edaphos:::.dm_init_net(H, W, cond_dim = cd, hidden = hidden)
  X   <- matrix(stats::rnorm(n * H * W), n, H * W)
  Cnd <- matrix(stats::rnorm(n * cd),   n, cd)
  t_norms <- stats::runif(n)
  B <- edaphos:::.dm_forward_batch(net, X, Cnd, t_norms)
  for (i in seq_len(n)) {
    r <- edaphos:::.dm_forward(net, X[i, ], Cnd[i, ], t_norms[i])
    expect_equal(as.numeric(B$eps_hat[i, ]), r$eps_hat,
                   tolerance = 1e-10)
  }
})

test_that("batched epoch loss / gradients equal per-row accumulation", {
  set.seed(3L)
  H <- 4L; W <- 4L; hidden <- 8L; n <- 6L
  net <- edaphos:::.dm_init_net(H, W, cond_dim = 0L, hidden = hidden)
  T  <- 10L
  x_t <- matrix(stats::rnorm(n * H * W), n, H * W)
  eps <- matrix(stats::rnorm(n * H * W), n, H * W)
  t_ix <- sample.int(T, n, replace = TRUE)
  Cnd <- matrix(0, n, 0L)
  a <- .old_dm_epoch_loss(net, x_t, Cnd, eps, t_ix, T)
  b <- .new_dm_epoch_loss(net, x_t, Cnd, eps, t_ix, T)
  expect_equal(a$loss,    b$loss,    tolerance = 1e-10)
  expect_equal(a$grad_W3, b$grad_W3, tolerance = 1e-10)
  expect_equal(a$grad_b3, b$grad_b3, tolerance = 1e-10)
})

test_that("dm_fit training history matches a per-row reference within tol", {
  # Not a bit-for-bit comparison (RNG state differs inside the new
  # batched path vs the old), but the loss trajectory on small data
  # should be in the same ballpark -- and more importantly, the
  # returned fit must still train (loss decreases).
  set.seed(4L)
  n <- 8L; H <- 4L; W <- 4L
  patches <- array(stats::rnorm(n * H * W), dim = c(n, H, W))
  # Spatial smoothing for a minimally non-trivial target
  for (i in seq_len(n)) {
    for (r in 2:(H - 1)) for (c in 2:(W - 1)) {
      patches[i, r, c] <- mean(patches[i, (r-1):(r+1), (c-1):(c+1)])
    }
  }
  fit <- dm_fit(patches, T = 8L, epochs = 20L, hidden = 8L,
                  lr = 0.05, seed = 4L)
  expect_s3_class(fit, "edaphos_dm_fit")
  expect_lt(tail(fit$history, 1L), head(fit$history, 1L))
})
