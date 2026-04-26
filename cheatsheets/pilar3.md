# Pilar 3 — 4D Pedometry (ConvLSTM + EnKF)

Multi-layer stacked Convolutional LSTM for spatio-temporal SOC
forecasting + a stochastic Ensemble Kalman Filter for sequential
assimilation of new in-situ observations.

## Core API

```r
# Build a (T, H, W, C) cube
cube <- temporal_cube_build(
  rasters       = list_of_terra_rasts,
  time_stamps   = as.Date(c("2020-01-01", "2020-02-01", ...)),
  static_covs   = c("elev", "slope")
)

# Train ConvLSTM
fit <- temporal_convlstm_fit(
  cube, target = "soc",
  hidden = 32L, n_layers = 2L,
  epochs = 100L, lr = 0.005,
  physics_loss_fn = NULL,    # or a P2 ODE-mass-balance loss
  seed = 1L
)

# Multi-step rollout forecast
fc <- temporal_convlstm_forecast(fit, n_steps = 12L)

# Sequential assimilation of new observations
fit_post <- temporal_kalman_update(
  fit, new_obs = data.frame(t = 13, row = 5, col = 8, y = 28),
  R_obs = 0.5
)
```

## v3.0.0 bridge: `temporal_piml_loss()` (Pilar 2 × Pilar 3)

Inject site-specific ODE kinetics as the ConvLSTM mass-balance
penalty.  See `cheatsheets/pilar2.md`.

## Key references

* Shi et al. (2015) ConvLSTM — original architecture.
* Evensen (2003) Ensemble Kalman Filter.
* Heuvelink et al. (2020) — spatio-temporal soil mapping.

## See also

* `vignette("pilar3-4d-soc")` — full tutorial on synthetic cube.
* `articles/pilar3-4d-real.Rmd` — case study on a real Cerrado MODIS
  cube.
