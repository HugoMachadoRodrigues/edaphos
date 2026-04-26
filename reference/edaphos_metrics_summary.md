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
