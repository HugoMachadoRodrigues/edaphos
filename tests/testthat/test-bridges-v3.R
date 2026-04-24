## Tests for the six v3.0.0 cross-pilar bridges.
##
##   al_query_neural_operator()   (P8 x P5)
##   al_query_diffusion()         (P9 x P5)
##   al_query_bhs()               (P7 x P5)
##   gnn_causal_discovery()       (P10 x P1)
##   temporal_piml_loss()         (P2 x P3)
##   qf_krr_on_gat_embeddings()   (P6 x P10)

# ---------------------------------------------------------------------------
# Shared synthetic generators (small to keep CI fast)
# ---------------------------------------------------------------------------

.mk_no_dataset <- function(n_obs = 16L, n_depths = 10L, p_in = 3L,
                             seed = 1L) {
  set.seed(seed)
  depths <- seq(5, 120, length.out = n_depths)
  cov_static <- matrix(stats::rnorm(n_obs * p_in), n_obs, p_in)
  make_profile <- function(cov_i, z) {
    amp  <- 10 + 5 * cov_i[1L]
    rate <- 0.02 + 0.005 * cov_i[2L]
    amp * exp(-rate * z) + cov_i[3L]
  }
  targets <- t(apply(cov_static, 1L, make_profile, z = depths))
  list(depths = depths, covariates = cov_static, targets = targets)
}

.mk_soil_patches <- function(n = 6L, H = 6L, W = 6L, seed = 1L) {
  set.seed(seed)
  patches <- array(0, dim = c(n, H, W))
  for (i in seq_len(n)) {
    a <- matrix(stats::rnorm(H * W), H, W)
    b <- a
    for (r in 2:(H - 1)) for (c in 2:(W - 1)) {
      b[r, c] <- mean(a[(r - 1):(r + 1), (c - 1):(c + 1)])
    }
    patches[i, , ] <- b
  }
  patches
}

.mk_spatial_bhs <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  x   <- stats::rnorm(n)
  D <- as.matrix(stats::dist(cbind(lon, lat)))
  R <- exp(-2 * D);  diag(R) <- diag(R) + 1e-8
  w <- as.numeric(t(chol(R)) %*% stats::rnorm(n))
  y <- 2 * x + w + stats::rnorm(n, 0, 0.3)
  data.frame(y = y, x = x, lon = lon, lat = lat)
}

.mk_profile_network <- function(n = 40L, seed = 1L) {
  set.seed(seed)
  lon <- stats::runif(n, -50, -48)
  lat <- stats::runif(n, -16, -14)
  x1 <- stats::rnorm(n);  x2 <- 0.5 * x1 + stats::rnorm(n, 0, 0.5)
  x3 <- stats::rnorm(n)
  y  <- 2 * x1 + 0.5 * x2 - x3 + stats::rnorm(n, 0, 0.3)
  data.frame(lon = lon, lat = lat, x1 = x1, x2 = x2, x3 = x3, y = y)
}

# ---------------------------------------------------------------------------
# P8 x P5 -- al_query_neural_operator
# ---------------------------------------------------------------------------

test_that("al_query_neural_operator: returns a well-formed query frame", {
  d <- .mk_no_dataset(n_obs = 12L, n_depths = 8L, p_in = 3L, seed = 1L)
  no <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                          branch_hidden = 8L, trunk_hidden = 8L,
                          output_dim = 4L, epochs = 40L, lr = 0.03,
                          seed = 1L)
  # Mock ODE fit with the flat fields the bridge falls back on.
  ode <- structure(list(
    params = list(lambda0 = 0.02, mu = 0, y_inf = 5, y0 = 25)
  ), class = "edaphos_piml_profile")
  q <- al_query_neural_operator(no, ode, d$covariates,
                                   pool_depths = d$depths,
                                   n_select = 4L, n_pert = 5L, seed = 1L)
  expect_s3_class(q, "edaphos_al_neural_operator_query")
  expect_s3_class(q, "data.frame")
  expect_equal(nrow(q), 12L)
  expect_true(all(c("pool_index", "score",
                      "no_ode_disagreement", "no_uncertainty_sd")
                    %in% names(q)))
  expect_true(all(is.finite(q$score)))
  # Descending by score
  expect_true(all(diff(q$score) <= 1e-10))
  # Attributes
  expect_equal(attr(q, "n_select"), 4L)
})

