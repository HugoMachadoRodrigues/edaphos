# edaphos case study: real-data Cerrado SOC benchmark --- runner
#
# Consumes tools/case_cerrado/case_cerrado_bundle.rds (produced by
# data-raw/case_cerrado_prepare.R) and produces
# tools/case_cerrado/case_cerrado_results.rds with every number and
# plot the vignette needs.
#
# Three stacks are benchmarked on the identical 80/20 train/test
# split:
#
#   (B1) Classical DSM baseline: ranger regression on the 31-layer
#        SoilGrids + WorldClim + SRTM covariate stack.
#
#   (B2) Baseline + residual kriging: (B1) point predictions plus
#        gstat::krige residual kriging, the canonical Hengl-style
#        DSM recipe (Hengl et al. 2017).
#
#   (E)  edaphos stack: (B1) covariates AUGMENTED with the 64-dim
#        MoCo v2 foundation embedding of a 16x16 neighbourhood patch
#        around every profile, using the publicly-released
#        edaphos-cerrado-moco-v1 encoder (DOI 10.5281/zenodo.19701276).
#
# Every stack returns a point estimate + 95 % prediction interval
# (via QRF quantile regression) so the interval-score and PICP rows
# of the final table are comparable.

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

message(sprintf("[run] loaded bundle: %d profiles (train=%d, test=%d), %d covariates",
                 nrow(profiles), sum(profiles$split == "train"),
                 sum(profiles$split == "test"), terra::nlyr(cov_stack)))

# ---- feature matrices ------------------------------------------------------

covariate_cols <- setdiff(names(profiles),
                            c("profile_id","profile_code","dataset_id",
                              "year","upper_depth","lower_depth","soc_gkg",
                              "licence","lon","lat","quadrant","split"))
message(sprintf("[run] %d covariate columns: %s",
                 length(covariate_cols),
                 paste(utils::head(covariate_cols, 8L), collapse = ", ")))

train_df <- profiles[profiles$split == "train", , drop = FALSE]
test_df  <- profiles[profiles$split == "test",  , drop = FALSE]

# ---- Stack B1: ranger quantile regression on covariates --------------------

message("[run] B1  ranger QRF on raw covariates (baseline)")
set.seed(2026L)
fmla_base <- stats::as.formula(paste("soc_gkg ~",
                                       paste(covariate_cols, collapse = " + ")))
rf_b1 <- ranger::ranger(
  formula        = fmla_base,
  data           = train_df,
  num.trees      = 500L,
  quantreg       = TRUE,
  respect.unordered.factors = "partition",
  seed           = 2026L
)
pred_b1_mean <- predict(rf_b1, data = test_df)$predictions
pred_b1_q    <- predict(rf_b1, data = test_df, type = "quantiles",
                          quantiles = c(0.025, 0.5, 0.975))$predictions
message(sprintf("  [ok] B1 test RMSE = %.3f g/kg",
                 edaphos_rmse(test_df$soc_gkg, pred_b1_mean)))

# ---- Stack B2: B1 + gstat residual kriging --------------------------------

message("[run] B2  B1 + gstat residual kriging")
train_pred_b1 <- predict(rf_b1, data = train_df)$predictions
train_df$residual <- train_df$soc_gkg - train_pred_b1

train_sf <- sf::st_as_sf(train_df, coords = c("lon", "lat"), crs = 4326)
test_sf  <- sf::st_as_sf(test_df,  coords = c("lon", "lat"), crs = 4326)

# Fit a spherical variogram; fall back to exponential if sph fit fails.
vg_emp  <- gstat::variogram(residual ~ 1, data = train_sf, cutoff = 500)
vg_init <- gstat::vgm(
  psill = stats::var(train_df$residual) * 0.5,
  model = "Sph",
  range = 200,
  nugget = stats::var(train_df$residual) * 0.5
)
vg_mod <- tryCatch(
  gstat::fit.variogram(vg_emp, model = vg_init),
  error = function(e) NULL
)
if (is.null(vg_mod)) {
  vg_init$model <- "Exp"
  vg_mod <- gstat::fit.variogram(vg_emp, model = vg_init)
}
kr <- gstat::krige(
  formula = residual ~ 1,
  locations = train_sf,
  newdata   = test_sf,
  model     = vg_mod,
  nmax      = 40
)
pred_b2_mean <- pred_b1_mean + kr$var1.pred
# Propagate the kriging variance into a Gaussian 95 % interval.
pred_b2_sd    <- sqrt(pmax(kr$var1.var, 0))
pred_b2_lower <- pred_b2_mean - 1.96 * pred_b2_sd
pred_b2_upper <- pred_b2_mean + 1.96 * pred_b2_sd
message(sprintf("  [ok] B2 test RMSE = %.3f g/kg (variogram: %s, range %.1f)",
                 edaphos_rmse(test_df$soc_gkg, pred_b2_mean),
                 as.character(vg_mod$model[2]),
                 vg_mod$range[2]))

# ---- Stack E: edaphos MoCo embedding + ranger ------------------------------

message("[run] E   edaphos-cerrado-moco-v1 embedding + ranger")

# Load pretrained encoder (pulls from Zenodo with SHA-256 verify +
# local cache; subsequent calls are instant).
moco <- foundation_weights_load("edaphos-cerrado-moco-v1",
                                  verbose = TRUE)

