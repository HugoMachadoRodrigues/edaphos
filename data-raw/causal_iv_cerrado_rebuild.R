#!/usr/bin/env Rscript
# =============================================================================
# Regenerate causal_iv_cerrado.rds with the REAL MoCo-v2 encoder embeddings.
#
# The v1.9.0 bundle used 27 engineered "proxy" features because the encoder was
# not yet trained; the vignette said so honestly. The encoder now exists
# (data-raw/foundation_encoder_iv.R), so the real-data slots are recomputed from
# its embeddings. The synthetic-DGP validation (syn_*, known truth beta = 1.5)
# is legitimate and preserved unchanged.
#
# All in one R session (torch pointers do not survive save/load). Needs
# libtorch. ~8 min on Apple MPS. Reads the real profiles from
# causal_cerrado_real_v2.rds and preserves the old bundle's syn_* slots.
# =============================================================================
suppressPackageStartupMessages({ library(terra); pkgload::load_all(".", quiet = TRUE) })
stopifnot(torch::torch_is_installed())
CACHE <- Sys.getenv("EDAPHOS_REAL_CACHE", file.path(tempdir(), "edaphos_real"))
dev <- if (torch::backends_mps_is_available()) "mps" else "cpu"

## ---- real encoder (same config as the shipped bundle) ----------------------
win <- terra::ext(-60, -41, -24, -2); rd <- function(p) terra::rast(file.path(CACHE, p))
lyr <- list(mat = rd("climate/wc2.1_2.5m/wc2.1_2.5m_bio_1.tif"),
            map = rd("climate/wc2.1_2.5m/wc2.1_2.5m_bio_12.tif"),
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

## ---- real profiles + embeddings --------------------------------------------
d <- readRDS("inst/extdata/causal_cerrado_real_v2.rds")$profiles
emb <- foundation_embed_at_coords(moco, coords = as.matrix(d[, c("lon", "lat")]),
                                  stack = stk, dataset = ds, patch_size = 24L, projection = FALSE)
keep <- stats::complete.cases(emb); emb <- emb[keep, ]; d <- d[keep, ]
pc <- stats::prcomp(emb, center = TRUE, scale. = TRUE)
covs <- c("mat", "elev", "slope", "clay", "sand", "bdod", "trees")
addpc <- function(df, K) cbind(df, setNames(as.data.frame(pc$x[, 1:K]), paste0("PC", 1:K)))
g <- function(x, ...) { for (n in c(...)) if (!is.null(x[[n]])) return(x[[n]]); NA_real_ }

## ---- benchmark table: OLS naive / backdoor OLS / 2SLS, 3 exposures ---------
adj <- list(map = c("slope", "mat"), trees = c("mat", "map"), clay = "slope")
bench <- do.call(rbind, lapply(names(adj), function(ex) {
  naive <- lm(stats::reformulate(ex, "soc"), d)
  bdr   <- lm(stats::reformulate(c(ex, adj[[ex]]), "soc"), d)
  ivdf  <- addpc(d[, c("soc", ex, covs)], 5L)
  fit   <- causal_iv_fit_2sls(ivdf, exposure = ex, outcome = "soc",
                              instruments = paste0("PC", 1:5), covariates = setdiff(covs, ex))
  fs    <- causal_iv_first_stage(ivdf, ex, instruments = paste0("PC", 1:5),
                                 covariates = setdiff(covs, ex))
  sar   <- causal_iv_sargan_test(ivdf, ex, "soc", instruments = paste0("PC", 1:5),
                                 covariates = setdiff(covs, ex))
  rbind(
    data.frame(exposure = ex, estimator = "OLS naive", beta = coef(naive)[[2]],
               se = summary(naive)$coef[2, 2], ci_lo = confint(naive)[2, 1],
               ci_hi = confint(naive)[2, 2], stage1_F = NA, sargan_p = NA),
    data.frame(exposure = ex, estimator = "Backdoor OLS", beta = coef(bdr)[[ex]],
               se = summary(bdr)$coef[ex, 2], ci_lo = confint(bdr)[ex, 1],
               ci_hi = confint(bdr)[ex, 2], stage1_F = NA, sargan_p = NA),
    data.frame(exposure = ex, estimator = "2SLS (real MoCo v2)", beta = g(fit, "effect", "estimate"),
               se = g(fit, "se"), ci_lo = g(fit, "ci_lo"), ci_hi = g(fit, "ci_hi"),
               stage1_F = g(fs, "F", "stage1_F"), sargan_p = g(sar, "p")))
}))
row.names(bench) <- NULL

## ---- sensitivity across n_pcs (MAP -> SOC) ---------------------------------
sens <- do.call(rbind, lapply(c(3L, 5L, 7L, 10L), function(K) {
  ivdf <- addpc(d[, c("soc", "map", covs)], K)
  fit  <- causal_iv_fit_2sls(ivdf, "map", "soc", instruments = paste0("PC", 1:K), covariates = covs)
  fs   <- causal_iv_first_stage(ivdf, "map", instruments = paste0("PC", 1:K), covariates = covs)
  sar  <- causal_iv_sargan_test(ivdf, "map", "soc", instruments = paste0("PC", 1:K), covariates = covs)
  data.frame(n_pcs = K, beta_iv = g(fit, "effect", "estimate"), se = g(fit, "se"),
             stage1_F = g(fs, "F", "stage1_F"), sargan_p = g(sar, "p"))
}))

## ---- preserve the synthetic-DGP validation slots ---------------------------
old <- readRDS("inst/extdata/causal_iv_cerrado.rds")
bundle <- list(
  version = "real-encoder", date_computed = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  n_profiles = nrow(d), embedding_dim = ncol(emb), n_pcs_default = 5L,
  encoder = list(channels = moco$in_channels, tiles = ds$n_patches, epochs = length(moco$loss_history),
                 device = dev, min_loss = min(moco$loss_history)),
  syn_summary = old$syn_summary, syn_posterior = old$syn_posterior, syn_diagnostics = old$syn_diagnostics,
  benchmark_table = bench, sensitivity_table = sens,
  dag_adjustment_sets = old$dag_adjustment_sets, used_real_encoder = TRUE)
saveRDS(bundle, "inst/extdata/causal_iv_cerrado.rds", compress = "xz")
cat("benchmark_table:\n"); print(bench, digits = 3)
cat("\nsensitivity_table:\n"); print(sens, digits = 3)
cat(sprintf("\nwrote causal_iv_cerrado.rds (%d profiles, real encoder, %.0f KB)\n",
            nrow(d), file.size("inst/extdata/causal_iv_cerrado.rds") / 1024))
