# Hierarchical Neural ODE over multiple pedons (Pillar 2 × Pillar 5)

Fits a covariate-conditioned Neural ODE \\dy/dz = f\_\theta(z, y,
\mathbf{x})\\ jointly across every pedon in a long-format data frame,
plus a sibling MLP \\y_0(\mathbf{x})\\ that predicts the surface value
from covariates. The two nets share the optimiser so training sees all
pedons at once.

## Usage

``` r
piml_hierarchical_fit(
  pedons,
  id_col,
  depth_col,
  value_col,
  covariate_cols,
  hidden = c(32L, 16L),
  y0_hidden = c(16L),
  n_steps = 4L,
  epochs = 500L,
  lr = 0.01,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- pedons:

  Data frame in long form (one row per horizon) with columns for pedon
  id, depth, value, and one or more covariates.

- id_col, depth_col, value_col:

  Character, column names.

- covariate_cols:

  Character vector, names of covariate columns. Assumed constant within
  a pedon — the first row of each pedon is used.

- hidden:

  Integer vector, MLP widths for the ODE vector field \\f\_\theta\\.

- y0_hidden:

  Integer vector, MLP widths for the surface-value head
  \\y_0(\mathbf{x})\\.

- n_steps:

  Integer, RK4 steps between successive observation depths.

- epochs, lr:

  Integer and numeric — Adam hyperparameters.

- seed, verbose:

  As elsewhere in edaphos.

## Value

A `edaphos_piml_hierarchical` object (S3).

## Details

Once fitted,
[`piml_hierarchical_predict()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_hierarchical_predict.md)
returns a profile for **any new location** given its covariates — no
horizon measurement required. Pair with
[`al_physics_gate_piml_hierarchical()`](https://hugomachadorodrigues.github.io/edaphos/reference/al_physics_gate_piml_hierarchical.md)
to use that per-location envelope as a rejection filter inside the
Active Learning loop.
