## Snapshot tests for the package's print() and summary() S3 methods.
##
## A print method that silently drops a number, swaps two labels or prints
## a value under the wrong name passes every expect_output(print(x), "<class>")
## check in the suite. These snapshots pin what each method actually writes.
##
## Platform stability. Numbers that come out of closed-form computations
## (lm / 2SLS / partial correlations, kernels, seeded draws summarised by
## mean / sd / quantile) are pinned verbatim. Numbers that come out of an
## iterative fit (Gibbs / Metropolis chains, Adam, optim, optimize) can move
## in their trailing digits between BLAS / libm builds, so those snapshots go
## through `.sig()`, which rounds every decimal number to a few significant
## figures and collapses padding (a %-9.4g field changes width when %g drops
## a trailing zero). Labels, counts, integers and warning branches are still
## pinned exactly. Random forests (ranger) are the exception: libc++ and
## libstdc++ implement std::uniform_int_distribution differently, so the
## forest itself differs between macOS and Linux and its error estimates are
## masked outright with `.mask_dbl()`.
##
## Fits run without torch, Python or the network (`backend = "r"` wherever a
## function takes a backend). Classes whose only constructor needs torch or
## Python/Qiskit are snapshotted from hand-built objects at the bottom of the
## file, with exactly the fields their constructor sets.

# A decimal number not glued to an identifier (so "q97.5" stays a label).
.num_rx <- "(?<![[:alnum:]_.])[-+]?(?:[0-9]+\\.[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"

.squeeze <- function(lines) gsub("(?<=\\S) {2,}", " ", lines, perl = TRUE)

# Round every decimal number in the output to `digits` significant figures.
.sig <- function(digits) {
  force(digits)
  function(lines) {
    m <- gregexpr(.num_rx, lines, perl = TRUE)
    regmatches(lines, m) <- lapply(regmatches(lines, m), function(v) {
      if (!length(v)) return(v)
      as.character(signif(as.numeric(v), digits))
    })
    .squeeze(lines)
  }
}

# Replace every decimal number with a placeholder.
.mask_dbl <- function(lines) {
  .squeeze(gsub(.num_rx, "<dbl>", lines, perl = TRUE))
}

.quiet <- function(expr) suppressWarnings(suppressMessages(expr))

# ---------------------------------------------------------------------------
# Pillar 1 -- causal
# ---------------------------------------------------------------------------

test_that("print.edaphos_causal_effect", {
  skip_if_not_installed("dagitty")
  data(br_cerrado, package = "edaphos", envir = environment())
  direct <- .quiet(causal_estimate_effect(br_cerrado, causal_cerrado_dag(),
                                          exposure = "ndvi", outcome = "soc"))
  expect_snapshot(print(direct))

  prof <- .quiet(edaphos_example_profiles())
  total <- .quiet(causal_estimate_effect(prof, causal_cerrado_real_dag(),
                                         "soilgrids_clay", "soc_topsoil_gkg",
                                         effect = "total"))
  expect_snapshot(print(total))
})

test_that("print.edaphos_causal_iv", {
  set.seed(42L)
  n <- 200L
  Z <- matrix(stats::rnorm(n * 3L), n, 3L,
              dimnames = list(NULL, paste0("Z", 1:3)))
  U <- stats::rnorm(n)
  X <- 0.7 * Z[, 1] + 0.5 * Z[, 2] + 0.4 * Z[, 3] + 0.6 * U +
    stats::rnorm(n, sd = 0.5)
  Y <- 1.5 * X + 0.8 * U + stats::rnorm(n, sd = 0.5)
  df <- data.frame(Y = Y, X = X, Z, W = stats::rnorm(n))
  # over-identified with a covariate: prints the covariates and Sargan lines
  over <- .quiet(causal_iv_fit_2sls(df, "X", "Y", c("Z1", "Z2", "Z3"),
                                    covariates = "W"))
  expect_snapshot(print(over))
  # just-identified: no Sargan line
  just <- .quiet(causal_iv_fit_2sls(df, "X", "Y", "Z1"))
  expect_snapshot(print(just))
})

test_that("print.edaphos_dag_test", {
  skip_if_not_installed("dagitty")
  prof <- .quiet(edaphos_example_profiles())
  tst <- .quiet(causal_dag_test(causal_cerrado_real_dag(), prof))
  expect_snapshot(print(tst))
})

