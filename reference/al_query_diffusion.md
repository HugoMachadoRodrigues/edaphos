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

## Examples

``` r
# \donttest{
# Pillar 9 wants a bank of patches: cut the 45 x 45 Cerrado SOC
# grid into 25 non-overlapping 9 x 9 tiles.
soc_grid <- matrix(br_cerrado$soc, 45L, 45L)
stack <- array(0, c(25L, 9L, 9L))
k <- 0L
for (i in 0:4) for (j in 0:4) {
  k <- k + 1L
  stack[k, , ] <- soc_grid[(i * 9L + 1L):(i * 9L + 9L),
                           (j * 9L + 1L):(j * 9L + 9L)]
}
dm <- dm_fit(stack, T = 40L, epochs = 200L, hidden = 24L,
             lr = 0.01, seed = 1L)
#> [dm_fit] backend = 'r' is a reference sampler whose draws are over-dispersed and spatially incoherent (not calibrated to the field's spatial statistics); use backend = 'torch' (the default when libtorch is present) for coherent samples.
c(first_epoch = dm$history[1L], last_epoch = dm$history[200L])
#> first_epoch  last_epoch 
#>    3.635594    1.019313 
# 3.64 -> 1.02 on the score-matching loss

q <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L, seed = 1L)
q
#> <edaphos_al_diffusion_query>  (Pilar 9 x Pilar 5)
#>   pool size : 81
#>   combine   : sd
#>   top-8 cells:
#>    row col posterior_mean posterior_sd    score
#> 29   2   4       18.84420     24.48650 24.48650
#> 69   6   8       24.79846     23.33976 23.33976
#> 33   6   4       12.79572     22.92125 22.92125
#> 24   6   3       20.74453     22.60002 22.60002
#> 31   4   4       16.93331     22.14337 22.14337
#> 49   4   6       13.54385     21.96488 21.96488
#> 14   5   2       21.88096     21.65317 21.65317
#> 63   9   7       22.24724     21.60520 21.60520

# The number that decides whether this ranking means anything is
# not in the frame: the width of the posterior draws against the
# variability of the maps they are meant to model.
emp_sd <- apply(stack, c(2L, 3L), sd)      # per-cell sd over 25 tiles
c(ddpm = mean(q$posterior_sd), data = mean(emp_sd))     # 19.3 vs 6.5
#>      ddpm      data 
#> 19.312258  6.478365 
# The pure-R denoiser trains a readout over frozen random features,
# so its ancestral samples are three times wider than the map they
# came from.  Most of "posterior SD" here is sampler noise.

# Which the ranking shows directly.  Redraw with another seed: the
# SD map hardly correlates with itself and one of the eight chosen
# cells survives.
q2 <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L, seed = 2L)
a <- q[order(q$row, q$col), ]; b <- q2[order(q2$row, q2$col), ]
cor(a$posterior_sd, b$posterior_sd)                          # 0.070
#> [1] 0.06958497
length(intersect(paste(q$row[1:8],  q$col[1:8]),
                 paste(q2$row[1:8], q2$col[1:8])))           # 1 of 8
#> [1] 1

# Four times the default draws lifts the seed-to-seed correlation
# to 0.30 and still does not settle which cells to visit.
c1 <- al_query_diffusion(dm, n_samples = 64L, n_select = 8L, seed = 1L)
c2 <- al_query_diffusion(dm, n_samples = 64L, n_select = 8L, seed = 2L)
cor(c1$posterior_sd[order(c1$row, c1$col)],
    c2$posterior_sd[order(c2$row, c2$col)])                  # 0.299
#> [1] 0.2993141

# And the structure it does have is not the map's: the DDPM SD
# field is uncorrelated with where the real tiles actually differ.
cor(a$posterior_sd, as.numeric(emp_sd[cbind(a$row, a$col)]))  # -0.043
#> [1] -0.04293965

# `combine` is not a tweak either -- weighting by the expected
# value keeps one of the same eight cells.
q3 <- al_query_diffusion(dm, n_samples = 16L, n_select = 8L,
                         combine = "sd_x_mean_abs", seed = 1L)
length(intersect(paste(q$row[1:8],  q$col[1:8]),
                 paste(q3$row[1:8], q3$col[1:8])))           # 1 of 8
#> [1] 1

# `candidate_cells` restricts the pool to the sites a field team
# can actually reach; `n_select`, as in the other AL bridges, is
# only an attribute and never subsets the frame.
reach <- expand.grid(row = 2:4, col = 2:4)
nrow(al_query_diffusion(dm, candidate_cells = reach,
                        n_samples = 8L, n_select = 3L, seed = 1L))  # 9
#> [1] 9
# }
```
