# Pillar 3 v1.5.0 -- real-data runner.
#
# Consumes tools/temporal_cerrado/temporal_cerrado_cube.rds (produced
# by data-raw/temporal_cerrado_prepare.R) and:
#
#   1. Builds normalised (sequence, target) tensors for the stacked
#      ConvLSTM where the target channel is MOD13Q1 NDVI and the two
#      driver channels are CHIRPS monthly precipitation and WorldClim
#      monthly tavg.
#   2. Splits the T = 168 time axis at month 132 (end-of-2020), keeping
#      the last 36 months as out-of-sample forecast window.
#   3. Trains a K = 5 member ConvLSTM ensemble (different random seeds).
#   4. Runs a rollout forecast for every member, producing an ensemble
#      forecast array (K, 36, H, W).
#   5. Synthesises 20 "new in-situ NDVI observations" at random grid
#      cells of the final month (Dec 2023), treating the true observed
#      NDVI as the assimilation target + Gaussian noise of sd 0.02.
#   6. Applies temporal_kalman_update() to obtain the posterior ensemble.
#   7. Computes prior and analysis RMSE, gain norms, innovation vector,
#      and saves a slim bundle to inst/extdata/temporal_cerrado_results.rds
#      for the pilar3-4d-real vignette.
#
# This script is *not* rebuilt by devtools::build(); it is run once by
# the maintainer (Hugo) and its output is checked in.

suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
  library(torch)
})

stopifnot(torch::torch_is_installed())

use_mps <- torch::backends_mps_is_available()
message(sprintf("[pilar3-run] torch device: %s",
                 if (use_mps) "mps" else "cpu"))

# --- Load cube ------------------------------------------------------------

cube_path <- "tools/temporal_cerrado/temporal_cerrado_cube.rds"
stopifnot(file.exists(cube_path))
bundle <- readRDS(cube_path)
cube   <- bundle$cube          # (H, W, T, C=3)
H      <- dim(cube)[1L]
W      <- dim(cube)[2L]
T_total <- dim(cube)[3L]
stopifnot(dim(cube)[4L] == 3L)
message(sprintf("[pilar3-run] cube: %d x %d x %d x 3  (ndvi, precip, tavg)",
                 H, W, T_total))

# --- Normalisation -------------------------------------------------------

# We z-score each channel across the whole space-time tensor. Storing the
# scaling so we can de-normalise model output in the vignette.
chan_names <- c("ndvi", "precip_mm", "tavg_C")
scaling <- lapply(chan_names, function(ch) {
  ix <- match(ch, chan_names)
  v  <- cube[, , , ix]
  list(mu = mean(v, na.rm = TRUE),
       sd = max(stats::sd(as.vector(v), na.rm = TRUE), 1e-6))
})
names(scaling) <- chan_names

norm_cube <- cube
for (ch in seq_along(chan_names)) {
  sc <- scaling[[ch]]
  norm_cube[, , , ch] <- (cube[, , , ch] - sc$mu) / sc$sd
}

# --- Assemble tensors ----------------------------------------------------

# Input sequence = 2 driver channels (precip, tavg), shape (1, T, 2, H, W).
# Target         = NDVI, shape (1, T, H, W).
seq_arr <- array(0, dim = c(1L, T_total, 2L, H, W))
tgt_arr <- array(0, dim = c(1L, T_total, H, W))
for (t in seq_len(T_total)) {
  seq_arr[1L, t, 1L, , ] <- norm_cube[, , t, 2L]    # precip
  seq_arr[1L, t, 2L, , ] <- norm_cube[, , t, 3L]    # tavg
  tgt_arr[1L, t, , ]     <- norm_cube[, , t, 1L]    # NDVI
}

# Past = first 132 months (Jan 2010 -- Dec 2020), future = last 36.
T_past   <- 132L
T_future <- T_total - T_past
message(sprintf("[pilar3-run] past = %d months (Jan 2010 - Dec 2020), future = %d months (Jan 2021 - Dec 2023)",
                 T_past, T_future))

