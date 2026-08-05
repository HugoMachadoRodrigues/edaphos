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
# Predictive-posterior calibration helper.
#
# The bootstrap- and seed-ensemble posteriors of P1/P6/P10 carry only
# EPISTEMIC uncertainty -- the spread of predictive MEANS under different
# model fits -- and so under-cover an honest 90 % predictive interval
# (PICP 0.07 - 0.25 in the v3.1.0 head-to-head).  A predictive interval
# needs the ALEATORIC term as well, so an estimate of the residual
# standard deviation is convolved into the posterior.  That much is
# standard and is not in question.
#
# HOW it is done matters.  The v3.4.0 implementation drew iid Gaussian
# noise and added it to the posterior matrix.  The benchmark then reads
# the point prediction as `colMeans(samples)`, and the column mean of
# n_draws iid draws is not zero -- it is a perturbation of standard
# deviation sigma/sqrt(n_draws).
#
# That perturbation adds to RMSE IN QUADRATURE, not linearly:
#   inflation = sqrt(RMSE^2 + sigma^2/n_draws) - RMSE
# so its size depends strongly on n_draws, and it is small whenever
# n_draws is large.  Measured against the shipped bundles:
#
#   method            n_draws   sigma   predicted   observed
#   P1 Causal+OLS       300      15.2     0.028       0.038
#   P6 Quantum KRR       10      14.6     0.138       0.158
#   P10 GAT ensemble      8      15.7     1.019       1.094
#
# P4/P5/P7 never called this helper at all (no `sigma_resid` in their
# posterior metadata), so their numbers were never affected by it.
# An earlier revision of this comment quoted sigma/sqrt(n_draws) itself
# (~0.44 g/kg) as the RMSE inflation.  That is the perturbation RMS, not
# the inflation, and overstates the effect by ~55x at n_draws = 300.
# The bug was negligible for P1 and material only for the small-ensemble
# methods P6 and P10 -- which is exactly where the biggest RMSE change
# appeared when it was fixed.
#
# The fix is to centre the noise within each test column before adding it
# and rescale so the marginal spread is unchanged.  The column mean of
# the noise is then exactly zero, so the point prediction is preserved
# bit-for-bit, while the interval still widens by the aleatoric term.
# Verified: the residue in colMeans drops to ~1e-14, so the point
# prediction is bit-stable while the interval still widens.
.bench_inject_aleatoric <- function(pred_mat, sigma_resid, seed = NULL) {
  if (!is.finite(sigma_resid) || sigma_resid <= 0) return(pred_mat)
  n <- nrow(pred_mat)
  if (n < 2L) return(pred_mat)
  if (!is.null(seed)) set.seed(seed + 13579L)
  noise <- matrix(stats::rnorm(length(pred_mat), 0, sigma_resid),
                    n, ncol(pred_mat))
  # exactly mean-zero per test row, then rescaled so centring does not
  # shrink the variance (centring n draws costs a factor (n-1)/n)
  noise <- sweep(noise, 2L, colMeans(noise), "-") * sqrt(n / (n - 1))
  pred_mat + noise
}

# Estimate the residual standard deviation of a point predictor.
#
# Uses the FULL training set rather than a bootstrap resample so the
# estimate is not contaminated by the ensemble it complements.  `n_params`
# applies the degrees-of-freedom correction: stats::sd() divides by n - 1,
# which is the right divisor only for an intercept-only model and
# under-estimates sigma for every fitted model with p coefficients.  Pass
# the number of estimated parameters where it is known; the default of 1
# reproduces stats::sd().
#
# This is still an IN-SAMPLE estimate and therefore optimistic: it is a
# lower bound on the true predictive residual sd.  Intervals built on it
# are correspondingly a lower bound on the honest width, which is stated
# in the benchmark output rather than left for a reader to discover.
.bench_residual_sd <- function(y_obs, y_hat, n_params = 1L) {
  resid <- as.numeric(y_obs) - as.numeric(y_hat)
  resid <- resid[is.finite(resid)]
  n <- length(resid)
  if (n < 2L) return(0)
  df <- max(n - n_params, 1)
  sqrt(sum(resid^2) / df)
}