# The encoder was pretrained on a 31-channel subset (5 SoilGrids +
# 24 WorldClim + elev + slope). The case-study stack happens to
# include TPI too -- keep that for the ranger baseline but drop it
# before feeding patches to the encoder, so channel counts line up.
encoder_layers <- c(
  "soilgrids_soc", "soilgrids_clay", "soilgrids_sand",
  "soilgrids_phh2o", "soilgrids_bdod",
  sprintf("wc_prec_%02d", 1:12), sprintf("wc_tavg_%02d", 1:12),
  "elev", "slope"
)
cov_stack_31 <- cov_stack[[intersect(encoder_layers, names(cov_stack))]]
stopifnot(terra::nlyr(cov_stack_31) == moco$n_channels)

# Build a tile dataset JUST for normalisation stats (means / sds per
# channel over the 31-channel subset). We don't actually sample
# patches from the dataset object -- just use the `means`/`sds`.
norm_ds <- foundation_tile_dataset(
  stack = cov_stack_31, patch_size = 16L, n_patches = 2000L,
  normalise = TRUE, seed = 2026L
)
stopifnot(norm_ds$n_channels == moco$n_channels)

# Extract 16x16 patches centred on every profile. Pads with NA when
# a profile is too close to the raster edge; such patches are dropped
# (and the corresponding SOC value also dropped from the eval set).
extract_patches <- function(points_df, stack, patch_size = 16L,
                              means, sds) {
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
    if (!keep[i]) {
      patches[i, , , ] <- NA_real_
      next
    }
    r0 <- rc[i, 1L] - half
    c0 <- rc[i, 2L] - half
    vals <- terra::values(
      stack, row = r0, nrows = patch_size,
      col = c0, ncols = patch_size
    )
    arr <- aperm(array(vals, dim = c(patch_size, patch_size, C)),
                  c(3L, 1L, 2L))
    for (ch in seq_len(C)) {
      arr[ch, , ] <- (arr[ch, , ] - means[ch]) / sds[ch]
    }
    patches[i, , , ] <- arr
  }
  list(patches = patches, keep = keep)
}

train_patches <- extract_patches(train_df, cov_stack_31,
                                   patch_size = moco$patch_size %||% 16L,
                                   means = norm_ds$means,
                                   sds   = norm_ds$sds)
test_patches  <- extract_patches(test_df, cov_stack_31,
                                   patch_size = moco$patch_size %||% 16L,
                                   means = norm_ds$means,
                                   sds   = norm_ds$sds)

message(sprintf("  [ok] patches: train %d / %d  test %d / %d (edge-clipped)",
                 sum(train_patches$keep), nrow(train_df),
                 sum(test_patches$keep),  nrow(test_df)))

# Embed via MoCo backbone features.
emb_train <- foundation_moco_embed(moco,
                                     train_patches$patches[train_patches$keep, , , ,
                                                            drop = FALSE])
emb_test  <- foundation_moco_embed(moco,
                                     test_patches$patches[test_patches$keep, , , ,
                                                           drop = FALSE])
emb_cols <- sprintf("emb_%02d", seq_len(ncol(emb_train)))
colnames(emb_train) <- emb_cols
colnames(emb_test)  <- emb_cols

train_df_e <- cbind(train_df[train_patches$keep, , drop = FALSE],
                     emb_train)
test_df_e  <- cbind(test_df[test_patches$keep, , drop = FALSE],
                     emb_test)

fmla_e <- stats::as.formula(paste(
  "soc_gkg ~",
  paste(c(covariate_cols, emb_cols), collapse = " + ")
))
set.seed(2026L)
rf_e <- ranger::ranger(
  formula    = fmla_e,
  data       = train_df_e,
  num.trees  = 500L,
  quantreg   = TRUE,
  seed       = 2026L
)
pred_e_mean <- predict(rf_e, data = test_df_e)$predictions
pred_e_q    <- predict(rf_e, data = test_df_e, type = "quantiles",
                         quantiles = c(0.025, 0.5, 0.975))$predictions
message(sprintf("  [ok] E  test RMSE = %.3f g/kg",
                 edaphos_rmse(test_df_e$soc_gkg, pred_e_mean)))

# ---- Metric table ----------------------------------------------------------

obs_all <- test_df$soc_gkg
obs_e   <- test_df_e$soc_gkg

results <- rbind(
  edaphos_metrics_summary(obs_all, pred_b1_mean,
                            lower = pred_b1_q[, 1L],
                            upper = pred_b1_q[, 3L],
                            method = "B1 ranger"),
  edaphos_metrics_summary(obs_all, pred_b2_mean,
                            lower = pred_b2_lower,
                            upper = pred_b2_upper,
                            method = "B2 ranger + kriging"),
  edaphos_metrics_summary(obs_e, pred_e_mean,
                            lower = pred_e_q[, 1L],
                            upper = pred_e_q[, 3L],
                            method = "E  ranger + MoCo embed")
)
print(results, row.names = FALSE)

# ---- Persist for the vignette ----------------------------------------------

saveRDS(
  list(
    profiles = profiles,
    covariate_cols = covariate_cols,
    emb_cols       = emb_cols,
    aoi = b$aoi,
    sources = b$sources,
    results = results,
    predictions = list(
      B1 = list(mean = pred_b1_mean, q = pred_b1_q),
      B2 = list(mean = pred_b2_mean, lower = pred_b2_lower,
                 upper = pred_b2_upper,
                 variogram = vg_mod),
      E  = list(mean = pred_e_mean,  q = pred_e_q,
                 keep = test_patches$keep)
    ),
    test_df      = test_df,
    test_df_e    = test_df_e,
    edaphos_ver  = as.character(packageVersion("edaphos")),
    created_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ),
  out_path
)
message(sprintf("[run] wrote %s (%.1f KB)",
                 out_path, file.info(out_path)$size / 1024))
