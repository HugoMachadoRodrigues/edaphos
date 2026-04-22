# MoCo v2 pretraining on the prepared Cerrado tile dataset.
# Consumes tools/pretrain/cerrado_dataset.rds and writes
# tools/pretrain/edaphos-cerrado-moco-v1/{encoder_q.pt,metadata.json,
# loss_history.rds}.
#
# Reproducibility
# ---------------
#   * seed is fixed at 2026L
#   * batch_size 64, queue_size 4096, feature_dim 64, proj_dim 32
#   * MoCo v2 momentum 0.999, temperature 0.07
#   * 20000 optimisation steps (each step = one mini-batch; MoCo v2
#     is conventionally measured in steps rather than epochs because
#     the contrastive loss samples random pairs each step)
#   * device = "mps" on an M1 Max (falls back to CPU if unavailable)

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(terra)
})

# `SpatRaster` C++ pointers do not survive `saveRDS`, so we rebuild the
# tile dataset fresh from the aligned on-disk `.tif` and recover the
# same patch_cells via the same seed as the prep script.
meta_in <- readRDS("tools/pretrain/cerrado_dataset_meta.rds")
aligned <- rast("tools/pretrain/cerrado_stack.tif")
ds <- foundation_tile_dataset(
  stack      = aligned,
  patch_size = meta_in$patch_size,
  n_patches  = meta_in$n_patches,
  normalise  = TRUE,
  seed       = 2026L
)
message(sprintf("[train] rebuilt dataset: %d patches x %d channels",
                 ds$n_patches, ds$n_channels))

out_dir <- "tools/pretrain/edaphos-cerrado-moco-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
fit <- foundation_moco_pretrain_tiles(
  dataset      = ds,
  feature_dim  = 64L,
  proj_dim     = 32L,
  queue_size   = 4096L,
  momentum     = 0.999,
  temperature  = 0.07,
  batch_size   = 64L,
  epochs       = 20000L,          # interpret as training steps
  lr           = 3e-4,
  # raster-specific augmentation policy tuned for 10-channel stacks
  crop_ratio        = c(0.6, 1.0),
  flip_prob         = 0.5,
  rot90_prob        = 0.75,
  channel_drop_prob = 0.2,
  cutout_prob       = 0.3,
  cutout_size_ratio = 0.2,
  brightness_jitter = 0.2,
  noise_sd          = 0.1,
  device           = "mps",
  seed             = 2026L,
  verbose          = TRUE,
  checkpoint_dir   = file.path(out_dir, "checkpoints"),
  checkpoint_every = 1000L
)
dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf("[train] done in %.1f min  (final InfoNCE = %.4f)",
                 dt / 60, fit$final_loss))

# Save the trained encoder + metadata in a layout that
# foundation_weights_load() can restore.
torch::torch_save(fit$encoder_q$state_dict(),
                   file.path(out_dir, "encoder_q.pt"))
saveRDS(fit$loss_history, file.path(out_dir, "loss_history.rds"))

meta <- list(
  name         = "edaphos-cerrado-moco-v1",
  description  = paste0(
    "MoCo v2 encoder pretrained on ", ds$n_patches,
    " ", ds$patch_size, "x", ds$patch_size,
    " Cerrado tiles (SoilGrids + WorldClim + SRTM) at 0.01 deg, ",
    meta_in$n_channels, " channels."
  ),
  n_channels    = as.integer(ds$n_channels),
  feature_dim   = 64L,
  proj_dim      = 32L,
  patch_size    = as.integer(ds$patch_size),
  queue_size    = 4096L,
  momentum      = 0.999,
  temperature   = 0.07,
  batch_size    = 64L,
  steps         = 20000L,
  lr            = 3e-4,
  aoi           = meta_in$aoi,
  target_res    = meta_in$target_res,
  layer_names   = meta_in$layer_names,
  means         = meta_in$means,
  sds           = meta_in$sds,
  training_duration_sec = dt,
  final_loss    = fit$final_loss,
  seed          = 2026L,
  edaphos_version = as.character(packageVersion("edaphos")),
  r_version       = R.version.string,
  created_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  license       = "CC-BY-4.0"
)
jsonlite::write_json(meta,
                      file.path(out_dir, "metadata.json"),
                      auto_unbox = TRUE, pretty = TRUE)

# SHA-256 of the encoder artefact for the registry.
if (requireNamespace("digest", quietly = TRUE)) {
  sha <- digest::digest(file = file.path(out_dir, "encoder_q.pt"),
                         algo = "sha256")
  writeLines(sha, file.path(out_dir, "encoder_q.pt.sha256"))
  message(sprintf("[train] encoder sha256: %s", sha))
} else {
  message("[train] `digest` not installed; skipping sha256 digest")
}

message("[train] artefacts: ", out_dir)
