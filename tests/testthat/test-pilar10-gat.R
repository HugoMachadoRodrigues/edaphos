## Tests for Pilar 10 -- Graph Attention Network (v2.6.0).

.mk_profile_network <- function(n = 40L, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  # Three correlated features
  x1 <- stats::rnorm(n);  x2 <- 0.5 * x1 + stats::rnorm(n, 0, 0.5)
  x3 <- stats::rnorm(n)
  # Target: weighted sum of features + spatial smoothing
  y  <- 2 * x1 + 0.5 * x2 - x3 + stats::rnorm(n, 0, 0.3)
  data.frame(lon = lon, lat = lat, x1 = x1, x2 = x2, x3 = x3, y = y)
}

test_that("gnn_build_graph: constructs a well-formed edaphos_gnn_graph", {
  dat <- .mk_profile_network(n = 30L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  expect_s3_class(g, "edaphos_gnn_graph")
  expect_equal(g$n, 30L)
  expect_equal(dim(g$features), c(30L, 3L))
  expect_equal(ncol(g$edge_index), 2L)
  expect_equal(nrow(g$edge_index), 30L * 5L)
  # Each node has exactly k=5 edges
  for (i in 1:30) {
    expect_equal(sum(g$edge_index[, 1L] == i), 5L)
  }
  # Edge weights sum to 1 per source node (soft-normalised)
  for (i in 1:30) {
    w <- g$edge_weight[g$edge_index[, 1L] == i]
    expect_equal(sum(w), 1, tolerance = 1e-8)
  }
})

test_that("gnn_build_graph: auto-selects numeric columns when feature_cols=NULL", {
  dat <- .mk_profile_network(n = 20L)
  g <- gnn_build_graph(dat, k = 3L)
  expect_true(all(c("x1", "x2", "x3", "y") %in% g$feature_names))
  expect_false(any(c("lon", "lat") %in% g$feature_names))
})

test_that("gnn_fit: trains and produces an embedding matrix of correct shape", {
  dat <- .mk_profile_network(n = 40L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, targets = dat$y,
                   hidden = 8L, n_heads = 2L, n_layers = 2L,
                   epochs = 50L, lr = 0.05, seed = 1L)
  expect_s3_class(fit, "edaphos_gnn_gat")
  expect_equal(fit$emb_dim, 16L)  # hidden * n_heads = 8 * 2
  emb <- gnn_embed(fit)
  expect_equal(dim(emb), c(40L, 16L))
})

test_that("gnn_fit: training MSE decreases", {
  dat <- .mk_profile_network(n = 50L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 8L, n_heads = 2L, n_layers = 2L,
                   epochs = 200L, lr = 0.05, seed = 1L)
  expect_lt(fit$history[length(fit$history)],
             fit$history[1L] * 0.9)
})

test_that("predict.edaphos_gnn_gat: returns a length-n vector on native scale", {
  dat <- .mk_profile_network(n = 30L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y,
                   hidden = 8L, n_heads = 2L, n_layers = 2L,
                   epochs = 100L, seed = 1L)
  pr <- predict(fit)
  expect_length(pr, 30L)
  expect_true(all(is.finite(pr)))
  # At least weakly correlated with truth
  expect_gt(stats::cor(pr, dat$y), 0)
})

test_that("print methods for both graph and fit emit readable headers", {
  dat <- .mk_profile_network(n = 20L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 20L, seed = 1L)
  o_g <- utils::capture.output(print(g))
  o_f <- utils::capture.output(print(fit))
  expect_true(any(grepl("edaphos_gnn_graph", o_g)))
  expect_true(any(grepl("edaphos_gnn_gat",   o_f)))
})
