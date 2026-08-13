# Mean bias (observed minus predicted)

Positive = prediction under-estimates the target; negative = over-
estimate.

## Usage

``` r
edaphos_bias(observed, predicted)
```

## Arguments

- observed, predicted:

  Numeric vectors.

## Value

Numeric scalar.

## Examples

``` r
obs  <- c(12.1, 18.4,  9.7, 22.0, 15.3)

# A model that is systematically 2 units low.
edaphos_bias(obs, obs - 2)
#> [1] 2

# Bias cancels, so it cannot see scatter: these two predictors have
# the same bias and very different accuracy.
noisy <- obs + c(-6, 6, -6, 6, 0)
c(bias_noisy = edaphos_bias(obs, noisy),
  bias_exact = edaphos_bias(obs, obs),
  rmse_noisy = edaphos_rmse(obs, noisy))
#> bias_noisy bias_exact rmse_noisy 
#>   0.000000   0.000000   5.366563 
```
