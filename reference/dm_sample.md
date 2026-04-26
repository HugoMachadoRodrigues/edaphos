# Sample new soil-map patches from a trained DDPM

Ancestral sampling (Ho et al. 2020 Algorithm 2): start from Gaussian
noise at t=T, iteratively apply the denoising network to walk back to
t=0. Optional conditioning vector c is passed in at every step.

## Usage

``` r
dm_sample(fit, n_samples = 4L, conditioning = NULL, seed = NULL)
```

## Arguments

- fit:

  An `edaphos_dm_fit` from
  [`dm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_fit.md).

- n_samples:

  Integer; number of independent map draws.

- conditioning:

  Optional `(n_samples, cond_dim)` matrix. Default: zero vector for
  every sample (unconditional).

- seed:

  Optional RNG seed.

## Value

3-D array `(n_samples, H, W)` of generated patches.