test_that("print/summary.edaphos_causal_kg and print.edaphos_causal_kg_summary", {
  skip_if_not_installed("igraph")
  kg <- causal_kg_new()
  kg <- causal_kg_add_edge(kg, "precip", "soc", source = "A", confidence = 0.7)
  kg <- causal_kg_add_edge(kg, "precip", "soc", source = "B", confidence = 0.6)
  kg <- causal_kg_add_edge(kg, "clay", "soc", source = "A", confidence = 0.9)
  kg <- causal_kg_add_edge(kg, "precip", "clay", source = "A",
                           confidence = 0.5)
  expect_snapshot(print(kg))
  expect_snapshot(summary(kg))

  empty <- causal_kg_new()
  expect_snapshot(print(empty))
  expect_snapshot(summary(empty))
})

test_that("print.edaphos_causal_4d", {
  set.seed(1L)
  grid <- expand.grid(t = 1:30, cell = 1:10)
  grid$z   <- stats::rnorm(nrow(grid))
  grid$map <- 0.3 * grid$z + stats::rnorm(nrow(grid))
  grid$soc <- 0.05 * grid$t * grid$map + 0.5 * grid$z +
    stats::rnorm(nrow(grid), 0, 0.3)
  res <- .quiet(causal_effect_time_varying(grid, NULL, exposure = "map",
                                           outcome = "soc", window = 10L,
                                           step = 5L, adjustment = "z",
                                           B = 20L, seed = 1L))
  expect_snapshot(print(res))
})

test_that("print.edaphos_causal_al_query", {
  skip_if_not_installed("dagitty")
  set.seed(1L)
  d <- data.frame(x = stats::rnorm(50), z = stats::rnorm(50))
  d$y <- 0.8 * d$x + 0.4 * d$z + stats::rnorm(50, 0, 0.3)
  pool <- data.frame(x = stats::rnorm(8), z = stats::rnorm(8), y = NA_real_)
  q <- .quiet(al_query_causal(d, pool,
                              dagitty::dagitty("dag { z -> x ; z -> y ; x -> y }"),
                              exposure = "x", outcome = "y", adjustment = "z",
                              n_select = 3L, strategy = "leverage"))
  expect_snapshot(print(q))
})

# ---------------------------------------------------------------------------
# Validation / uncertainty containers
# ---------------------------------------------------------------------------

test_that("print.edaphos_spatial_folds", {
  data(br_cerrado, package = "edaphos", envir = environment())
  xy <- br_cerrado[seq(1, nrow(br_cerrado), by = 25), c("x", "y")]
  buffered <- .quiet(spatial_block_folds(xy, k = 5, buffer_km = 10, seed = 1))
  expect_snapshot(print(buffered))
  # buffer_km = 0 adds the unbuffered-blocking NOTE
  unbuffered <- .quiet(spatial_block_folds(xy, k = 5, buffer_km = 0, seed = 1))
  expect_snapshot(print(unbuffered))
})

test_that("print/summary.edaphos_posterior", {
  set.seed(1L)
  post <- edaphos_posterior(samples = matrix(stats::rnorm(200 * 3), 200, 3),
                            method = "ensemble", query_type = "map",
                            units = "g/kg")
  expect_snapshot(print(post))
  expect_snapshot(summary(post))

  set.seed(2L)
  gauss <- edaphos_posterior(mean = c(1, 2), sd = c(0.1, 0.2),
                             epistemic_sd = c(0.08, 0.1),
                             aleatoric_sd = c(0.06, 0.17),
                             method = "gaussian", query_type = "param")
  expect_snapshot(print(gauss))
})

# ---------------------------------------------------------------------------
# Pillar 5 -- active learning
# ---------------------------------------------------------------------------

test_that("print/summary.edaphos_al_model", {
  set.seed(1L)
  n <- 40L
  d <- data.frame(x = stats::runif(n, 0, 100), y = stats::runif(n, 0, 100))
  d$elev <- 50 + 0.2 * d$x + stats::rnorm(n, 0, 2)
  d$dist <- sqrt((d$x - 50)^2 + (d$y - 50)^2) / 70
  d$lead <- 40 + 180 * exp(-d$dist * 2) + 0.3 * d$elev +
    stats::rnorm(n, 0, 5)
  m <- .quiet(al_fit(d[1:25, ], "lead", c("dist", "elev"),
                     coords = c("x", "y"), num.trees = 100L, seed = 1L))
  m <- .quiet(al_update(m, d[26:30, ]))
  # ranger's forest differs between C++ standard libraries: mask its errors
  expect_snapshot(print(m), transform = .mask_dbl)
  expect_snapshot(summary(m), transform = .mask_dbl)
})

