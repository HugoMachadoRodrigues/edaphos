# Predict class probabilities / labels from a fine-tuned classifier

Predict class probabilities / labels from a fine-tuned classifier

## Usage

``` r
# S3 method for class 'edaphos_foundation_classifier'
predict(object, x, type = c("class", "prob"), device = NULL, ...)
```

## Arguments

- object:

  An `edaphos_foundation_classifier`.

- x:

  A 4-D array `(N, C, H, W)` of new patches.

- type:

  `"class"` (default — factor of predicted labels) or `"prob"`
  (N-by-n_classes matrix of softmax probabilities).

- device:

  Optional override — defaults to the fit-time device.

- ...:

  Unused; S3 predict compatibility.

## Value

A factor (type = "class") or a numeric matrix (type = "prob").
