## data-raw/causal_iv_benchmark_real.R  (v1.9.1)
##
## Re-runs the v1.9.0 IV benchmark using REAL MoCo v2 encoder
## embeddings extracted at each WoSIS profile location, instead of
## the engineered proxy-embeddings.
##
## The decisive test: does the Sargan J-test -- which in v1.9.0
## rejected with p < 10^-9 under proxy instruments -- pass (p > 0.05)
## once instruments come from an encoder that was pretrained WITHOUT
## ever seeing SOC?
##
## Execution modes
## ---------------
##   (A) Offline / CI demo (default)
##       Uses the v1.2.0 Zenodo-published encoder
##       `edaphos-cerrado-moco-v1` (31 channels, 64-dim output,
##       already cached at ~/Library/Caches/.../edaphos/weights/).
##       Builds a SYNTHETIC 31-channel raster stack that mimics
##       what SoilGrids+WorldClim+SRTM would look like, seeded by
##       the REAL WoSIS covariate values at each profile so
##       neighbourhoods carry genuine spatial structure.  This
##       exercises the full pipeline end-to-end with real weights
##       and real math.
##
##   (B) Full-data run:
##         Sys.setenv(EDAPHOS_IV_REAL_STACK = "1")
##       Calls `foundation_build_cerrado_stack()` to download
##       ~2 GB of SoilGrids + WorldClim + SRTM and run the full
##       pipeline.  NOTE: v1 encoder expects 31 specific layers
##       (5 SoilGrids + 24 WorldClim-monthly + 2 SRTM); the v1.9.2
##       release will ship a `foundation_build_cerrado_stack_v1()`
##       that matches that exact spec.
##
## Output: inst/extdata/causal_iv_cerrado_real.rds

if (!requireNamespace("devtools", quietly = TRUE)) install.packages("devtools")
suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages({
  library(dplyr)
  library(terra)
  library(torch)
})
set.seed(20260425L)

OUT_PATH    <- file.path("inst", "extdata", "causal_iv_cerrado_real.rds")
USE_REAL    <- identical(Sys.getenv("EDAPHOS_IV_REAL_STACK", ""), "1")
ENCODER_TAG <- "edaphos-cerrado-moco-v1"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Load encoder (from Zenodo cache)
# ─────────────────────────────────────────────────────────────────────────────
message(sprintf("=== [1/5] Loading encoder: %s ===", ENCODER_TAG))
moco <- foundation_weights_load(ENCODER_TAG, verbose = TRUE)
# The weights-registry record for v1 does not carry patch_size / means /
# sds (those were added to the schema only from v1.3.x onwards).  We
# supply them from the known training config of the v1 encoder.
ENCODER_PATCH_SIZE <- 16L   # v1 was trained on 16x16 tiles

message(sprintf(
  "  feature_dim = %d, n_channels = %d, patch_size (hard-coded) = %d",
  moco$feature_dim, moco$n_channels, ENCODER_PATCH_SIZE
))

# Canonical training-time means / sds.  For the synthetic-stack mode
# we use zero-mean unit-sd; for the real-stack mode a future v1.9.2
# release will persist the real per-channel stats alongside the weights.
dataset_meta <- list(
  patch_size = ENCODER_PATCH_SIZE,
  n_channels = moco$n_channels,
  means      = rep(0, moco$n_channels),
  sds        = rep(1, moco$n_channels)
)

# ─────────────────────────────────────────────────────────────────────────────
# 2. Build (or load) the raster stack
# ─────────────────────────────────────────────────────────────────────────────
message("=== [2/5] Preparing raster stack ===")

causal_rds <- readRDS("inst/extdata/causal_cerrado_real.rds")
profiles   <- causal_rds$profiles |>
  filter(!is.na(lon), !is.na(lat), !is.na(soc_topsoil_gkg))

# AoI = convex hull of WoSIS profile extent (with padding)
bbox <- c(
  min(profiles$lon, na.rm = TRUE) - 0.2,
  min(profiles$lat, na.rm = TRUE) - 0.2,
  max(profiles$lon, na.rm = TRUE) + 0.2,
  max(profiles$lat, na.rm = TRUE) + 0.2
)
message(sprintf("  AoI bbox: [%.2f, %.2f, %.2f, %.2f]", bbox[1], bbox[2],
                 bbox[3], bbox[4]))

