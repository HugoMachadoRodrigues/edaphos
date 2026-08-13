# Posterior predictive distribution of an edaphos Active-Learning fit

Samples the conditional distribution of the target at every row of
`candidates` by asking the underlying Quantile Regression Forest
(ranger) for a grid of quantiles. The returned `edaphos_posterior`
carries those quantile samples directly, so
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md)
and
[`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
work without changes.

## Usage

``` r
active_learning_posterior(model, newdata, n_quantiles = 99L, units = NULL)
```

## Arguments

- model:

  An `edaphos_al_model` produced by
  [`al_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_fit.md).

- newdata:

  A data frame with (at least) the columns used as covariates at fit
  time.

- n_quantiles:

  Integer; size of the equally-spaced grid of quantiles to request from
  the QRF. Defaults to `99L` (1 % to 99 % in 1 % steps, which is a
  reasonable trade-off between a smooth empirical CDF and
  `ranger::predict()` cost).

- units:

  Optional free-text units tag.

## Value

An `edaphos_posterior` with `method = "ensemble"` (the QRF conditional
distribution being itself an ensemble over tree leaves) and
`query_type = "sample"`.

## References

Meinshausen, N. (2006). Quantile regression forests. *Journal of Machine
Learning Research* **7**, 983-999.

## Examples

``` r
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
set.seed(42)
i_lab <- sample(nrow(br_cerrado), 30)
lab   <- br_cerrado[i_lab, ]

# set.seed() as well as `seed`: ranger builds the quantile lookup
# this function reads with R's own RNG at fit time, so without it
# every number below moves between sessions.
set.seed(1)
m <- al_fit(lab, target = "soc", covariates = covs, seed = 1)

# 100 held-out cells whose true SOC we know, so the posterior can be
# scored rather than admired.
hold <- br_cerrado[-i_lab, ][seq(3, 1995, by = 20), ]
post <- active_learning_posterior(m, hold, n_quantiles = 99,
                                  units = "g/kg")
post
#> <edaphos_posterior>
#>   method      : ensemble
#>   query_type  : sample
#>   units       : g/kg
#>   n_samples   : 99
#>   query shape : 100
#>   mean range  : [+7.4465, +26.0562]  mean = +16.9541
#>   sd   range  : [+2.9539, +7.7714]  mean = +5.4522
dim(post$samples)   # 99 x 100 -- n_samples IS n_quantiles, not draws
#> [1]  99 100

cal <- uncertainty_calibrate(post, hold$soc)
round(c(crps = cal$crps, rmse = cal$point_rmse,
        mean_only_rmse = sqrt(mean((hold$soc - mean(lab$soc))^2))), 2)
#>           crps           rmse mean_only_rmse 
#>           3.48           5.90           7.38 

# The intervals are too narrow at every level worth quoting: 82 % of
# the truths fall inside the nominal 90 % interval, 74 % inside the
# 80 %. Report this next to the CRPS, which does not show it.
round(cal$picp[c("0.50", "0.80", "0.90")], 2)
#> 0.50 0.80 0.90 
#> 0.51 0.72 0.79 
sum(cal$reliability_df$diff < 0)      # under-covers at 16 of 19 levels
#> [1] 17

# Part of that gap is structural, not a tuning failure. A quantile
# regression forest can only return values it has seen labeled, so
# the posterior's support is exactly the labeled SOC range; the six
# held-out cells outside it have coverage 0 however wide you make the
# intervals. Adding labels at the extremes is the only fix -- which
# is the argument for the active-learning loop.
round(rbind(posterior = range(post$samples),
            labeled   = range(lab$soc),
            holdout   = range(hold$soc)), 2)
#>           [,1]  [,2]
#> posterior 5.00 31.48
#> labeled   5.00 31.48
#> holdout   6.03 37.12
out <- hold$soc < min(lab$soc) | hold$soc > max(lab$soc)
lo <- apply(post$samples, 2, stats::quantile, 0.05)
hi <- apply(post$samples, 2, stats::quantile, 0.95)
round(c(n_outside = sum(out),
        picp90_outside = mean(hold$soc[out]  >= lo[out]  &
                              hold$soc[out]  <= hi[out]),
        picp90_inside  = mean(hold$soc[!out] >= lo[!out] &
                              hold$soc[!out] <= hi[!out])), 2)
#>      n_outside picp90_outside  picp90_inside 
#>           6.00           0.00           0.84 

# Rows with an NA covariate are dropped silently, so the posterior
# can be shorter than `newdata` and uncertainty_calibrate() then
# refuses the truth vector. Subset it with the same rule.
hold_na <- hold; hold_na$twi[1] <- NA
p_na <- active_learning_posterior(m, hold_na)
c(rows = nrow(hold_na), cells = length(p_na$mean))       # 100 vs 99
#>  rows cells 
#>   100    99 
ok <- stats::complete.cases(hold_na[, covs])
round(uncertainty_calibrate(p_na, hold_na$soc[ok])$point_rmse, 2)
#> [1] 5.93
```
