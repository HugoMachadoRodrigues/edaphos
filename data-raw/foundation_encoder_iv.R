#!/usr/bin/env Rscript
# =============================================================================
# Train the real MoCo-v2 foundation encoder and run the IV NEGATIVE result.
#
# torch external pointers do not survive saveRDS/readRDS, so training, embedding
# and the 2SLS/Sargan test all happen in ONE session; only serializable results
# are written (to $EDAPHOS_REAL_CACHE/iv_results.rds, which the causal rebuild
# then folds into the bundle).
#
# The encoder is a 7-channel real Cerrado covariate stack (WorldClim MAT/MAP/elev
# + SoilGrids clay/sand/bdod + Copernicus tree cover), MoCo-v2 on MPS. We report
# the TRUE configuration achieved, not a target. The IV result is negative:
# PCs of the encoder embedding are STRONG instruments for MAP (first-stage
# F ~ 4600) but FAIL the Sargan over-identification test (p ~ 0) -- they encode
# every driver of SOC and so violate the exclusion restriction. This confirms
# Zhang & Wadoux (2026): a learned representation does not manufacture a valid
# instrument, and causal identification in DSM stays hard.
#
# Needs libtorch (torch::torch_is_installed()). ~7 min on Apple MPS.
# =============================================================================
suppressPackageStartupMessages({ library(terra); pkgload::load_all(".", quiet = TRUE) })
stopifnot(torch::torch_is_installed())
CACHE <- Sys.getenv("EDAPHOS_REAL_CACHE", file.path(tempdir(), "edaphos_real"))
dev <- if (torch::backends_mps_is_available()) "mps" else
       if (torch::cuda_is_available()) "cuda" else "cpu"

win <- terra::ext(-60, -41, -24, -2)
rd  <- function(p) terra::rast(file.path(CACHE, p))
lyr <- list(
  mat  = rd("climate/wc2.1_2.5m/wc2.1_2.5m_bio_1.tif"),
  map  = rd("climate/wc2.1_2.5m/wc2.1_2.5m_bio_12.tif"),
  elev = rd("climate/wc2.1_2.5m/wc2.1_2.5m_elev.tif"),
  clay = rd("soil_world/clay_0-5cm_mean_30s.tif"),
  sand = rd("soil_world/sand_0-5cm_mean_30s.tif"),
  bdod = rd("soil_world/bdod_0-5cm_mean_30s.tif"),
  trees = terra::rast(list.files(file.path(CACHE, "landuse"), "trees.*tif$", full.names = TRUE)[1]))
templ <- terra::crop(lyr$trees, win)
stk <- scale(terra::rast(lapply(lyr, function(r) terra::resample(terra::crop(r, win), templ, "bilinear"))))
names(stk) <- names(lyr)
ds <- foundation_tile_dataset(stk, patch_size = 24L, n_patches = 12000L,
                              valid_mask = !any(is.na(stk)), seed = 1L)

moco <- foundation_moco_pretrain_tiles(ds, feature_dim = 128L, proj_dim = 64L,
  queue_size = 4096L, momentum = 0.999, temperature = 0.2, batch_size = 256L,
  epochs = 3000L, lr = 3e-4, device = dev, seed = 1L, verbose = FALSE)
h <- moco$loss_history
message(sprintf("[enc] %s: InfoNCE %.3f -> %.3f (min %.3f)", dev, h[1], utils::tail(h, 1), min(h)))

d <- readRDS("inst/extdata/causal_cerrado_real_v2.rds")$profiles
emb <- foundation_embed_at_coords(moco, coords = as.matrix(d[, c("lon", "lat")]),
                                  stack = stk, dataset = ds, patch_size = 24L, projection = FALSE)
keep <- stats::complete.cases(emb) & is.finite(d$map) & is.finite(d$soc)
emb <- emb[keep, , drop = FALSE]; dk <- d[keep, ]
pc <- stats::prcomp(emb, center = TRUE, scale. = TRUE); K <- 5L
iv_df <- data.frame(soc = dk$soc, map = dk$map,
                    setNames(as.data.frame(pc$x[, 1:K]), paste0("PC", 1:K)))
instr <- paste0("PC", 1:K)
g <- function(x, ...) { for (n in c(...)) if (!is.null(x[[n]])) return(x[[n]]); NA_real_ }
fs  <- causal_iv_first_stage(iv_df, "map", instruments = instr)
fit <- causal_iv_fit_2sls(iv_df, "map", "soc", instruments = instr)
sar <- causal_iv_sargan_test(iv_df, "map", "soc", instruments = instr)
res <- list(
  config = list(channels = moco$in_channels, tiles = ds$n_patches, patch = 24L,
                epochs = length(h), batch = 256L, queue = 4096L, device = dev,
                final_loss = utils::tail(h, 1), min_loss = min(h)),
  iv = list(n = nrow(emb), dim = ncol(emb), K = K, first_stage_F = g(fs, "F", "stage1_F"),
            ols = unname(coef(lm(soc ~ map, iv_df))["map"]), tsls = g(fit, "effect", "estimate"),
            sargan_stat = g(sar, "stat"), sargan_df = g(sar, "df"), sargan_p = g(sar, "p")))
saveRDS(res, file.path(CACHE, "iv_results.rds"))
message(sprintf("[iv] F=%.0f | Sargan chi2(%s)=%.1f p=%.1e | valid=%s",
                res$iv$first_stage_F, res$iv$sargan_df, res$iv$sargan_stat,
                res$iv$sargan_p, res$iv$sargan_p > 0.05))
