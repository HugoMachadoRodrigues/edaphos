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

v280 <- tryCatch(readRDS(V280_PATH), error = function(e) NULL)
if (is.null(v280))
  stop("v2.8.0 benchmark RDS missing; run data-raw/benchmark_wosis_p4_p5_p7.R first.")
folds <- v280$folds
profiles$fold5 <- folds

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
  train_ix <- which(profiles$fold5 != fd)
  test_ix  <- which(profiles$fold5 == fd)
  train    <- profiles[train_ix, , drop = FALSE]
  test     <- profiles[test_ix,  , drop = FALSE]
  n_tr <- nrow(train); n_te <- nrow(test)
  message(sprintf("    train=%d, test=%d", n_tr, n_te))

  # P1 Causal (parametric bootstrap OLS on DAG-adjusted set)
  t1 <- system.time({
    post1 <- tryCatch(benchmark_fit_p1_causal(train, test, cov_cols,
                                                    dag = causal_rds$dag,
                                                    n_boot = 300L),
                        error = function(e) {
                          message("    [P1 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]

  # P6 Quantum (bootstrap-ensemble over circuit KRR).
  # n_pcs = 6, reps = 1 keeps the full 1 095-profile run within ~15 min.
  t6 <- system.time({
    post6 <- tryCatch(benchmark_fit_p6_quantum(train, test, cov_cols,
                                                     n_pcs = 6L, reps = 1L,
                                                     n_boot = 10L,
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

  grab <- function(name, post, cal, elapsed) {
    if (is.null(cal)) {
      return(data.frame(method = name, fold = fd, n_test = n_te,
                          rmse = NA, mae = NA, r2 = NA,
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
    r2_val     <- max(0, 1 -
                          mean((point_pred - truth)^2, na.rm = TRUE) /
                          mean((truth - mean(truth))^2))
    data.frame(method = name, fold = fd, n_test = n_te,
                 rmse = rmse_val, mae = mae_val, r2 = r2_val,
                 crps = cal$crps, picp90 = picp90, mpiw90 = mpiw90,
                 elapsed_s = elapsed, stringsAsFactors = FALSE)
  }
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P1 Causal+OLS",     post1, c1, t1)
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P6 Quantum KRR",    post6, c6, t6)
  fold_rows_new[[length(fold_rows_new) + 1L]] <- grab("P10 GAT ensemble",  post10, c10, t10)
  post_bank_new[[fd]] <- list(p1 = post1, p6 = post6, p10 = post10,
                                truth = truth)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# 4. Merge with v2.8.0 fold-level table + re-aggregate
# ---------------------------------------------------------------------------
message("=== [4/7] Merging with v2.8.0 triple + aggregating ===")
cv_tbl_new <- bind_rows(fold_rows_new)
cv_tbl_all <- bind_rows(v280$cv_fold_table, cv_tbl_new)

agg <- cv_tbl_all |>
  group_by(method) |>
  summarise(
    n_folds     = dplyr::n(),
    rmse_mean   = mean(rmse,   na.rm = TRUE),
    rmse_sd     = stats::sd(rmse, na.rm = TRUE),
    r2_mean     = mean(r2,     na.rm = TRUE),
    picp90_mean = mean(picp90, na.rm = TRUE),
    mpiw90_mean = mean(mpiw90, na.rm = TRUE),
    crps_mean   = mean(crps,   na.rm = TRUE),
    elapsed_sum = sum(elapsed_s, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(rmse_mean)

print(agg)

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
  cv_aggregate      = agg,
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
