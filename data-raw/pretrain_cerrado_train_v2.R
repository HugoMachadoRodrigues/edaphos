# Pretraining v2 -- same Cerrado dataset as v1, 10x the optimisation
# budget. Produces `edaphos-cerrado-moco-v2` and writes it to
# tools/pretrain/edaphos-cerrado-moco-v2/ for a separate Zenodo
# deposit. v1 remains byte-immutable at its published DOI.
#
# Rationale: the v1 encoder was trained for 20000 InfoNCE steps
# which is ~2 % of the canonical MoCo v2 budget in the literature
# (He et al. 2020; Chen et al. 2020b run 200-800 epochs on
# ImageNet-scale). On the honest Cerrado benchmark in v1.3.0 the
# v1 embedding did not improve over raw-covariate ranger, with
# the undertrained encoder as the first-order suspect. v2 bumps
# training to 200000 steps with otherwise identical hyperparameters
# so the comparison becomes a fair test of the contrastive
# representation rather than of a half-baked one.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(terra)
})

# The SpatRaster pointer in cerrado_dataset.rds does not survive a
# saveRDS round-trip; rebuild the dataset fresh from the on-disk .tif
# with the same seed so patch_cells match the v1 training run.
meta_in <- readRDS("tools/pretrain/cerrado_dataset_meta.rds")
aligned <- rast("tools/pretrain/cerrado_stack.tif")
ds <- foundation_tile_dataset(
  stack      = aligned,
  patch_size = meta_in$patch_size,
  n_patches  = meta_in$n_patches,
  normalise  = TRUE,
  seed       = 2026L
)
message(sprintf("[train-v2] rebuilt dataset: %d patches x %d channels",
                 ds$n_patches, ds$n_channels))

out_dir <- "tools/pretrain/edaphos-cerrado-moco-v2"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# v3.11.0 -- resume support.  If a partial checkpoint exists at
# `out_dir/checkpoints/state.rds`, replay training from the last
# completed epoch instead of restarting at zero.  This makes the
# 200000-step run killable / resumable across multiple sessions
# (typically 2-3 hours total on Apple Silicon MPS).
ck_dir     <- file.path(out_dir, "checkpoints")
resume_arg <- NULL
if (file.exists(file.path(ck_dir, "state.rds"))) {
  ck_state <- readRDS(file.path(ck_dir, "state.rds"))
  message(sprintf("[train-v2] resuming from epoch %d (loss %.3f)",
                   ck_state$next_epoch - 1L,
                   tail(ck_state$loss_history, 1L)))
  resume_arg <- ck_dir
}

t0 <- Sys.time()
fit <- foundation_moco_pretrain_tiles(
  dataset      = ds,
  feature_dim  = 64L,
  proj_dim     = 32L,
  queue_size   = 4096L,
  momentum     = 0.999,
  temperature  = 0.07,
  batch_size   = 64L,
  epochs       = 200000L,           # 10 x the v1 budget
  lr           = 3e-4,
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
  checkpoint_dir   = ck_dir,
  checkpoint_every = 10000L,        # checkpoint every 5 %
  resume           = resume_arg
)
dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf("[train-v2] done in %.1f min  (final InfoNCE = %.4f)",
                 dt / 60, fit$final_loss))

torch::torch_save(fit$encoder_q$state_dict(),
                   file.path(out_dir, "encoder_q.pt"))
saveRDS(fit$loss_history, file.path(out_dir, "loss_history.rds"))

meta <- list(
  name         = "edaphos-cerrado-moco-v2",
  description  = paste0(
    "MoCo v2 encoder (v2 -- 10x the v1 training budget) pretrained on ",
    ds$n_patches, " ", ds$patch_size, "x", ds$patch_size,
    " Cerrado tiles. 200000 InfoNCE steps vs v1's 20000; same dataset, ",
    "same seed, same hyperparameters otherwise."
  ),
  n_channels    = as.integer(ds$n_channels),
  feature_dim   = 64L,
  proj_dim      = 32L,
  patch_size    = as.integer(ds$patch_size),
  queue_size    = 4096L,
  momentum      = 0.999,
  temperature   = 0.07,
  batch_size    = 64L,
  steps         = 200000L,
  lr            = 3e-4,
  aoi           = meta_in$aoi,
  target_res    = meta_in$target_res,
  layer_names   = meta_in$layer_names,
  means         = meta_in$means,
  sds           = meta_in$sds,
  training_duration_sec = dt,
  final_loss    = fit$final_loss,
  seed          = 2026L,
  supersedes    = "edaphos-cerrado-moco-v1 (10.5281/zenodo.19701276)",
  edaphos_version = as.character(packageVersion("edaphos")),
  r_version       = R.version.string,
  created_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  license       = "CC-BY-4.0"
)
jsonlite::write_json(meta, file.path(out_dir, "metadata.json"),
                      auto_unbox = TRUE, pretty = TRUE)

if (requireNamespace("digest", quietly = TRUE)) {
  sha <- digest::digest(file = file.path(out_dir, "encoder_q.pt"),
                         algo = "sha256")
  writeLines(sha, file.path(out_dir, "encoder_q.pt.sha256"))
  message(sprintf("[train-v2] encoder sha256: %s", sha))
}
message("[train-v2] artefacts: ", out_dir)
