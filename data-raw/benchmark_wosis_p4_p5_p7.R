## data-raw/benchmark_wosis_p4_p5_p7.R  (v2.8.0)
##
## Head-to-head benchmark of three pillars on the 1 095 real WoSIS
## Cerrado topsoil profiles:
##
##   P4 Foundation (MoCo v1 embeddings + RBF-KRR head)
##   P5 Active-Learning backbone (QRF quantile-regression forest)
##   P7 Bayesian Hierarchical Spatial (Gibbs sampler, v2.3.0)
##
## Evaluation: 5-fold spatial CV (k-means on lon/lat).  For each fold
## each method produces either a quantile grid (P5, P4 RBF-KRR) or an
## MCMC posterior (P7 Gibbs); we unify them through the v1.6.0
## `edaphos_posterior` class and score with `uncertainty_calibrate()`.
##
## Output: inst/extdata/benchmark_wosis_p4_p5_p7.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(dplyr))
set.seed(20260424L)

OUT_PATH <- file.path("inst", "extdata", "benchmark_wosis_p4_p5_p7.rds")

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load the 1 095 real WoSIS Cerrado profiles
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/7] Loading WoSIS profiles ===")
causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
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
message(sprintf("  n = %d profiles", nrow(profiles)))
message(sprintf("  soc: mean=%.2f, sd=%.2f, range=[%.2f, %.2f]",
                mean(profiles$soc), stats::sd(profiles$soc),
                min(profiles$soc),  max(profiles$soc)))

cov_cols <- c("map", "mat", "slope", "elev", "clay", "sand", "bd",
               "trees", "cropland", "grass")
