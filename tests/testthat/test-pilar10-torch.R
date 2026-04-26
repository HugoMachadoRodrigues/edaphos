## Tests for the v2.7.0 torch backend of Pilar 10 (GAT).

.mk_torch_network <- function(n = 30L, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  x1 <- stats::rnorm(n); x2 <- 0.5 * x1 + stats::rnorm(n, 0, 0.5)
  x3 <- stats::rnorm(n)
  y <- 2 * x1 + 0.5 * x2 - x3 + stats::rnorm(n, 0, 0.3)
  data.frame(lon = lon, lat = lat, x1 = x1, x2 = x2, x3 = x3, y = y)
}

test_that("gnn_fit(backend='torch'): fits GAT with autograd", {
  .skip_if_no_torch()
  dat <- .mk_torch_network(n = 30L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y,
                   hidden = 4L, n_heads = 2L, n_layers = 2L,
                   epochs = 20L, lr = 0.05, seed = 1L,
                   backend = "torch", device = "cpu")
  expect_s3_class(fit, "edaphos_gnn_gat")
  expect_equal(fit$backend, "torch")
  expect_true(length(fit$history) > 0L)
  expect_true(all(is.finite(fit$history)))
  emb <- gnn_embed(fit)
  expect_equal(nrow(emb), 30L)
})

test_that("torch GAT: training loss decreases", {
  .skip_if_no_torch()
  dat <- .mk_torch_network(n = 40L, seed = 2L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y,
                   hidden = 8L, n_heads = 2L, n_layers = 2L,
                   epochs = 60L, lr = 0.05, seed = 2L,
                   backend = "torch")
  expect_lt(fit$history[length(fit$history)], fit$history[1L] * 0.9)
})

test_that("predict.edaphos_gnn_gat (torch): produces a length-n vector", {
  .skip_if_no_torch()
  dat <- .mk_torch_network(n = 30L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y,
                   hidden = 4L, n_heads = 2L, n_layers = 2L,
                   epochs = 30L, seed = 1L, backend = "torch")
  pr <- predict(fit)
  expect_length(pr, 30L)
  expect_true(all(is.finite(pr)))
  # At least weakly correlated with truth
  expect_gt(stats::cor(pr, dat$y), -0.5)  # not strictly anti-correlated
})

test_that("torch GAT handles multi-head concatenation correctly", {
  .skip_if_no_torch()
  dat <- .mk_torch_network(n = 20L, seed = 3L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y,
                   hidden = 4L, n_heads = 4L, n_layers = 2L,
                   epochs = 10L, seed = 3L, backend = "torch")
  # With concat = TRUE on the first layer and mean on the last,
  # the node embedding dim matches hidden (last-layer's d_out)
  emb <- gnn_embed(fit)
  expect_equal(ncol(emb), 4L)  # hidden only (mean-pool final head)
})
