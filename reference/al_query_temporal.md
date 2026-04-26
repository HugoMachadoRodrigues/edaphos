# Temporal Active Learning: rank candidate cells by their Kalman gain norm after the latest EnKF assimilation

Closes the loop between Pillar 3 (4D ConvLSTM + stochastic EnKF
assimilation) and Pillar 5 (autonomous active learning). The Kalman-gain
norm is a forward-looking estimate of how much the posterior ensemble
would shrink if a new observation were placed at each spatial cell;
candidates with high gain are the natural next sampling locations.

## Usage

``` r
al_query_temporal(
  kalman_update,
  candidate_coords = NULL,
  n_select = 10L,
  combine = c("gain", "gain_sd", "gain_sd_normalised")
)
```

## Arguments

- kalman_update:

  A `edaphos_temporal_kalman` object returned by
  [`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md).
  Must carry the `gain_row_norm` and `analysis_sd` fields (they are
  produced by default).

- candidate_coords:

  Optional data frame with `lon`, `lat` columns that restrict scoring to
  a finite set of physically accessible cells. When `NULL`, every cell
  of the analysis grid is a candidate.

- n_select:

  Integer; how many candidates to return.

- combine:

  One of `"gain"` (rank by pure gain norm, the v1.5.0 default),
  `"gain_sd"` (weighted product of gain and remaining analysis SD), or
  `"gain_sd_normalised"` (same but each term is percentile-normalised
  first).

## Value

Data frame sorted by descending priority with columns `row`, `col`,
`gain`, `analysis_sd`, `priority`.
