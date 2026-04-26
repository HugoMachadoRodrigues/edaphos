# Interval score (Gneiting and Raftery 2007)

Proper scoring rule balancing sharpness (narrower intervals score
better) against calibration (penalising intervals that miss the observed
value). Lower is better.

## Usage

``` r
edaphos_interval_score(observed, lower, upper, alpha = 0.05)
```

## Arguments

- observed, lower, upper:

  Numeric vectors.

- alpha:

  Nominal miscoverage level (1 - nominal PICP). Default `0.05` for a 95%
  prediction interval.

## Value

Non-negative numeric scalar (mean over the test set).

## Details

\$\$IS\_\alpha = (u - \ell) + \frac{2}{\alpha}(\ell - y) \mathbb 1\\y \<
\ell\\ + \frac{2}{\alpha}(y - u) \mathbb 1\\y \> u\\.\$\$

## References

Gneiting, T. and Raftery, A. E. (2007). Strictly proper scoring rules,
prediction, and estimation. *Journal of the American Statistical
Association* **102**(477), 359-378.
