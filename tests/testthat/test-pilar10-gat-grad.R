## Analytic gradients of the GAT must match central finite differences.
##
## Through v3.10.0 the "r" backend never updated W / a_l / a_r: only the linear
## head was fitted, so "attention" was a random projection.  Training them
## requires reverse-mode gradients through the grouped softmax, and a wrong
## gradient is silent -- the loss still decreases, just towards the wrong
## place.  These tests are the guard.
##
## The comparison uses a MIXED criterion: relative error where the gradient is
## large enough for a ratio to mean something, absolute error where it is not.
## A pure relative criterion reports huge errors on entries where both the
## analytic and the numeric gradient are ~1e-12, which says nothing.

## Central differences with step h carry an absolute noise floor of roughly
## eps_machine * |loss| / h ~ 1e-16 / 1e-5 = 1e-11, plus O(h^2) truncation.
## Requiring a tight RELATIVE match on a gradient whose magnitude is itself
## near that floor asks finite differences for precision they do not have, so
## the criterion is `|diff| <= abs_tol + rel_tol * |numeric|` -- the standard
## combined form.
grad_agrees <- function(analytic, numeric_g, rel_tol = 1e-4, abs_tol = 1e-7) {
  all(abs(analytic - numeric_g) <= abs_tol + rel_tol * abs(numeric_g))
}

make_case <- function(n = 40L, hidden = 4L, n_heads = 2L, n_layers = 2L,
                      k = 5L, seed = 31L) {
  set.seed(seed)
  df <- data.frame(lon = stats::runif(n, -52, -46),
                   lat = stats::runif(n, -20, -12),
                   f1 = stats::rnorm(n), f2 = stats::rnorm(n),
                   f3 = stats::rnorm(n))
  g <- gnn_build_graph(df, k = k, feature_cols = c("f1", "f2", "f3"))
  mask <- rep(c(TRUE, FALSE), length.out = n)
  set.seed(seed + 1L)
  d_in <- ncol(g$features)
  Wl <- lapply(seq_len(n_layers), function(l)
    lapply(seq_len(n_heads), function(h) {
      cd <- if (l == 1L) d_in else hidden * n_heads
      matrix(stats::rnorm(cd * hidden, sd = 0.4), cd, hidden)
    }))
  al <- lapply(seq_len(n_layers), function(l)
    lapply(seq_len(n_heads), function(h)
      list(a_l = stats::rnorm(hidden) * 0.3,
           a_r = stats::rnorm(hidden) * 0.3)))
  list(g = g, mask = mask, Wl = Wl, al = al, hidden = hidden,
       n_heads = n_heads, n_layers = n_layers,
       y = stats::rnorm(sum(mask)))
}

check_config <- function(residual, average_heads, cs = make_case()) {
  emb_dim <- if (average_heads) cs$hidden else cs$hidden * cs$n_heads
  set.seed(99L)
  w_head <- stats::rnorm(emb_dim, sd = 0.3); b_head <- 0.1

  loss_of <- function(Wl, al) {
    e <- edaphos:::.gat_forward_all(cs$g$features, cs$g, Wl, al,
                                    cs$n_layers, cs$n_heads,
                                    residual, average_heads)$emb
    mean((as.numeric(e[cs$mask, , drop = FALSE] %*% w_head + b_head) - cs$y)^2)
  }
  fw <- edaphos:::.gat_forward_all(cs$g$features, cs$g, cs$Wl, cs$al,
                                   cs$n_layers, cs$n_heads,
                                   residual, average_heads)
  gy <- 2 * (as.numeric(fw$emb[cs$mask, , drop = FALSE] %*% w_head + b_head) -
               cs$y) / sum(cs$mask)
  g_emb <- matrix(0, cs$g$n, emb_dim)
  g_emb[cs$mask, ] <- outer(gy, w_head)
  bw <- edaphos:::.gat_backward_all(fw$caches, g_emb, cs$n_layers,
                                    cs$n_heads, cs$hidden)

  h <- 1e-5
  fd <- function(setter, i) {
    lp <- loss_of(setter(i, +h)$Wl, setter(i, +h)$al)
    lm <- loss_of(setter(i, -h)$Wl, setter(i, -h)$al)
    (lp - lm) / (2 * h)
  }
  ok <- TRUE
  for (l in seq_len(cs$n_layers)) for (hh in seq_len(cs$n_heads)) {
    for (nm in c("W", "a_l", "a_r")) {
      ana <- if (nm == "W") bw$g_W[[l]][[hh]] else bw$g_a[[l]][[hh]][[nm]]
      # the largest entry plus a few random ones
      idx <- unique(c(which.max(abs(ana)),
                      sample(length(ana), min(4L, length(ana)))))
      setter <- function(i, delta) {
        W2 <- cs$Wl; a2 <- cs$al
        if (nm == "W") W2[[l]][[hh]][i] <- W2[[l]][[hh]][i] + delta
        else a2[[l]][[hh]][[nm]][i] <- a2[[l]][[hh]][[nm]][i] + delta
        list(Wl = W2, al = a2)
      }
      num <- vapply(idx, function(i) fd(setter, i), numeric(1))
      ok <- ok && grad_agrees(ana[idx], num)
    }
  }
  ok
}