# ---------------------------------------------------------------------------
# Pillar 3 -- temporal
# ---------------------------------------------------------------------------

test_that("print.edaphos_temporal_kalman", {
  set.seed(1L)
  fc <- array(stats::rnorm(20 * 6 * 6), dim = c(20, 6, 6))
  ku <- .quiet(temporal_kalman_update(fc, obs_value = 3, obs_row = 3L,
                                      obs_col = 3L, obs_sd = 0.1, seed = 1L))
  expect_snapshot(print(ku))
})

test_that("print.edaphos_temporal_al_query", {
  # al_query_temporal() needs per-cell gain / sd maps; temporal_kalman_update()
  # returns gain_row_norm per observation, so build the per-cell input here
  # (as test-temporal-active-learning.R does).
  set.seed(1L)
  ku <- structure(list(gain_row_norm = matrix(stats::runif(16), 4L, 4L),
                       analysis_sd   = matrix(stats::runif(16), 4L, 4L)),
                  class = "edaphos_temporal_kalman")
  q <- .quiet(al_query_temporal(ku, n_select = 4L, combine = "gain"))
  expect_snapshot(print(q))
})

# ---------------------------------------------------------------------------
# Pillar 2 -- physics-informed profiles
# ---------------------------------------------------------------------------

.pz <- c(5, 15, 30, 60, 100)
.py <- c(25, 18, 12, 8, 6.5)

test_that("print.edaphos_piml_profile", {
  fit <- .quiet(piml_profile_fit(.pz, .py))
  expect_snapshot(print(fit), transform = .sig(3L))
  # a non-monotone profile adds the out-of-scope NOTE
  bulge <- .quiet(piml_profile_fit(.pz, c(12, 16, 14, 9, 7)))
  expect_snapshot(print(bulge), transform = .sig(3L))
})

test_that("print.edaphos_piml_mech", {
  fit <- .quiet(piml_profile_fit_mechanistic(.pz, .py))
  expect_snapshot(print(fit), transform = .sig(3L))
})

test_that("print/summary.edaphos_piml_bayes", {
  lap <- .quiet(piml_profile_fit_bayesian(.pz, .py, method = "laplace",
                                          seed = 1L))
  expect_snapshot(print(lap), transform = .sig(3L))
  expect_snapshot(summary(lap), transform = .sig(3L))
  # a deliberately short chain: pins the NOT CONVERGED branch
  mc <- .quiet(piml_profile_fit_bayesian(.pz, .py, method = "mcmc",
                                         n_iter = 600L, n_burn = 200L,
                                         n_chains = 2L, seed = 1L))
  expect_snapshot(print(mc), transform = .sig(3L))
})

# ---------------------------------------------------------------------------
# Pillar 6 -- quantum kernels (pure-R statevector path)
# ---------------------------------------------------------------------------

test_that("print.edaphos_quantum_krr", {
  set.seed(1L)
  X <- quantum_scale(matrix(stats::rnorm(20 * 2), 20, 2))
  y <- stats::rnorm(20)
  fit <- .quiet(quantum_krr_fit(X, y, reps = 1L, lambda = 0.2))
  expect_snapshot(print(fit))
})

test_that("print.edaphos_qf_krr", {
  set.seed(1L)
  emb <- matrix(stats::rnorm(30 * 5), 30, 5)
  fit <- .quiet(qf_krr_fit(emb, stats::rnorm(30), n_pcs = 3L, reps = 1L,
                           lambda = 0.1))
  expect_snapshot(print(fit))
})

test_that("print.edaphos_piml_qkrr", {
  z <- seq(5, 150, length.out = 12)
  y <- 5 + 23 * exp(-0.015 * z)
  X <- quantum_scale(cbind(z / 150, y / 30))
  fit <- .quiet(piml_qkrr_fit(X, y, z,
                              list(lambda0 = 0.015, mu = -0.01, y_inf = 5,
                                   y0 = 28),
                              alpha = 0.5, reps = 1L, lambda = 0.1,
                              backend = "r"))
  expect_snapshot(print(fit))
})

# ---------------------------------------------------------------------------
# Pillar 10 -- graph attention
# ---------------------------------------------------------------------------