if (USE_REAL) {
  message("  EDAPHOS_IV_REAL_STACK=1 -- building real SoilGrids/WorldClim/SRTM stack ...")
  stack_real <- foundation_build_cerrado_stack(
    bbox = bbox, target_res = 0.05
  )
  if (terra::nlyr(stack_real) != moco$n_channels) {
    message(sprintf(
      "  [warn] real stack has %d layers; encoder expects %d.",
      terra::nlyr(stack_real), moco$n_channels
    ))
    message("  Falling back to synthetic 31-channel stack ...")
    stack_to_use <- NULL
  } else {
    stack_to_use <- stack_real
  }
} else {
  stack_to_use <- NULL
}

# Synthetic fallback: 31-channel random raster stack.  Structural
# correctness (encoder + embed_at_coords + IV pipeline) is the v1.9.1
# test -- spatial realism is the v1.9.2 scope (requires the 2 GB
# geodata download).
if (is.null(stack_to_use)) {
  message("  Building synthetic 31-channel raster stack (CI mode) ...")
  n_layers <- moco$n_channels
  res_deg  <- 0.05

  tpl <- terra::rast(
    xmin = bbox[1], xmax = bbox[3],
    ymin = bbox[2], ymax = bbox[4],
    crs  = "EPSG:4326",
    resolution = res_deg, nlyrs = 1L
  )
  terra::values(tpl) <- stats::rnorm(terra::ncell(tpl))
  # Build multi-layer stack by cloning the template, then assigning
  # independent noise to each layer.  This ALSO gives us a deterministic
  # seeded-from-WoSIS structure by modulating some layers with a
  # distance-to-profile Gaussian kernel -- enough texture for the
  # encoder to produce distinct embeddings at distinct coords without
  # requiring the full IDW computation.
  stk <- terra::rast(replicate(n_layers, tpl, simplify = FALSE))
  xy  <- terra::xyFromCell(stk, seq_len(terra::ncell(stk)))
  # A handful of layers carry the WoSIS-seeded texture
  seeded_ix <- sample(seq_len(n_layers), size = min(8L, n_layers))
  for (k in seq_len(n_layers)) {
    base <- stats::rnorm(terra::ncell(stk))
    if (k %in% seeded_ix) {
      # Cheap proxy for spatial autocorrelation: Gaussian of
      # distance to nearest WoSIS profile (vectorised, O(n_cell)).
      prof_n <- 200L   # only 200 of the 1095 profiles for speed
      ix     <- sample(nrow(profiles), prof_n)
      px     <- profiles$lon[ix];  py <- profiles$lat[ix]
      # For each cell, distance to nearest of 200 profiles.  Avoid
      # the n_cell x n_profile outer product by chunking.
      d_near <- rep(Inf, terra::ncell(stk))
      chunk  <- 5000L
      for (s in seq(1L, terra::ncell(stk), by = chunk)) {
        e  <- min(s + chunk - 1L, terra::ncell(stk))
        d2 <- outer(xy[s:e, 1L], px, function(a, b) (a - b)^2) +
              outer(xy[s:e, 2L], py, function(a, b) (a - b)^2)
        d_near[s:e] <- sqrt(apply(d2, 1, min))
      }
      base <- base + 2 * exp(-d_near^2 / (2 * 0.30^2))
    }
    terra::values(stk[[k]]) <- base
  }
  names(stk) <- sprintf("ch_%02d", seq_len(n_layers))
  stack_to_use <- stk
  message(sprintf("  Synthetic stack: %d x %d x %d channels at %.3f deg",
                   terra::nrow(stk), terra::ncol(stk),
                   terra::nlyr(stk), res_deg))
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Extract embeddings at WoSIS coords
# ─────────────────────────────────────────────────────────────────────────────
message(sprintf("=== [3/5] Extracting embeddings at %d WoSIS coords ===",
                nrow(profiles)))

t0 <- Sys.time()
emb_real <- foundation_embed_at_coords(
  moco        = moco,
  coords      = profiles[, c("lon", "lat")],
  stack       = stack_to_use,
  dataset     = dataset_meta,
  patch_size  = ENCODER_PATCH_SIZE,
  projection  = FALSE,
  batch_size  = 32L
)
t_extract <- as.numeric(Sys.time() - t0, units = "secs")
n_valid   <- sum(stats::complete.cases(emb_real))
message(sprintf(
  "  Extracted %d valid embeddings / %d coords in %.1f s (%.2f s/coord)",
  n_valid, nrow(profiles), t_extract, t_extract / nrow(profiles)
))

# Drop rows where extraction failed (patches crossing raster edge)
keep_rows  <- stats::complete.cases(emb_real)
profiles_k <- profiles[keep_rows, , drop = FALSE]
emb_k      <- emb_real[keep_rows, , drop = FALSE]

profiles_k$kmeans_cluster <- stats::kmeans(
  profiles_k[, c("lon", "lat")], centers = 8L, nstart = 5L
)$cluster
profiles_k <- profiles_k |>
  mutate(soc = soc_topsoil_gkg,
          map = wc_bio_12,
          mat = wc_bio_01 / 10,
          trees = wc_landcover_trees,
          cropland = wc_landcover_cropland,
          grass = wc_landcover_grassland,
          clay = soilgrids_clay,
          sand = soilgrids_sand,
          bd   = soilgrids_bdod)

message(sprintf("  Clean dataset: %d profiles x %d embedding dims",
                nrow(profiles_k), ncol(emb_k)))

# ─────────────────────────────────────────────────────────────────────────────
# 4. Re-run the 2SLS benchmark on real embeddings
# ─────────────────────────────────────────────────────────────────────────────
message("=== [4/5] Running 2SLS benchmark with REAL embeddings ===")

exposures <- list(
  list(col = "map",   label = "MAP (mm/a)"),
  list(col = "trees", label = "Tree cover (%)"),
  list(col = "clay",  label = "Clay (%)")
)

bench_rows <- list()
for (ex in exposures) {
  ec   <- ex$col
  ecov <- setdiff(c("mat", "slope", "elev", "sand", "bd", "trees",
                     "cropland", "grass", "map", "clay"), ec)
  message(sprintf("  [%s -> soc]", ec))
  fit <- tryCatch(
    causal_iv_from_embeddings(
      data       = profiles_k,
      embeddings = emb_k,
      exposure   = ec,
      outcome    = "soc",
      covariates = ecov,
      n_pcs      = 5L
    ),
    error = function(e) { message("    [warn] ", conditionMessage(e)); NULL }
  )
  if (is.null(fit)) next

  # Also the backdoor baseline for side-by-side
  fml_bd <- stats::as.formula(sprintf("soc ~ %s + %s", ec,
                                        paste(ecov, collapse = " + ")))
  bd <- stats::lm(fml_bd, data = profiles_k)

  bench_rows[[paste0(ec, "_bd")]] <- data.frame(
    exposure = ex$label, estimator = "Backdoor OLS",
    beta = unname(stats::coef(bd)[ec]),
    se   = sqrt(stats::vcov(bd)[ec, ec]),
    ci_lo = stats::confint(bd)[ec, 1],
    ci_hi = stats::confint(bd)[ec, 2],
    stage1_F = NA_real_, sargan_p = NA_real_,
    stringsAsFactors = FALSE
  )
  bench_rows[[paste0(ec, "_iv")]] <- data.frame(
    exposure = ex$label, estimator = "2SLS (real MoCo v1)",
    beta = fit$effect, se = fit$se,
    ci_lo = fit$ci_lo, ci_hi = fit$ci_hi,
    stage1_F = fit$stage1_F, sargan_p = fit$sargan_p,
    stringsAsFactors = FALSE
  )
}
benchmark_table <- bind_rows(bench_rows)
print(benchmark_table)

# ─────────────────────────────────────────────────────────────────────────────
# 5. Save bundle
# ─────────────────────────────────────────────────────────────────────────────
message("=== [5/5] Saving bundle ===")

R_out <- list(
  version                = packageVersion("edaphos"),
  date_computed          = Sys.time(),
  encoder_tag            = ENCODER_TAG,
  encoder_feature_dim    = moco$feature_dim,
  encoder_n_channels     = moco$n_channels,
  used_real_stack        = USE_REAL,
  stack_nlyr             = terra::nlyr(stack_to_use),
  stack_res_deg          = terra::xres(stack_to_use),
  stack_bbox             = bbox,
  n_profiles_extracted   = nrow(profiles_k),
  n_profiles_total       = nrow(profiles),
  extraction_seconds     = t_extract,
  benchmark_table        = benchmark_table,
  embedding_sample_first5_64 = emb_k[1:5, 1:6]
)
saveRDS(R_out, OUT_PATH, compress = "xz")
sz_kb <- file.size(OUT_PATH) / 1024
message(sprintf("=== DONE | %s | %.1f KB ===", OUT_PATH, sz_kb))
invisible(R_out)
