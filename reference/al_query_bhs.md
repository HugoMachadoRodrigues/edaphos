# Bayesian Hierarchical Active Learning (Pilar 7 x Pilar 5)

Ranks candidate sites by their predictive variance averaged over the BHS
posterior MCMC draws – Thompson-sampling-style AL in the language of
Settles (2009, Section 3.3).

## Usage

``` r
al_query_bhs(bhs_fit, pool_data, n_select = 5L, n_draws = 200L)
```

## Arguments

- bhs_fit:

  An `edaphos_bhs` from
  [`bhs_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/bhs_fit.md).

- pool_data:

  Data frame of candidate sites with covariates + coords.

- n_select:

  Integer; number of candidates to return.

- n_draws:

  Integer; number of posterior draws to average.

## Value

`edaphos_al_bhs_query` data frame sorted by descending average
predictive variance.

## Examples

``` r
# A contiguous 15 x 15 block of the Cerrado grid, so the candidate
# spacing is the grid step and the GP range is resolvable at all.
gx <- sort(unique(br_cerrado$x)); gy <- sort(unique(br_cerrado$y))
blk <- br_cerrado[br_cerrado$x %in% gx[1:15] &
                  br_cerrado$y %in% gy[1:15], ]
names(blk)[names(blk) == "x"] <- "lon"
names(blk)[names(blk) == "y"] <- "lat"
set.seed(4)
tr   <- sort(sample(nrow(blk), 150L))
trn  <- blk[tr, ]; pool <- blk[-tr, ]     # 150 measured, 75 candidates

bh <- bhs_fit(trn, soc ~ elev + twi + map_mm, coords = c("lon", "lat"),
              backend = "gibbs", nmcmc = 600L, burn = 300L,
              phi_range = c(0.1, 500), seed = 1L)

# al_query_bhs() draws its MCMC subset from the ambient RNG and
# takes no seed of its own: set one, or the variances move between
# runs (the ORDER does not -- see below).
set.seed(7)
q <- al_query_bhs(bh, pool, n_select = 5L, n_draws = 50L)
q
#> <edaphos_al_bhs_query>  (Pilar 7 x Pilar 5)
#>   pool size : 75
#>   n_draws   : 50   n_select: 5
#>   top candidates by avg posterior variance:
#>     pool_index posterior_var posterior_sd
#> 276         31      29.91711     5.469654
#> 549         63      29.91651     5.469599
#> 15           3      29.88958     5.467136
#> 330         43      29.88881     5.467066
#> 645         75      29.88445     5.466667

# Read the ranking against the diagnostic that says whether it can
# mean anything.  The profile-MLE correlation length is a third of
# the sampling interval, so no candidate is informed by its
# neighbours...
c(range_deg = 1 / bh$phi_hat, grid_step = gx[2L] - gx[1L])
#>   range_deg   grid_step 
#> 0.002590180 0.007954545 
# 0.0026 vs 0.0080 degrees

# ...and every candidate's predictive variance therefore sits at
# sigma^2 + tau^2, the variance of a site the model knows nothing
# about.  The whole pool spans 1.3 % of that.
c(min = min(q$posterior_var), max = max(q$posterior_var),
  no_information = mean(bh$sigma2_draws) + mean(bh$tau2_draws))
#>            min            max no_information 
#>       29.52374       29.91711       29.59848 
# 29.52  29.92  29.60

# What survives is geometry.  Averaging over posterior draws cannot
# reorder anything: var = sigma^2 (1 - k'R^-1k) + tau^2 is monotone
# in the kriging term for every draw, so the ranking is identical
# at 50 and at 400 draws (silently capped at the 300 stored).
set.seed(7)
q400 <- al_query_bhs(bh, pool, n_select = 5L, n_draws = 400L)
identical(q$pool_index, q400$pool_index)   # TRUE
#> [1] TRUE
attr(q400, "n_draws")                      # 300 -- silently capped
#> [1] 300
                                           # at the draws stored

# Nor do the covariates: `pool_data` must carry every training
# column, but the design matrix built from them is never used --
# beta uncertainty is not in the formula.  Wreck them and nothing
# moves.
pw <- pool
pw$elev <- rev(pw$elev); pw$twi <- pw$twi * 100
pw$map_mm <- pw$map_mm + 5000
set.seed(7)
identical(q$posterior_var,
          al_query_bhs(bh, pw, n_draws = 50L)$posterior_var)   # TRUE
#> [1] TRUE

# So what this returns is a distance-to-nearest-measurement
# ranking wearing a posterior's clothes.
D <- as.matrix(dist(rbind(as.matrix(trn[, c("lon", "lat")]),
                          as.matrix(pool[, c("lon", "lat")]))))
d_nn <- apply(D[151:225, 1:150, drop = FALSE], 1L, min)
cor(q$posterior_var[order(q$pool_index)], d_nn,
    method = "spearman")                                       # 0.561
#> [1] 0.5607671

# Finally, the faster Pillar 7 backend is refused even though it
# stores the same draws -- refit with backend = "gibbs" for AL.
bhr <- bhs_fit(trn, soc ~ elev + twi + map_mm,
               coords = c("lon", "lat"), backend = "rcpp",
               nmcmc = 300L, burn = 150L, phi_range = c(0.1, 500),
               seed = 1L)
try(al_query_bhs(bhr, pool))
#> Error : al_query_bhs() currently supports backend = 'gibbs' only.
```