.snap_graph <- function() {
  set.seed(3L)
  d <- data.frame(lon = stats::runif(24, -50, -48),
                  lat = stats::runif(24, -16, -14),
                  x1 = stats::rnorm(24), x2 = stats::rnorm(24))
  d$y <- 1.5 * d$x1 - d$x2 + stats::rnorm(24, 0, 0.3)
  list(g = gnn_build_graph(d, k = 4L, feature_cols = c("x1", "x2")), y = d$y)
}

test_that("print.edaphos_gnn_graph", {
  s <- .quiet(.snap_graph())
  expect_snapshot(print(s$g))
})

test_that("print.edaphos_gnn_gat, edaphos_gnn_ensemble, edaphos_qf_krr_gat", {
  s <- .quiet(.snap_graph())
  fit <- .quiet(gnn_fit(s$g, s$y, hidden = 4L, n_heads = 1L, n_layers = 1L,
                        epochs = 10L, seed = 1L, backend = "r"))
  expect_snapshot(print(fit), transform = .sig(3L))

  ens <- .quiet(gnn_fit_ensemble(s$g, s$y, n_ensemble = 2L, seed = 1L,
                                 hidden = 4L, n_heads = 1L, n_layers = 1L,
                                 epochs = 5L, backend = "r"))
  expect_snapshot(print(ens), transform = .sig(3L))

  qk <- .quiet(qf_krr_on_gat_embeddings(fit, s$y, n_pcs = 3L, reps = 1L,
                                        lambda = 0.5))
  expect_snapshot(print(qk))
})

# ---------------------------------------------------------------------------
# Pillar 8 -- neural operators (pure-R backend)
# ---------------------------------------------------------------------------

.snap_operator_data <- function() {
  set.seed(1L)
  depths <- seq(5, 120, length.out = 6)
  cov <- matrix(stats::rnorm(8 * 2), 8, 2)
  targets <- t(apply(cov, 1L, function(c)
    (10 + 5 * c[1]) * exp(-(0.02 + 0.005 * c[2]) * depths)))
  list(depths = depths, cov = cov, targets = targets)
}

test_that("print.edaphos_no_deeponet and edaphos_al_neural_operator_query", {
  d <- .snap_operator_data()
  fit <- .quiet(no_deeponet_fit(d$depths, d$targets, d$cov,
                                branch_hidden = 4L, trunk_hidden = 4L,
                                output_dim = 2L, epochs = 10L, seed = 1L,
                                backend = "r"))
  expect_snapshot(print(fit), transform = .sig(3L))

  ode <- structure(list(params = list(lambda0 = 0.02, mu = 0, y_inf = 4,
                                      y0 = 20)),
                   class = "edaphos_piml_profile")
  q <- .quiet(al_query_neural_operator(fit, ode, d$cov, n_select = 2L,
                                       n_pert = 2L, seed = 1L))
  expect_snapshot(print(q), transform = .sig(3L))
})

test_that("print.edaphos_no_fno", {
  d <- .snap_operator_data()
  cov_dep <- array(rep(d$cov[, 1], length(d$depths)),
                   dim = c(nrow(d$cov), length(d$depths), 1L))
  fit <- .quiet(no_fno_fit(d$depths, d$targets, cov_dep, n_modes = 2L,
                           width = 4L, n_blocks = 1L, epochs = 5L, seed = 1L,
                           backend = "r"))
  expect_snapshot(print(fit), transform = .sig(3L))
})

# ---------------------------------------------------------------------------
# Pillar 9 -- diffusion (pure-R backend)
# ---------------------------------------------------------------------------

test_that("print.edaphos_dm_fit and edaphos_al_diffusion_query", {
  set.seed(1L)
  patches <- array(stats::rnorm(4 * 6 * 6), dim = c(4, 6, 6))
  fit <- .quiet(dm_fit(patches, T = 4L, epochs = 2L, hidden = 4L, lr = 0.05,
                       seed = 1L, backend = "r"))
  expect_snapshot(print(fit), transform = .sig(3L))
  q <- .quiet(al_query_diffusion(fit, n_samples = 3L, n_select = 3L,
                                 seed = 1L))
  expect_snapshot(print(q), transform = .sig(3L))
})

# ---------------------------------------------------------------------------
# Pillar 7 -- Bayesian hierarchical spatial
# ---------------------------------------------------------------------------

