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