test_that("al_query_neural_operator: tiny pert_sd still yields finite scores", {
  d <- .mk_no_dataset(n_obs = 12L, n_depths = 8L, p_in = 3L, seed = 42L)
  no <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                          branch_hidden = 8L, trunk_hidden = 8L,
                          output_dim = 4L, epochs = 60L, lr = 0.02,
                          seed = 42L)
  ode <- structure(list(
    params = list(lambda0 = 0.02, mu = 0, y_inf = 3, y0 = 18)
  ), class = "edaphos_piml_profile")
  # Very small pert_sd -> collapsed per-site spread; bridge must floor
  # site_sd so score stays finite.
  q <- al_query_neural_operator(no, ode, d$covariates,
                                   n_select = 3L, n_pert = 3L,
                                   pert_sd = 1e-12, seed = 1L)
  expect_true(all(is.finite(q$score)))
  expect_true(all(q$no_uncertainty_sd >= 1e-6 - 1e-12))
})

test_that("al_query_neural_operator: print emits a header", {
  d <- .mk_no_dataset(n_obs = 6L, n_depths = 5L, p_in = 2L, seed = 3L)
  no <- no_deeponet_fit(d$depths, d$targets, d$covariates,
                          branch_hidden = 4L, trunk_hidden = 4L,
                          output_dim = 2L, epochs = 10L, lr = 0.02,
                          seed = 3L)
  ode <- structure(list(
    params = list(lambda0 = 0.02, mu = 0, y_inf = 4, y0 = 20)
  ), class = "edaphos_piml_profile")
  q <- al_query_neural_operator(no, ode, d$covariates,
                                   n_select = 2L, n_pert = 2L, seed = 1L)
  out <- utils::capture.output(print(q))
  expect_true(any(grepl("edaphos_al_neural_operator_query", out)))
  expect_true(any(grepl("Pilar 8 x Pilar 5", out)))
})

# ---------------------------------------------------------------------------
# P9 x P5 -- al_query_diffusion
# ---------------------------------------------------------------------------

test_that("al_query_diffusion: ranks candidate cells by posterior SD", {
  p <- .mk_soil_patches(n = 6L, H = 6L, W = 6L, seed = 1L)
  fit <- dm_fit(p, T = 6L, epochs = 3L, hidden = 8L, lr = 0.05, seed = 1L)
  q <- al_query_diffusion(fit, n_samples = 5L, n_select = 4L,
                             combine = "sd", seed = 1L)
  expect_s3_class(q, "edaphos_al_diffusion_query")
  expect_equal(nrow(q), fit$H * fit$W)
  expect_true(all(c("row", "col",
                      "posterior_mean", "posterior_sd", "score")
                    %in% names(q)))
  expect_true(all(diff(q$score) <= 1e-10))
  expect_true(all(q$posterior_sd >= 0))
})

test_that("al_query_diffusion: sd_x_mean_abs scoring differs from sd alone", {
  p <- .mk_soil_patches(n = 6L, H = 5L, W = 5L, seed = 2L)
  fit <- dm_fit(p, T = 6L, epochs = 3L, hidden = 6L, lr = 0.05, seed = 2L)
  q_sd   <- al_query_diffusion(fit, n_samples = 5L, n_select = 3L,
                                  combine = "sd", seed = 1L)
  q_comb <- al_query_diffusion(fit, n_samples = 5L, n_select = 3L,
                                  combine = "sd_x_mean_abs", seed = 1L)
  # Same grid; scoring rule is different, so top-cell identities should
  # often disagree.  Guarantee the two frames carry different 'score'
  # vectors.
  expect_false(isTRUE(all.equal(q_sd$score, q_comb$score)))
  expect_equal(attr(q_comb, "combine"), "sd_x_mean_abs")
})

test_that("al_query_diffusion: accepts explicit candidate_cells", {
  p <- .mk_soil_patches(n = 6L, H = 5L, W = 5L, seed = 3L)
  fit <- dm_fit(p, T = 6L, epochs = 3L, hidden = 6L, lr = 0.05, seed = 3L)
  cand <- data.frame(row = c(1L, 2L, 3L), col = c(1L, 2L, 3L))
  q <- al_query_diffusion(fit, n_samples = 4L, candidate_cells = cand,
                             n_select = 2L, seed = 1L)
  expect_equal(nrow(q), 3L)
  expect_true(all(q$row %in% 1:3))
  expect_true(all(q$col %in% 1:3))
})

# ---------------------------------------------------------------------------
# P7 x P5 -- al_query_bhs
# ---------------------------------------------------------------------------

