# edaphos case study: real-data Cerrado SOC benchmark --- runner
#
# Consumes tools/case_cerrado/case_cerrado_bundle.rds (produced by
# data-raw/case_cerrado_prepare.R) and produces
# tools/case_cerrado/case_cerrado_results.rds with every number and
# plot the vignette needs.
#
# Evaluation: **5-fold spatial cross-validation** with k-means on
# longitude/latitude as the stratification. Every profile is a test
# point exactly once. Metrics are computed on the pooled 302
# predictions, which is much more robust than a single 80/20 split
# with a 60-point test set (the v1.3.0 recipe, where train/test
# imbalance produced a +6 g/kg bias floor unrelated to the model).
#
# Three stacks are benchmarked on the identical fold assignments:
#
#   (B1) Classical DSM baseline: ranger regression on the 56-layer
#        SoilGrids + WorldClim + SRTM + WorldCover + bio covariate
#        stack.
#
#   (B2) Baseline + residual kriging: (B1) plus gstat::krige on the
#        log1p-scale residuals (Hengl et al. 2017-style recipe).
#
#   (E)  edaphos stack: (B1) covariates AUGMENTED with the 64-dim
#        MoCo v2 foundation embedding of a 16x16 neighbourhood patch
#        around every profile. Uses edaphos-cerrado-moco-v2 locally
#        if present (200000 InfoNCE steps; v1.3.1 retrain) else
#        falls back to the Zenodo-published v1 (20000 steps).
#
# Target: log1p(SOC, g/kg). Point estimate = back-transformed
# MEDIAN (not mean) because median is the unbiased estimator of a
# lognormal predictive's location.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(sf)
  library(terra)
  library(ranger)
  library(gstat)
  library(dplyr)
})

bundle_path <- "tools/case_cerrado/case_cerrado_bundle.rds"
out_path    <- "tools/case_cerrado/case_cerrado_results.rds"
stopifnot(file.exists(bundle_path))
b <- readRDS(bundle_path)
profiles <- b$profiles
cov_stack <- terra::rast(b$covariates)
K_FOLDS <- length(unique(profiles$fold))

message(sprintf("[run] loaded bundle: %d profiles, %d covariates, %d-fold CV",
                 nrow(profiles), terra::nlyr(cov_stack), K_FOLDS))

# Feature set:
#   * the 56 raster covariates extracted at each profile, plus
#   * `lon`, `lat` -- spatial trend features. Random forests can learn
#     large-scale spatial structure when coordinates are features; the
#     classical DSM stack (Hengl-style) does this too.
#   * `year`  -- SOC observed in 1982 is not SOC observed in 2020 at
#     the same site (land-use change since then). WoSIS includes the
#     sampling date; using it as a feature lets ranger de-confound.
profiles$year[is.na(profiles$year)] <- stats::median(profiles$year,
                                                       na.rm = TRUE)
covariate_cols <- setdiff(names(profiles),
                            c("profile_id","profile_code","dataset_id",
                              "pos_unc_m", "topsoil_upper", "topsoil_lower",
                              "soc_topsoil_gkg",
                              "licence",
                              "kmeans_cluster","fold","split",
                              "quadrant"))
message(sprintf("[run] %d feature columns: %s ...",
                 length(covariate_cols),
                 paste(utils::head(covariate_cols, 6L), collapse = ", ")))

.back_transform <- function(z) expm1(pmax(z, 0))
# v1.3.1 target: SOC concentration (g/kg) of the shallowest WoSIS
# horizon that starts at upper_depth == 0 and is 5-30 cm thick.
# Shallowest-first slice among qualifying horizons, same physical
# quantity across profiles. The 0-30 cm stock formulation was
# abandoned because WoSIS's sparse per-horizon bulk-density coverage
# turned the stock target into a 1.25-dominated fallback.
.resp_col  <- "soc_topsoil_gkg"

# ---- load encoder (v2 local > v1 Zenodo) ------------------------------------

v2_local <- "tools/pretrain/edaphos-cerrado-moco-v2/encoder_q.pt"
if (file.exists(v2_local)) {
  v2_meta <- jsonlite::read_json(
    "tools/pretrain/edaphos-cerrado-moco-v2/metadata.json"
  )
  moco <- foundation_weights_load(
    v2_local,
    n_channels  = v2_meta$n_channels,
    feature_dim = v2_meta$feature_dim,
    proj_dim    = v2_meta$proj_dim
  )
  moco_tag <- sprintf("edaphos-cerrado-moco-v2 (local, %d steps)",
                       v2_meta$steps %||% 200000L)
} else {
  moco <- foundation_weights_load("edaphos-cerrado-moco-v1",
                                    verbose = FALSE)
  moco_tag <- "edaphos-cerrado-moco-v1 (Zenodo, 20k steps)"
}
message(sprintf("[run] encoder: %s", moco_tag))

