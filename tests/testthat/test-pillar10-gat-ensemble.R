## gnn_fit_ensemble() had no test. Its help page promises: members that
## differ only in their seed (base seed + member index), a prediction that is
## the mean of the members, and member_sd that is their spread -- zero for a
## single member. Each is checked against an independent refit.

.ens_graph <- function(n = 36L, seed = 3L) {
  set.seed(seed)
  d <- data.frame(lon = stats::runif(n, -50, -48), lat = stats::runif(n, -16, -14),
                  x1 = stats::rnorm(n), x2 = stats::rnorm(n))
  d$y <- 1.5 * d$x1 - d$x2 + stats::rnorm(n, 0, 0.3)
  list(g = gnn_build_graph(d, k = 4L, feature_cols = c("x1", "x2")), y = d$y)
}

test_that("members are gnn_fit() with seed = base + index, and the summary is their mean and sd", {
  s <- .ens_graph()
  args <- list(hidden = 4L, n_heads = 1L, n_layers = 1L, epochs = 15L,
               backend = "r")
  ens <- do.call(gnn_fit_ensemble,
                 c(list(s$g, s$y, n_ensemble = 3L, seed = 10L), args))
  expect_s3_class(ens, "edaphos_gnn_ensemble")
  expect_length(ens$members, 3L)

  # Member 2 must be exactly the single fit with seed 10 + 2.
  solo <- do.call(gnn_fit, c(list(s$g, s$y, seed = 12L), args))
  expect_equal(predict(ens$members[[2]]), predict(solo), tolerance = 1e-12)

  P <- vapply(ens$members, predict, numeric(s$g$n))
  expect_equal(predict(ens), rowMeans(P), tolerance = 1e-12)
  expect_equal(ens$member_sd, apply(P, 1L, stats::sd), tolerance = 1e-12)
  # Different seeds must give different members; identical seeds would make
  # the spread vanish and the "ensemble" one model repeated.
  expect_gt(mean(ens$member_sd), 0)
  expect_output(print(ens), "members = 3")
})

test_that("one member has zero spread, and a non-positive size is refused", {
  s <- .ens_graph(n = 24L)
  one <- gnn_fit_ensemble(s$g, s$y, n_ensemble = 1L, seed = 1L, hidden = 4L,
                          n_heads = 1L, n_layers = 1L, epochs = 5L,
                          backend = "r")
  expect_equal(one$member_sd, rep(0, s$g$n))
  expect_equal(predict(one), predict(one$members[[1]]))
  expect_error(gnn_fit_ensemble(s$g, s$y, n_ensemble = 0L), "positive integer")
})

test_that("the training mask follows the NA targets", {
  s <- .ens_graph(n = 24L)
  y <- s$y; y[c(2, 5, 11)] <- NA
  ens <- gnn_fit_ensemble(s$g, y, n_ensemble = 2L, seed = 1L, hidden = 4L,
                          n_heads = 1L, n_layers = 1L, epochs = 5L,
                          backend = "r")
  expect_false(any(ens$train_mask[c(2, 5, 11)]))
  expect_equal(sum(ens$train_mask), 21L)
  # Predictions exist for every node, labelled or not.
  expect_true(all(is.finite(predict(ens))))
})
