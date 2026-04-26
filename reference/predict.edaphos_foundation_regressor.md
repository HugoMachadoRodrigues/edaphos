# Predict numeric targets from a fine-tuned regressor

Predict numeric targets from a fine-tuned regressor

## Usage

``` r
# S3 method for class 'edaphos_foundation_regressor'
predict(object, x, device = NULL, ...)
```

## Arguments

- object:

  An `edaphos_foundation_regressor`.

- x:

  A 4-D array `(N, C, H, W)` of new patches.

- device:

  Optional override — defaults to the fit-time device.

- ...:

  Unused.

## Value

Numeric vector of predicted targets, back-transformed to the original
scale of `y`.
