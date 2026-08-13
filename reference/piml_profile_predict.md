# Forward-integrate a Physics-Informed depth profile

Evaluates the solution of ODE (1)-(2) at the requested `depths`, with
`y(0) = params$y0`. The equation is separable and its solution is
analytic, so this is a direct evaluation of the closed form rather than
a numerical integration – earlier versions called
[`deSolve::lsoda`](https://rdrr.io/pkg/deSolve/man/lsoda.html) on every
prediction, which was slower and less accurate, and made the
depth-averaged observation operator impractical. The closed form is held
to the integrator's own answer in
`tests/testthat/test-piml-closed-form.R`.

## Usage

``` r
piml_profile_predict(params, depths)
```

## Arguments

- params:

  Named list with numeric elements `lambda0`, `mu`, `y_inf`, `y0`.

- depths:

  Numeric vector of positive depths (same units as the depths used at
  fit time).

## Value

Numeric vector of predicted values, one per element of `depths`.

## Examples

``` r
# A synthetic profile from the pedogenetic ODE itself, so the true
# parameters are known.
set.seed(1)
z <- c(5, 15, 30, 60, 100)
y <- 8 + (32 - 8) * exp(-(0.06 / 0.025) * (1 - exp(-0.025 * z))) +
     stats::rnorm(5, 0, 0.4)

fit <- piml_profile_fit(z, y)

# Predict at depths that were never sampled: the ODE solution is
# continuous in z, so the profile can be evaluated anywhere.
piml_profile_predict(fit$params, depths = c(10, 45, 80))
#> [1] 21.92925 12.90414 11.30140

# Monotone decay with depth is a property of the governing equation,
# not something the fit has to be asked for.
p <- piml_profile_predict(fit$params, depths = seq(5, 100, by = 5))
all(diff(p) < 0)
#> [1] TRUE
```
