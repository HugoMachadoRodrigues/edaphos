## Tests for Pillar 10 -- Graph Attention Network.

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
  skip_on_cran()  # over 0.5 s on a Windows runner; runs on every GitHub Actions leg
  dat <- .mk_profile_network(n = 30L)
  g <- gnn_build_graph(dat, k = 5L,
                         feature_cols = c("x1", "x2", "x3"))
  expect_s3_class(g, "edaphos_gnn_graph")
  expect_equal(g$n, 30L)
  expect_equal(dim(g$features), c(30L, 3L))
  expect_equal(ncol(g$edge_index), 2L)
  # k neighbours + 1 self-loop per node.  k-NN never returns a node as its own
  # neighbour, so without the self-loop a profile's own covariates never reach
  # its own prediction -- see gnn_build_graph(self_loops =).
  expect_equal(nrow(g$edge_index), 30L * 6L)
  for (i in 1:30) {
    expect_equal(sum(g$edge_index[, 1L] == i), 6L)
    expect_equal(sum(g$edge_index[, 1L] == i & g$edge_index[, 2L] == i), 1L)
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
  # Heads are AVERAGED on the output layer (the convention of Velickovic et
  # al. 2018); the previous code concatenated them everywhere, so the learned
  # representation is now `hidden` wide rather than hidden * n_heads.
  emb <- gnn_embed(fit)
  expect_equal(dim(emb), c(40L, 8L))
  # emb_dim describes the HEAD's design matrix, which additionally carries the
  # 3 raw features through the readout skip.
  expect_equal(fit$emb_dim, 8L + 3L)
  expect_equal(ncol(fit$head_design), fit$emb_dim)

  # concatenating heads and dropping the skip restores the historical shape
  fit0 <- gnn_fit(g, targets = dat$y, hidden = 8L, n_heads = 2L,
                    n_layers = 2L, epochs = 10L, lr = 0.05, seed = 1L,
                    average_heads = FALSE, readout_skip = FALSE)
  expect_equal(dim(gnn_embed(fit0)), c(40L, 16L))
  expect_equal(fit0$emb_dim, 16L)
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

test_that("print(fit) reports the epoch whose weights were returned, not the last one", {
  # 24 nodes, 10 epochs: validation loss rises from epoch 1, so early
  # stopping keeps epoch 1 while 10 epochs are run. The print used to show
  # the epoch-10 training loss as "final MSE" with "(epochs = 10)".
  set.seed(3L)
  d <- data.frame(lon = stats::runif(24, -50, -48),
                  lat = stats::runif(24, -16, -14),
                  x1 = stats::rnorm(24), x2 = stats::rnorm(24))
  d$y <- 1.5 * d$x1 - d$x2 + stats::rnorm(24, 0, 0.3)
  g <- gnn_build_graph(d, k = 4L, feature_cols = c("x1", "x2"))
  fit <- gnn_fit(g, d$y, hidden = 4L, n_heads = 1L, n_layers = 1L,
                 epochs = 10L, seed = 1L, backend = "r")
  be <- fit$best_epoch
  expect_lt(be, length(fit$history))     # the case the old print got wrong
  out <- paste(utils::capture.output(print(fit)), collapse = "\n")
  expect_false(grepl("final MSE", out, fixed = TRUE))
  expect_match(out, sprintf("%d run, weights from epoch %d",
                            length(fit$history), be), fixed = TRUE)
  # the loss printed is the one recorded for the returned epoch, labelled
  # with its scale and the penalty it includes
  expect_match(out, sprintf("epoch %d, standardised y: train %.4g (MSE + ridge)",
                            be, fit$history[be]), fixed = TRUE)
  expect_match(out, sprintf("val MSE %.4g", fit$val_history[be]), fixed = TRUE)
  expect_match(out, sprintf("%d fitted, %d held out", fit$n_train - fit$n_val,
                            fit$n_val), fixed = TRUE)
})

test_that("print(fit) and print(qf_krr_on_gat_embeddings(fit)) count the same columns", {
  dat <- .mk_profile_network(n = 20L)
  g <- gnn_build_graph(dat, k = 3L, feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 1L, n_layers = 1L,
                 epochs = 5L, seed = 1L)
  n_learned <- ncol(gnn_embed(fit))
  o_fit <- paste(utils::capture.output(print(fit)), collapse = "\n")
  expect_match(o_fit, sprintf("%d learned + 3 raw-feature skip = %d head columns",
                              n_learned, fit$emb_dim), fixed = TRUE)
  qk <- qf_krr_on_gat_embeddings(fit, dat$y, n_pcs = 2L, reps = 1L)
  o_qk <- paste(utils::capture.output(print(qk)), collapse = "\n")
  expect_match(o_qk, sprintf("%d learned columns (excludes the 3 raw-feature skip)",
                             n_learned), fixed = TRUE)
  # no bare "emb_dim" figure left to contradict the other print
  expect_false(grepl("emb_dim", o_fit)); expect_false(grepl("emb_dim", o_qk))

  fit0 <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 1L, n_layers = 1L,
                  epochs = 5L, seed = 1L, readout_skip = FALSE)
  expect_output(print(fit0), "4 learned columns (no readout skip)", fixed = TRUE)
})
