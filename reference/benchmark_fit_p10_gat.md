# Benchmark wrapper: Pilar 10 – GAT seed-ensemble on k-NN graph

Builds a joint k-NN co-location graph on `rbind(train, test)` using
(lon, lat) for adjacency and `cov_cols` as node features, then fits
`n_ensemble` independent GAT regressors with different seeds, and
harvests predictions at the test nodes. Predictive posterior is the seed
ensemble.

## Usage

``` r
benchmark_fit_p10_gat(
  train,
  test,
  cov_cols,
  k = 8L,
  hidden = 12L,
  n_heads = 2L,
  n_layers = 2L,
  epochs = 100L,
  lr = 0.03,
  n_ensemble = 10L,
  seed = 1L,
  calibrate = TRUE
)
```

## Arguments

- train, test:

  Data frames with `soc`, `lon`, `lat`, and `cov_cols`.

- cov_cols:

  Character vector of covariate columns used as node features.

- k:

  Integer; k-NN degree of the co-location graph.

- hidden, n_heads, n_layers:

  Architecture. See
  [`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md).

- epochs, lr:

  Training hyperparameters.

- n_ensemble:

  Integer; number of seed-distinct fits.

- seed:

  Base RNG seed (each member uses `seed + b`).

- calibrate:

  Logical (default `TRUE`). When `TRUE`, residual noise from a
  representative full-data GAT fit is injected on every posterior sample
  (see Pilar-1 wrapper for the rationale).

## Value

An `edaphos_posterior` with `method = "ensemble"`, `query_type = "map"`.

## Examples

``` r
data(br_cerrado)
set.seed(3)
sub <- br_cerrado[sample(nrow(br_cerrado), 160L), ]
names(sub)[names(sub) == "x"] <- "lon"
names(sub)[names(sub) == "y"] <- "lat"
covs  <- c("elev", "slope", "twi", "map_mm", "ndvi")
train <- sub[1:120, ]; test <- sub[121:160, ]

# The k-NN graph spans train AND test, but only the training nodes carry
# an observed target, so `test` never needs a `soc` column: the wrapper
# fills the held-out targets with NA and masks them out of the loss.
post <- benchmark_fit_p10_gat(train, test[, c("lon", "lat", covs)], covs,
                              k = 6L, hidden = 8L, n_heads = 2L,
                              n_layers = 2L, epochs = 40L, lr = 0.05,
                              n_ensemble = 4L, seed = 1L)
#> Warning: P10: inner blocked CV could not run on this training partition; the residual scale falls back to training residuals and the interval is expected to undercover.
dim(post$samples)                 # 4 seed-distinct members x 40 sites
#> [1]  4 40

# Two baselines, both computed here: the training mean and OLS on the
# same five covariates.  5.090 / 7.289 / 4.679 -- on 120 training nodes
# the attention over the co-location graph beats the mean by 30% and
# still loses to the linear model by 9%.  A GAT row in a benchmark
# table means nothing without that middle column.
cal <- uncertainty_calibrate(post, truth = test$soc)
ols <- lm(soc ~ elev + slope + twi + map_mm + ndvi, data = train)
round(c(gat  = cal$point_rmse,
        null = sqrt(mean((mean(train$soc) - test$soc)^2)),
        ols  = sqrt(mean((predict(ols, test) - test$soc)^2))), 3)
#>   gat  null   ols 
#> 4.930 7.289 4.679 

# `n_ensemble` is not only how precisely the point prediction is
# averaged: the posterior IS the ensemble, so a 90% interval read off
# four draws cannot be wider than their range.  Going to eight members
# widens it from 7.75 to 9.62 g/kg and lifts coverage from 0.50 to
# 0.60 -- closer to nominal, still well short of it.
big <- benchmark_fit_p10_gat(train, test, covs, k = 6L, hidden = 8L,
                             n_heads = 2L, n_layers = 2L, epochs = 40L,
                             lr = 0.05, n_ensemble = 8L, seed = 1L)
#> Warning: P10: inner blocked CV could not run on this training partition; the residual scale falls back to training residuals and the interval is expected to undercover.
cal_big <- uncertainty_calibrate(big, truth = test$soc)
round(c(picp90_4 = cal$picp[["0.90"]], picp90_8 = cal_big$picp[["0.90"]],
        mpiw90_4 = cal$mpiw[["0.90"]], mpiw90_8 = cal_big$mpiw[["0.90"]]), 3)
#> picp90_4 picp90_8 mpiw90_4 mpiw90_8 
#>    0.525    0.550    7.832    9.086 

# Where that width comes from matters.  `calibrate = FALSE` leaves only
# the seed-to-seed spread of the fitted means -- 1.10 g/kg, and 20%
# coverage -- against a residual sd of 3.79.  The members disagree far
# less with each other than any of them disagrees with the truth, which
# is the usual state of a deep ensemble and the reason the aleatoric
# term is added by default.
epi <- benchmark_fit_p10_gat(train, test, covs, k = 6L, hidden = 8L,
                             n_heads = 2L, n_layers = 2L, epochs = 40L,
                             lr = 0.05, n_ensemble = 4L, seed = 1L,
                             calibrate = FALSE)
round(c(sd_epistemic = mean(apply(epi$samples, 2L, sd)),
        sd_calibrated = mean(apply(post$samples, 2L, sd)),
        sigma_resid = post$metadata$sigma_resid,
        picp90_epistemic =
          uncertainty_calibrate(epi, truth = test$soc)$picp[["0.90"]]), 3)
#>     sd_epistemic    sd_calibrated      sigma_resid picp90_epistemic 
#>            1.054            3.957            3.681            0.175 

# Member-by-member RMSE, for scale: the four seeds score 4.98 to 5.46
# and their average scores 5.09 -- inside that range, not below it.  On
# this problem the ensemble is buying an interval, not accuracy.
round(apply(epi$samples, 1L, function(p) sqrt(mean((p - test$soc)^2))), 3)
#> [1] 5.138 5.133 4.764 5.087

# Each member is one gnn_fit() on a single transductive graph: train
# and test nodes together, held-out targets NA, loss on the training
# mask.  Rebuilding member 1 by hand reproduces it exactly -- and shows
# what `epochs` actually did.  gnn_fit() keeps a validation slice and
# restores its best epoch, which here is epoch 2 of the 40 asked for;
# it stops at 22 and discards the rest.  Nothing above is a training
# curve, which is the other half of why this loses to lm().
df_all <- rbind(cbind(train[, c("lon", "lat", covs)], soc = train$soc),
                cbind(test[,  c("lon", "lat", covs)], soc = NA_real_))
g1 <- gnn_build_graph(df_all, k = 6L, feature_cols = covs)
f1 <- gnn_fit(g1, df_all$soc, train_mask = !is.na(df_all$soc),
              hidden = 8L, n_heads = 2L, n_layers = 2L, epochs = 40L,
              lr = 0.05, seed = 2L)          # member b uses seed + b
c(best_epoch = f1$best_epoch, epochs_run = length(f1$history))
#> best_epoch epochs_run 
#>          2         22 
isTRUE(all.equal(predict(f1)[121:160], epi$samples[1, ]))
#> [1] TRUE
```
