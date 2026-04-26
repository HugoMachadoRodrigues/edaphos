# Benchmark helpers for the v3.1.0 6-pilar head-to-head on WoSIS
# topsoil SOC regression.  Each wrapper returns an `edaphos_posterior`
# consumable by `uncertainty_calibrate()`.
#
# These helpers are used by `data-raw/benchmark_wosis_6pilar.R`.  They
# are EXPORTED so that users reproducing the benchmark on their own
# regional subset can call them directly, and so that downstream
# consumers can validate that their input frames satisfy the
# structural requirements (response column `soc`, coord columns `lon`,
# `lat`, and the requested covariates).
#
# Reasons for not including every pilar:
#   P2 -- targets depth-profile dynamics, not topsoil scalar regression.
#   P3 -- targets time-stacked raster cubes.
#   P8 -- parameterised over a depth function space.
#   P9 -- generates raster patches; no natural point-regression readout.
# Each has its own task-appropriate benchmark in the corresponding
# vignette.

# ---------------------------------------------------------------------------
# Helpers (v3.4.0)
# ---------------------------------------------------------------------------
#
# Predictive-posterior calibration helper.  The bootstrap- and seed-
# ensemble posteriors of P1/P6/P10 in v3.1.0 carry only EPISTEMIC
# uncertainty (the spread of predictive means under different model
# fits) and consequently UNDER-COVER honest 90 % intervals (PICP
# 0.07 - 0.25 in the v3.1.0 benchmark).  v3.4.0 adds the missing
# ALEATORIC term: an estimate of the in-sample residual standard
# deviation `sigma_resid` is injected as iid Gaussian noise on every
# (sample, test-row) entry of the posterior matrix, so the
# resulting posterior covers BOTH model-fit uncertainty AND
# irreducible noise.  PICP at the v3.1.0 head-to-head settings
# moves from ~0.20 to ~0.85, matching P4/P5/P7.
.bench_inject_aleatoric <- function(pred_mat, sigma_resid, seed = NULL) {
  if (!is.finite(sigma_resid) || sigma_resid <= 0) return(pred_mat)
  if (!is.null(seed)) set.seed(seed + 13579L)
  noise <- matrix(stats::rnorm(length(pred_mat), 0, sigma_resid),
                    nrow(pred_mat), ncol(pred_mat))
  pred_mat + noise
}

# Estimate `sigma_resid` from training residuals of a single point-
# predictor fit.  We deliberately use the FULL training set (not a
# bootstrap resample) so the noise estimate is not contaminated by
# the very ensemble it is meant to complement.
.bench_residual_sd <- function(y_obs, y_hat) {
  resid <- as.numeric(y_obs) - as.numeric(y_hat)
  resid <- resid[is.finite(resid)]
  if (length(resid) < 2L) return(0)
  stats::sd(resid)
}

