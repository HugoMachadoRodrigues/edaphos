# Train a tiny DDPM on a collection of soil-map patches

Train a tiny DDPM on a collection of soil-map patches

## Usage

``` r
dm_fit(
  stack,
  conditioning = NULL,
  T = 50L,
  epochs = 100L,
  hidden = 32L,
  lr = 0.01,
  seed = NULL,
  backend = c("r", "torch"),
  device = c("cpu", "mps", "cuda")
)
```

## Arguments

- stack:

  A 3-D array of shape `(n_patches, H, W)` of soil- property patches
  (e.g. SOC at each pixel, already standardised to zero mean / unit
  variance).

- conditioning:

  Optional matrix of shape `(n_patches, cond_dim)` giving a per-patch
  covariate summary fed to the denoising network as conditioning.
  Default `NULL`.

- T:

  Integer; number of diffusion timesteps.

- epochs:

  Integer; training epochs.

- hidden:

  Integer; hidden width of the denoising MLP.

- lr:

  Numeric; learning rate.

- seed:

  Optional RNG seed.

- backend:

  `"r"` (default, ELM-style MLP denoiser) or `"torch"` (autograd U-Net
  denoiser via
  [`torch::optim_adam`](https://torch.mlverse.org/docs/reference/optim_adam.html);
  requires the `torch` Suggests dependency). v2.7.0 upgrade.

- device:

  `"cpu"` (default), `"mps"`, or `"cuda"` when `backend = "torch"`.

## Value

An `edaphos_dm_fit` fit.