# ---------------------------------------------------------------------------
# The predictive interval of an ensemble method is (member spread) + injected
# aleatoric noise. Getting the second term right is not a detail: three of the
# six benchmarked methods build their interval this way, and until now all
# three estimated the noise from TRAINING residuals with `n_params = 1L`.
#
# For P1 that is defensible -- ordinary least squares passes its true
# coefficient count and the classical df correction is exact. For a kernel
# ridge and a graph attention network it is not: both absorb a large part of
# the training response, so their training residuals are optimistic, the
# injected noise is too small, and the published coverage is too low for a
# reason that has nothing to do with the method. P6 and P10 report the two
# worst PICP values in the benchmark (0.471 and 0.729 against a nominal 0.90),
# and they are two of the three using this recipe. That confound had to be
# removed before either number could be read as a property of the method.
#
# `.bench_edf_krr` supplies the exact effective degrees of freedom for kernel
# ridge, tr(K (K + lambda I)^-1) -- a closed form, not an approximation. The
# GAT has no such expression, so its residual scale is estimated by an inner
# spatially blocked CV inside the training partition (see the P10 fitter).
# ---------------------------------------------------------------------------
.bench_edf_krr <- function(K, lambda) {
  n <- nrow(K)
  sum(diag(solve(K + lambda * diag(n), K)))
}