#' Benchmark wrapper: Pilar 1 -- DAG-adjusted OLS + parametric bootstrap
#'
#' Restricts OLS to covariates that appear in the supplied DAG as
#' direct parents of the outcome (falling back to the full covariate
#' set when the DAG has no matching variables) and generates a
#' parametric-bootstrap predictive posterior.  Intended for the
#' v3.1.0 WoSIS head-to-head; the exported API is stable enough for
#' use on any regional subset that follows the same schema.
#'
#' @param train,test Data frames with a response column `soc`, coord
#'   columns `lon`/`lat`, and the columns listed in `cov_cols`.
#' @param cov_cols Character vector of candidate covariate names.
#' @param dag A `dagitty` DAG object (or `NULL` to use the full
#'   covariate set).
#' @param n_boot Number of bootstrap resamples.  Default `300`.
#' @param seed Optional RNG seed.
#' @param calibrate Logical (default `TRUE`).  When `TRUE`, an
#'   estimate of the in-sample residual standard deviation is added
#'   as iid Gaussian noise to every posterior sample so the
#'   predictive posterior carries BOTH epistemic (bootstrap-spread)
#'   AND aleatoric (residual) uncertainty.  Set to `FALSE` to
#'   reproduce the v3.1.0 epistemic-only behaviour.
#' @return An `edaphos_posterior` with
#'   `method = "bootstrap"`, `query_type = "map"`.
#' @export
benchmark_fit_p1_causal <- function(train, test, cov_cols, dag = NULL,
                                        n_boot = 300L, seed = 1L,
                                        calibrate = TRUE) {
  stopifnot("soc" %in% names(train),
             all(cov_cols %in% names(train)),
             all(cov_cols %in% names(test)))
  in_dag <- cov_cols
  if (!is.null(dag) && requireNamespace("dagitty", quietly = TRUE)) {
    # Use generic names() which dispatches to the (internal) dagitty
    # method without requiring the symbol to be exported.
    dag_vars <- names(dag)
    # DAGs can be written with either the "friendly" WoSIS nickname
    # (e.g. `trees`) or the underlying SoilGrids / WorldClim variable
    # name (e.g. `wc_landcover_trees`).  Accept a covariate if EITHER
    # of its two forms appears in the DAG.
    aliasing <- c(
      map      = "wc_bio_12",
      mat      = "wc_bio_01",
      trees    = "wc_landcover_trees",
      cropland = "wc_landcover_cropland",
      grass    = "wc_landcover_grassland",
      clay     = "soilgrids_clay",
      sand     = "soilgrids_sand",
      bd       = "soilgrids_bdod"
    )
    keep <- vapply(cov_cols, function(cc) {
      alt <- aliasing[cc]
      cc %in% dag_vars || (!is.na(alt) && alt %in% dag_vars)
    }, logical(1L))
    in_dag <- cov_cols[keep]
    if (length(in_dag) < 2L) in_dag <- cov_cols
  }
  fml  <- stats::as.formula(paste("soc ~",
                                      paste(in_dag, collapse = " + ")))
  set.seed(seed)
  pred_mat <- matrix(NA_real_, nrow = n_boot, ncol = nrow(test))
  for (b in seq_len(n_boot)) {
    ix <- sample.int(nrow(train), nrow(train), replace = TRUE)
    lm_b <- stats::lm(fml, data = train[ix, ])
    pred_mat[b, ] <- stats::predict(lm_b, newdata = test)
  }
  # Aleatoric noise term: residual SD from a single full-data OLS
  # fit (uncontaminated by the bootstrap itself).
  sigma_resid <- 0
  if (isTRUE(calibrate)) {
    full_lm <- stats::lm(fml, data = train)
    sigma_resid <- .bench_residual_sd(train$soc, stats::fitted(full_lm))
    pred_mat <- .bench_inject_aleatoric(pred_mat, sigma_resid, seed = seed)
  }
  edaphos_posterior(samples = pred_mat, method = "bootstrap",
                      query_type = "map", units = "g/kg",
                      metadata = list(adjusted_features = in_dag,
                                        n_boot = n_boot,
                                        calibrate = calibrate,
                                        sigma_resid = sigma_resid))
}

#' Benchmark wrapper: Pilar 6 -- bootstrap-ensembled quantum KRR
#'
#' PCA-reduces the covariate matrix to `n_pcs` components rescaled to
#' `[-pi, pi]`, then trains `n_boot` quantum-kernel ridge regressors
#' on bootstrap resamples and aggregates their predictions into a
#' predictive posterior.
#'
#' @param train,test Data frames with `soc` + `cov_cols`.
#' @param cov_cols Character vector of covariate column names.
#' @param n_pcs Integer; number of PCs (= qubits).  Default `6L`.
#' @param reps Integer; ZZFeatureMap repetitions.  Default `2L`.
#' @param lambda Ridge regulariser.  Default `0.5`.
#' @param n_boot Integer; number of bootstrap KRR fits.  Default `20L`.
#' @param seed Optional RNG seed.
#' @param calibrate Logical (default `TRUE`).  When `TRUE`, residual
#'   noise from a full-data quantum-KRR fit is injected into every
#'   posterior sample (see Pilar-1 wrapper for the rationale).
#' @return An `edaphos_posterior` with
#'   `method = "ensemble"`, `query_type = "map"`.
#' @export
benchmark_fit_p6_quantum <- function(train, test, cov_cols,
                                         n_pcs = 6L, reps = 2L,
                                         lambda = 0.5, n_boot = 20L,
                                         seed = 1L,
                                         calibrate = TRUE) {
  stopifnot("soc" %in% names(train),
             all(cov_cols %in% names(train)),
             all(cov_cols %in% names(test)))
  set.seed(seed)
  X_tr <- as.matrix(train[, cov_cols, drop = FALSE])
  X_te <- as.matrix(test[,  cov_cols, drop = FALSE])
  y_tr <- as.numeric(train$soc)
  n_tr <- nrow(X_tr)
  red_all <- qf_embed_reduce(rbind(X_tr, X_te), n_pcs = n_pcs)
  Xq_tr <- red_all$X_q[seq_len(n_tr),          , drop = FALSE]
  Xq_te <- red_all$X_q[seq(n_tr + 1L, nrow(red_all$X_q)), , drop = FALSE]
  pred_mat <- matrix(NA_real_, nrow = n_boot, ncol = nrow(test))
  for (b in seq_len(n_boot)) {
    ix <- sample.int(n_tr, n_tr, replace = TRUE)
    fit <- quantum_krr_fit(Xq_tr[ix, , drop = FALSE], y_tr[ix],
                              reps = reps, lambda = lambda)
    pred_mat[b, ] <- stats::predict(fit, Xq_te)
  }
  sigma_resid <- 0
  if (isTRUE(calibrate)) {
    full_fit <- quantum_krr_fit(Xq_tr, y_tr, reps = reps, lambda = lambda)
    sigma_resid <- .bench_residual_sd(y_tr,
                                          stats::predict(full_fit, Xq_tr))
    pred_mat <- .bench_inject_aleatoric(pred_mat, sigma_resid, seed = seed)
  }
  edaphos_posterior(samples = pred_mat, method = "ensemble",
                      query_type = "map", units = "g/kg",
                      metadata = list(n_pcs = n_pcs, reps = reps,
                                        lambda = lambda, n_boot = n_boot,
                                        calibrate = calibrate,
                                        sigma_resid = sigma_resid))
}

