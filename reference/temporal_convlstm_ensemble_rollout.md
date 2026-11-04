# Roll every ensemble member forward and stack the forecasts

Produces the `(K_ens, T_future, H, W)` array that
[`temporal_kalman_update()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_kalman_update.md)
and
[`as_edaphos_posterior()`](https://hugomachadorodrigues.github.io/edaphos/reference/as_edaphos_posterior.md)
consume.

## Usage

``` r
temporal_convlstm_ensemble_rollout(object, past_sequence, future_drivers)
```

## Arguments

- object:

  An `edaphos_temporal_convlstm_ensemble`.

- past_sequence, future_drivers:

  Passed through to
  [`temporal_convlstm_rollout()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_rollout.md)
  for each member.

## Value

A 4-D numeric array `(K_ens, T_future, H, W)`.

## Examples

``` r
# Forecast months 10-12 of the synthetic Cerrado SOC cube from an
# ensemble trained on months 1-9, then score the across-member
# spread as if it were a predictive interval.
if (requireNamespace("torch", quietly = TRUE) &&
    isTRUE(torch::torch_is_installed())) {

  cube <- temporal_synth_soc_cube(H = 8L, W = 8L, T_total = 12L,
                                  seed = 42L)
  tt   <- temporal_cube_to_tensor(cube)
  past_seq <- tt$sequence[, 1:9,   , , , drop = FALSE]
  past_tgt <- tt$target[,   1:9,   , , drop = FALSE]
  fut_seq  <- tt$sequence[, 10:12, , , , drop = FALSE]  # known drivers

  ens <- temporal_convlstm_ensemble_fit(
    sequence = past_seq, target = past_tgt, hidden_dims = 4L,
    return_sequence = TRUE, epochs = 20L, lr = 0.05,
    K_ens = 3L, base_seed = 7L)

  rolls <- temporal_convlstm_ensemble_rollout(
    ens, past_sequence = past_seq, future_drivers = fut_seq)
  print(dim(rolls))                # (K_ens, T_future, H, W) = 3 3 8 8

  # Undo the z-scaling so every number below is in g/kg.
  gkg   <- rolls * tt$scaling$soc_sd + tt$scaling$soc_mu
  truth <- cube$soc[10:12, , ]

  # Spread and error, side by side, per lead time. The nominal-90%
  # band is mean +/- 1.645 * across-member sd and `covered` is the
  # PICP numerator out of the 64 grid cells.
  print(round(t(vapply(1:3, function(h) {
    mu <- apply(gkg[, h, , ], c(2, 3), mean)
    sm <- apply(gkg[, h, , ], c(2, 3), stats::sd)
    y  <- as.numeric(truth[h, , ])
    c(spread  = mean(sm),
      rmse    = edaphos_rmse(y, as.numeric(mu)),
      bias    = edaphos_bias(y, as.numeric(mu)),
      picp90  = edaphos_picp(y, as.numeric(mu - 1.645 * sm),
                                as.numeric(mu + 1.645 * sm)),
      covered = sum(abs(y - as.numeric(mu)) <= 1.645 * as.numeric(sm)),
      persistence_rmse = edaphos_rmse(y, as.numeric(cube$soc[9L, , ])))
  }, numeric(6))), 3))

  # Two readings. (1) The spread barely doubles across the horizon
  # (4.13 -> 8.83 g/kg) while RMSE more than quadruples (3.35 ->
  # 15.13), so coverage falls from 0.922 to 0.406. (2) Carrying
  # month 9 forward unchanged has RMSE 3.23 g/kg at +3 months
  # against this ensemble's 15.13: persistence wins by 4.7x. Treat
  # the fit as a harness for the uncertainty API, not as a forecast.

  # Why it drifts: the network sees elevation and precipitation, no
  # calendar. Months 10-12 are the driest quarter and their drivers
  # look like months 1-2, when SOC was 20 g/kg -- so the +3-month
  # forecast lands 14.7 g/kg low, back at the month-5/6 level of the
  # cube, instead of continuing the 20 -> 43 g/kg accumulation. A
  # confounded driver, not a flaw in the ensembling.
  print(round(rbind(precip = apply(cube$precip, 1L, mean),
                    soc    = apply(cube$soc,    1L, mean)), 1))

  mu <- apply(gkg[, 3L, , ], c(2, 3), mean)
  sm <- apply(gkg[, 3L, , ], c(2, 3), stats::sd)
  y  <- as.numeric(truth[3L, , ])

  # At +3 months the error is almost pure bias: residuals scatter by
  # 3.57 g/kg about a mean miss of 14.71, and the ensemble spread
  # (8.83) is 2.5x that scatter. The members disagree plenty; they
  # are simply all wrong in the same direction, because they share
  # an architecture and a training window. A deep ensemble measures
  # disagreement, never the bias its members hold in common.
  b <- edaphos_bias(y, as.numeric(mu))
  print(round(c(bias       = b,
                resid_sd   = stats::sd(y - as.numeric(mu)),
                ens_spread = mean(sm)), 2))

  # So the interval score refuses the usual repair. Tripling the
  # band buys PICP 1.000 and scores WORSE than the honest narrow one
  # (87.11 vs 66.90); only recentring pays (29.04) -- and that used
  # the truth, so it is a diagnosis, not something you can deploy.
  sc <- function(lo, hi) c(
    picp = edaphos_picp(y, as.numeric(lo), as.numeric(hi)),
    IS   = edaphos_interval_score(y, as.numeric(lo), as.numeric(hi),
                                  alpha = 0.10))
  print(round(rbind(
    as_is      = sc(mu - 1.645 * sm,     mu + 1.645 * sm),
    widened_3x = sc(mu - 3 * 1.645 * sm, mu + 3 * 1.645 * sm),
    debiased   = sc(mu + b - 1.645 * sm, mu + b + 1.645 * sm)), 3))

  # The same rollout in the unified container. The adapter re-runs
  # the rollout internally and keeps the LAST future step by default
  # (time_step = 3 here), which is the worst-calibrated one.
  post <- as_edaphos_posterior(ens, past_sequence = past_seq,
                               future_drivers = fut_seq,
                               units = "SOC z-units")
  print(post)
  print(unlist(post$metadata))
}
#> [1] 3 3 8 8
#>      spread   rmse   bias picp90 covered persistence_rmse
#> [1,]  4.126  3.351  2.401  0.922      59            1.857
#> [2,]  7.583  8.978  8.569  0.844      54            2.844
#> [3,]  8.826 15.128 14.706  0.406      26            3.233
#>        [,1] [,2] [,3]  [,4]  [,5]  [,6]  [,7]  [,8] [,9] [,10] [,11] [,12]
#> precip 18.2 44.5 81.1 116.8 143.5 152.7 142.6 117.3 81.5  43.1  17.4   8.6
#> soc    20.1 20.5 21.7  23.8  26.8  30.4  34.1  37.4 40.1  41.9  42.8  43.2
#>       bias   resid_sd ens_spread 
#>      14.71       3.57       8.83 
#>             picp     IS
#> as_is      0.406 66.897
#> widened_3x 1.000 87.112
#> debiased   1.000 29.037
#> <edaphos_posterior>
#>   method      : ensemble
#>   query_type  : map
#>   units       : SOC z-units
#>   n_samples   : 3
#>   query shape : 8 x 8
#>   mean range  : [-1.1454, +0.5598]  mean = -0.3543
#>   sd   range  : [+0.4339, +1.5385]  mean = +0.9218
#>                                K_ens                            time_step 
#>                                  "3"                                  "3" 
#>                               source 
#> "temporal_convlstm_ensemble_rollout" 
```