test_that("GAT gradients match central finite differences (heads concatenated)", {
  expect_true(check_config(residual = FALSE, average_heads = FALSE))
  expect_true(check_config(residual = TRUE,  average_heads = FALSE))
})

test_that("GAT gradients match central finite differences (heads averaged)", {
  expect_true(check_config(residual = FALSE, average_heads = TRUE))
  expect_true(check_config(residual = TRUE,  average_heads = TRUE))
})

test_that("training the attention actually reduces the loss", {
  # The target must carry LEARNABLE structure.  With pure noise the honest
  # answer is "stop at epoch 1", early stopping returns the initialisation,
  # and asserting that the parameters moved would be asserting that the
  # optimiser overfits.  Build a target that depends on the node features.
  cs <- make_case(n = 80L)
  X <- cs$g$features
  set.seed(3L)
  y_full <- as.numeric(X %*% c(2, -1.5, 0.5)) + stats::rnorm(nrow(X), 0, 0.3)
  y <- rep(NA_real_, cs$g$n)
  y[cs$mask] <- y_full[cs$mask]

  fit <- gnn_fit(cs$g, y, train_mask = cs$mask, hidden = 4L, n_heads = 2L,
                 n_layers = 2L, epochs = 120L, lr = 0.02, seed = 3L)
  expect_true(length(fit$history) > 1L)
  expect_lt(min(fit$history), fit$history[1L])

  # The attention parameters must have MOVED: the v3.10.0 backend left them at
  # their random initialisation and fitted only the head.
  fit0 <- gnn_fit(cs$g, y, train_mask = cs$mask, hidden = 4L, n_heads = 2L,
                  n_layers = 2L, epochs = 1L, lr = 0.02, seed = 3L)
  expect_gt(fit$best_epoch, 1L)
  expect_false(isTRUE(all.equal(fit$W_list, fit0$W_list)))
  expect_false(isTRUE(all.equal(fit$a_list, fit0$a_list)))

  # and training must beat the intercept on the held-out nodes
  truth <- y_full[!cs$mask]
  null_p <- rep(mean(y_full[cs$mask]), sum(!cs$mask))
  nse_fit <- 1 - sum((truth - predict(fit)[!cs$mask])^2) /
                 sum((truth - null_p)^2)
  expect_gt(nse_fit, 0)
})

test_that("held-out targets never influence the fit", {
  cs <- make_case(n = 60L)
  y_a <- y_b <- rep(NA_real_, cs$g$n)
  set.seed(4L)
  obs <- stats::rnorm(sum(cs$mask))
  y_a[cs$mask] <- obs; y_b[cs$mask] <- obs
  y_b[!cs$mask] <- 999                      # absurd values on held-out nodes
  fa <- gnn_fit(cs$g, y_a, train_mask = cs$mask, epochs = 20L, seed = 8L)
  fb <- gnn_fit(cs$g, y_b, train_mask = cs$mask, epochs = 20L, seed = 8L)
  expect_equal(fa$W_head, fb$W_head)
  expect_equal(fa$y_mu, fb$y_mu)
  expect_equal(predict(fa), predict(fb))
})
