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

## References

Nichol, A. Q. and Dhariwal, P. (2021). Improved Denoising Diffusion
Probabilistic Models. *Proceedings of the 38th International Conference
on Machine Learning* **139**, 8162-8171.

## Examples

``` r
sch <- dm_cosine_schedule(T = 100L)

# alphabar is the fraction of the original signal surviving to step
# t: it starts near 1 and decays monotonically to ~0.
round(sch$alphabar[c(1, 25, 50, 75, 100)], 4)
#> [1] 0.9995 0.8471 0.4939 0.1443 0.0000

# The three arrays are mutually consistent -- alphabar is the
# running product of alphas -- which is what makes the reverse step
# algebraically valid.
c(complementary = isTRUE(all.equal(sch$alphas + sch$betas, rep(1, 100))),
  running_prod  = isTRUE(all.equal(sch$alphabar, cumprod(sch$alphas))))
#> complementary  running_prod 
#>          TRUE          TRUE 

# beta is clipped at 0.999 (Nichol and Dhariwal 2021) to keep the
# 1/sqrt(alpha_t) factor of the reverse step finite near t = T.
max(sch$betas)
#> [1] 0.999
```
