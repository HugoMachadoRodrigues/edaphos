## data-raw/quantum_foundation_benchmark.R
##
## Head-to-head benchmark of four SOC-regression methods on the WoSIS
## Cerrado profiles:
##
##   1. ranger (QRF) baseline on raw covariates
##   2. RBF Kernel Ridge Regression on foundation-embedding PCs
##   3. Quantum Kernel Ridge Regression on raw covariates (Pillar 6)
##   4. Quantum Kernel Ridge Regression on foundation-embedding PCs
##      (the Pillar 4 x Pillar 6 fusion)
##
## WHAT THIS RUN IS. A NEGATIVE CONTROL, and it has to be read as one. The
## raster stack the encoder sees is white noise -- `stats::rnorm()` into every
## cell of every channel, built below -- so the "foundation embeddings" are
## embeddings of a landscape that carries no signal. Three of the four methods
## therefore predict from features that cannot contain information about SOC,
## by construction. The expected result is that they lose to the mean.
##
## The header of this script used to promise "or real if
## EDAPHOS_IV_REAL_STACK=1". That environment variable is read nowhere, in
## this script or anywhere in the package: the synthetic stack is
## unconditional. The promise is removed rather than reworded. For the real
## covariate answer see inst/extdata/benchmark_wosis_6pilar.rds, which scores
## quantum KRR on measured SoilGrids / WorldClim / SRTM covariates.
##
## WHY IT IS BEING RE-RUN. The shipped bundle was built 2026-04-23 by a
## version of qf_krr_benchmark() that computed `max(0, 1 - SS_res/SS_tot)`.
## Seventeen of its twenty per-fold R-squared values are exactly zero -- not
## measured as zero, floored to it -- and the README read that flat column as
## "the four regressors are statistically indistinguishable". The clamp is
## gone (R/quantum_foundation.R:462-478 delegates to edaphos_r2, which is
## Nash-Sutcliffe and unclamped), but the artefact was never rebuilt, so the
## censored numbers are what the package still publishes. This run replaces
## them with what the benchmark actually produces.
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
# THIS IS THE NOISE. Every channel is independent white noise, so nothing
# downstream of the encoder can carry information about SOC. Keep this line in
# view when reading the table: it is what makes the run a negative control.
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

# Aggregate across folds.
#
# THE MEAN OF PER-FOLD R2 IS NOT A SAFE HEADLINE HERE, and reporting it alone
# would replace one false ranking with another. edaphos_r2() is
# Nash-Sutcliffe against each test fold's OWN mean, so a fold whose profiles
# happen to be homogeneous has a tiny denominator and its R2 swings wildly.
# Fold 2 of this partition has sd(SOC) = 5.9 g/kg against 11-21 in the other
# four; ranger scores -4.28 there, which by itself drags ranger's fold-mean to
# -0.80 and makes it look like the worst of the four. Pooled over folds --
# one ratio of summed squares, not a mean of ratios -- ranger is -0.07, which
# is the middle of the pack.
#
# Both are reported. The pooled value is the headline because it does not let
# one small-variance fold decide the ranking; the fold mean and its spread are
# kept so the instability is visible rather than smoothed away.
cv_summary <- cv_tbl |>
  group_by(method) |>
  summarise(
    rmse_mean = mean(rmse), rmse_sd = stats::sd(rmse),
    mae_mean  = mean(mae),  r2_mean = mean(r2),
    r2_sd     = stats::sd(r2),
    r2_min    = min(r2),
    # Pooled: 1 - sum(SS_res) / sum(SS_tot) across folds. Each fold's target
    # variance is recovered from its own RMSE and R2, since
    # R2 = 1 - RMSE^2 / var  =>  var = RMSE^2 / (1 - R2).
    r2_pooled = 1 - sum(n_test * rmse^2) /
                    sum(n_test * (rmse^2 / (1 - r2))),
    rmse_pooled = sqrt(sum(n_test * rmse^2) / sum(n_test)),
    n_folds   = dplyr::n(),
    .groups   = "drop"
  ) |>
  arrange(desc(r2_pooled))
print(as.data.frame(cv_summary))

# ─────────────────────────────────────────────────────────────────────────────
# 5. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/5] Saving bundle ===")

    # How many per-fold R2 are below zero, i.e. worse than predicting the
    # training mean. Recorded because it is the whole point of the re-run: the
    # shipped bundle had 17 of 20 sitting at exactly 0.000, and a reader
    # cannot tell a measured zero from a censored one without this.
n_negative_r2 <- sum(cv_tbl$r2 < 0)
cat(sprintf("\n%d of %d per-fold R2 are negative (worse than the mean); %d are exactly zero\n",
            n_negative_r2, nrow(cv_tbl), sum(cv_tbl$r2 == 0)))

R_out <- list(
  # Binds this bundle to the script that made it: see R/provenance.R.
  provenance        = edaphos_provenance(
                        n_profiles = nrow(emb_k),
                        stack = "synthetic white noise (negative control)"),
  version           = packageVersion("edaphos"),
  date_computed     = Sys.time(),
  n_pcs             = N_PCS,
  n_profiles_used   = nrow(emb_k),
  cv_table          = cv_tbl,
  cv_summary        = cv_summary,
  n_negative_r2     = n_negative_r2,
  # The design, carried with the numbers so a reader of the bundle alone
  # cannot mistake this for a real-covariate benchmark.
  stack_mode        = "synthetic",
  stack_note        = paste("Encoder input is white noise; the embedding-based",
                            "methods cannot carry SOC signal by construction.",
                            "This is a negative control, not a covariate",
                            "benchmark."),
  kernel_comparison = ker_cmp$diagnostics,
  kernel_rbf_sigma  = ker_cmp$rbf_sigma,
  built_by          = "data-raw/quantum_foundation_benchmark.R"
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