test_that("al_query_bhs: returns posterior variance-ranked candidates", {
  dat <- .mk_spatial_bhs(n = 60L, seed = 1L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 200L, burn = 100L, seed = 1L,
                   phi_range = c(0.1, 10))
  pool <- data.frame(
    x   = stats::rnorm(15),
    lon = stats::runif(15, -49.9, -48.1),
    lat = stats::runif(15, -15.9, -14.1)
  )
  q <- al_query_bhs(fit, pool, n_select = 5L, n_draws = 50L)
  expect_s3_class(q, "edaphos_al_bhs_query")
  expect_equal(nrow(q), 15L)
  expect_true(all(q$posterior_var >= 0))
  expect_true(all(diff(q$posterior_var) <= 1e-10))
  expect_equal(q$posterior_sd, sqrt(q$posterior_var), tolerance = 1e-12)
})

test_that("al_query_bhs: errors when backend != 'gibbs'", {
  dat <- .mk_spatial_bhs(n = 30L, seed = 2L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 100L, burn = 50L, seed = 2L)
  fit$backend <- "spBayes"  # simulate other backend for the guard
  pool <- data.frame(
    x = 0, lon = -49, lat = -15
  )
  expect_error(al_query_bhs(fit, pool), "backend = 'gibbs'")
})

test_that("al_query_bhs: prefers sites far from training coords", {
  # Far-from-training sites should have higher predictive variance
  # because R_cross is small -> 1 - k'R_inv k approaches 1.
  dat <- .mk_spatial_bhs(n = 40L, seed = 3L)
  fit <- bhs_fit(dat, y ~ x, c("lon", "lat"),
                   nmcmc = 150L, burn = 75L, seed = 3L,
                   phi_range = c(0.5, 10))
  pool_close <- data.frame(x = 0,
                              lon = dat$lon[1L] + 1e-3,
                              lat = dat$lat[1L] + 1e-3)
  pool_far   <- data.frame(x = 0, lon = -200, lat = -200)
  q_close <- al_query_bhs(fit, pool_close, n_draws = 50L)
  q_far   <- al_query_bhs(fit, pool_far,   n_draws = 50L)
  expect_gt(q_far$posterior_var, q_close$posterior_var)
})

# ---------------------------------------------------------------------------
# P10 x P1 -- gnn_causal_discovery
# ---------------------------------------------------------------------------

test_that("gnn_causal_discovery: returns a KG restricted to user features", {
  skip_if_not_installed("bnlearn")
  skip_if_not_installed("igraph")
  dat <- .mk_profile_network(n = 30L, seed = 1L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 6L, n_heads = 2L, n_layers = 1L,
                   epochs = 25L, lr = 0.05, seed = 1L)
  feat_df <- dat[, c("x1", "x2", "x3", "y")]
  kg <- gnn_causal_discovery(fit, feat_df, method = "hc",
                                n_emb_cols = 3L, seed = 1L)
  expect_s3_class(kg, "edaphos_causal_kg")
  expect_true("edges_feature_only" %in% names(kg))
  # Every surviving feature-only edge must join feature names
  if (nrow(kg$edges_feature_only) > 0L) {
    expect_true(all(kg$edges_feature_only[, 1L] %in%
                       c("x1", "x2", "x3", "y")))
    expect_true(all(kg$edges_feature_only[, 2L] %in%
                       c("x1", "x2", "x3", "y")))
  }
  expect_equal(kg$n_emb_cols, 3L)
})

test_that("gnn_causal_discovery: rejects row-count mismatches", {
  skip_if_not_installed("bnlearn")
  dat <- .mk_profile_network(n = 20L, seed = 2L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 10L, lr = 0.05, seed = 2L)
  bad <- dat[1:10, c("x1", "x2", "x3", "y")]
  expect_error(gnn_causal_discovery(fit, bad, n_emb_cols = 2L),
                "same number of rows")
})

test_that("gnn_causal_discovery: clamps n_emb_cols to embedding dim", {
  skip_if_not_installed("bnlearn")
  dat <- .mk_profile_network(n = 20L, seed = 3L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 10L, lr = 0.05, seed = 3L)
  feat_df <- dat[, c("x1", "x2", "x3", "y")]
  # Request WAY more conditioners than the embedding actually has
  kg <- gnn_causal_discovery(fit, feat_df, method = "hc",
                                n_emb_cols = 9999L, seed = 1L)
  expect_lte(kg$n_emb_cols, ncol(fit$emb))
})

# ---------------------------------------------------------------------------
# P2 x P3 -- temporal_piml_loss
# ---------------------------------------------------------------------------