test_that("print.edaphos_bhs and edaphos_al_bhs_query", {
  set.seed(1L)
  n <- 30L
  d <- data.frame(x = stats::rnorm(n), lon = stats::runif(n, -50, -48),
                  lat = stats::runif(n, -16, -14))
  d$y <- 2 * d$x + stats::rnorm(n, 0, 0.5)
  # no spatial signal in y, so phi rails: pins the railed-phi warning branch
  fit <- .quiet(bhs_fit(d, y ~ x, c("lon", "lat"), nmcmc = 100L, burn = 50L,
                        seed = 1L, phi_range = c(0.1, 10)))
  expect_snapshot(print(fit), transform = .sig(3L))

  set.seed(2L)
  pool <- data.frame(x = stats::rnorm(5), lon = stats::runif(5, -49.9, -48.1),
                     lat = stats::runif(5, -15.9, -14.1))
  q <- .quiet(al_query_bhs(fit, pool, n_select = 3L, n_draws = 20L))
  expect_snapshot(print(q), transform = .sig(3L))
})

# ---------------------------------------------------------------------------
# Pillar 4 -- foundation tiles (terra, no torch)
# ---------------------------------------------------------------------------

test_that("print.edaphos_tile_dataset", {
  skip_if_not_installed("terra")
  set.seed(1L)
  r <- terra::rast(nrows = 20, ncols = 20, nlyrs = 2,
                   vals = stats::rnorm(800))
  names(r) <- c("a", "b")
  td <- .quiet(foundation_tile_dataset(r, patch_size = 4L, n_patches = 10L,
                                       seed = 1L))
  expect_snapshot(print(td))
})

# ---------------------------------------------------------------------------
# Classes whose constructors need torch or Python/Qiskit.
#
# The print methods below only format scalar fields, so they are pinned on
# hand-built objects carrying exactly the fields (and attributes) their
# constructor sets -- see the structure() call cited for each. If a
# constructor renames a field, update the object here as well.
# ---------------------------------------------------------------------------

test_that("print.edaphos_foundation_classifier (fields: foundation_fit_classifier)", {
  x <- structure(list(classes = c("Ferralsol", "Acrisol", "Arenosol"),
                      feature_dim = 64L, head_type = "mlp",
                      freeze_backbone = TRUE,
                      loss_history = c(1.1, 0.8, 0.61),
                      val_accuracy_history = c(0.5, NA, 0.72),
                      device = "cpu"),
                 class = "edaphos_foundation_classifier")
  expect_snapshot(print(x))
  x$freeze_backbone <- FALSE
  x$val_accuracy_history <- c(NA_real_, NA_real_, NA_real_)
  expect_snapshot(print(x))
})

test_that("print.edaphos_foundation_regressor (fields: foundation_fit_regressor)", {
  x <- structure(list(feature_dim = 64L, head_type = "linear",
                      freeze_backbone = FALSE, y_mean = 21.5, y_sd = 7.25,
                      loss_fn = "huber", loss_history = c(0.9, 0.4, 0.35),
                      val_rmse_history = c(NA, 0.6, 0.55), device = "mps"),
                 class = "edaphos_foundation_regressor")
  expect_snapshot(print(x))
})

test_that("print.edaphos_foundation_ensemble (fields: foundation_finetune_ensemble)", {
  x <- structure(list(task = "regression", K_ens = 3L,
                      final_losses = c(0.31, 0.27, 0.4)),
                 class = "edaphos_foundation_ensemble")
  expect_snapshot(print(x))
})

test_that("print.edaphos_foundation_moco (fields: foundation_moco_pretrain)", {
  x <- structure(list(in_channels = 6L, feature_dim = 128L, proj_dim = 64L,
                      queue_size = 4096L, momentum = 0.999,
                      temperature = 0.2, batch_size = 64L,
                      loss_history = c(8.1, 7.4, 6.9), final_loss = 6.9),
                 class = "edaphos_foundation_moco")
  expect_snapshot(print(x))
})

test_that("print.edaphos_foundation_simclr (fields: foundation_simclr_pretrain)", {
  x <- structure(list(in_channels = 6L, feature_dim = 128L, proj_dim = 64L,
                      batch_size = 32L, temperature = 0.5,
                      loss_history = c(4.2, 3.9), final_loss = 3.9),
                 class = "edaphos_foundation_simclr")
  expect_snapshot(print(x))
})

test_that("print.edaphos_piml_hierarchical (fields: piml_hierarchical_fit)", {
  x <- structure(list(n_pedons = 40L, covariate_cols = c("clay", "map_mm"),
                      loss_history = c(1.2, 0.5, 0.21), final_loss = 0.21),
                 class = "edaphos_piml_hierarchical")
  expect_snapshot(print(x))
})