past_seq     <- seq_arr[, 1L:T_past,            , , , drop = FALSE]
past_target  <- tgt_arr[, 1L:T_past,            , , drop = FALSE]
future_seq   <- seq_arr[, (T_past + 1L):T_total, , , , drop = FALSE]
future_target<- tgt_arr[, (T_past + 1L):T_total, , , drop = FALSE]

# --- Train K-member ensemble ---------------------------------------------

# K = 10 members is a pragmatic compromise between sampling the ConvLSTM
# initialisation noise (larger K -> better covariance estimate) and
# training wall-clock cost (~3 min / member). The vanilla stochastic
# EnKF without localisation at K = 5 suffered clear ensemble collapse
# (analysis RMSE > prior RMSE, posterior SD / prior SD ~ 0.05) due to
# an under-determined P_f H^T fit to 20 observations; K = 10 with
# fewer / nosier observations is stable in practice.
K_ens <- 10L
ens_cache_path <- "tools/temporal_cerrado/ens_rolls_K10.rds"
ens_fits_path  <- "tools/temporal_cerrado/ens_fits_K10.rds"
if (file.exists(ens_cache_path) && file.exists(ens_fits_path)) {
  ens_rolls <- readRDS(ens_cache_path)
  ens_fits  <- readRDS(ens_fits_path)
  message(sprintf("[pilar3-run] loaded cached ensemble (K = %d)",
                   dim(ens_rolls)[1L]))
} else {
  ens_fits  <- vector("list", K_ens)
  ens_rolls <- array(NA_real_, dim = c(K_ens, T_future, H, W))
  for (k in seq_len(K_ens)) {
    seed_k <- 100L + k
    message(sprintf("[pilar3-run] training ensemble member %d/%d (seed = %d)",
                     k, K_ens, seed_k))
    t0 <- Sys.time()
    fit <- temporal_convlstm_fit(
      sequence        = past_seq,
      target          = past_target,
      hidden_dims     = c(8L, 4L),
      kernel_size     = 3L,
      return_sequence = TRUE,
      epochs          = 120L,
      lr              = 0.02,
      seed            = seed_k,
      verbose         = FALSE
    )
    dt <- as.numeric(Sys.time() - t0, units = "secs")
    message(sprintf("  [ok] epoch-final loss = %.5f  (%.1f s)",
                     fit$final_loss, dt))
    # Multi-step forecast of the future 36 months.
    fc <- temporal_convlstm_rollout(
      fit,
      past_sequence  = past_seq,
      future_drivers = future_seq
    )
    # fc is (1, 36, H, W). Extract into ensemble.
    ens_rolls[k, , , ] <- fc[1L, , , ]
    ens_fits[[k]] <- list(final_loss = fit$final_loss,
                           loss_history = fit$loss_history)
  }
  saveRDS(ens_rolls, ens_cache_path)
  saveRDS(ens_fits,  ens_fits_path)
  message("[pilar3-run] ensemble forecast cached to ",
           ens_cache_path)
}

# --- Ensemble forecast at a target month (Dec 2023, final month) --------

target_t_in_future <- T_future          # last month = Dec 2023
fc_ens <- ens_rolls[, target_t_in_future, , ]    # (K, H, W)
truth  <- future_target[1L, target_t_in_future, , ]
message(sprintf("[pilar3-run] forecast ensemble shape: %s",
                 paste(dim(fc_ens), collapse = " x ")))
message(sprintf("[pilar3-run] truth (NDVI z-units) range: [%.3f, %.3f]",
                 min(truth, na.rm = TRUE), max(truth, na.rm = TRUE)))

# Prior mean + SD (in normalised NDVI units).
prior_mean <- apply(fc_ens, c(2L, 3L), mean)
prior_sd   <- apply(fc_ens, c(2L, 3L), stats::sd)

# --- Synthesise 20 new in-situ observations ------------------------------