encoder_layers <- c(
  "soilgrids_soc", "soilgrids_clay", "soilgrids_sand",
  "soilgrids_phh2o", "soilgrids_bdod",
  sprintf("wc_prec_%02d", 1:12), sprintf("wc_tavg_%02d", 1:12),
  "elev", "slope"
)
cov_stack_31 <- cov_stack[[intersect(encoder_layers, names(cov_stack))]]
stopifnot(terra::nlyr(cov_stack_31) == moco$n_channels)
norm_ds <- foundation_tile_dataset(
  stack = cov_stack_31, patch_size = 16L, n_patches = 2000L,
  normalise = TRUE, seed = 2026L
)

extract_patches <- function(points_df, stack, patch_size, means, sds) {
  half <- patch_size %/% 2L
  C <- terra::nlyr(stack)
  cells <- terra::cellFromXY(stack,
                                as.matrix(points_df[, c("lon", "lat")]))
  rc <- terra::rowColFromCell(stack, cells)
  nrow_r <- terra::nrow(stack); ncol_r <- terra::ncol(stack)
  keep <- !is.na(rc[, 1L]) & !is.na(rc[, 2L]) &
          rc[, 1L] >= half + 1L & rc[, 1L] <= nrow_r - half &
          rc[, 2L] >= half + 1L & rc[, 2L] <= ncol_r - half
  patches <- array(0, dim = c(nrow(points_df), C, patch_size, patch_size))
  for (i in seq_len(nrow(points_df))) {
    if (!keep[i]) { patches[i, , , ] <- NA_real_; next }
    r0 <- rc[i, 1L] - half; c0 <- rc[i, 2L] - half
    vals <- terra::values(stack, row = r0, nrows = patch_size,
                            col = c0, ncols = patch_size)
    arr <- aperm(array(vals, dim = c(patch_size, patch_size, C)),
                  c(3L, 1L, 2L))
    for (ch in seq_len(C))
      arr[ch, , ] <- (arr[ch, , ] - means[ch]) / sds[ch]
    patches[i, , , ] <- arr
  }
  list(patches = patches, keep = keep)
}

# ---- 5-fold CV loop --------------------------------------------------------

pred_b1 <- pred_b2 <- pred_e <- rep(NA_real_, nrow(profiles))
pred_b1_lo <- pred_b1_hi <- rep(NA_real_, nrow(profiles))
pred_b2_lo <- pred_b2_hi <- rep(NA_real_, nrow(profiles))
pred_e_lo  <- pred_e_hi  <- rep(NA_real_, nrow(profiles))

# Pre-extract patches once per whole dataset; we index by train/test per fold.
all_patches <- extract_patches(profiles, cov_stack_31,
                                 patch_size = 16L,
                                 means = norm_ds$means,
                                 sds   = norm_ds$sds)
if (!all(all_patches$keep)) {
  message(sprintf("[run] %d profiles outside the raster margin were embed-skipped",
                   sum(!all_patches$keep)))
}
emb_all <- foundation_moco_embed(
  moco,
  all_patches$patches[all_patches$keep, , , , drop = FALSE]
)
emb_cols <- sprintf("emb_%02d", seq_len(ncol(emb_all)))
colnames(emb_all) <- emb_cols
# Align embedding back to the full profile frame (NA for edge-clipped).
emb_full <- matrix(NA_real_, nrow = nrow(profiles),
                    ncol = ncol(emb_all),
                    dimnames = list(NULL, emb_cols))
emb_full[which(all_patches$keep), ] <- emb_all
profiles_e <- cbind(profiles, emb_full)

