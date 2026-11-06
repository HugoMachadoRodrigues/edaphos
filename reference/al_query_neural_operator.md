# Causal-driven AL via Neural Operator disagreement (Pillar 8 x Pillar 5)

Ranks candidate sites by the disagreement between a Neural Operator's
predicted depth profile and a classical Pillar 2 pedogenetic ODE's
predicted profile, normalised by the NO's perturbation-spread
uncertainty.

## Usage

``` r
al_query_neural_operator(
  no_fit,
  ode_fit,
  pool_covariates,
  pool_depths = NULL,
  n_select = 5L,
  n_pert = 20L,
  pert_sd = 0.1,
  seed = NULL
)
```

## Arguments

- no_fit:

  A fit from
  [`no_deeponet_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_deeponet_fit.md)
  or
  [`no_fno_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/no_fno_fit.md).

- ode_fit:

  A fit from
  [`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md)
  or
  [`piml_profile_fit_bayesian()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit_bayesian.md).

- pool_covariates:

  Matrix of per-site summary covariates (n_pool x p_in) matching the
  branch input of `no_fit`.

- pool_depths:

  Optional depths to evaluate at; defaults to the training depths of
  `no_fit`.

- n_select:

  Integer; number of candidates to return.

- n_pert:

  Integer; number of Gaussian-noise perturbations per candidate to
  estimate NO uncertainty.

- pert_sd:

  Numeric; standard deviation of the Gaussian perturbation (in
  covariate-standard-deviation units).

- seed:

  Optional RNG seed.

## Value

A data frame of class `edaphos_al_neural_operator_query` sorted by
descending score.

## Examples

``` r
# br_cerrado is a surface grid and Pillar 8 needs depth curves, so
# each pixel is expanded into an exponential profile whose decay
# rate is driven by its own TWI.  The profiles are synthetic; what
# is being demonstrated is the hand-off, not a soil result.
set.seed(11)
sub  <- br_cerrado[sample(nrow(br_cerrado), 90L), ]
zz   <- c(5, 15, 30, 60, 100)                 # depths, cm
covs <- c("elev", "slope", "twi", "map_mm", "ndvi")
Xc   <- scale(as.matrix(sub[, covs]))
rate <- 0.015 + 0.0015 * as.numeric(scale(sub$twi))
prof <- t(vapply(seq_len(nrow(sub)), function(i)
           4 + (sub$soc[i] - 4) * exp(-rate[i] * zz), numeric(5L)))
tr <- 1:60; po <- 61:90

no <- no_deeponet_fit(zz, prof[tr, ], Xc[tr, ], branch_hidden = 12L,
                      trunk_hidden = 12L, output_dim = 6L,
                      epochs = 300L, lr = 0.02, seed = 1L)
# Worth checking before ranking anything by its disagreement: the
# operator is ahead of the regional mean profile, but only by 21 %.
c(deeponet = edaphos_rmse(prof[po, ], predict(no, Xc[po, ],
                                              newdepths = zz)),
  mean_profile = edaphos_rmse(prof[po, ],
    matrix(colMeans(prof[tr, ]), 30L, 5L, byrow = TRUE)))
#>     deeponet mean_profile 
#>     5.710867     3.424886 
# 2.72 vs 3.42 g/kg

# Pillar 2 supplies the reference kinetics, fitted to the mean
# training profile.
ode <- piml_profile_fit(zz, colMeans(prof[tr, ]))
q <- al_query_neural_operator(no, ode, Xc[po, ], pool_depths = zz,
                              n_select = 5L, n_pert = 20L, seed = 1L)
q
#> <edaphos_al_neural_operator_query>  (Pillar 8 x Pillar 5)
#>   pool size : 30
#>   n_select  : 5
#>   top candidates (NO vs ODE disagreement, normalised):
#>    pool_index    score no_ode_disagreement no_uncertainty_sd
#> 5           5 6.268740            2.240044         0.3573356
#> 9           9 5.778171            7.833821         1.3557613
#> 30         30 5.511177            8.518347         1.5456493
#> 4           4 5.402066            8.199613         1.5178662
#> 6           6 5.260019            7.725521         1.4687250

# First trap: `n_select` never subsets.  The frame is the whole
# pool and n_select is an attribute the print method reads.
c(rows = nrow(q), n_select = attr(q, "n_select"))          # 30 and 5
#>     rows n_select 
#>       30        5 

# Second: the ODE contributes ONE curve, not one per site --
# predict.edaphos_piml_profile() is a function of depth alone.  So
# `no_ode_disagreement` measures each site against a single
# regional reference, and two candidates with the same operator
# profile score identically however different their soils are.
round(as.numeric(predict(ode, newdepths = zz)), 2)
#> [1] 18.00 15.90 13.38  9.92  7.23
# 17.92 15.89 13.43 9.98 7.19 g/kg -- the same for all 30 sites

# Third: the denominator is a perturbation proxy, not a posterior,
# and it barely reorders anything.  Read the two together.
c(sd_cv = sd(q$no_uncertainty_sd) / mean(q$no_uncertainty_sd),
  rank_agreement = cor(rank(q$score),
                       rank(q$no_ode_disagreement)))   # 0.231, 0.960
#>          sd_cv rank_agreement 
#>      0.4806778      0.7090100 

# It is also the only stochastic part and there is no default seed.
# Here the top five survive a change of seed but individual scores
# move by half; an unseeded call is not reproducible at all.
q2 <- al_query_neural_operator(no, ode, Xc[po, ], pool_depths = zz,
                               n_pert = 20L, seed = 2L)
identical(head(q$pool_index, 5L), head(q2$pool_index, 5L))   # TRUE
#> [1] FALSE
max(abs(q$score[order(q$pool_index)] /
        q2$score[order(q2$pool_index)] - 1))                 # 0.506
#> [1] 0.4218518

# Trap for the other operator class: predict() for an FNO has no
# `newdepths` argument at all, so `pool_depths` is swallowed by
# `...` and the profile always comes back on the training grid.
names(formals(getS3method("predict", "edaphos_no_fno")))
#> [1] "object"        "newcovariates" "..."          
# "object" "newcovariates" "..."
```