cov_cols <- intersect(cov_cols, names(profiles))
profiles <- profiles[stats::complete.cases(profiles[, cov_cols]), ]
message(sprintf("  After NA drop: %d profiles", nrow(profiles)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. 5-fold spatial CV (k-means cluster)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/7] Building 5 spatial folds ===")
set.seed(1L)
folds <- stats::kmeans(profiles[, c("lon", "lat")],
                         centers = 5L, nstart = 10L)$cluster
profiles$fold5 <- folds
tab <- table(folds)
message(sprintf("  fold sizes: %s",
                 paste(sprintf("%d=%d", as.integer(names(tab)),
                                 as.integer(tab)),
                        collapse = ", ")))

# ─────────────────────────────────────────────────────────────────────────────
# 3. Method wrappers  -- each returns a posterior of (n_test) preds
# ─────────────────────────────────────────────────────────────────────────────

# P5: QRF quantile regression forest -> quantile grid
fit_p5_qrf <- function(train, test, cov_cols) {
  df_tr <- train[, c("soc", cov_cols), drop = FALSE]
  rf <- ranger::ranger(soc ~ ., data = df_tr,
                         num.trees = 500L, quantreg = TRUE,
                         verbose = FALSE)
  qs <- seq(0.01, 0.99, length.out = 99L)
  pr <- predict(rf, data = test[, cov_cols, drop = FALSE],
                 type = "quantiles", quantiles = qs)$predictions
  edaphos_posterior(samples = t(pr), method = "loo_cv",
                      query_type = "map", units = "g/kg")
}

# P4 Foundation: MoCo v1 encoder + ranger head on embeddings
fit_p4_foundation <- function(train, test, cov_cols, moco, dataset_meta,
                                synth_stack) {
  emb_all <- foundation_embed_at_coords(
    moco        = moco,
    coords      = rbind(train[, c("lon", "lat")],
                           test[, c("lon", "lat")]),
    stack       = synth_stack,
    dataset     = dataset_meta,
    patch_size  = 16L, batch_size = 64L
  )
  n_tr <- nrow(train)
  emb_tr <- emb_all[seq_len(n_tr), , drop = FALSE]
  emb_te <- emb_all[seq(n_tr + 1L, nrow(emb_all)), , drop = FALSE]
  # Impute column-mean for any NA rows at the edge -- ranger cannot
  # accept NA; training points with NA get their embedding row
  # replaced by the training-pool mean, same for test.
  col_mean_tr <- colMeans(emb_tr, na.rm = TRUE)
  fill_na <- function(M, means) {
    for (j in seq_len(ncol(M))) {
      na_ij <- is.na(M[, j])
      if (any(na_ij)) M[na_ij, j] <- means[j]
    }
    M
  }
  emb_tr <- fill_na(emb_tr, col_mean_tr)
  emb_te <- fill_na(emb_te, col_mean_tr)
  df_tr <- cbind(train[, c("soc", cov_cols), drop = FALSE],
                   as.data.frame(emb_tr))
  df_te <- cbind(test[, cov_cols, drop = FALSE],
                   as.data.frame(emb_te))
  rf <- ranger::ranger(soc ~ ., data = df_tr,
                         num.trees = 500L, quantreg = TRUE,
                         verbose = FALSE)
  qs <- seq(0.01, 0.99, length.out = 99L)
  pr <- predict(rf, data = df_te,
                 type = "quantiles", quantiles = qs)$predictions
  edaphos_posterior(samples = t(pr), method = "ensemble",
                      query_type = "map", units = "g/kg")
}

# P7 BHS: Bayesian hierarchical spatial (Gibbs v2.3.0)
fit_p7_bhs <- function(train, test, cov_cols,
                         nmcmc = 400L, burn = 200L) {
  # Simple additive model with a spatial random effect
  fml <- stats::as.formula(paste("soc ~", paste(cov_cols, collapse = " + ")))
  fit <- bhs_fit(data = train, formula = fml,
                   coords = c("lon", "lat"),
                   backend = "gibbs",
                   nmcmc = nmcmc, burn = burn,
                   phi_range = c(0.05, 5),
                   seed = 1L, verbose = FALSE)
  pr <- predict(fit, newdata = test,
                 quantiles = seq(0.025, 0.975, length.out = 20L),
                 n_draws = 200L)
  # Reconstruct samples ~ N(mean, sd) via the predicted summary
  # (predict.edaphos_bhs returns mean+sd+quantiles).
  samps <- matrix(NA_real_, nrow = 200L, ncol = nrow(test))
  for (j in seq_len(nrow(test))) {
    samps[, j] <- stats::rnorm(200L, pr$mean[j], pr$sd[j])
  }
  edaphos_posterior(samples = samps, method = "bayesian",
                      query_type = "map", units = "g/kg")
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Set up MoCo v1 encoder + synthetic stack (shared across folds)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/7] Loading MoCo v1 encoder + building synthetic stack ===")
moco <- foundation_weights_load("edaphos-cerrado-moco-v1", verbose = FALSE)
dataset_meta <- list(
  patch_size = 16L, n_channels = moco$n_channels,
  means = rep(0, moco$n_channels), sds = rep(1, moco$n_channels)
)
bbox <- c(min(profiles$lon) - 0.2, min(profiles$lat) - 0.2,
           max(profiles$lon) + 0.2, max(profiles$lat) + 0.2)
library(terra)
tpl <- terra::rast(xmin = bbox[1], xmax = bbox[3],
                    ymin = bbox[2], ymax = bbox[4],
                    crs  = "EPSG:4326",
                    resolution = 0.05,
                    nlyrs = 1L)
terra::values(tpl) <- stats::rnorm(terra::ncell(tpl))
stk <- terra::rast(replicate(moco$n_channels, tpl, simplify = FALSE))
for (k in seq_len(moco$n_channels))
  terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))
message(sprintf("  synthetic stack: %d x %d x %d",
                terra::nrow(stk), terra::ncol(stk), terra::nlyr(stk)))

# ─────────────────────────────────────────────────────────────────────────────
# 5. Run 5-fold CV
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/7] Running 5-fold spatial CV ===")

fold_rows <- list()
posterior_bank <- list()