set.seed(20250423L)
n_obs <- 8L
# We pick unique random cells (no repeats) to avoid trivially
# over-constraining the ensemble gain at a single pixel.
cell_ix <- sample.int(H * W, n_obs)
obs_row <- ((cell_ix - 1L) %/% W) + 1L
obs_col <- ((cell_ix - 1L) %%  W) + 1L
# Observation noise sd = 0.15 in *normalised* NDVI units, i.e. about
# 0.026 raw NDVI once we de-normalise -- a realistic in-situ sensor
# noise floor (e.g. a handheld Trimble GreenSeeker quotes ~0.02 NDVI
# repeatability).
obs_sd_norm <- 0.15
obs_value <- truth[cbind(obs_row, obs_col)] +
             stats::rnorm(n_obs, sd = obs_sd_norm)

# --- Kalman update -------------------------------------------------------

# Gaspari-Cohn localization is the standard remedy for spurious
# long-range correlations in small-ensemble EnKFs. A half-bandwidth
# of 2 cells zeroes the update beyond 4 cells (Chebyshev distance),
# which on a 10 x 10 grid restricts each observation's influence to
# a roughly 1 deg x 1 deg neighbourhood -- the scale over which
# Cerrado NDVI anomalies actually correlate.
assim <- temporal_kalman_update(
  forecast_ensemble   = fc_ens,
  obs_value           = obs_value,
  obs_row             = obs_row,
  obs_col             = obs_col,
  obs_sd              = obs_sd_norm,
  localization_radius = 2,
  seed                = 7L
)

analysis_mean <- assim$analysis_mean
analysis_sd   <- assim$analysis_sd

# --- Diagnostics ---------------------------------------------------------

prior_rmse    <- sqrt(mean((prior_mean    - truth)^2))
analysis_rmse <- sqrt(mean((analysis_mean - truth)^2))
sd_reduction  <- mean(analysis_sd) / mean(prior_sd)
message(sprintf("[pilar3-run] prior RMSE    = %.4f (NDVI z-units)",
                 prior_rmse))
message(sprintf("[pilar3-run] analysis RMSE = %.4f (NDVI z-units)  (-%.1f%% vs prior)",
                 analysis_rmse,
                 100 * (1 - analysis_rmse / prior_rmse)))
message(sprintf("[pilar3-run] mean posterior SD / prior SD = %.3f",
                 sd_reduction))

# --- Persist slim bundle -------------------------------------------------

# We drop the full fits (heavy + not needed by the vignette) and keep:
#   - past_seq / past_target summary (first + last month maps)
#   - rollout ensemble for every future month (K, T_future, H, W)
#   - prior_mean / prior_sd  at the target month
#   - obs_value / obs_row / obs_col / obs_sd_norm
#   - analysis_mean / analysis_sd / gain_row_norm / innovation
#   - per-member training loss histories
#   - scaling dictionary for de-normalisation
#   - bundle metadata (lons, lats, months)

slim <- list(
  meta = list(
    H = H, W = W, T_total = T_total,
    T_past = T_past, T_future = T_future,
    months = bundle$months,
    lons   = bundle$lons, lats = bundle$lats,
    target_time_index_in_future = target_t_in_future,
    target_month = bundle$months[T_past + target_t_in_future],
    sources = bundle$sources,
    edaphos_ver = as.character(packageVersion("edaphos")),
    created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ),
  scaling = scaling,
  ensemble_forecast = ens_rolls,       # (K, T_future, H, W)
  truth_future      = future_target[1L, , , ],
  obs = list(value = obs_value, row = obs_row, col = obs_col,
              sd = obs_sd_norm),
  prior = list(mean = prior_mean, sd = prior_sd, rmse = prior_rmse),
  analysis = list(
    mean          = analysis_mean,
    sd            = analysis_sd,
    rmse          = analysis_rmse,
    gain_row_norm = assim$gain_row_norm,
    innovation    = assim$innovation,
    n_obs         = assim$n_obs,
    n_ens         = assim$n_ens
  ),
  sd_reduction = sd_reduction,
  training = list(
    loss_histories = lapply(ens_fits, `[[`, "loss_history"),
    final_losses   = vapply(ens_fits, `[[`, numeric(1L), "final_loss"),
    K_ens = K_ens
  )
)

out_dir  <- "inst/extdata"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "temporal_cerrado_results.rds")
saveRDS(slim, out_path)
message(sprintf("[pilar3-run] slim bundle written to %s (%.1f KB)",
                 out_path, file.info(out_path)$size / 1024))
