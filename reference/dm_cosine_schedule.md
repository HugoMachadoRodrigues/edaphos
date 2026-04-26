# Build a DDPM noise schedule

Cosine schedule of Nichol & Dhariwal (2021). Returns per-step `alphas`,
`betas`, `alphabar`, `sqrt_alphabar`, `sqrt_one_minus_alphabar`.

## Usage

``` r
dm_cosine_schedule(T = 50L, s = 0.008)
```

## Arguments

- T:

  Integer; number of diffusion steps.

- s:

  Numeric; small offset to avoid alphabar = 0 at t = T.

## Value

Named list.
