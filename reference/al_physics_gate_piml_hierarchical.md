# Per-location physics gate backed by a hierarchical PIML fit

Upgrades the global-envelope
[`al_physics_gate_piml()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml.md)
to a **per-candidate** envelope: each candidate's profile is predicted
from its own covariates, giving a tighter physical plausibility window
driven by the local pedogenic context.

## Usage

``` r
al_physics_gate_piml_hierarchical(
  hier_fit,
  candidate_covariate_cols = hier_fit$covariate_cols,
  safety_factor = 1.2,
  envelope_depths = c(0, 5, 15, 30, 60)
)
```

## Arguments

- hier_fit:

  A `edaphos_piml_hierarchical`.

- candidate_covariate_cols:

  Character vector with the column names in the candidate table that
  correspond to the training covariates (must be the same set, can have
  different order — the function reorders them).

- safety_factor:

  Numeric `>= 1`, widening factor on each side.

- envelope_depths:

  Numeric, depths (same units as training) at which the profile is
  probed to compute `min` and `max` for each candidate. Defaults span
  surface to a deep horizon.

## Value

A function suitable for `al_query(..., physics_gate = <this>)`.
