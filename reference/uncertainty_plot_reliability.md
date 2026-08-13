# Reliability diagram from a calibration result

Given the output of
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md),
draws a reliability diagram (nominal vs empirical coverage) with the
identity line.

## Usage

``` r
uncertainty_plot_reliability(calib, ...)
```

## Arguments

- calib:

  List returned by
  [`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md).

- ...:

  Ignored.

## Value

A `ggplot` object.

## Examples

``` r
# Two posteriors over the same 200 held-out Cerrado cells: a linear
# model, and the null every soil map has to beat -- the training
# marginal pasted on every cell, covariates ignored.
if (requireNamespace("ggplot2", quietly = TRUE)) {
  set.seed(2024)
  holdout <- sample(nrow(br_cerrado), 200L)
  test    <- br_cerrado[holdout, ]
  train   <- br_cerrado[-holdout, ]
  fit     <- stats::lm(soc ~ elev + slope + twi + map_mm + ndvi,
                       data = train)
  mu      <- as.numeric(stats::predict(fit, newdata = test))

  model <- edaphos_posterior(mean = mu,
                             sd   = rep(summary(fit)$sigma, 200L),
                             method = "gaussian",
                             query_type = "sample")
  clim  <- edaphos_posterior(mean = rep(mean(train$soc), 200L),
                             sd   = rep(stats::sd(train$soc), 200L),
                             method = "gaussian",
                             query_type = "sample")
  cal_m <- uncertainty_calibrate(model, test$soc)
  cal_c <- uncertainty_calibrate(clim,  test$soc)

  p_model <- uncertainty_plot_reliability(cal_m)
  p_clim  <- uncertainty_plot_reliability(cal_c)

  # Both curves hug the identity line: the climatology is as well
  # calibrated as the model (worst gap 0.060 against 0.045). A
  # reliability diagram cannot tell a skilful map from a useless one.
  print(round(c(model = max(abs(cal_m$reliability_df$diff)),
                clim  = max(abs(cal_c$reliability_df$diff))), 3))

  # Which is why the title carries CRPS and RMSE -- those do separate
  # them (2.4314 / 4.2480 against 3.7034 / 6.4965).
  print(c(model = p_model$labels$title, clim = p_clim$labels$title))

  # Sharpness is the other half and appears nowhere on the diagram:
  # the climatology's 90% interval is 21.3 g/kg wide, the model's
  # 14.1. Always show `mpiw` beside the plot.
  print(round(c(mpiw90_model = cal_m$mpiw[["0.90"]],
                mpiw90_clim  = cal_c$mpiw[["0.90"]]), 2))

  # The plot draws `reliability_df` verbatim -- 19 points, one per
  # nominal level, no smoothing, no re-binning, so a wobble of one
  # point is one binomial estimate and not a trend.
  print(identical(p_model$data, cal_m$reliability_df))

  p_model
}
#> model  clim 
#> 0.045 0.060 
#>                                         model 
#> "Reliability  (CRPS = 2.4314, RMSE = 4.2480)" 
#>                                          clim 
#> "Reliability  (CRPS = 3.7034, RMSE = 6.4965)" 
#> mpiw90_model  mpiw90_clim 
#>        14.12        21.30 
#> [1] TRUE
```
