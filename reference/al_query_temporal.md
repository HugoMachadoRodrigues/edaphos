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

  A `edaphos_temporal_kalman` object whose `gain_row_norm` and
  `analysis_sd` slots are both `H x W` matrices of per-cell values.
  `analysis_sd` already is one, but note that
  [`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
  fills `gain_row_norm` with one number per *observation* (the column
  norms of the Kalman gain), so a result taken straight from it is
  rejected: write a per-cell informativeness map into that slot first.
  See the examples.

- candidate_coords:

  Optional data frame with integer `row` and `col` grid indices (not lon
  / lat) that restrict scoring to a finite set of physically accessible
  cells. When `NULL`, every cell of the analysis grid is a candidate.

- n_select:

  Integer; how many candidates to return. More than the number of
  candidates simply returns them all.

- combine:

  One of `"gain"` (rank by pure gain norm, the v1.5.0 default),
  `"gain_sd"` (weighted product of gain and remaining analysis SD), or
  `"gain_sd_normalised"` (same but each term is min-max rescaled first –
  over the *candidate* set, so restricting `candidate_coords` reorders
  this ranking instead of only filtering it).

## Value

Data frame sorted by descending priority with columns `row`, `col`,
`gain`, `analysis_sd`, `priority`.

## Examples

``` r
# Pillar 3 -> Pillar 5. A 30-member forecast of month-12 SOC over a
# 12 x 12 Cerrado grid, biased 2 g/kg low, plus an EnKF assimilation
# of three fresh profiles. No torch needed for any of this.
cube  <- temporal_synth_soc_cube(H = 12L, W = 12L, T_total = 12L,
                                 seed = 42L)
soc12 <- cube$soc[12L, , ]
set.seed(2024L)
fc <- array(rep(as.numeric(soc12) - 2, each = 30L),
            dim = c(30L, 12L, 12L)) +
      array(stats::rnorm(30L * 144L, 0, 1.5), dim = c(30L, 12L, 12L))
obs_row <- c(3L, 9L, 6L)
obs_col <- c(3L, 9L, 11L)
ku <- temporal_kalman_update(fc,
                             obs_value = soc12[cbind(obs_row, obs_col)],
                             obs_row = obs_row, obs_col = obs_col,
                             obs_sd = 0.5, localization_radius = 3,
                             seed = 9L)

# Trap first: ku$gain_row_norm holds one number per OBSERVATION, not
# the H x W per-cell map this function ranks, so the raw EnKF result
# is refused.
c(is_matrix = is.matrix(ku$gain_row_norm),
  length    = length(ku$gain_row_norm))
#> is_matrix    length 
#>         0         3 
tryCatch(al_query_temporal(ku), error = function(e) conditionMessage(e))
#> [1] "`gain_row_norm` and `analysis_sd` must both be H x W matrices of per-cell values. temporal_kalman_update() returns `gain_row_norm` as one value per observation (the column norms of the Kalman gain), so write a per-cell informativeness map into that slot before calling."

# Supply a per-cell informativeness map instead. The realised spread
# shrinkage (forecast sd - analysis sd) is the one you can build
# from what the EnKF actually returns; with localization_radius = 3
# it is 1.099 at the sampled cells and ~0 (median 0.002) elsewhere.
ku$gain_row_norm <- apply(fc, c(2, 3), stats::sd) - ku$analysis_sd
round(c(at_observed = mean(ku$gain_row_norm[cbind(obs_row, obs_col)]),
        grid_median = stats::median(ku$gain_row_norm),
        far_corner  = ku$gain_row_norm[1L, 1L]), 4)
#> at_observed grid_median  far_corner 
#>      1.0993      0.0019     -0.0032 

# combine = "gain" then hands back the three cells you have ALREADY
# sampled as the top three. Gain is highest where an observation
# sits, so ranking on it alone re-visits your own boreholes.
al_query_temporal(ku, n_select = 5L, combine = "gain")
#> <edaphos_temporal_al_query>  (Pilar 3 x Pilar 5 bridge)
#>   grid dims : 12 x 12
#>   combine   : gain
#>   n_select  : 5
#>   top-5 cells (sorted by priority):
#>     row col      gain analysis_sd  priority
#> 27    3   3 1.1077663   0.4628177 1.1077663
#> 126   6  11 1.1006539   0.4096461 1.1006539
#> 105   9   9 1.0893340   0.4550861 1.0893340
#> 127   7  11 0.1069342   1.5825599 0.1069342
#> 3     3   1 0.1066447   1.4231513 0.1066447

# Multiplying by the remaining analysis SD is what stops that: those
# cells are now the best-constrained on the grid (sd 0.443 against a
# grid median of 1.440), so the product demotes all three out of the
# top 5. Read the two columns together, never `gain` alone.
round(c(sd_at_observed = mean(ku$analysis_sd[cbind(obs_row, obs_col)]),
        sd_grid_median = stats::median(ku$analysis_sd)), 3)
#> sd_at_observed sd_grid_median 
#>          0.443          1.440 
as.data.frame(al_query_temporal(ku, n_select = 5L,
                                combine = "gain_sd_normalised"))
#>     row col       gain analysis_sd   priority
#> 103   7   9 0.08334152    1.964040 0.08917262
#> 127   7  11 0.10693424    1.582560 0.08311628
#> 3     3   1 0.10664468    1.423151 0.07165223
#> 115   7  10 0.06311852    1.774312 0.06250246
#> 80    8   7 0.06554957    1.579451 0.05520442

# candidate_coords takes row / col grid indices -- not lon / lat --
# and is where already-sampled cells get dropped. Even then pure
# gain picks (7, 11), one cell away from the (6, 11) profile:
# spatial redundancy is the SD factor's other job.
grid <- expand.grid(row = 1:12, col = 1:12)
cand <- grid[!(paste(grid$row, grid$col) %in%
               paste(obs_row, obs_col)), ]
as.data.frame(al_query_temporal(ku, cand, n_select = 3L,
                                combine = "gain"))
#>     row col       gain analysis_sd   priority
#> 127   7  11 0.10693424    1.582560 0.10693424
#> 3     3   1 0.10664468    1.423151 0.10664468
#> 103   7   9 0.08334152    1.964040 0.08334152

# "gain_sd_normalised" rescales within the candidate set, so these
# two rankings over the identical 141 cells disagree on the order.
a <- al_query_temporal(ku, cand, n_select = 141L,
                       combine = "gain_sd_normalised")
b <- al_query_temporal(ku, cand, n_select = 141L, combine = "gain_sd")
rbind(normalised  = head(paste(a$row, a$col), 4L),
      raw_product = head(paste(b$row, b$col), 4L))
#>             [,1]   [,2]   [,3]   [,4]  
#> normalised  "7 9"  "7 11" "7 10" "3 1" 
#> raw_product "7 11" "7 9"  "3 1"  "7 10"

# Finally, what the assimilation this ranks was worth. Three
# profiles on 144 cells sharpen the analysis only where they sit:
# RMSE improves by 0.02 g/kg while 90% coverage (0.694 -> 0.667) and
# the interval score (6.24 -> 6.36) both get slightly worse, because
# the 2 g/kg prior bias survives wherever the taper is zero. That is
# the argument for spending the next sample well.
truth <- as.numeric(soc12)
pk    <- as_edaphos_posterior(ku, units = "g/kg")
plo   <- as.numeric(apply(fc, c(2, 3), stats::quantile, 0.05))
phi   <- as.numeric(apply(fc, c(2, 3), stats::quantile, 0.95))
round(rbind(
  prior = c(
    rmse   = edaphos_rmse(truth, as.numeric(apply(fc, c(2, 3), mean))),
    picp90 = edaphos_picp(truth, plo, phi),
    IS     = edaphos_interval_score(truth, plo, phi, alpha = 0.10)),
  analysis = c(
    rmse   = edaphos_rmse(truth, as.numeric(ku$analysis_mean)),
    picp90 = edaphos_picp(truth, as.numeric(pk$quantiles$q05),
                                 as.numeric(pk$quantiles$q95)),
    IS     = edaphos_interval_score(truth,
                                    as.numeric(pk$quantiles$q05),
                                    as.numeric(pk$quantiles$q95),
                                    alpha = 0.10))), 3)
#>           rmse picp90    IS
#> prior    2.011  0.694 6.238
#> analysis 1.990  0.667 6.364
```
