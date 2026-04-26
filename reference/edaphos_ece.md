# Expected calibration error (ECE) for a regression reliability diagram

Bins predictions by their predicted quantile, then within each bin
compares the empirical miscoverage rate to the nominal level. Lower is
better; 0 = perfect calibration.

## Usage

``` r
edaphos_ece(observed, predicted_quantiles, quantile_levels)
```

## Arguments

- observed:

  Numeric vector.

- predicted_quantiles:

  A numeric matrix with one column per nominal quantile level in
  `quantile_levels`.

- quantile_levels:

  Numeric vector in `(0, 1)` giving the nominal level of each column of
  `predicted_quantiles`.

## Value

Numeric scalar (mean of per-level absolute calibration errors).

## Details

For each quantile level \\q_k = k / K\\ we compute the fraction of test
points whose observed value is below the predicted \\q_k\\ quantile and
compare to the nominal level.
