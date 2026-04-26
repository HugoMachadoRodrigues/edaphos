# Fit a Neural ODE depth profile (Pillar 2, deep variant)

Models the vector field \\dy/dz = f\_\theta(z, y)\\ where \\f\_\theta\\
is a small MLP (default `2 x 16` + tanh). The forward model is a
fixed-step RK4 integrator that runs end-to-end on `torch`, so training
drives the MLP weights — and, optionally, the surface value \\y_0\\ — by
back-propagating through the whole integration (a proper Neural ODE,
Chen et al. 2018).

## Usage

``` r
piml_neural_ode_fit(
  depths,
  values,
  y_surface = NULL,
  hidden = c(16L, 16L),
  n_steps = 4L,
  epochs = 500L,
  lr = 0.01,
  seed = NULL,
  verbose = FALSE
)
```

## Arguments

- depths:

  Numeric vector of horizon mid-depths.

- values:

  Numeric vector of observed values, same length.

- y_surface:

  Optional numeric; if supplied, \$y_0\$ is fixed (no learnable
  parameter) — used when you trust a specific 0 cm reading.

- hidden:

  Integer vector with MLP hidden-layer widths.

- n_steps:

  Integer, RK4 steps between successive observation depths. Higher =
  more accurate, slower.

- epochs, lr:

  Integer and numeric — training hyperparameters for Adam.

- seed:

  Optional integer — forwarded to
  [`torch::torch_manual_seed`](https://torch.mlverse.org/docs/reference/torch_manual_seed.html)
  for reproducibility.

- verbose:

  Logical; print training loss every 50 epochs.

## Value

A `edaphos_piml_neural_ode` object (S3).

## Details

Compared to
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md),
the Neural ODE variant can capture **non-monotone** profiles (E horizons
below an A, bulge in a Bt) that the parametric exponential-asymptote ODE
cannot represent.