#' Benchmark wrapper: Pilar 10 -- GAT seed-ensemble on k-NN graph
#'
#' Builds a joint k-NN co-location graph on `rbind(train, test)`
#' using (lon, lat) for adjacency and `cov_cols` as node features,
#' then fits `n_ensemble` independent GAT regressors with different
#' seeds, and harvests predictions at the test nodes.  Predictive
#' posterior is the seed ensemble.
#'
#' @param train,test Data frames with `soc`, `lon`, `lat`, and
#'   `cov_cols`.
#' @param cov_cols Character vector of covariate columns used as node
#'   features.
#' @param k Integer; k-NN degree of the co-location graph.
#' @param hidden,n_heads,n_layers Architecture.  See [`gnn_fit()`].
#' @param epochs,lr Training hyperparameters.
#' @param n_ensemble Integer; number of seed-distinct fits.
#' @param seed Base RNG seed (each member uses `seed + b`).
#' @param calibrate Logical (default `TRUE`).  When `TRUE`, residual
#'   noise from a representative full-data GAT fit is injected on
#'   every posterior sample (see Pilar-1 wrapper for the rationale).
#' @return An `edaphos_posterior` with
#'   `method = "ensemble"`, `query_type = "map"`.
#' @export
benchmark_fit_p10_gat <- function(train, test, cov_cols,
                                      k = 8L, hidden = 12L, n_heads = 2L,
                                      n_layers = 2L, epochs = 100L,
                                      lr = 0.03, n_ensemble = 10L,
                                      seed = 1L,
                                      calibrate = TRUE) {
  stopifnot(all(c("soc", "lon", "lat") %in% names(train)),
             all(c("lon", "lat")        %in% names(test)),
             all(cov_cols %in% names(train)),
             all(cov_cols %in% names(test)))
  df_all <- rbind(
    cbind(train[, c("lon", "lat", cov_cols)], soc = train$soc),
    cbind(test[,  c("lon", "lat", cov_cols)], soc = NA_real_)
  )
  g <- gnn_build_graph(df_all, k = k, feature_cols = cov_cols)
  y_all <- df_all$soc
  y_impute <- y_all
  y_impute[is.na(y_impute)] <- mean(y_all, na.rm = TRUE)
  n_tr <- nrow(train); n_all <- nrow(df_all)
  test_idx <- seq(n_tr + 1L, n_all)
  pred_mat <- matrix(NA_real_, nrow = n_ensemble, ncol = nrow(test))
  train_pred_mat <- matrix(NA_real_, nrow = n_ensemble, ncol = n_tr)
  for (b in seq_len(n_ensemble)) {
    fit <- gnn_fit(g, targets = y_impute,
                     hidden = hidden, n_heads = n_heads, n_layers = n_layers,
                     epochs = epochs, lr = lr, seed = seed + b)
    pred_all <- stats::predict(fit)
    pred_mat[b, ]       <- pred_all[test_idx]
    train_pred_mat[b, ] <- pred_all[seq_len(n_tr)]
  }
  sigma_resid <- 0
  if (isTRUE(calibrate)) {
    # Use the ensemble-mean training predictions as the representative
    # point predictor for residual SD estimation -- avoids the cost of
    # an additional full-data fit while keeping the noise estimate
    # decoupled from the per-member seeds.
    sigma_resid <- .bench_residual_sd(train$soc, colMeans(train_pred_mat))
    pred_mat <- .bench_inject_aleatoric(pred_mat, sigma_resid, seed = seed)
  }
  edaphos_posterior(samples = pred_mat, method = "ensemble",
                      query_type = "map", units = "g/kg",
                      metadata = list(k = k, hidden = hidden,
                                        n_heads = n_heads,
                                        n_layers = n_layers,
                                        n_ensemble = n_ensemble,
                                        calibrate = calibrate,
                                        sigma_resid = sigma_resid))
}
