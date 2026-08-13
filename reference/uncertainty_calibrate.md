# Calibration diagnostics for an `edaphos_posterior`

Computes the continuous ranked probability score (CRPS), a
prediction-interval coverage probability (PICP) at each requested
nominal level, the mean prediction-interval width (MPIW) at the same
levels, and a ready-for-ggplot reliability data frame.

## Usage

``` r
uncertainty_calibrate(post, truth, probs = seq(0.05, 0.95, by = 0.05))
```

## Arguments

- post:

  An `edaphos_posterior`.

- truth:

  Numeric array with the same shape as `post$mean`; the ground-truth
  values.

- probs:

  Nominal coverage probabilities at which to report PICP + MPIW, and for
  the reliability curve. Defaults to `seq(0.05, 0.95, by = 0.05)`.

## Value

A list with:

- crps:

  Mean sample-based CRPS across query cells.

- crps_per:

  Numeric vector of per-query-cell CRPS, in the flattened order of
  `post$mean`; `crps` is its mean.

- picp:

  Named vector of empirical coverage, one per `probs`.

- mpiw:

  Named vector of mean interval widths, one per `probs`.

- reliability_df:

  Data frame with columns `nominal`, `empirical`, `diff` suitable for
  [`ggplot2::geom_line`](https://ggplot2.tidyverse.org/reference/geom_path.html).

- point_rmse:

  Root-mean-squared error of the posterior mean against the truth.

## Details

The CRPS for a sample-based posterior `F` and a scalar truth `y` is
computed from the Monte-Carlo formula \\ \mathrm{CRPS}(F, y) =
\tfrac{1}{N}\sum_i \|s_i - y\| - \tfrac{1}{2N^2}\sum\_{i,j} \|s_i -
s_j\| \\ (see Gneiting & Raftery 2007 for the derivation and its
strictly proper scoring rule interpretation). The per-query CRPS is
averaged across all query cells for a single reported scalar.

## References

Gneiting, T. and Raftery, A. E. (2007). Strictly proper scoring rules,
prediction, and estimation. *Journal of the American Statistical
Association* **102**(477), 359-378.

## Examples

``` r
# A stand-in for a pillar posterior: `lm()` on 1825 Cerrado cells
# gives a predictive mean for 200 held-out cells and a residual sd.
# A real posterior arrives via as_edaphos_posterior() on a pillar
# fit; nothing below depends on which pillar produced it.
set.seed(2024)
holdout <- sample(nrow(br_cerrado), 200L)
test    <- br_cerrado[holdout, ]
train   <- br_cerrado[-holdout, ]
fit     <- stats::lm(soc ~ elev + slope + twi + map_mm + ndvi,
                     data = train)
mu      <- as.numeric(stats::predict(fit, newdata = test))
sigma   <- summary(fit)$sigma          # 4.3064 g/kg

# Same predictive mean, two claims about its spread. The second
# understates the sd by a factor of three on purpose.
honest <- edaphos_posterior(mean = mu, sd = rep(sigma, 200L),
                            method = "gaussian",
                            query_type = "sample", units = "g/kg")
tight  <- edaphos_posterior(mean = mu, sd = rep(sigma / 3, 200L),
                            method = "gaussian",
                            query_type = "sample", units = "g/kg")
cal_h <- uncertainty_calibrate(honest, test$soc)
cal_t <- uncertainty_calibrate(tight,  test$soc)

# `point_rmse` is blind to the difference -- the means are identical.
# Accuracy and calibration are separate questions.
c(honest = cal_h$point_rmse, tight = cal_t$point_rmse)
#>   honest    tight 
#> 4.248001 4.248001 

# Coverage is not blind. Nominal 90% intervals hold 90.5% of the
# truth for the honest posterior and 39.5% for the overconfident one.
round(rbind(honest = cal_h$picp[c("0.50", "0.90")],
            tight  = cal_t$picp[c("0.50", "0.90")]), 3)
#>         0.50  0.90
#> honest 0.490 0.905
#> tight  0.175 0.395

# Read those against sampling noise before calling it miscalibrated:
# on 200 cells the binomial standard error of a 90% coverage
# estimate is 0.021, so the honest posterior (0.005 off nominal) is
# indistinguishable from calibrated and the tight one is 24 SEs out.
round(c(se90   = sqrt(0.9 * 0.1 / 200),
        honest = cal_h$picp[["0.90"]] - 0.9,
        tight  = cal_t$picp[["0.90"]] - 0.9), 4)
#>    se90  honest   tight 
#>  0.0212  0.0050 -0.5050 

# CRPS is a proper score and does move the right way, but only by
# 16% for a 3x understated sd. A report quoting CRPS alone can hide
# a badly overconfident map that PICP catches instantly.
round(c(crps_honest = cal_h$crps, crps_tight = cal_t$crps), 4)
#> crps_honest  crps_tight 
#>      2.4314      2.8262 

# The reliability curve is the readable version: all 19 nominal
# levels under-covered, none over, worst by 0.51.
all(cal_t$reliability_df$diff < 0)
#> [1] TRUE
round(max(abs(cal_t$reliability_df$diff)), 3)
#> [1] 0.51

# Coverage on its own is still not enough: it is bought with width.
# Read PICP next to MPIW at the same level -- 14.1 g/kg against 4.7.
round(c(mpiw90_honest = cal_h$mpiw[["0.90"]],
        mpiw90_tight  = cal_t$mpiw[["0.90"]]), 3)
#> mpiw90_honest  mpiw90_tight 
#>        14.123         4.695 

# `crps_per` holds the 200 per-cell scores behind the scalar. Every
# cell here was handed the same sd, so CRPS is monotone in |error|
# and its worst cell is merely the worst residual; the per-cell
# scores only add information once sd varies by cell.
length(cal_h$crps_per)
#> [1] 200
identical(which.max(cal_h$crps_per), which.max(abs(mu - test$soc)))
#> [1] TRUE
```
