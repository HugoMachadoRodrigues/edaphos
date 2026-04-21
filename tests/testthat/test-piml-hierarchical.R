skip_if_no_torch <- function() {
  skip_if_not_installed("torch")
  tryCatch(torch::torch_tensor(1), error = function(e) skip("torch runtime unavailable"))
}

make_hier_dataset <- function(n_pedons = 8L, seed = 1L) {
  set.seed(seed)
  pedons <- list()
  for (i in seq_len(n_pedons)) {
    elev   <- stats::runif(1, 100, 800)
    clim   <- stats::runif(1, 500, 1800)
    # Covariate-driven y0 and y_inf: higher clim -> higher surface SOC,
    # higher elev -> higher y_inf (parent-material proxy).
    y0 <- 10 + 0.02 * clim + stats::rnorm(1, 0, 1)
    y_inf <- 3 + 0.005 * elev + stats::rnorm(1, 0, 0.5)
    depths <- c(5, 15, 30, 60, 100)
    true <- y_inf + (y0 - y_inf) * exp(-0.03 * depths)
    vals <- true + stats::rnorm(length(depths), 0, 0.3)
    pedons[[i]] <- data.frame(
      id = paste0("p", i), depth = depths, soc = vals,
      elev = elev, clim = clim
    )
  }
  do.call(rbind, pedons)
}

test_that("piml_hierarchical_fit converges and predicts new pedons", {
  skip_if_no_torch()
  d <- make_hier_dataset(n_pedons = 10L, seed = 4L)
  fit <- piml_hierarchical_fit(
    d, id_col = "id", depth_col = "depth", value_col = "soc",
    covariate_cols = c("elev", "clim"),
    hidden = c(16L, 16L), y0_hidden = c(8L),
    epochs = 300L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  expect_s3_class(fit, "edaphos_piml_hierarchical")
  expect_lt(fit$final_loss, fit$loss_history[1] * 0.6)

  new_covs <- data.frame(elev = c(200, 600), clim = c(700, 1500))
  profiles <- piml_hierarchical_predict(fit, new_covs,
                                         newdepths = c(5, 30, 100))
  expect_equal(dim(profiles), c(2L, 3L))
  expect_true(all(is.finite(profiles)))
})

test_that("al_physics_gate_piml_hierarchical builds per-location envelopes", {
  skip_if_no_torch()
  d <- make_hier_dataset(n_pedons = 8L, seed = 5L)
  fit <- piml_hierarchical_fit(
    d, id_col = "id", depth_col = "depth", value_col = "soc",
    covariate_cols = c("elev", "clim"),
    epochs = 200L, lr = 0.02, seed = 1L, verbose = FALSE
  )
  gate <- al_physics_gate_piml_hierarchical(fit, safety_factor = 1.2)
  expect_true(is.function(gate))

  candidates <- data.frame(
    id = paste0("c", 1:5),
    elev = c(150, 300, 500, 700, 900),
    clim = c(700, 900, 1200, 1500, 1700)
  )
  # Use realistic predicted means inside the likely envelope
  mask <- gate(candidates, predicted_mean = c(12, 15, 18, 20, 22))
  expect_length(mask, 5L)
  expect_true(any(mask))
  # Extreme predictions must be rejected
  mask_out <- gate(candidates, predicted_mean = c(-100, -100, -100, -100, -100))
  expect_true(all(!mask_out))
})

test_that("print.edaphos_piml_hierarchical works", {
  skip_if_no_torch()
  d <- make_hier_dataset(n_pedons = 4L, seed = 2L)
  fit <- piml_hierarchical_fit(
    d, id_col = "id", depth_col = "depth", value_col = "soc",
    covariate_cols = c("elev", "clim"),
    epochs = 30L, lr = 0.02, seed = 1L
  )
  expect_output(print(fit), "piml_hierarchical")
})
