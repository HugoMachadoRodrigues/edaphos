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
  top = NULL,
  bottom = NULL,
  family = c("lognormal", "gaussian", "gamma"),
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

- top, bottom:

  Optional numeric vectors giving the upper and lower boundary of each
  horizon, same length as `values`. When supplied, each observation is
  compared to the model's **depth-average over its horizon** rather than
  to a point evaluation at the mid-depth, which is what a laboratory
  value actually measures. Recommended whenever the boundaries are
  known: the point-at-midpoint shortcut predicts too low on a convex
  profile, by the mid-point rule error. The correction is concentrated
  in the thick, strongly curved surface horizons — across 207 WoSIS
  pedons it moves the fitted `y0` by a median 0.28 g/kg and the
  asymptote by 0.03.

- family:

  Observation family. `"gaussian"` (default, for backward compatibility)
  assumes additive error of constant absolute size; `"lognormal"` and
  `"gamma"` assume multiplicative error of constant *relative* size,
  which is what laboratory error on a concentration looks like, and both
  keep the prediction as the mean of the observation. The choice is not
  cosmetic: with a constant absolute error, a profile running from 30
  g/kg at the surface to 2 g/kg at 5 m is fitted almost entirely by its
  topsoil, and the deep horizons that carry the asymptote contribute
  almost nothing.

- start:

  Optional named numeric vector of starting parameters on the internal
  log scale (`log_kappa`, `log_mu`, `log_y_asym`, and optionally
  `log_y0`). If `NULL`, several data-driven starts are tried and the
  best is kept.

- reg:

  Numeric L2 regularisation strength on the parameter vector.

- control:

  List passed to [`stats::optim`](https://rdrr.io/r/stats/optim.html)'s
  `control` argument (default is `list(maxit = 2000)`).

## Value

A `edaphos_piml_profile` object with components:

- params:

  Named list with the fitted `lambda0`, `mu`, `y_inf`, `y0`, plus the
  identified coordinates `kappa` and `y_asym`.

- theta:

  The unconstrained parameter vector the optimiser found.

- objective:

  Final regularised SSE loss.

- converged:

  Logical, whether `optim` reported convergence.

- depths, values, y_surface, top, bottom:

  Inputs echoed back.

- rmse:

  Unregularised RMSE on the training data.

## Parameterisation

The model is estimated in the identified, positive coordinates \\(y_0,
A, \kappa, \mu)\\, where \\A = y(\infty)\\ is the **attainable deep
value** and \\\kappa = \lambda_0/\mu\\ is the total relaxation. The
familiar `lambda0` and `y_inf` are recovered for reporting. This matters
because \\y\_\infty\\ is *not* the asymptote of the solution: since the
rate decays with depth, the profile only traverses a fraction \\1 -
e^{-\kappa}\\ of the \\y_0 \to y\_\infty\\ gap. Estimating \\A\\
directly also removes the near-collinearity of \\\lambda_0\\ and \\\mu\\
(the data constrain their ratio far better than either alone) and,
because all four coordinates are exponentiated, it rules out the
physically impossible fits the old free-sign parameterisation returned
on real data: negative surface carbon and rates that *grow*
exponentially with depth.

## Examples

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)   # e.g. SOC (g/kg) decreasing with depth
fit <- piml_profile_fit(depths, values)
fit
#> <edaphos_piml_profile>
#>   dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
#>   lambda0 = 0.05004   mu = 0.006045
#>   y0      = 30.36     y(Inf) = 5.962      (kappa = 8.28)
#>   y_inf   = 5.956     (ODE coordinate, not the attained value)
#>   n obs   = 5 (point)        rmse = 0.09523
#>   converged = TRUE 
piml_profile_predict(fit$params, c(10, 50))
#> [1] 20.975101  8.772824

# With horizon boundaries, each value is matched to the layer average:
piml_profile_fit(depths, values,
                 top    = c(0, 10, 20, 40, 80),
                 bottom = c(10, 20, 40, 80, 120))
#> <edaphos_piml_profile>
#>   dy/dz = -lambda0 * exp(-mu*z) * (y - y_inf)
#>   lambda0 = 0.05112   mu = 0.005584
#>   y0      = 30.33     y(Inf) = 5.987      (kappa = 9.16)
#>   y_inf   = 5.984     (ODE coordinate, not the attained value)
#>   n obs   = 5 (layer)         rmse = 0.1297
#>   converged = TRUE 
```
