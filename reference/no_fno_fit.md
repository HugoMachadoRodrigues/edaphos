# Fit a 1-D Fourier Neural Operator for depth-profile operators

Learns the solution map `u(z) -> y(z)` from a collection of (covariate
trajectory, target profile) pairs. The trained operator predicts the
depth profile at new sites without re-fitting.

## Usage

``` r
no_fno_fit(
  depths,
  targets,
  covariates,
  n_modes = 4L,
  width = 8L,
  n_blocks = 2L,
  epochs = 200L,
  lr = 0.01,
  seed = NULL,
  backend = c("r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- depths:

  Numeric vector of depths (common grid, length `n_depths`). Depth must
  be equally spaced for the DFT to be exact; if not equally spaced, the
  implementation falls back to a FFT on the reindexed series.

- targets:

  Matrix of observed profile values, shape `(n_obs, n_depths)`. Each row
  is one site.

- covariates:

  Matrix of depth-dependent covariate values, shape
  `(n_obs, n_depths, n_channels)` – the covariate trajectory that drives
  the operator. A 2-D matrix is accepted and treated as
  `n_channels = 1`.

- n_modes:

  Integer; number of Fourier modes retained in each spectral
  convolution. Default `4L`.

- width:

  Integer; number of latent channels. Default `8L`.

- n_blocks:

  Integer; number of FNO blocks. Default `2L`.

- epochs:

  Integer; SGD epochs.

- lr:

  Learning rate.

- seed:

  RNG seed.

- backend:

  `"r"` (default, pure-R ELM-style) or `"torch"` (full autograd via
  [`torch::optim_adam`](https://torch.mlverse.org/docs/reference/optim_adam.html);
  requires the `torch` Suggests dependency). v2.7.0 upgrade.

- device:

  `"cpu"` (default), `"mps"` (Apple Silicon) or `"cuda"` when
  `backend = "torch"`.

## Value

An `edaphos_no_fno` fit.
