# Predict a depth profile from a fitted Neural ODE

Predict a depth profile from a fitted Neural ODE

## Usage

``` r
piml_neural_ode_predict(object, newdepths, ...)
```

## Arguments

- object:

  A `edaphos_piml_neural_ode`.

- newdepths:

  Numeric vector of depths at which to evaluate the profile.

- ...:

  Unused.

## Value

Numeric vector, one value per element of `newdepths`.
