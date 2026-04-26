# Forward-integrate a Physics-Informed depth profile

Solves ODE (1)-(2) from z = 0 down to the requested `depths`, starting
at `y(0) = params$y0`. Uses a fixed-step RK4 solver from the `deSolve`
package.

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
