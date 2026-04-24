## data-raw/quantum_foundation_benchmark.R  (v2.0.0)
##
## Head-to-head benchmark of four SOC-regression methods on the 1 095
## WoSIS Cerrado profiles:
##
##   1. ranger (QRF) baseline on raw covariates
##   2. RBF Kernel Ridge Regression on foundation-embedding PCs
##   3. Quantum Kernel Ridge Regression on raw covariates (Pillar 6)
##   4. **Quantum Kernel Ridge Regression on foundation-embedding PCs**
##      (v2.0.0 contribution -- Pillar 4 x Pillar 6 fusion)
##
## Re-extracts embeddings using the v1.9.1 infrastructure with the
## cached v1 encoder + synthetic raster stack (or real if
## EDAPHOS_IV_REAL_STACK=1).
##
## Output: inst/extdata/quantum_foundation_cerrado.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages({
  library(dplyr); library(terra); library(torch)
})
set.seed(20260425L)

OUT_PATH <- file.path("inst", "extdata", "quantum_foundation_cerrado.rds")
N_PCS    <- 6L  # qubits for the quantum lift (6 -> Hilbert dim 64)

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load encoder + build stack + extract embeddings
# ─────────────────────────────────────────────────────────────────────────────
message("=== [1/5] Loading encoder + building synthetic stack ===")
moco <- foundation_weights_load("edaphos-cerrado-moco-v1", verbose = TRUE)
ENCODER_PATCH_SIZE <- 16L

dataset_meta <- list(
  patch_size = ENCODER_PATCH_SIZE,
  n_channels = moco$n_channels,
  means      = rep(0, moco$n_channels),
  sds        = rep(1, moco$n_channels)
)

causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles <- causal_rds$profiles |>
  filter(!is.na(soc_topsoil_gkg), !is.na(lon), !is.na(lat))
bbox <- c(min(profiles$lon) - 0.2, min(profiles$lat) - 0.2,
           max(profiles$lon) + 0.2, max(profiles$lat) + 0.2)

tpl <- terra::rast(xmin = bbox[1], xmax = bbox[3],
                    ymin = bbox[2], ymax = bbox[4],
                    crs  = "EPSG:4326", resolution = 0.05, nlyrs = 1L)
stk <- terra::rast(replicate(moco$n_channels, tpl, simplify = FALSE))
for (k in seq_len(moco$n_channels))
  terra::values(stk[[k]]) <- stats::rnorm(terra::ncell(stk))
names(stk) <- sprintf("ch_%02d", seq_len(moco$n_channels))

message(sprintf("  Extracting embeddings at %d coords ...",
                nrow(profiles)))
emb <- foundation_embed_at_coords(
  moco        = moco,
  coords      = profiles[, c("lon", "lat")],
  stack       = stk,
  dataset     = dataset_meta,
  patch_size  = ENCODER_PATCH_SIZE,
  batch_size  = 32L
)
keep <- stats::complete.cases(emb)
profiles_k <- profiles[keep, , drop = FALSE]
emb_k <- emb[keep, , drop = FALSE]
y <- profiles_k$soc_topsoil_gkg

message(sprintf("  %d clean profiles x %d embedding dims",
                nrow(emb_k), ncol(emb_k)))

# ─────────────────────────────────────────────────────────────────────────────
# 2. Build the raw-covariate matrix for comparison
# ─────────────────────────────────────────────────────────────────────────────
raw_cols <- c("wc_bio_12", "wc_bio_01", "soilgrids_clay",
               "soilgrids_sand", "soilgrids_bdod",
               "elev", "slope",
               "wc_landcover_trees", "wc_landcover_cropland",
               "wc_landcover_grassland")
raw_cols <- intersect(raw_cols, names(profiles_k))
cov_mat  <- as.matrix(profiles_k[, raw_cols, drop = FALSE])
# Any NAs -> column mean
for (j in seq_len(ncol(cov_mat))) {
  na_ix <- is.na(cov_mat[, j])
  if (any(na_ix))
    cov_mat[na_ix, j] <- mean(cov_mat[, j], na.rm = TRUE)
}
message(sprintf("  Raw-covariate matrix: %d x %d",
                nrow(cov_mat), ncol(cov_mat)))

# ─────────────────────────────────────────────────────────────────────────────
# 3. Kernel comparison on a 300-row subsample (speed)
# ─────────────────────────────────────────────────────────────────────────────
message("=== [3/5] Kernel comparison on a 300-row subsample ===")

sub_ix <- sample.int(nrow(emb_k), min(300L, nrow(emb_k)))
red_sub <- qf_embed_reduce(emb_k[sub_ix, ], n_pcs = N_PCS)
ker_cmp <- qf_kernel_compare(red_sub$X_q, reps = 2L)
print(ker_cmp$diagnostics)

# ─────────────────────────────────────────────────────────────────────────────
# 4. 5-fold spatial CV benchmark
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/5] 5-fold spatial CV benchmark ===")

cluster_ix <- stats::kmeans(profiles_k[, c("lon", "lat")],
                              centers = 5L, nstart = 5L)$cluster
cv_rows <- list()
for (f in 1:5) {
  test_ix  <- which(cluster_ix == f)
  train_ix <- setdiff(seq_len(nrow(emb_k)), test_ix)
  # Cap training at 250 for the quantum-kernel path (O(n^2) cost)
  if (length(train_ix) > 250L) {
    train_ix <- sort(sample(train_ix, 250L))
  }
  message(sprintf("  fold %d: %d train, %d test",
                   f, length(train_ix), length(test_ix)))
  bm <- tryCatch(
    qf_krr_benchmark(
      embeddings = emb_k,
      covariates = cov_mat,
      y          = y,
      train_ix   = train_ix,
      test_ix    = test_ix,
      n_pcs      = N_PCS,
      reps       = 2L,
      lambda     = 0.5
    ),
    error = function(e) {
      message(sprintf("    [warn] fold %d failed: %s", f,
                       conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(bm)) {
    bm$fold <- f
    cv_rows[[f]] <- bm
  }
}
cv_tbl <- bind_rows(cv_rows)
print(cv_tbl)

# Aggregate across folds
cv_summary <- cv_tbl |>
  group_by(method) |>
  summarise(
    rmse_mean = mean(rmse), rmse_sd = stats::sd(rmse),
    mae_mean  = mean(mae),  r2_mean = mean(r2),
    n_folds   = dplyr::n(),
    .groups   = "drop"
  )
print(cv_summary)

# ─────────────────────────────────────────────────────────────────────────────
# 5. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/5] Saving bundle ===")

R_out <- list(
  version           = packageVersion("edaphos"),
  date_computed     = Sys.time(),
  n_pcs             = N_PCS,
  n_profiles_used   = nrow(emb_k),
  cv_table          = cv_tbl,
  cv_summary        = cv_summary,
  kernel_comparison = ker_cmp$diagnostics,
  kernel_rbf_sigma  = ker_cmp$rbf_sigma
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
