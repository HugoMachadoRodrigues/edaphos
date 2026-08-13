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
  ## The target is the sign of an interaction between two covariates -- a
  ## checkerboard. In the population neither a linear rule nor a threshold
  ## on a single column beats chance on it, so a score here reflects the
  ## kernel and not the task. (A target such as y = sign(x1 - mean(x1))
  ## is instead solved exactly by the one-line rule that defines it, and a
  ## perfect score on it would say nothing about any estimator.)
  set.seed(1)
  u <- matrix(runif(2 * 400L), ncol = 2L)
  y <- sign((u[, 1L] - 0.5) * (u[, 2L] - 0.5))
  X <- quantum_scale(u)          # ZZFeatureMap needs features in [0, pi]
  tr <- 1:200; te <- 201:400     # fit on 200 points, score on 200 unseen

  fit <- quantum_krr_fit(X[tr, ], y[tr], reps = 2L, lambda = 0.1)
  mean(predict(fit, X[te, ], type = "class") == y[te])   # 0.75, held out
#> [1] 0.75

  ## The two numbers 0.75 has to beat before it means anything:
  max(table(y[te])) / length(te)                         # 0.53, majority class
#> [1] 0.53

  ## A fitted linear rule has no signal to latch onto here, so its held-out
  ## accuracy is chance in expectation and swings widely from split to
  ## split; on this split it happens to land above the majority class.
  lin <- lm(y[tr] ~ X[tr, ])
  mean(sign(cbind(1, X[te, ]) %*% coef(lin)) == y[te])   # 0.6
#> [1] 0.6

  ## The same fit scored in sample instead -- optimistic, which is why the
  ## held-out number above is the one to read:
  mean(predict(fit, X[tr, ], type = "class") == y[tr])   # 0.78, in sample
#> [1] 0.78

  ## This is a demonstration on two simulated covariates, not a benchmark:
  ## it shows the quantum kernel picks up an interaction a linear model
  ## cannot, on data with no noise in the labels. Claiming it beats a
  ## classical kernel would need the same held-out protocol run against,
  ## say, an RBF-kernel ridge fit, repeated over splits, on real data.
# }
```
