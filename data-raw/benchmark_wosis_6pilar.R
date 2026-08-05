## data-raw/benchmark_wosis_6pilar.R  (v3.1.0)
##
## Extends the v2.8.0 triple (P4 Foundation + P5 QRF + P7 BHS) to a
## six-pilar head-to-head on the 1 095 real WoSIS Cerrado topsoil
## profiles by adding three methods that are natural fits to a static
## point-regression task:
##
##   P1 Causal  DAG-restricted OLS + parametric bootstrap
##   P6 Quantum ZZFeatureMap kernel ridge on PCA(covariates) ensemble
##   P10 GAT    k-NN co-location graph + Graph Attention Network ensemble
##
## We ALSO document why P2 (profile ODE), P3 (temporal ConvLSTM),
## P8 (neural operators) and P9 (DDPM) are NOT part of the head-to-head:
## they target depth profiles, temporal stacks, and raster patches
## respectively -- fundamentally different data modalities from a
## topsoil scalar regression.  Each of those four pilares has its
## own task-appropriate benchmark in the corresponding vignette.
##
## Evaluation: 5-fold spatial CV (k-means on lon/lat), same harness as
## v2.8.0.  Posteriors are unified through `edaphos_posterior` and
## scored via `uncertainty_calibrate()`.
##
## Output: inst/extdata/benchmark_wosis_6pilar.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260501L)

OUT_PATH  <- file.path("inst", "extdata", "benchmark_wosis_6pilar.rds")
V280_PATH <- file.path("inst", "extdata", "benchmark_wosis_p4_p5_p7.rds")
DAG_RDS   <- file.path("inst", "extdata", "causal_cerrado_real.rds")

# ---------------------------------------------------------------------------
# 1. Load WoSIS profiles + v2.8.0 posterior bank (re-used for P4/P5/P7)
# ---------------------------------------------------------------------------
message("=== [1/7] Loading WoSIS profiles ===")
causal_rds <- readRDS(DAG_RDS)
profiles <- causal_rds$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat)) |>
  mutate(
    soc      = soc_topsoil_gkg,
    map      = wc_bio_12,
    mat      = wc_bio_01 / 10,
    trees    = wc_landcover_trees,
    cropland = wc_landcover_cropland,
    grass    = wc_landcover_grassland,
    clay     = soilgrids_clay,
    sand     = soilgrids_sand,
    bd       = soilgrids_bdod
  )
cov_cols <- c("map", "mat", "slope", "elev", "clay", "sand", "bd",
               "trees", "cropland", "grass")
cov_cols <- intersect(cov_cols, names(profiles))
profiles <- profiles[stats::complete.cases(profiles[, cov_cols]), ]
message(sprintf("  n = %d profiles; cov_cols = {%s}",
                 nrow(profiles), paste(cov_cols, collapse = ", ")))

# ---------------------------------------------------------------------------
# Response scale.  SOC in g/kg is strongly right-skewed here: 11 of 1095
# profiles (1.0 %) carry 48.2 % of the total sum of squares, with a maximum of
# 194 g/kg against a median of 13.3.  On the raw scale R2 therefore measures
# how well a method reproduces a handful of extreme profiles, and every method
# scores near or below zero.  On log1p(SOC) -- the conventional scale for soil
# organic carbon -- the same covariates under these same blocked folds give
# OLS R2 = +0.161 and ranger R2 = +0.134, so the raw-scale result is a property
# of the scale and not of the prediction problem.  Fit on log1p by default.
# Set EDAPHOS_BENCH_SCALE=raw to reproduce the historical raw-scale numbers.
RESPONSE_SCALE <- if (identical(Sys.getenv("EDAPHOS_BENCH_SCALE"), "raw"))
  "raw" else "log1p"
if (RESPONSE_SCALE == "log1p") profiles$soc <- log1p(profiles$soc)
RESPONSE_UNITS <- if (RESPONSE_SCALE == "log1p") "log1p(g/kg)" else "g/kg"
message(sprintf("  response scale: %s (%s)", RESPONSE_SCALE, RESPONSE_UNITS))

