# Ensemble Kalman update of a Pillar 3 forecast by new point observations

Nudges a `temporal_convlstm_rollout` forecast toward a set of new
in-situ observations at known grid coordinates, using the stochastic
Ensemble Kalman Filter of Evensen (1994) and Burgers, van Leeuwen and
Evensen (1998).

## Usage

``` r
temporal_kalman_update(
  forecast_ensemble,
  obs_value,
  obs_row,
  obs_col,
  obs_sd,
  time_step = 1L,
  localization_radius = NULL,
  seed = NULL
)
```

## Arguments

- forecast_ensemble:

  A 3-D array `(N_ens, H, W)` (single-step forecast) or 4-D array
  `(N_ens, H, W, T)` (multi-step). For 4-D input the update is applied
  at `time_step`.

- obs_value:

  Numeric vector of length `n_obs` — the observed values to assimilate.

- obs_row, obs_col:

  Integer vectors of length `n_obs` — the row / column indices (1-based,
  row-major from the top-left of the grid) at which the observations
  were taken.

- obs_sd:

  Numeric scalar or vector of length `n_obs` — the standard deviation of
  each observation. Sets the diagonal of the observation-noise
  covariance matrix \\R\\.

- time_step:

  Integer — when `forecast_ensemble` is 4-D, which time slice to update.
  Ignored for 3-D input.

- localization_radius:

  Optional numeric — if supplied, applies a Gaspari-Cohn (1999)
  5th-order polynomial taper to the Kalman gain as a function of
  grid-cell distance from each observation. The taper is 1 at distance
  0, half-bandwidth `localization_radius` cells, and identically zero
  beyond `2 * localization_radius` cells. Typical choices are
  `localization_radius = 2`..`5` cells for ensembles in the
  `K = 5`..`30` range. The default `NULL` disables localization (pure
  stochastic EnKF).

- seed:

  Optional integer — seeds the Gaussian perturbations.

## Value

A list with:

- analysis_ensemble:

  The updated ensemble, same shape as `forecast_ensemble`.

- analysis_mean, analysis_sd:

  Pointwise posterior mean / standard deviation across ensemble members,
  at the updated time step.

- gain_row_norm:

  For diagnostics: the \\L_2\\ norm of each column of the Kalman gain,
  one per observation. Large values indicate observations that moved the
  posterior a lot.

- innovation:

  The vector \\y - H \bar X_f\\ of observation-minus-forecast
  differences, a standard EnKF diagnostic.

## Details

The forecast must be an ensemble: the stochastic EnKF treats the first
dimension of `forecast_ensemble` as the ensemble axis (size
\\N\_{\mathrm{ens}}\\). A point estimate (single-member "ensemble") is
supported but the update collapses to a deterministic nudge and the
posterior uncertainty cannot be recovered from a single run.

**Algorithm (stochastic EnKF)**. For each ensemble member \\X_f^{(i)}\\:

1.  Draw an observation perturbation \\\varepsilon^{(i)} \sim \mathcal
    N(0, R)\\.

2.  Compute the Kalman gain \\K = P_f H^T (H P_f H^T + R)^{-1}\\, where
    \\P_f\\ is estimated from the ensemble and \\H\\ is the linear
    operator mapping the full grid to the observed cells.

3.  Analysis step: \\X_a^{(i)} = X_f^{(i)} + K (y + \varepsilon^{(i)} -
    H X_f^{(i)})\\.

## Spatial localization

For small ensembles (`N_ens < ~100`), the raw sample covariance develops
spurious long-range correlations that drag the analysis away from the
truth far from the observations. The optional `localization_radius`
argument applies a Gaspari-Cohn (1999) 5th-order polynomial taper to the
Kalman gain, zeroing the update outside a neighbourhood of each
observation. Without localization (`localization_radius = NULL`, the
default), small ensembles often exhibit the classic ensemble-collapse
pathology in which the analysis RMSE grows above the prior RMSE even as
the posterior spread shrinks.

## References

Evensen, G. (1994). Sequential data assimilation with a nonlinear
quasi-geostrophic model using Monte Carlo methods to forecast error
statistics. *Journal of Geophysical Research: Oceans* **99**(C5),
10143-10162.

Burgers, G., van Leeuwen, P. J. and Evensen, G. (1998). Analysis scheme
in the ensemble Kalman filter. *Monthly Weather Review* **126**,
1719-1724.

## Examples

``` r
if (FALSE) { # \dontrun{
  # Forecast ensemble from a ConvLSTM with K members
  fc <- array(rnorm(10 * 20 * 20), dim = c(10, 20, 20))

  # Three in-situ observations at known grid cells
  assim <- temporal_kalman_update(
    forecast_ensemble = fc,
    obs_value = c(0.62, 0.58, 0.51),
    obs_row   = c(5L, 10L, 15L),
    obs_col   = c(5L, 10L, 15L),
    obs_sd    = 0.02,
    seed      = 1L
  )
  assim$analysis_mean          # posterior mean field
  assim$analysis_sd            # posterior SD field
} # }
```