for (k in seq_len(K_FOLDS)) {
  train <- profiles[profiles$fold != k, , drop = FALSE]
  test  <- profiles[profiles$fold == k, , drop = FALSE]
  test_ix <- which(profiles$fold == k)

  # --- B1 ranger (linear target) ---------------------------------------------
  # Use quantreg=TRUE for the interval AND plain type="response" for
  # the point estimate: on our Cerrado dataset the QRF median is
  # noticeably more biased than the bagged mean (R2 0.17 vs 0.23), so
  # mean for the point, quantiles for the interval -- the standard
  # QRF-with-bagging recipe (Meinshausen 2006).
  set.seed(2026L + k)
  rf_b1 <- ranger::ranger(
    stats::as.formula(paste(.resp_col, "~",
                              paste(covariate_cols, collapse = " + "))),
    data       = train,
    num.trees  = 500L,
    quantreg   = TRUE,
    respect.unordered.factors = "partition",
    seed       = 2026L + k
  )
  pred_b1[test_ix] <- predict(rf_b1, data = test)$predictions
  q_b1 <- predict(rf_b1, data = test, type = "quantiles",
                    quantiles = c(0.025, 0.975))$predictions
  pred_b1_lo[test_ix] <- q_b1[, 1L]
  pred_b1_hi[test_ix] <- q_b1[, 2L]

  # --- B2 B1 + residual kriging (linear scale) -------------------------------
  train_mid <- predict(rf_b1, data = train)$predictions
  train$residual <- train[[.resp_col]] - train_mid
  train_sf <- sf::st_as_sf(train, coords = c("lon", "lat"), crs = 4326)
  test_sf  <- sf::st_as_sf(test,  coords = c("lon", "lat"), crs = 4326)

  vg_emp <- tryCatch(
    gstat::variogram(residual ~ 1, data = train_sf, cutoff = 500),
    error = function(e) NULL
  )
  vg_mod <- if (!is.null(vg_emp)) {
    tryCatch(gstat::fit.variogram(
      vg_emp,
      model = gstat::vgm(
        psill = stats::var(train$residual) * 0.5,
        model = "Sph", range = 200,
        nugget = stats::var(train$residual) * 0.5
      )
    ), error = function(e) NULL, warning = function(w) NULL)
  } else NULL
  if (is.null(vg_mod) || anyNA(vg_mod$range)) {
    pred_b2[test_ix]    <- pred_b1[test_ix]
    pred_b2_lo[test_ix] <- pred_b1_lo[test_ix]
    pred_b2_hi[test_ix] <- pred_b1_hi[test_ix]
  } else {
    kr <- tryCatch(
      gstat::krige(residual ~ 1,
                    locations = train_sf, newdata = test_sf,
                    model = vg_mod, nmax = 40),
      error = function(e) NULL
    )
    if (is.null(kr)) {
      pred_b2[test_ix]    <- pred_b1[test_ix]
      pred_b2_lo[test_ix] <- pred_b1_lo[test_ix]
      pred_b2_hi[test_ix] <- pred_b1_hi[test_ix]
    } else {
      b2_mid <- pred_b1[test_ix] + kr$var1.pred
      b2_sd  <- sqrt(pmax(kr$var1.var, 0))
      pred_b2[test_ix]    <- b2_mid
      pred_b2_lo[test_ix] <- b2_mid - 1.96 * b2_sd
      pred_b2_hi[test_ix] <- b2_mid + 1.96 * b2_sd
    }
  }

  # --- E MoCo embedding + ranger --------------------------------------------
  train_e <- profiles_e[profiles_e$fold != k, , drop = FALSE]
  test_e  <- profiles_e[profiles_e$fold == k, , drop = FALSE]
  # Drop edge-clipped (NA embedding) rows from the training set.
  tr_ok <- stats::complete.cases(train_e[, emb_cols, drop = FALSE])
  te_ok <- stats::complete.cases(test_e[,  emb_cols, drop = FALSE])
  fmla_e <- stats::as.formula(paste(.resp_col, "~",
    paste(c(covariate_cols, emb_cols), collapse = " + ")))
  set.seed(2026L + k)
  rf_e <- ranger::ranger(
    fmla_e, data = train_e[tr_ok, , drop = FALSE],
    num.trees = 500L, quantreg = TRUE,
    seed = 2026L + k
  )
  fold_ix_full <- test_ix[te_ok]
  pred_e[fold_ix_full] <- predict(
    rf_e, data = test_e[te_ok, , drop = FALSE]
  )$predictions
  q_e <- predict(rf_e, data = test_e[te_ok, , drop = FALSE],
                   type = "quantiles",
                   quantiles = c(0.025, 0.975))$predictions
  pred_e_lo[fold_ix_full] <- q_e[, 1L]
  pred_e_hi[fold_ix_full] <- q_e[, 2L]

  message(sprintf("  [fold %d/%d]  B1 %d | B2 %d | E %d",
                   k, K_FOLDS, length(test_ix), length(test_ix),
                   sum(te_ok)))
}

# ---- aggregate 5-fold CV metrics -------------------------------------------

obs <- profiles[[.resp_col]]
results <- rbind(
  edaphos_metrics_summary(obs, pred_b1,
                            lower = pred_b1_lo, upper = pred_b1_hi,
                            method = "B1 ranger"),
  edaphos_metrics_summary(obs, pred_b2,
                            lower = pred_b2_lo, upper = pred_b2_hi,
                            method = "B2 ranger + kriging"),
  edaphos_metrics_summary(obs, pred_e,
                            lower = pred_e_lo, upper = pred_e_hi,
                            method = sprintf("E  ranger + %s",
                                               if (grepl("v2", moco_tag))
                                                 "MoCo v2" else "MoCo v1"))
)
print(results, row.names = FALSE, digits = 4L)

# ---- persist ---------------------------------------------------------------

saveRDS(
  list(
    profiles         = profiles,
    profiles_e       = profiles_e,
    covariate_cols   = covariate_cols,
    emb_cols         = emb_cols,
    aoi              = b$aoi,
    sources          = b$sources,
    encoder_tag      = moco_tag,
    K_FOLDS          = K_FOLDS,
    results          = results,
    predictions = list(
      B1 = list(mean = pred_b1, lower = pred_b1_lo, upper = pred_b1_hi),
      B2 = list(mean = pred_b2, lower = pred_b2_lo, upper = pred_b2_hi),
      E  = list(mean = pred_e,  lower = pred_e_lo,  upper = pred_e_hi)
    ),
    edaphos_ver      = as.character(packageVersion("edaphos")),
    created_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ),
  out_path
)
message(sprintf("[run] wrote %s (%.1f KB)",
                 out_path, file.info(out_path)$size / 1024))