# ---------------------------------------------------------------------------
# Provenance of the response relative to the covariates.  The WoSIS profiles
# were sampled decades before the covariate rasters were measured, so part of
# the irreducible error is temporal mismatch rather than model inadequacy.
# Recorded in the bundle so no table can present the result without it.
PROFILE_YEARS <- suppressWarnings(as.numeric(profiles$year))
YEAR_SUMMARY <- list(
  min = suppressWarnings(min(PROFILE_YEARS, na.rm = TRUE)),
  q25 = unname(stats::quantile(PROFILE_YEARS, 0.25, na.rm = TRUE)),
  median = stats::median(PROFILE_YEARS, na.rm = TRUE),
  q75 = unname(stats::quantile(PROFILE_YEARS, 0.75, na.rm = TRUE)),
  max = suppressWarnings(max(PROFILE_YEARS, na.rm = TRUE)),
  n_missing = sum(is.na(PROFILE_YEARS)),
  covariate_epoch = "SoilGrids 2020 / WorldClim 2.1 (1970-2000) / SRTM 2000 / WorldCover 2020",
  note = paste("Land cover is measured decades after the median profile was",
               "sampled; the covariates cannot describe the land surface as",
               "it was at sampling time.")
)
# Ensemble budgets, recorded per row so a table cannot present methods with
# 30x different budgets as a like-for-like comparison.
P1_N_BOOT  <- 300L
P6_N_BOOT  <- 100L
P10_N_ENS  <- 8L

message(sprintf("  profile years: %g-%g (median %g, %d missing)",
                YEAR_SUMMARY$min, YEAR_SUMMARY$max, YEAR_SUMMARY$median,
                YEAR_SUMMARY$n_missing))

v280 <- tryCatch(readRDS(V280_PATH), error = function(e) NULL)
if (is.null(v280))
  stop("v2.8.0 benchmark RDS missing; run data-raw/benchmark_wosis_p4_p5_p7.R first.")
# Reuse the IDENTICAL buffered split P4/P5/P7 were scored on. Three methods on
# buffered folds and three on unbuffered would not be a matched benchmark.
SF <- v280$spatial_folds
if (is.null(SF)) {
  stop("the P4/P5/P7 bundle predates buffered blocking; re-run ",
       "data-raw/benchmark_wosis_p4_p5_p7.R before this script.", call. = FALSE)
}
folds <- SF$fold
profiles$fold5 <- folds
message(sprintf("  buffered folds: %.0f km, %d training rows discarded, ",
                SF$buffer_km, sum(SF$n_buffered)),
        sprintf("min train-test distance %.1f km", min(SF$min_dist_km)))

# ---------------------------------------------------------------------------
# 2. New method wrappers (P1, P6, P10) -- canonical exports from R/benchmark_wosis.R
# ---------------------------------------------------------------------------
# The package-exported benchmark wrappers live in R/benchmark_wosis.R:
#   * benchmark_fit_p1_causal(train, test, cov_cols, dag = NULL, n_boot, seed)
#   * benchmark_fit_p6_quantum(train, test, cov_cols, n_pcs, reps, lambda,
#                               n_boot, seed)
#   * benchmark_fit_p10_gat(train, test, cov_cols, k, hidden, n_heads,
#                             n_layers, epochs, lr, n_ensemble, seed)
# devtools::load_all() above pulled them into the session.

# ---------------------------------------------------------------------------
# 3. 5-fold CV loop (only for the three NEW methods; re-use v2.8.0 for P4/5/7)
# ---------------------------------------------------------------------------
message("=== [3/7] Running 5-fold spatial CV on P1, P6, P10 ===")

fold_rows_new <- list()
post_bank_new <- list()

