# Predict with an edaphos_foundation_ensemble

Returns the per-member prediction stack. For regression this is a
`(K_ens, N)` matrix; for classification this is a
`(K_ens, N, n_classes)` array of softmax probabilities.

## Usage

``` r
# S3 method for class 'edaphos_foundation_ensemble'
predict(object, x, ...)
```

## Arguments

- object:

  An `edaphos_foundation_ensemble`.

- x:

  New patches `(N, C, H, W)`.

- ...:

  Forwarded to the member-wise
  [`predict()`](https://rdrr.io/r/stats/predict.html) methods.

## Value

A per-member prediction array (see above).
