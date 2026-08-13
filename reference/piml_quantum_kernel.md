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

  Numeric; RBF bandwidth on the residual scale. Default: the median
  absolute deviation of the training residuals *about their median*,
  unscaled — which is neither the median absolute residual nor
  [`stats::mad()`](https://rdrr.io/r/stats/mad.html), the latter
  multiplying the same quantity by 1.4826. The example prints all three.

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

## Examples

``` r
data(br_cerrado)
set.seed(2)
d <- br_cerrado[sample(nrow(br_cerrado), 60L), ]
X <- quantum_scale(as.matrix(d[, c("elev", "slope", "twi", "ndvi")]))

# The reference pedon the residuals are measured against. br_cerrado
# ships a single 0-5 cm layer, so every site enters at the same
# mid-depth of 2.5 cm --- which is where the first trap lives.
ref <- piml_profile_fit(c(5, 15, 30, 60, 100), c(25, 18, 12, 8, 6.5))
K <- piml_quantum_kernel(X, d$soc, depths = rep(2.5, 60L), ode_fit = ref)

# TRAP. With one sampling depth the ODE prediction is one number, so
# e_i = y_i - 27.361 and the physics half is EXACTLY a Gaussian
# kernel on the response. 30% of this Gram matrix is the label.
unique(round(d$soc - attr(K, "residuals"), 6))
#> [1] 27.51427
Kq <- quantum_kernel(X, reps = 2L)
Kp <- (K - 0.7 * Kq) / 0.3
max(abs(Kp - exp(-outer(d$soc, d$soc, "-")^2 /
                 (2 * attr(K, "sigma")^2))))
#> [1] 7.771561e-16

# The mixture is PSD as advertised (smallest eigenvalue 0.0266) ...
signif(min(eigen(unclass(K), symmetric = TRUE,
                 only.values = TRUE)$values), 4)
#> [1] 0.02663

# ... but "alpha = 0.7 is quantum-heavy" is not what the numbers say
# on these four covariates. The ZZ kernel's off-diagonals sit near
# zero (median 0.072), so after weighting, the 30% physics block
# carries MORE off-diagonal variation than the 70% quantum block,
# and the mixture tracks the physics block more closely.
od <- upper.tri(K)
round(stats::quantile(Kq[od], c(0.5, 0.9, 1)), 4)
#>    50%    90%   100% 
#> 0.0719 0.2568 0.8971 
round(c(quantum = stats::sd(0.7 * Kq[od]),
        physics = stats::sd(0.3 * Kp[od])), 4)
#> quantum physics 
#>  0.0778  0.1092 
round(c(quantum = stats::cor(K[od], Kq[od]),
        physics = stats::cor(K[od], Kp[od])), 4)
#> quantum physics 
#>  0.6110  0.8257 

# Read that next to what the quantum block encodes at all: on these
# covariates it barely tracks feature-space proximity (r = 0.23
# against -distance), where a plain RBF at the median-distance
# bandwidth is nearly collinear with it (0.99).
D <- as.matrix(stats::dist(X))
Krbf <- exp(-D^2 / (2 * stats::median(D[od])^2))
round(c(quantum = stats::cor(Kq[od], -D[od]),
        rbf     = stats::cor(Krbf[od], -D[od])), 4)
#> quantum     rbf 
#>  0.2334  0.9906 

# The default `sigma` is the median absolute deviation of the
# residuals about their median, unscaled --- 3.115 here, against
# 8.221 for the median absolute residual and 4.618 for stats::mad().
# Pass `sigma` explicitly if you meant one of the other two.
r <- attr(K, "residuals")
round(c(default    = attr(K, "sigma"),
        mad_median = stats::median(abs(r - stats::median(r))),
        median_abs = stats::median(abs(r)),
        stats_mad  = stats::mad(r)), 4)
#>    default mad_median median_abs  stats_mad 
#>     3.1150     3.1150     8.3743     4.6183 

# alpha = 1 and alpha = 0 recover the two ends exactly.
K1 <- piml_quantum_kernel(X, d$soc, rep(2.5, 60L), ref, alpha = 1)
K0 <- piml_quantum_kernel(X, d$soc, rep(2.5, 60L), ref, alpha = 0)
c(alpha1_is_quantum = max(abs(unclass(K1) - Kq)),
  alpha0_is_physics = max(abs(unclass(K0) - Kp)))
#> alpha1_is_quantum alpha0_is_physics 
#>      0.000000e+00      4.440892e-16 
```