for (fd in 1:5) {
  message(sprintf("  fold %d/5", fd))
  # SF$train already has the buffered rows removed; the complement would not.
  train_ix <- SF$train[[fd]]
  test_ix  <- SF$test[[fd]]
  train    <- profiles[train_ix, , drop = FALSE]
  test     <- profiles[test_ix,  , drop = FALSE]
  n_tr <- nrow(train); n_te <- nrow(test)
  message(sprintf("    train=%d, test=%d", n_tr, n_te))

  # P1 Causal (parametric bootstrap OLS on DAG-adjusted set)
  t1 <- system.time({
    post1 <- tryCatch(benchmark_fit_p1_causal(train, test, cov_cols,
                                                    dag = causal_rds$dag,
                                                    n_boot = P1_N_BOOT),
                        error = function(e) {
                          message("    [P1 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]

  # P6 Quantum (bootstrap-ensemble over circuit KRR).
  # Previously n_boot = 10 against P1's 300 -- an ensemble 30x smaller, which
  # is not a like-for-like comparison of the METHODS but of their budgets.
  # Raised to 100; the quantum kernel is O(n^2 * 2^n_pcs) so 300 is out of
  # reach, and the residual disparity is recorded per row as `n_ensemble`.
  t6 <- system.time({
    post6 <- tryCatch(benchmark_fit_p6_quantum(train, test, cov_cols,
                                                     n_pcs = 6L, reps = 1L,
                                                     n_boot = P6_N_BOOT,
                                                     lambda = 0.5),
                        error = function(e) {
                          message("    [P6 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]

  # P10 GAT (seed-ensemble)
  t10 <- system.time({
    post10 <- tryCatch(benchmark_fit_p10_gat(train, test, cov_cols,
                                                   k = 8L, hidden = 12L,
                                                   n_heads = 2L,
                                                   n_layers = 2L,
                                                   epochs = 80L, lr = 0.03,
                                                   n_ensemble = 8L),
                         error = function(e) {
                           message("    [P10 warn] ", conditionMessage(e))
                           NULL
                         })
  })["elapsed"]

  truth <- test$soc
  eval_post <- function(post) {
    if (is.null(post)) return(NULL)
    tryCatch(uncertainty_calibrate(post, truth = truth),
              error = function(e) NULL)
  }
  c1 <- eval_post(post1); c6 <- eval_post(post6); c10 <- eval_post(post10)

  budget_of <- function(name)
    if (grepl("^P1 ", name)) P1_N_BOOT
    else if (grepl("^P6 ", name)) P6_N_BOOT
    else if (grepl("^P10 ", name)) P10_N_ENS else NA_integer_

  grab <- function(name, post, cal, elapsed) {
    if (is.null(cal)) {
      return(data.frame(method = name, fold = fd, n_test = n_te,
                          n_train = n_tr, train_capped = FALSE,
                          n_ensemble = budget_of(name),
                          rmse = NA, mae = NA, r2 = NA, nse = NA,
                          crps = NA, picp90 = NA, mpiw90 = NA,
                          elapsed_s = elapsed, stringsAsFactors = FALSE))
    }
    safe_lookup <- function(v, keys) {
      nm <- names(v)
      for (k in keys) if (k %in% nm) return(as.numeric(v[[k]]))
      NA_real_
    }
    picp90 <- safe_lookup(cal$picp, c("0.90", "0.9"))
    mpiw90 <- safe_lookup(cal$mpiw, c("0.90", "0.9"))
    point_pred <- if (!is.null(post$samples)) colMeans(post$samples)
                  else post$mean
    mae_val    <- mean(abs(point_pred - truth), na.rm = TRUE)
    rmse_val   <- sqrt(mean((point_pred - truth)^2, na.rm = TRUE))
    # Unclamped on purpose -- see the note in benchmark_wosis_p4_p5_p7.R.
    r2_val     <- edaphos_r2(truth, point_pred)
    # Skill against the ACHIEVABLE null: the mean of this fold's TRAINING
    # rows. edaphos_r2() divides by the variance of the test values about
    # THEIR OWN mean, which no deployed map knows -- a strictly harder bar,
    # and the one the manuscript mislabelled as achievable.
    nse_val    <- edaphos_nse(truth, point_pred,
                              null_prediction = mean(train$soc, na.rm = TRUE))
    data.frame(method = name, fold = fd, n_test = n_te,
                 n_train = n_tr, train_capped = FALSE,
                 n_ensemble = budget_of(name),
                 rmse = rmse_val, mae = mae_val, r2 = r2_val, nse = nse_val,
                 crps = cal$crps, picp90 = picp90, mpiw90 = mpiw90,
                 elapsed_s = elapsed, stringsAsFactors = FALSE)
  }
  # Labels describe what each row actually fits.  "P1 Causal+OLS" was renamed
  # because no causal estimand is computed here, only a DAG-based variable
  # selection step (which itself was a no-op until the parents() fix).  "P10
  # GAT" was labelled "random attention + ridge head" while that was true; the
  # attention is now trained by analytic gradients, so the label is dropped.
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P1 OLS (DAG-selected covariates)", post1, c1, t1)
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P6 Quantum KRR",    post6, c6, t6)
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P10 GAT (trained attention)",              post10, c10, t10)
  # Point predictions only -- see the note in benchmark_wosis_p4_p5_p7.R.
  .point_of <- function(p) if (is.null(p)) NULL
                           else if (!is.null(p$samples)) colMeans(p$samples)
                           else as.numeric(p$mean)
  post_bank_new[[fd]] <- list(
    p1 = .point_of(post1), p6 = .point_of(post6), p10 = .point_of(post10),
    # achievable null for this fold
    train_mean = mean(train$soc, na.rm = TRUE),
    truth = truth)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# 4. Merge with v2.8.0 fold-level table + re-aggregate
# ---------------------------------------------------------------------------
message("=== [4/7] Merging with v2.8.0 triple + aggregating ===")
cv_tbl_new <- bind_rows(fold_rows_new)

# The merged bundle must have been produced on the same response scale, or the
# combined table silently mixes g/kg rows with log1p rows.
v280_scale <- v280$response_scale %||% "raw"
if (!identical(v280_scale, RESPONSE_SCALE))
  stop(sprintf(paste("scale mismatch: %s carries response_scale = '%s' but this",
                     "run is '%s'. Re-run data-raw/benchmark_wosis_p4_p5_p7.R",
                     "with the same EDAPHOS_BENCH_SCALE first."),
               basename(V280_PATH), v280_scale, RESPONSE_SCALE), call. = FALSE)
cv_tbl_all <- bind_rows(v280$cv_fold_table, cv_tbl_new)

`%||%` <- function(a, b) if (is.null(a)) b else a

agg <- cv_tbl_all |>
  group_by(method) |>
  summarise(
    n_folds     = dplyr::n(),
    rmse_mean   = mean(rmse,   na.rm = TRUE),
    rmse_sd     = stats::sd(rmse, na.rm = TRUE),
    r2_mean     = mean(r2,     na.rm = TRUE),
    # skill against the achievable (training-fold mean) null; r2_mean
    # above is against the oracle (test-fold mean) null
    nse_mean    = mean(nse,    na.rm = TRUE),
    nse_sd      = stats::sd(nse, na.rm = TRUE),
    picp90_mean = mean(picp90, na.rm = TRUE),
    mpiw90_mean = mean(mpiw90, na.rm = TRUE),
    crps_mean   = mean(crps,   na.rm = TRUE),
    elapsed_sum = sum(elapsed_s, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(rmse_mean)

print(agg)

# ---------------------------------------------------------------------------
# Pooled metrics.  Concatenate every fold's test predictions and score once,
# against the achievable null (each fold's TRAINING-fold mean) rather than the
# global mean, which is an oracle over the very rows being scored.
# ---------------------------------------------------------------------------
pooled_tbl <- local({
  banks <- c(v280$posterior_bank, post_bank_new)
  # A bank slot holds a method's predictions when it is a numeric vector as
  # long as that fold's truth.  Identifying methods structurally -- rather than
  # by excluding known bookkeeping names -- keeps this correct when a new field
  # is added to the bank, and it accepts both the old full-posterior banks and
  # the compact point-prediction ones.
  n_truth  <- function(el) if (is.null(el$truth)) 0L else length(el$truth)
  point_of <- function(p, n) {
    if (inherits(p, "edaphos_posterior"))
      return(if (!is.null(p$samples)) colMeans(p$samples) else as.numeric(p$mean))
    if (is.numeric(p) && length(p) == n) return(as.numeric(p))
    NULL
  }
  meths <- unique(unlist(lapply(banks, function(el) {
    n <- n_truth(el)
    nm <- setdiff(names(el), c("truth", "train_mean"))
    nm[vapply(nm, function(k) !is.null(point_of(el[[k]], n)), logical(1))]
  })))

  acc <- setNames(vector("list", length(meths)), meths)
  truth_v <- null_v <- numeric(0)
  seen <- character(0)
  for (el in banks) {
    if (is.null(el$truth)) next
    # the two banks cover the same folds; count truth and the null once
    fid <- paste0("f", length(el$truth), "_", round(sum(el$truth), 6))
    if (!(fid %in% seen)) {
      seen    <- c(seen, fid)
      truth_v <- c(truth_v, el$truth)
      null_v  <- c(null_v, rep(el$train_mean %||% mean(el$truth),
                               length(el$truth)))
    }
    for (m in meths) {
      pt <- point_of(el[[m]], length(el$truth))
      if (!is.null(pt)) acc[[m]] <- c(acc[[m]], pt)
    }
  }
  ss_null <- sum((truth_v - null_v)^2)
  rows <- lapply(meths, function(m) {
    pr <- acc[[m]]
    if (length(pr) != length(truth_v)) {
      message(sprintf("    [pooled] skipping %s: %d predictions for %d rows",
                      m, length(pr), length(truth_v)))
      return(NULL)
    }
    ok <- is.finite(pr) & is.finite(truth_v)
    data.frame(method = m, n = sum(ok),
      pooled_rmse = edaphos_rmse(truth_v[ok], pr[ok]),
      pooled_r2_vs_global_mean = edaphos_r2(truth_v[ok], pr[ok]),
      nse_vs_training_fold_mean = 1 - sum((truth_v[ok] - pr[ok])^2) / ss_null,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (!is.null(out)) out <- out[order(-out$nse_vs_training_fold_mean), ]
  out
})
cat("
--- pooled (achievable null = training-fold mean) ---
")
print(pooled_tbl)

# ---------------------------------------------------------------------------
# 5. Save combined bundle
# ---------------------------------------------------------------------------
message("=== [5/7] Saving combined bundle ===")
R_out <- list(
  version           = packageVersion("edaphos"),
  date_computed     = Sys.time(),
  n_profiles        = nrow(profiles),
  cov_cols          = cov_cols,
  folds             = folds,
  cv_fold_table     = cv_tbl_all,
  response_scale    = RESPONSE_SCALE,
  response_units    = RESPONSE_UNITS,
  profile_years     = YEAR_SUMMARY,
  ensemble_budgets  = list(P1 = P1_N_BOOT, P6 = P6_N_BOOT, P10 = P10_N_ENS),
  cv_aggregate      = agg,
  # Pooled metrics: every fold's test predictions concatenated and scored once.
  # The unweighted mean of per-fold R2 is not a usable summary under blocked
  # folds -- fold SOC sd ranges 6.5 to 20.7 here, so a fold with a narrow
  # spread dominates the mean regardless of model quality.  `null_*` is the
  # achievable baseline: predict each fold's TRAINING-fold mean.  The global
  # mean is an oracle and is not used as the reference.
  cv_pooled         = pooled_tbl,
  posterior_bank    = c(v280$posterior_bank, post_bank_new),
  excluded_pilares  = list(
    P2 = "Profile ODE (pedogenetic depth dynamics) -- targets full depth profile, not topsoil scalar.",
    P3 = "ConvLSTM 4D pedometry -- requires a temporal stack of maps.",
    P8 = "Neural operators (DeepONet/FNO) -- parameterised over depth function space.",
    P9 = "DDPM -- generates soil-property maps as raster patches; posterior over map draws, not site-level regression."
  ),
  v280_bundle_path = V280_PATH
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
