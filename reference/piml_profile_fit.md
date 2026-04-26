# Fit a Physics-Informed depth-profile model (Pillar 2)

Fits the ODE \$\$\frac{dy}{dz} = -\lambda_0 e^{-\mu z} (y -
y\_\infty)\$\$ to one soil pedon by minimising the sum of squared errors
between the ODE-predicted and the observed values, with an L2
regulariser on the (re-parametrised) parameters. Physics is encoded in
**the forward model itself** — the fit can never produce a profile that
violates the prescribed exponential-asymptote dynamics.

## Usage

``` r
piml_profile_fit(
  depths,
  values,
  y_surface = NULL,
  start = NULL,
  reg = 0.001,
  control = list(maxit = 2000)
)
```

## Arguments

- depths:

  Numeric vector of horizon mid-depths (same units, e.g. centimetres
  below surface).

- values:

  Numeric vector of observed property values, same length as `depths`.

- y_surface:

  Optional numeric; if supplied, the surface value `y(0) = y_surface` is
  fixed and not optimised. Use this when you have a reliable 0 cm
  observation (or a laboratory A-horizon value).

- start:

  Optional named numeric vector of starting parameters (`log_lambda0`,
  `mu`, `y_inf`, and optionally `y0`). If `NULL`, a data-driven guess is
  built from the observed range and depths.

- reg:

  Numeric L2 regularisation strength on the parameter vector.

- control:

  List passed to [`stats::optim`](https://rdrr.io/r/stats/optim.html)'s
  `control` argument (default is `list(maxit = 2000)`).

## Value

A `edaphos_piml_profile` object with components:

- params:

  Named list with the fitted `lambda0`, `mu`, `y_inf`, `y0`.

- theta:

  The unconstrained parameter vector the optimiser found.

- objective:

  Final regularised SSE loss.

- converged:

  Logical, whether `optim` reported convergence.

- depths, values, y_surface:

  Inputs echoed back.

- rmse:

  Unregularised RMSE on the training data.

## Examples

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)   # e.g. SOC (g/kg) decreasing with depth
fit <- piml_profile_fit(depths, values)
fit
#> <edaphos_piml_profile>
#>   dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
#>   lambda0 = 0.04846   mu = 0.003277
#>   y_inf   = 6.162     y0 = 30.08   
#>   n obs   = 5         rmse = 0.09798
#>   converged = TRUE 
piml_profile_predict(fit$params, c(10, 50))
#> [1] 21.009577  8.720935
```
