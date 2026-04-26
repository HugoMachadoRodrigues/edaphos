# Fit a Quantum Kernel Ridge Regression (Pillar 6)

Closed-form dual solution \$\$\boldsymbol{\alpha} = (K + \lambda
I)^{-1}\mathbf{y}\$\$ using the quantum Gram matrix from
[`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md).
Works both for regression (`y` numeric) and binary classification
(encode `y \in \{-1, +1\}` and threshold the prediction at zero).

## Usage

``` r
quantum_krr_fit(X, y, reps = 2L, lambda = 0.1)
```

## Arguments

- X:

  Feature matrix already rescaled to `[0, pi]` —
  [`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md)
  is the recommended preprocessor.

- y:

  Numeric response vector (or `\pm 1` for classification).

- reps:

  Integer, encoding depth of the ZZFeatureMap.

- lambda:

  Numeric ridge regulariser (`> 0`).

## Value

An `edaphos_quantum_krr` object.

## Examples

``` r
# \donttest{
  set.seed(1)
  X <- quantum_scale(matrix(runif(60), ncol = 3L))
  y <- sign(X[, 1L] - mean(X[, 1L]))
  fit <- quantum_krr_fit(X, y, reps = 2L, lambda = 0.1)
  mean(predict(fit, X, type = "class") == y)  # training accuracy
#> [1] 1
# }
```
