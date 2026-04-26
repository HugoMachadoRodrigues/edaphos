# Physics-informed ConvLSTM mass-balance loss (Pilar 2 x Pilar 3)

Factory that returns a `function(y_pred, y_true, driver)` closure
suitable as the `physics_loss_fn` argument of
[`temporal_convlstm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/temporal_convlstm_fit.md).
The closure penalises SOC-dynamics predictions that violate the
local-rate kinetics inferred from the Pilar 2 ODE fit.

## Usage

``` r
temporal_piml_loss(ode_fit, weight = 0.1)
```

## Arguments

- ode_fit:

  An `edaphos_piml_profile` or `edaphos_piml_bayes` fit.

- weight:

  Numeric; loss weight relative to the MSE term. Default `0.1`.

## Value

A function `loss_fn(y_pred, y_true, driver)` returning a scalar
tensor/number (same shape agnostic to torch / R).
