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

## Examples

``` r
set.seed(1)
n   <- 200
obs <- stats::rnorm(n, mean = 20, sd = 3)
band <- function(half) list(lower = rep(20 - half, n),
                            upper = rep(20 + half, n))

# The interval score is negatively oriented (lower is better) and
# penalises width as well as missed coverage, so -- unlike PICP --
# it cannot be gamed by widening the interval.
ok   <- band(1.96 * 3)
wide <- band(1e3)
tight <- band(0.5)

c(calibrated     = edaphos_interval_score(obs, ok$lower, ok$upper),
  too_wide       = edaphos_interval_score(obs, wide$lower, wide$upper),
  over_confident = edaphos_interval_score(obs, tight$lower, tight$upper))
#>     calibrated       too_wide over_confident 
#>       12.83710     2000.00000       71.27969 
```