test_that("print.edaphos_piml_neural_ode (fields: piml_neural_ode_fit)", {
  x <- structure(list(hidden = c(16L, 16L), depths = c(5, 15, 30, 60, 100),
                      rmse = 0.42, loss_history = c(0.9, 0.05, 0.012)),
                 class = "edaphos_piml_neural_ode")
  expect_snapshot(print(x))
})

test_that("print.edaphos_piml_neural_ode_ensemble (fields: piml_neural_ode_fit_ensemble)", {
  x <- structure(list(K = 5L, hidden = c(16L, 16L),
                      depths = c(5, 15, 30, 60, 100), rmse = 0.38,
                      fitted_sd = c(0.1, 0.25, 0.4, 0.8, 1.6)),
                 class = "edaphos_piml_neural_ode_ensemble")
  expect_snapshot(print(x))
})

test_that("print.edaphos_temporal_convlstm (fields: temporal_convlstm_fit)", {
  x <- structure(list(input_dim = 3L, hidden_dims = c(8L, 4L),
                      kernel_size = 3L, return_sequence = FALSE,
                      loss_history = c(0.5, 0.2, 0.11), final_loss = 0.11),
                 class = "edaphos_temporal_convlstm")
  expect_snapshot(print(x))
})

test_that("print.edaphos_temporal_convlstm_ensemble (fields: temporal_convlstm_ensemble_fit)", {
  x <- structure(list(K_ens = 4L, final_losses = c(0.12, 0.1, 0.15, 0.11),
                      config = list(hidden_dims = c(8L, 4L))),
                 class = "edaphos_temporal_convlstm_ensemble")
  expect_snapshot(print(x))
})

.mock_hamiltonian <- function() {
  # 9 terms, so the "... more term(s)" line is exercised
  terms <- c(IIII = -0.81, ZIII = 0.17, IZII = -0.22, IIZI = 0.17,
             IIIZ = -0.22, ZZII = 0.12, XXYY = 0.045, YYXX = 0.045,
             ZIZI = 0.165)
  structure(list(op = NULL, pauli_terms = terms, n_qubits = 4L),
            class = "edaphos_quantum_hamiltonian")
}

test_that("print.edaphos_quantum_hamiltonian (fields: quantum_hamiltonian)", {
  expect_snapshot(print(.mock_hamiltonian()))
})

test_that("print.edaphos_quantum_hamiltonian_nature (attrs: quantum_hamiltonian_from_pyscf)", {
  h <- .mock_hamiltonian()
  attr(h, "nuclear_repulsion_energy") <- 0.719969
  attr(h, "frozen_core_shift")        <- 0
  attr(h, "active_space_shift")       <- -0.5
  attr(h, "reference_energy")         <- -1.116759
  attr(h, "num_particles")            <- c(1L, 1L)
  attr(h, "num_spatial_orbitals")     <- 2L
  attr(h, "basis")  <- "sto3g"
  attr(h, "mapper") <- "parity"
  class(h) <- c("edaphos_quantum_hamiltonian_nature", class(h))
  expect_snapshot(print(h))
  # a preset sets the variant; missing particle counts print as "?"
  attr(h, "variant") <- "methanediol"
  attr(h, "num_particles") <- c(NA_integer_, NA_integer_)
  expect_snapshot(print(h))
})

test_that("print.edaphos_quantum_vqe (fields: quantum_vqe_fit)", {
  x <- structure(list(hamiltonian = .mock_hamiltonian(), ansatz_reps = 2L,
                      optimizer = "COBYLA", backend = "aer_statevector",
                      shots = NULL, mitigation = NULL, ibmq_backend = NULL,
                      energy = -1.137270, exact = -1.137306,
                      gap = abs(-1.137270 - -1.137306),
                      parameters = rep(0.1, 16L), n_iter = 214L),
                 class = "edaphos_quantum_vqe")
  expect_snapshot(print(x))
  x$backend <- "ibmq"; x$shots <- 4000; x$mitigation <- "twirling"
  x$ibmq_backend <- "ibm_brisbane"; x$n_iter <- NA_integer_
  expect_snapshot(print(x))
})

test_that("print.edaphos_quantum_ibmq_job (fields: quantum_ibmq_submit)", {
  x <- structure(list(job_id = "job-0001", backend = "ibm_brisbane",
                      expectation = -1.1203, std_error = 0.0042,
                      shots = 4000L, mitigation = "none", metadata = list()),
                 class = "edaphos_quantum_ibmq_job")
  expect_snapshot(print(x))
})