# Total predictive SD is (ensemble variance) + (injected variance). Given a
# target total, the injected part is what the ensemble does not already carry;
# adding a full out-of-sample sigma on top of the member spread would count
# the epistemic component twice.
.bench_aleatoric_gap <- function(sigma_total, pred_mat) {
  if (!is.finite(sigma_total) || sigma_total <= 0) return(0)
  v_ens <- mean(apply(pred_mat, 2L, stats::var))
  sqrt(max(0, sigma_total^2 - v_ens))
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
#' @examples
#' data(br_cerrado)
#'
#' # The wrapper checks for the response `soc` and the named covariates
#' # and nothing else -- it never reads a coordinate column, and its
#' # bootstrap is a plain row resample. So the split below is RANDOM, not
#' # spatial, and the interval it produces does not account for spatial
#' # dependence between train and test. For a spatially blocked
#' # comparison see `data-raw/benchmark_wosis_6pilar.R`, which is what
#' # the published six-pillar figures use.
#' set.seed(1)
#' sub <- br_cerrado[sample(nrow(br_cerrado), 300L), ]
#' covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' train <- sub[1:240, ]; test <- sub[241:300, ]
#'
#' post <- benchmark_fit_p1_causal(train, test, covs, n_boot = 300L, seed = 1L)
#' dim(post$samples)          # 300 bootstrap draws x 60 held-out sites
#'
#' # Score it against the baseline any soil map has to beat -- predicting
#' # the training mean everywhere.  3.680 g/kg against 6.173.
#' cal <- uncertainty_calibrate(post, truth = test$soc)
#' round(c(rmse = cal$point_rmse,
#'         null = sqrt(mean((mean(train$soc) - test$soc)^2))), 3)
#'
#' # `calibrate = TRUE` (the default) convolves the in-sample residual sd
#' # into every draw.  The noise is centred within each test column, so the
#' # point prediction survives untouched -- colMeans() moves by ~3e-14 --
#' # and only the interval changes.
#' raw <- benchmark_fit_p1_causal(train, test, covs, n_boot = 300L,
#'                                seed = 1L, calibrate = FALSE)
#' max(abs(colMeans(post$samples) - colMeans(raw$samples)))
#'
#' # Read that next to the coverage, which is the whole point of the term.
#' # Bootstrap spread alone is the uncertainty of the FITTED MEAN, not of a
#' # new profile: its 90% intervals are 1.99 g/kg wide and hold 22% of the
#' # held-out truth.  With the aleatoric term they are 13.46 wide and hold
#' # 93%, which on 60 sites is 0.9 binomial standard errors off nominal --
#' # calibrated, as far as this test set can tell.
#' cal_raw <- uncertainty_calibrate(raw, truth = test$soc)
#' round(c(picp90_raw = cal_raw$picp[["0.90"]],
#'         picp90_cal = cal$picp[["0.90"]],
#'         mpiw90_raw = cal_raw$mpiw[["0.90"]],
#'         mpiw90_cal = cal$mpiw[["0.90"]],
#'         se90 = sqrt(0.9 * 0.1 / nrow(test))), 3)
#'
#' # TRAP: the DAG filter asks for the parents of a hard-coded outcome node
#' # named "soc_topsoil_gkg".  A DAG that calls its outcome anything else
#' # raises inside dagitty::parents(), and the fallback keeps every node
#' # NAME in the graph -- so `elev` and `slope`, parents of nothing but
#' # `ndvi` and `twi`, survive a selection advertised as causal.
#' if (requireNamespace("dagitty", quietly = TRUE)) {
#'   d_wrong <- dagitty::dagitty(
#'     "dag { elev -> ndvi ; ndvi -> soc ; map_mm -> soc ; slope -> twi }")
#'   print(dagitty::parents(d_wrong, "soc"))     # map_mm, ndvi
#'   print(benchmark_fit_p1_causal(train, test, covs, dag = d_wrong,
#'                                 n_boot = 50L,
#'                                 seed = 1L)$metadata$adjusted_features)
#'
#'   # Name the outcome the way the wrapper expects and the parent set is
#'   # honoured: three covariates instead of five.
#'   d_ok <- dagitty::dagitty(
#'     "dag { map_mm -> soc_topsoil_gkg ; ndvi -> soc_topsoil_gkg ;
#'            twi -> soc_topsoil_gkg ; elev -> map_mm ; slope -> twi }")
#'   print(benchmark_fit_p1_causal(train, test, covs, dag = d_ok,
#'                                 n_boot = 50L,
#'                                 seed = 1L)$metadata$adjusted_features)
#'
#'   # And a DAG leaving fewer than two covariates reverts to the full set
#'   # rather than fitting a one-covariate model -- also silently.
#'   # `metadata$adjusted_features` is the only place any of this shows.
#'   d_one <- dagitty::dagitty("dag { ndvi -> soc_topsoil_gkg }")
#'   print(benchmark_fit_p1_causal(train, test, covs, dag = d_one,
#'                                 n_boot = 50L,
#'                                 seed = 1L)$metadata$adjusted_features)
#' }
#' @export
benchmark_fit_p1_causal <- function(train, test, cov_cols, dag = NULL,
                                        n_boot = 300L, seed = 1L,
                                        calibrate = TRUE) {
  stopifnot("soc" %in% names(train),
             all(cov_cols %in% names(train)),
             all(cov_cols %in% names(test)))
  in_dag <- cov_cols
  if (!is.null(dag) && requireNamespace("dagitty", quietly = TRUE)) {
    # Direct parents of the outcome, which is what this function documents.
    #
    # This used to test membership in names(dag) -- every node in the graph,
    # outcome included -- so every covariate passed and the "DAG-adjusted"
    # subset was silently the full covariate set.  The filter was a no-op and
    # the row was labelled as if a causal selection had happened.  Fall back
    # to names(dag) only if the parent set cannot be resolved.
    outcome  <- "soc_topsoil_gkg"
    dag_vars <- tryCatch({
      pr <- dagitty::parents(dag, outcome)
      if (length(pr)) pr else names(dag)
    }, error = function(e) names(dag))
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
    sigma_resid <- .bench_residual_sd(train$soc, stats::fitted(full_lm),
                                          n_params = length(stats::coef(full_lm)))
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
#' @examples
#' data(br_cerrado)
#' set.seed(2)
#' sub <- br_cerrado[sample(nrow(br_cerrado), 120L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' train <- sub[1:90, ]; test <- sub[91:120, ]
#'
#' # `n_pcs` IS the qubit count: the simulator carries a 2^n_pcs state
#' # vector per site and the Gram matrix needs O(n^2) of them, so keep it
#' # small.  It also cannot exceed the number of non-constant covariates --
#' # with these five columns the package default of 6 stops the fit.
#' try(benchmark_fit_p6_quantum(train, test, covs, n_pcs = 6L, n_boot = 2L))
#'
#' post <- benchmark_fit_p6_quantum(train, test, covs, n_pcs = 4L, reps = 1L,
#'                                  n_boot = 5L, lambda = 0.5, seed = 1L)
#' dim(post$samples)                  # 5 bootstrap members x 30 sites
#'
#' # Do not read this as a working model.  Against the training mean and
#' # against OLS on the same five covariates: 7.047 / 7.048 / 4.361.
#' cal <- uncertainty_calibrate(post, truth = test$soc)
#' ols <- lm(soc ~ elev + slope + twi + map_mm + ndvi, data = train)
#' round(c(qkrr = cal$point_rmse,
#'         null = sqrt(mean((mean(train$soc) - test$soc)^2)),
#'         ols  = sqrt(mean((predict(ols, test) - test$soc)^2))), 3)
#'
#' # It ties the null because it has collapsed onto it.  At 4 qubits the
#' # ZZFeatureMap Gram matrix is nearly the identity (mean off-diagonal
#' # 0.063), the dual weights explain almost nothing, and predictions fall
#' # back on the offset that quantum_krr_fit() centres the response with --
#' # i.e. mean(train$soc).  The predictions vary by 1.75 g/kg where the
#' # truth varies by 7.13.
#' pt <- colMeans(post$samples)
#' red <- qf_embed_reduce(as.matrix(rbind(train[, covs], test[, covs])),
#'                        n_pcs = 4L)
#' K <- quantum_kernel(red$X_q[1:90, ], reps = 1L)
#' round(c(sd_pred = sd(pt), sd_truth = sd(test$soc),
#'         mean_pred = mean(pt), train_mean = mean(train$soc),
#'         gram_offdiag = mean(K[upper.tri(K)])), 3)
#'
#' # Note which rows went into that PCA: the wrapper reduces
#' # rbind(train, test) jointly, so the rotation and the [-pi, pi] rescale
#' # have seen the test covariates.  Fine for a benchmark of the kernel,
#' # not a clean out-of-sample protocol -- PC1 takes 0.489 of the variance
#' # jointly against 0.477 on the training rows alone.
#' round(rbind(joint = red$variance_explained,
#'             train_only = qf_embed_reduce(as.matrix(train[, covs]),
#'                                          n_pcs = 4L)$variance_explained), 3)
#'
#' # The interval story is separate, and n_boot bounds it: a 90% interval
#' # read off 5 members cannot be wider than their range.  More members
#' # widen it, but they cannot rescue a posterior centred in the wrong
#' # place -- coverage is still 0.467 at n_boot = 50.
#' picp <- vapply(c(5L, 20L, 50L), function(nb) {
#'   p <- benchmark_fit_p6_quantum(train, test, covs, n_pcs = 4L, reps = 1L,
#'                                 n_boot = nb, lambda = 0.5, seed = 1L)
#'   uncertainty_calibrate(p, truth = test$soc)$picp[["0.90"]]
#' }, numeric(1))
#' round(picp, 3)
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
    # Exact effective degrees of freedom for kernel ridge. The previous call
    # used the `n_params = 1L` default, dividing by n - 1 a residual sum that
    # a model with tens of effective parameters had already shrunk.
    edf <- .bench_edf_krr(full_fit$K_train, lambda)
    sigma_total <- .bench_residual_sd(y_tr, stats::predict(full_fit, Xq_tr),
                                          n_params = edf)
    sigma_resid <- .bench_aleatoric_gap(sigma_total, pred_mat)
    pred_mat <- .bench_inject_aleatoric(pred_mat, sigma_resid, seed = seed)
  }
  edaphos_posterior(samples = pred_mat, method = "ensemble",
                      query_type = "map", units = "g/kg",
                      metadata = list(n_pcs = n_pcs, reps = reps,
                                        lambda = lambda, n_boot = n_boot,
                                        calibrate = calibrate,
                                        sigma_resid = sigma_resid,
                                        edf = if (isTRUE(calibrate)) edf else NA_real_))
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
#' @examples
#' data(br_cerrado)
#' set.seed(3)
#' sub <- br_cerrado[sample(nrow(br_cerrado), 160L), ]
#' names(sub)[names(sub) == "x"] <- "lon"
#' names(sub)[names(sub) == "y"] <- "lat"
#' covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
#' train <- sub[1:120, ]; test <- sub[121:160, ]
#'
#' # The k-NN graph spans train AND test, but only the training nodes carry
#' # an observed target, so `test` never needs a `soc` column: the wrapper
#' # fills the held-out targets with NA and masks them out of the loss.
#' post <- benchmark_fit_p10_gat(train, test[, c("lon", "lat", covs)], covs,
#'                               k = 6L, hidden = 8L, n_heads = 2L,
#'                               n_layers = 2L, epochs = 40L, lr = 0.05,
#'                               n_ensemble = 4L, seed = 1L)
#' dim(post$samples)                 # 4 seed-distinct members x 40 sites
#'
#' # Two baselines, both computed here: the training mean and OLS on the
#' # same five covariates.  5.090 / 7.289 / 4.679 -- on 120 training nodes
#' # the attention over the co-location graph beats the mean by 30% and
#' # still loses to the linear model by 9%.  A GAT row in a benchmark
#' # table means nothing without that middle column.
#' cal <- uncertainty_calibrate(post, truth = test$soc)
#' ols <- lm(soc ~ elev + slope + twi + map_mm + ndvi, data = train)
#' round(c(gat  = cal$point_rmse,
#'         null = sqrt(mean((mean(train$soc) - test$soc)^2)),
#'         ols  = sqrt(mean((predict(ols, test) - test$soc)^2))), 3)
#'
#' # `n_ensemble` is not only how precisely the point prediction is
#' # averaged: the posterior IS the ensemble, so a 90% interval read off
#' # four draws cannot be wider than their range.  Going to eight members
#' # widens it from 7.75 to 9.62 g/kg and lifts coverage from 0.50 to
#' # 0.60 -- closer to nominal, still well short of it.
#' big <- benchmark_fit_p10_gat(train, test, covs, k = 6L, hidden = 8L,
#'                              n_heads = 2L, n_layers = 2L, epochs = 40L,
#'                              lr = 0.05, n_ensemble = 8L, seed = 1L)
#' cal_big <- uncertainty_calibrate(big, truth = test$soc)
#' round(c(picp90_4 = cal$picp[["0.90"]], picp90_8 = cal_big$picp[["0.90"]],
#'         mpiw90_4 = cal$mpiw[["0.90"]], mpiw90_8 = cal_big$mpiw[["0.90"]]), 3)
#'
#' # Where that width comes from matters.  `calibrate = FALSE` leaves only
#' # the seed-to-seed spread of the fitted means -- 1.10 g/kg, and 20%
#' # coverage -- against a residual sd of 3.79.  The members disagree far
#' # less with each other than any of them disagrees with the truth, which
#' # is the usual state of a deep ensemble and the reason the aleatoric
#' # term is added by default.
#' epi <- benchmark_fit_p10_gat(train, test, covs, k = 6L, hidden = 8L,
#'                              n_heads = 2L, n_layers = 2L, epochs = 40L,
#'                              lr = 0.05, n_ensemble = 4L, seed = 1L,
#'                              calibrate = FALSE)
#' round(c(sd_epistemic = mean(apply(epi$samples, 2L, sd)),
#'         sd_calibrated = mean(apply(post$samples, 2L, sd)),
#'         sigma_resid = post$metadata$sigma_resid,
#'         picp90_epistemic =
#'           uncertainty_calibrate(epi, truth = test$soc)$picp[["0.90"]]), 3)
#'
#' # Member-by-member RMSE, for scale: the four seeds score 4.98 to 5.46
#' # and their average scores 5.09 -- inside that range, not below it.  On
#' # this problem the ensemble is buying an interval, not accuracy.
#' round(apply(epi$samples, 1L, function(p) sqrt(mean((p - test$soc)^2))), 3)
#'
#' # Each member is one gnn_fit() on a single transductive graph: train
#' # and test nodes together, held-out targets NA, loss on the training
#' # mask.  Rebuilding member 1 by hand reproduces it exactly -- and shows
#' # what `epochs` actually did.  gnn_fit() keeps a validation slice and
#' # restores its best epoch, which here is epoch 2 of the 40 asked for;
#' # it stops at 22 and discards the rest.  Nothing above is a training
#' # curve, which is the other half of why this loses to lm().
#' df_all <- rbind(cbind(train[, c("lon", "lat", covs)], soc = train$soc),
#'                 cbind(test[,  c("lon", "lat", covs)], soc = NA_real_))
#' g1 <- gnn_build_graph(df_all, k = 6L, feature_cols = covs)
#' f1 <- gnn_fit(g1, df_all$soc, train_mask = !is.na(df_all$soc),
#'               hidden = 8L, n_heads = 2L, n_layers = 2L, epochs = 40L,
#'               lr = 0.05, seed = 2L)          # member b uses seed + b
#' c(best_epoch = f1$best_epoch, epochs_run = length(f1$history))
#' isTRUE(all.equal(predict(f1)[121:160], epi$samples[1, ]))
#' @export
# Out-of-sample residual scale for the GAT, by inner spatially blocked CV
# inside the training partition. The network has no closed-form effective
# degrees of freedom, so the only honest estimate of how large its errors are
# at an unseen location is to hold locations out and look.
#
# The inner blocking mirrors the outer protocol -- same helper, same buffer --
# so the residual scale is estimated under the same spatial regime it will be
# applied in. Nothing outside `train` is touched.
#
# Returns NA if the training partition cannot carry the inner blocking (too
# few profiles survive the buffer), so the caller can fall back and SAY it
# fell back rather than silently reverting to training residuals.
.p10_inner_sigma <- function(train, cov_cols, k, hidden, n_heads, n_layers,
                                epochs, lr, n_ensemble, seed,
                                n_inner = 3L, buffer_km = 68) {
  co <- cbind(train$lon, train$lat)
  SF <- tryCatch(spatial_block_folds(co, k = n_inner, buffer_km = buffer_km,
                                        seed = seed),
                   error = function(e) NULL)
  if (is.null(SF)) return(NA_real_)

  res <- vector("list", n_inner)
  for (fd in seq_len(n_inner)) {
    tr_ix <- SF$train[[fd]]; te_ix <- SF$test[[fd]]
    if (length(tr_ix) < 30L || length(te_ix) < 5L) return(NA_real_)
    itr <- train[tr_ix, , drop = FALSE]; ite <- train[te_ix, , drop = FALSE]
    df_all <- rbind(
      cbind(itr[, c("lon", "lat", cov_cols)], soc = itr$soc),
      cbind(ite[, c("lon", "lat", cov_cols)], soc = NA_real_))
    g <- gnn_build_graph(df_all, k = k, feature_cols = cov_cols)
    n_i <- nrow(itr); n_a <- nrow(df_all)
    mask <- c(rep(TRUE, n_i), rep(FALSE, n_a - n_i))
    P <- matrix(NA_real_, nrow = n_ensemble, ncol = nrow(ite))
    for (b in seq_len(n_ensemble)) {
      f <- gnn_fit(g, targets = df_all$soc, train_mask = mask,
                     hidden = hidden, n_heads = n_heads, n_layers = n_layers,
                     epochs = epochs, lr = lr, seed = seed + 1000L * fd + b)
      P[b, ] <- stats::predict(f)[seq(n_i + 1L, n_a)]
    }
    res[[fd]] <- ite$soc - colMeans(P)
  }
  r <- unlist(res); r <- r[is.finite(r)]
  if (length(r) < 10L) return(NA_real_)
  sqrt(mean(r^2))
}

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
  n_tr <- nrow(train); n_all <- nrow(df_all)
  # Transductive split: the graph spans both sets so message passing can use
  # the full spatial structure, but only the training nodes carry an observed
  # target.  Through v3.10.0 the held-out targets were filled with the training
  # mean and the head was fitted over ALL nodes, so the model was explicitly
  # trained to emit that mean at every test location.  Under spatially blocked
  # folds nearly all of a test node's k-NN neighbours are other test nodes, so
  # that pulled the whole test block towards the mean and made P10 look like a
  # mean predictor by construction.
  train_mask <- c(rep(TRUE, n_tr), rep(FALSE, n_all - n_tr))
  test_idx <- seq(n_tr + 1L, n_all)
  pred_mat <- matrix(NA_real_, nrow = n_ensemble, ncol = nrow(test))
  train_pred_mat <- matrix(NA_real_, nrow = n_ensemble, ncol = n_tr)
  for (b in seq_len(n_ensemble)) {
    fit <- gnn_fit(g, targets = y_all, train_mask = train_mask,
                     hidden = hidden, n_heads = n_heads, n_layers = n_layers,
                     epochs = epochs, lr = lr, seed = seed + b)
    pred_all <- stats::predict(fit)
    pred_mat[b, ]       <- pred_all[test_idx]
    train_pred_mat[b, ] <- pred_all[seq_len(n_tr)]
  }
  sigma_resid <- 0
  if (isTRUE(calibrate)) {
    # Training residuals will not do here. A network with a few hundred
    # parameters absorbs much of the training response, so `sd(train$soc -
    # fitted)` measures how well it memorised, not how wrong it will be at an
    # unsurveyed site -- and the injected noise, and therefore the published
    # coverage, comes out too small for a reason that is not about the method.
    sigma_total <- .p10_inner_sigma(train, cov_cols, k = k, hidden = hidden,
                                        n_heads = n_heads, n_layers = n_layers,
                                        epochs = epochs, lr = lr,
                                        n_ensemble = n_ensemble, seed = seed)
    sigma_source <- "inner blocked CV"
    if (!is.finite(sigma_total)) {
      # Fall back, but on the record: an interval built from training
      # residuals is known to be too narrow and must not pass as calibrated.
      sigma_total <- .bench_residual_sd(train$soc, colMeans(train_pred_mat))
      sigma_source <- "training residuals (inner blocking failed)"
      warning("P10: inner blocked CV could not run on this training ",
                "partition; the residual scale falls back to training ",
                "residuals and the interval is expected to undercover.",
                call. = FALSE)
    }
    sigma_resid <- .bench_aleatoric_gap(sigma_total, pred_mat)
    pred_mat <- .bench_inject_aleatoric(pred_mat, sigma_resid, seed = seed)
  }
  edaphos_posterior(samples = pred_mat, method = "ensemble",
                      query_type = "map", units = "g/kg",
                      metadata = list(k = k, hidden = hidden,
                                        n_heads = n_heads,
                                        n_layers = n_layers,
                                        n_ensemble = n_ensemble,
                                        calibrate = calibrate,
                                        sigma_resid = sigma_resid,
                                        sigma_total = if (isTRUE(calibrate)) sigma_total else NA_real_,
                                        sigma_source = if (isTRUE(calibrate)) sigma_source else NA_character_))
}