for (fd in 1:5) {
  message(sprintf("  fold %d/5", fd))
  train_ix <- which(profiles$fold5 != fd)
  test_ix  <- which(profiles$fold5 == fd)
  train    <- profiles[train_ix, , drop = FALSE]
  test     <- profiles[test_ix,  , drop = FALSE]
  n_tr <- nrow(train); n_te <- nrow(test)
  message(sprintf("    train=%d, test=%d", n_tr, n_te))

  # P5 QRF
  t5 <- system.time({
    post5 <- tryCatch(fit_p5_qrf(train, test, cov_cols),
                        error = function(e) {
                          message("    [P5 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]
  # P4 Foundation
  t4 <- system.time({
    post4 <- tryCatch(fit_p4_foundation(train, test, cov_cols,
                                           moco, dataset_meta, stk),
                        error = function(e) {
                          message("    [P4 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]
  # P7 BHS (cap training at 300 for MCMC speed)
  train_bhs <- if (n_tr > 300L) train[sample(n_tr, 300L), ] else train
  t7 <- system.time({
    post7 <- tryCatch(fit_p7_bhs(train_bhs, test, cov_cols,
                                    nmcmc = 300L, burn = 150L),
                        error = function(e) {
                          message("    [P7 warn] ", conditionMessage(e))
                          NULL
                        })
  })["elapsed"]

  # Evaluate each posterior
  truth <- test$soc
  eval_post <- function(post) {
    if (is.null(post)) return(NULL)
    tryCatch(uncertainty_calibrate(post, truth = truth),
              error = function(e) NULL)
  }
  c5 <- eval_post(post5); c4 <- eval_post(post4); c7 <- eval_post(post7)

  grab <- function(name, post, cal, elapsed) {
    if (is.null(cal)) {
      return(data.frame(method = name, fold = fd, n_test = n_te,
                          rmse = NA, mae = NA, r2 = NA,
                          crps = NA, picp90 = NA, mpiw90 = NA,
                          elapsed_s = elapsed, stringsAsFactors = FALSE))
    }
    picp90 <- if ("0.90" %in% names(cal$picp)) cal$picp[["0.90"]] else
              if ("0.9"  %in% names(cal$picp)) cal$picp[["0.9"]]  else NA_real_
    mpiw90 <- if ("0.90" %in% names(cal$mpiw)) cal$mpiw[["0.90"]] else
              if ("0.9"  %in% names(cal$mpiw)) cal$mpiw[["0.9"]]  else NA_real_
    # Point predictions = posterior mean along axis 2
    point_pred <- if (!is.null(post$samples))
      colMeans(post$samples) else post$mean
    abs_err    <- abs(point_pred - truth)
    mae_val    <- mean(abs_err, na.rm = TRUE)
    rmse_val   <- sqrt(mean((point_pred - truth)^2, na.rm = TRUE))
    r2_val     <- max(0, 1 -
                           mean((point_pred - truth)^2, na.rm = TRUE) /
                           mean((truth - mean(truth))^2))
    data.frame(
      method    = name, fold = fd, n_test = n_te,
      rmse      = rmse_val, mae = mae_val, r2 = r2_val,
      crps      = cal$crps,
      picp90    = picp90,
      mpiw90    = mpiw90,
      elapsed_s = elapsed,
      stringsAsFactors = FALSE
    )
  }
  fold_rows[[length(fold_rows) + 1L]] <- grab("P5 QRF",           post5, c5, t5)
  fold_rows[[length(fold_rows) + 1L]] <- grab("P4 Foundation+QRF", post4, c4, t4)
  fold_rows[[length(fold_rows) + 1L]] <- grab("P7 BHS",            post7, c7, t7)
  posterior_bank[[fd]] <- list(p5 = post5, p4 = post4, p7 = post7,
                                 truth = truth)
}

cv_tbl <- bind_rows(fold_rows)
message("=== [5/7] Fold-level table ===")
print(cv_tbl)

# ─────────────────────────────────────────────────────────────────────────────
# 6. Aggregate
# ─────────────────────────────────────────────────────────────────────────────
message("=== [6/7] Cross-fold aggregate ===")

agg <- cv_tbl |>
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
  )
print(agg)

# ─────────────────────────────────────────────────────────────────────────────
# 7. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [7/7] Saving bundle ===")
R_out <- list(
  version        = packageVersion("edaphos"),
  date_computed  = Sys.time(),
  n_profiles     = nrow(profiles),
  cov_cols       = cov_cols,
  folds          = folds,
  cv_fold_table  = cv_tbl,
  cv_aggregate   = agg,
  posterior_bank = posterior_bank
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
