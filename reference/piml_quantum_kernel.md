# Physics-informed quantum kernel via ODE-residual fusion

Builds a physics-informed Gram matrix by combining the Pilar 6
ZZFeatureMap kernel over raw features with an RBF similarity over the
depth-profile residuals of a fitted Pilar 2 ODE:

## Usage

``` r
piml_quantum_kernel(
  X,
  y,
  depths,
  ode_fit,
  alpha = 0.7,
  sigma = NULL,
  reps = 2L,
  backend = c("rcpp", "r")
)
```

## Arguments

- X:

  Numeric matrix (rows = samples, columns = features to encode through
  the ZZFeatureMap). Features should already be in `[0, pi]` – use
  [`quantum_scale()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_scale.md)
  if needed.

- y:

  Numeric response vector (one per row of `X`) used to compute residuals
  against the ODE fit.

- depths:

  Numeric vector of depths (same length as `y`) at which observations
  were taken.

- ode_fit:

  A fitted object from
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
  or
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md)
  providing a [`predict()`](https://rdrr.io/r/stats/predict.html)
  method.

- alpha:

  Numeric in `[0, 1]`; mixing weight. Default `0.7` (quantum-heavy,
  physics-informed but not physics-dominated).

- sigma:

  Numeric; RBF bandwidth on the residual scale. Default: median absolute
  residual over the training set (Silverman's rule of thumb).

- reps:

  Integer; ZZFeatureMap repetitions (forwarded to
  [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md)).

- backend:

  Forwarded to
  [`quantum_kernel()`](https://hugomachadorodrigues.github.io/edaphos/reference/quantum_kernel.md);
  `"rcpp"` by default.

## Value

A PSD matrix of shape `(n, n)`.

## Details

\$\$K\_{PI}(x_i, x_j) = \alpha\\ K\_{quantum}(x_i, x_j) + (1 - \alpha)\\
\exp\\\Bigl(-\frac{(e_i - e_j)^2}{2\\\sigma^2}\Bigr)\$\$

where \\e_i = y_i - \hat y\_{ODE}(z_i, x_i)\\ is the residual between
the observed \\y_i\\ and the ODE-predicted value at depth \\z_i\\. The
output is PSD for any \\\alpha \in \[0, 1\]\\.

## References

Bishop, T. F. A. et al. (1999). Modelling soil attribute depth functions
with equal-area quadratic smoothing splines. *Geoderma* **91**, 27-45.
