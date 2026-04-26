## Edge-case tests for Pilar 10 GAT (v2.9.0 expansion)

.mk_net <- function(n = 30L, seed = 1L, p = 3L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48); lat <- stats::runif(n, -16, -14)
  feats <- matrix(stats::rnorm(n * p), n, p,
                    dimnames = list(NULL, paste0("x", seq_len(p))))
  y <- rowSums(feats) + stats::rnorm(n, 0, 0.3)
  cbind(data.frame(lon = lon, lat = lat), feats, y = y)
}

test_that("gnn_build_graph: k = 1 produces exactly n edges", {
  d <- .mk_net(n = 20L)
  g <- gnn_build_graph(d, k = 1L,
                         feature_cols = c("x1", "x2", "x3"))
  expect_equal(nrow(g$edge_index), 20L)
  # Each source row appears exactly once
  expect_equal(sort(g$edge_index[, 1L]), 1:20)
})

test_that("gnn_build_graph: k = n-1 turns into a complete graph", {
  d <- .mk_net(n = 10L)
  g <- gnn_build_graph(d, k = 9L,
                         feature_cols = c("x1", "x2", "x3"))
  expect_equal(nrow(g$edge_index), 10L * 9L)
})

test_that("gnn_build_graph: rejects when no numeric feature columns exist", {
  d <- data.frame(lon = 1:5, lat = 1:5,
                    cat = letters[1:5])  # character column
  expect_error(gnn_build_graph(d, k = 2L,
                                   feature_cols = "cat"),
                regexp = ".")  # accept any error (character features can't be numeric)
})

test_that("gnn_build_graph: identical-coordinate rows handled without Inf weights", {
  d <- .mk_net(n = 15L)
  d$lon[c(1, 5)] <- d$lon[2]
  d$lat[c(1, 5)] <- d$lat[2]
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  expect_true(all(is.finite(g$edge_weight)))
  # Edges from duplicates still have weights that sum to 1 per source
  per_src <- tapply(g$edge_weight, g$edge_index[, 1L], sum)
  expect_true(all(abs(per_src - 1) < 1e-8))
})

test_that("gnn_fit: NA feature rows propagated as 0 via standardisation fallback", {
  d <- .mk_net(n = 20L)
  d$x1[c(3, 7)] <- NA
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  # The standardiser replaces NAs with 0 after scaling
  expect_false(any(is.na(g$features)))
})

test_that("gnn_fit: n_heads = 1 still produces coherent embedding dim", {
  d <- .mk_net(n = 20L)
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, d$y,
                   hidden = 5L, n_heads = 1L, n_layers = 2L,
                   epochs = 10L, seed = 1L)
  expect_equal(fit$emb_dim, 5L)  # hidden * n_heads = 5 * 1
})

test_that("gnn_fit: n_layers = 1 (single GAT layer) works", {
  d <- .mk_net(n = 20L)
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, d$y,
                   hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 10L, seed = 1L)
  expect_s3_class(fit, "edaphos_gnn_gat")
  expect_equal(fit$n_layers, 1L)
})

test_that("gnn_fit: reproducibility with same seed", {
  d <- .mk_net(n = 15L)
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  f1 <- gnn_fit(g, d$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                  epochs = 10L, seed = 42L)
  f2 <- gnn_fit(g, d$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                  epochs = 10L, seed = 42L)
  # ELM-style: hidden layers are fixed at random init under same seed
  expect_equal(f1$emb, f2$emb, tolerance = 1e-10)
})

test_that("gnn_fit(backend='torch'): n_heads = 1 still works", {
  .skip_if_no_torch()
  d <- .mk_net(n = 15L)
  g <- gnn_build_graph(d, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, d$y,
                   hidden = 4L, n_heads = 1L, n_layers = 2L,
                   epochs = 5L, seed = 1L,
                   backend = "torch", device = "cpu")
  expect_equal(fit$backend, "torch")
  expect_true(all(is.finite(fit$history)))
})

test_that("gnn_fit: very small graph (n = 5) does not crash", {
  set.seed(1L)
  d <- .mk_net(n = 5L)
  g <- gnn_build_graph(d, k = 2L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, d$y,
                   hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 5L, seed = 1L)
  expect_s3_class(fit, "edaphos_gnn_gat")
  expect_length(predict(fit), 5L)
})
