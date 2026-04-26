# Fit a Physics-Informed Quantum Kernel Ridge Regression

Composes
[`piml_quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_quantum_kernel.md)
with the closed-form KRR dual solution \\\boldsymbol{\alpha} = (K +
\lambda I)^{-1} y\\. The returned object carries the training-time
residuals and ODE fit so
[`predict()`](https://rdrr.io/r/stats/predict.html) handles the full
forward pipeline (ODE predict -\> residual -\> PI kernel row -\> dual
sum).

## Usage

``` r
piml_qkrr_fit(
  X,
  y,
  depths,
  ode_fit,
  alpha = 0.7,
  sigma = NULL,
  reps = 2L,
  lambda = 0.1,
  backend = c("rcpp", "r")
)
```

## Arguments

- X, y, depths, ode_fit, alpha, sigma, reps, backend:

  See
  [`piml_quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_quantum_kernel.md).

- lambda:

  Ridge regulariser; positive.

## Value

An `edaphos_piml_qkrr` fit.