test_that("temporal_piml_loss: returns a callable closure with correct env", {
  ode <- structure(list(
    params = list(lambda0 = 0.03, mu = 0, y_inf = 2, y0 = 20)
  ), class = "edaphos_piml_profile")
  loss <- temporal_piml_loss(ode, weight = 0.2)
  expect_true(is.function(loss))
  # The closure's environment should hold the frozen parameters
  env_vars <- ls(environment(loss))
  expect_true(all(c("lambda0", "mu", "yi", "weight") %in% env_vars))
  expect_equal(environment(loss)$lambda0, 0.03)
  expect_equal(environment(loss)$weight,  0.2)
})

test_that("temporal_piml_loss: R-matrix branch returns a non-negative scalar", {
  ode <- structure(list(
    params = list(lambda0 = 0.02, mu = 0, y_inf = 5, y0 = 25)
  ), class = "edaphos_piml_profile")
  loss <- temporal_piml_loss(ode, weight = 0.5)
  # (n_t, H, W) = (5, 4, 4) cube of predictions
  set.seed(1L)
  y_pred <- array(stats::rnorm(5 * 4 * 4, mean = 10), dim = c(5L, 4L, 4L))
  y_true <- y_pred + stats::rnorm(80, 0, 0.1)
  v <- loss(y_pred, y_true, NULL)
  expect_true(is.numeric(v))
  expect_equal(length(v), 1L)
  expect_true(v >= 0)
})

test_that("temporal_piml_loss: n_t < 2 short-circuits to zero", {
  ode <- structure(list(
    params = list(lambda0 = 0.02, mu = 0, y_inf = 5, y0 = 25)
  ), class = "edaphos_piml_profile")
  loss <- temporal_piml_loss(ode, weight = 0.5)
  y_pred <- array(stats::rnorm(1 * 3 * 3), dim = c(1L, 3L, 3L))
  v <- loss(y_pred, y_pred, NULL)
  expect_equal(v, 0)
})

test_that("temporal_piml_loss: reads bayes-fit params from $map", {
  ode <- structure(list(
    map = list(lambda0 = 0.05, mu = 0.01, y_inf = 1, y0 = 30)
  ), class = "edaphos_piml_bayes")
  loss <- temporal_piml_loss(ode, weight = 0.1)
  expect_equal(environment(loss)$lambda0, 0.05)
  expect_equal(environment(loss)$yi,       1)
})

# ---------------------------------------------------------------------------
# P6 x P10 -- qf_krr_on_gat_embeddings
# ---------------------------------------------------------------------------

test_that("qf_krr_on_gat_embeddings: fits and predicts on training nodes", {
  dat <- .mk_profile_network(n = 30L, seed = 1L)
  g <- gnn_build_graph(dat, k = 4L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 6L, n_heads = 2L, n_layers = 1L,
                   epochs = 30L, lr = 0.05, seed = 1L)
  qk <- qf_krr_on_gat_embeddings(fit, dat$y, n_pcs = 4L,
                                    reps = 1L, lambda = 0.5)
  expect_s3_class(qk, "edaphos_qf_krr_gat")
  expect_s3_class(qk, "edaphos_qf_krr")
  # predict() with no newdata -> predicts on the training embeddings
  pr <- predict(qk)
  expect_equal(length(pr), nrow(dat))
  expect_true(all(is.finite(pr)))
  # The KRR should fit the training data better than a horizontal line
  rmse_fit  <- sqrt(mean((pr - dat$y)^2))
  rmse_null <- sqrt(mean((mean(dat$y) - dat$y)^2))
  expect_lt(rmse_fit, rmse_null)
})

test_that("qf_krr_on_gat_embeddings: rejects length-mismatched targets", {
  dat <- .mk_profile_network(n = 20L, seed = 2L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 10L, lr = 0.05, seed = 2L)
  expect_error(qf_krr_on_gat_embeddings(fit, y = c(1, 2, 3),
                                             n_pcs = 3L, reps = 1L))
})

test_that("qf_krr_on_gat_embeddings: print method emits bridge tag", {
  dat <- .mk_profile_network(n = 20L, seed = 3L)
  g <- gnn_build_graph(dat, k = 3L,
                         feature_cols = c("x1", "x2", "x3"))
  fit <- gnn_fit(g, dat$y, hidden = 4L, n_heads = 2L, n_layers = 1L,
                   epochs = 10L, lr = 0.05, seed = 3L)
  qk <- qf_krr_on_gat_embeddings(fit, dat$y, n_pcs = 3L,
                                    reps = 1L, lambda = 0.5)
  out <- utils::capture.output(print(qk))
  expect_true(any(grepl("edaphos_qf_krr_gat", out)))
  expect_true(any(grepl("Pilar 6 x Pilar 10", out)))
})
