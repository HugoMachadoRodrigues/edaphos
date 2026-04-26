# Rescale a covariate matrix into `[lower, upper]` column-wise

Utility for preparing a feature matrix for quantum encoding. The
ZZFeatureMap is only expressive when features are on a compact range —
the de-facto convention is `[0, pi]`.

## Usage

``` r
quantum_scale(X, lower = 0, upper = pi)
```

## Arguments

- X:

  Numeric matrix / data frame.

- lower, upper:

  Target interval bounds (default `0` and `pi`).

## Value

Numeric matrix with the same dimensions as `X`, rescaled column-wise.
