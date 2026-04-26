# Build a physics gate from a PIML profile fit

Convenience helper for constructing the `physics_gate` argument of
[`al_query()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_query.md)
and
[`al_loop()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_loop.md)
from an existing PIML fit — either the parametric profile
([`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md))
or the Neural ODE variant
([`piml_neural_ode_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_neural_ode_fit.md)).

## Usage

``` r
al_physics_gate_piml(
  profile_fit,
  safety_factor = 1.2,
  lower = NULL,
  upper = NULL
)
```

## Arguments

- profile_fit:

  A `edaphos_piml_profile` or `edaphos_piml_neural_ode` object.

- safety_factor:

  Numeric (\>= 1). 1 = strict envelope; 1.2 = allow 20 % slack on each
  side.

- lower:

  Optional hard lower bound in the target units (e.g. `0` for mass
  fractions). If supplied, overrides the lower end of the envelope.

- upper:

  Optional hard upper bound.

## Value

A function `function(candidates, predicted_mean)` suitable for
`al_query(..., physics_gate = <this>)`.

## Details

The gate rejects any candidate whose model-predicted target value falls
outside a physically plausible envelope derived from the PIML fit. For
the parametric ODE the envelope is `[min(y0, y_inf), max(y0, y_inf)]`;
for the Neural ODE it is the range of predictions between `z = 0` and
the deepest training depth (extrapolated to `2 * max(depth)` as a
conservative floor). Both are widened by `safety_factor`.
