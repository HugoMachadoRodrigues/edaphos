# Summarise a pointwise + interval prediction against observations

Convenience wrapper returning a one-row data frame with RMSE, MAE, R2,
bias, PICP and the interval score at the stated level. Used as the
row-per-method aggregator in the case-study benchmark table.

## Usage

``` r
edaphos_metrics_summary(
  observed,
  predicted,
  lower = NULL,
  upper = NULL,
  interval = 0.95,
  method = "unnamed"
)
```

## Arguments

- observed:

  Numeric vector.

- predicted:

  Numeric vector (point estimate).

- lower, upper:

  Optional numeric vectors with the interval bounds. When `NULL` the
  PICP and interval-score columns are returned as `NA`.

- interval:

  Nominal coverage of `[lower, upper]`; default 0.95.

- method:

  Character label written into the `method` column.

## Value

A one-row data frame.

## Examples

``` r
set.seed(1)
obs  <- stats::rnorm(100, 20, 3)
pred <- obs + stats::rnorm(100, 0, 1)

# Point metrics only.
edaphos_metrics_summary(obs, pred, method = "qrf")
#>   method   n      rmse       mae        r2       bias picp interval_score
#> 1    qrf 100 0.9538273 0.7611936 0.8734342 0.03780808   NA             NA

# Adding intervals turns on the calibration columns, so a single
# row carries accuracy, sharpness and coverage together.
edaphos_metrics_summary(obs, pred,
                        lower = pred - 1.96, upper = pred + 1.96,
                        method = "qrf + intervals")
#>            method   n      rmse       mae        r2       bias picp
#> 1 qrf + intervals 100 0.9538273 0.7611936 0.8734342 0.03780808 0.96
#>   interval_score
#> 1       4.254597
```
