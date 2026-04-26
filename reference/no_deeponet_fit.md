# Fit a DeepONet for depth-profile operators

Fit a DeepONet for depth-profile operators

## Usage

``` r
no_deeponet_fit(
  depths,
  targets,
  covariates,
  branch_hidden = 16L,
  trunk_hidden = 16L,
  output_dim = 8L,
  epochs = 300L,
  lr = 0.02,
  seed = NULL,
  backend = c("r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- depths:

  Numeric vector of depths (length `n_depths`).

- targets:

  Matrix of targets, shape `(n_obs, n_depths)`.

- covariates:

  Matrix of per-site summary covariates, shape `(n_obs, p)` – NOT a
  depth-dependent trajectory; each site is represented by a vector of
  static covariates. This is the canonical DeepONet setup where the
  branch input is a fixed- length vector.

- branch_hidden, trunk_hidden:

  Integer hidden sizes for the branch and trunk MLPs.

- output_dim:

  Integer; dimension of the inner-product space (`p` in the notes
  above).

- epochs, lr:

  Training hyperparameters.

- seed:

  RNG seed.

- backend:

  `"r"` (default) or `"torch"` (full autograd).

- device:

  `"cpu"`, `"mps"`, or `"cuda"` when `backend = "torch"`.
