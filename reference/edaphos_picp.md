# Prediction-interval coverage probability (PICP)

Fraction of test points whose observed value falls inside the
`[lower, upper]` prediction interval. For a well-calibrated interval the
PICP should equal the nominal level (e.g. 0.95 for a 95% interval).

## Usage

``` r
edaphos_picp(observed, lower, upper)
```

## Arguments

- observed:

  Numeric vector.

- lower, upper:

  Numeric vectors of the same length giving the lower and upper bounds
  of the prediction interval at each point.

## Value

Numeric scalar in `[0, 1]`.

## References

Shrestha, D. L. and Solomatine, D. P. (2006). Machine learning
approaches for estimation of prediction interval for the model output.
*Neural Networks* **19**, 225-235.

## Examples

``` r
set.seed(1)
n   <- 200
obs <- stats::rnorm(n, mean = 20, sd = 3)

# `lower` and `upper` are per-observation, so a constant band has to
# be recycled explicitly.
band <- function(half) list(lower = rep(20 - half, n),
                            upper = rep(20 + half, n))

# Correctly calibrated 95% intervals cover about 95% of the time.
b <- band(1.96 * 3)
edaphos_picp(obs, b$lower, b$upper)
#> [1] 0.955

# Over-confident intervals under-cover ...
b <- band(0.5 * 3)
edaphos_picp(obs, b$lower, b$upper)
#> [1] 0.415

# ... and absurdly wide ones cover perfectly, which is why coverage
# must always be read together with interval width.
b <- band(1e6)
edaphos_picp(obs, b$lower, b$upper)
#> [1] 1
```
