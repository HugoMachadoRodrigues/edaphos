# Diffusion-posterior-driven AL (Pilar 9 x Pilar 5)

Ranks candidate cells by the standard deviation of DDPM posterior
samples. High-SD cells are the most uncertain map locations; labelling
there delivers the largest reduction in model entropy per sample.

## Usage

``` r
al_query_diffusion(
  dm_fit,
  conditioning = NULL,
  n_samples = 16L,
  candidate_cells = NULL,
  n_select = 10L,
  combine = c("sd", "sd_x_mean_abs"),
  seed = NULL
)
```

## Arguments

- dm_fit:

  An `edaphos_dm_fit` from
  [`dm_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_fit.md).

- conditioning:

  Optional `(n_samples, cond_dim)` matrix (one row per posterior draw);
  when `NULL` the model is sampled unconditionally.

- n_samples:

  Integer; number of posterior draws.

- candidate_cells:

  Optional integer matrix with columns `row`, `col` restricting the
  candidate pool to accessible sites. Defaults to the full H x W grid.

- n_select:

  Integer; how many cells to return.

- combine:

  One of `"sd"` or `"sd_x_mean_abs"` to weight SD by the absolute
  expected value (prioritises cells where the model thinks the SOC is
  BOTH high and uncertain).

- seed:

  RNG seed.

## Value

A data frame of class `edaphos_al_diffusion_query` sorted by descending
score.
