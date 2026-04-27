# Getting started with edaphos

``` r
library(edaphos)
set.seed(1L)
```

## What this vignette is for

edaphos is organised around **ten research pillars**. This vignette is
the 200-line orientation tour: one minimal, self-contained example per
pillar and per cross-pillar bridge, all running on synthetic
Cerrado-like data that ships with the package.

Every function called here runs offline in seconds. For the full
treatment of each pillar – real WoSIS datasets, MCMC diagnostics,
head-to-head benchmarks – see the per-pillar vignettes in the sidebar.

## A shared toy dataset

A 60-profile synthetic data frame with pedological covariates and
topsoil soil-organic-carbon (SOC) as the regression target. Every pillar
below consumes this same object.

``` r
n <- 60L
dat <- data.frame(
  lon   = runif(n, -50, -48),
  lat   = runif(n, -16, -14),
  map   = runif(n, 900, 1500),   # mean annual precipitation
  mat   = runif(n, 21, 27),      # mean annual temperature
  clay  = runif(n, 10, 50),
  sand  = runif(n, 20, 70),
  trees = runif(n, 0, 50)
)
dat$soc <- with(dat,
  8 + 0.02 * map + 0.10 * clay - 0.15 * trees + rnorm(n, 0, 2))
head(dat)
#>         lon       lat      map      mat     clay     sand     trees      soc
#> 1 -49.46898 -14.17425 1495.103 22.76238 22.25773 53.68561  5.455048 38.98083
#> 2 -49.25575 -15.41279 1197.356 22.14756 33.13416 24.74289 16.663899 33.60234
#> 3 -48.85429 -15.08187 1190.610 26.31871 46.41481 44.62981 41.870828 29.37256
#> 4 -48.18358 -15.33521 1004.065 24.02004 15.70416 43.07759 13.842492 24.83493
#> 5 -49.59664 -14.69826 1352.893 26.26235 26.60191 38.76083 29.351757 35.29095
#> 6 -48.20322 -15.48397 1172.337 22.13516 18.43703 69.55496 41.836613 30.05445
```

Train / test split we will reuse throughout:

``` r
tr_ix <- sample.int(n, 45L)
tr    <- dat[tr_ix,  ]
te    <- dat[-tr_ix, ]
cov_cols <- c("map", "mat", "clay", "sand", "trees")
```

## Pilar 1 – Causal AI with backdoor adjustment

A pedogenetic DAG gives the minimally sufficient set of adjustment
variables;
[`benchmark_fit_p1_causal()`](https://hugomachadorodrigues.github.io/edaphos/reference/benchmark_fit_p1_causal.md)
then runs a bootstrap OLS restricted to that set and produces a
predictive posterior.

``` r
post_p1 <- benchmark_fit_p1_causal(tr, te, cov_cols,
                                       dag = NULL, n_boot = 100L)
uncertainty_calibrate(post_p1, truth = te$soc)$crps
#> [1] 1.305664
```

## Pilar 2 – Physics-Informed profile ODE

The pedogenetic ODE `dy/dz = -lambda0 exp(-mu z) (y - y_inf)` is fit to
a single pedon’s SOC profile with
[`piml_profile_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/piml_profile_fit.md).

``` r
depths <- c(5, 15, 30, 60, 100)
values <- c(25, 18, 12, 8, 6.5)
ode_fit <- piml_profile_fit(depths, values)
ode_fit$params
#> $lambda0
#> log_lambda0 
#>  0.04846412 
#> 
#> $mu
#>          mu 
#> 0.003277219 
#> 
#> $y_inf
#>    y_inf 
#> 6.162168 
#> 
#> $y0
#>       y0 
#> 30.07967
```

## Pilar 3 – Temporal 4D cube (ConvLSTM)

``` r
# Skipped in the getting-started tour -- ConvLSTM training needs
# a temporal raster stack, covered in `pilar3-4d-soc.Rmd`.
```

## Pilar 4 – Foundation models (SimCLR / MoCo)

``` r
# Pre-trained MoCo weights live on Zenodo and are pulled by
# `foundation_weights_load()`; see `pilar4-simclr-embeddings.Rmd`.
```

## Pilar 5 – Active Learning

A hybrid uncertainty + diversity acquisition function selects the next 3
profiles to sample from a pool of candidates.

``` r
al_mod <- al_fit(labeled    = tr,
                   target     = "soc",
                   covariates = cov_cols,
                   coords     = c("lon", "lat"),
                   num.trees  = 200L)
pool <- dat[sample.int(n, 20L), c(cov_cols, "lon", "lat")]
picks <- al_query(al_mod, pool, n = 3L, strategy = "hybrid")
picks
#> [1]  9  6 10
```

## Pilar 6 – Quantum KRR

A 6-qubit ZZFeatureMap kernel ridge regression trained on the PCA of the
covariates, with a bootstrap-ensemble posterior.

``` r
post_p6 <- benchmark_fit_p6_quantum(tr, te, cov_cols,
                                         n_pcs = 4L, reps = 1L,
                                         n_boot = 5L, lambda = 0.5)
uncertainty_calibrate(post_p6, truth = te$soc)$crps
#> [1] 9.143574
```

## Pilar 7 – Bayesian Hierarchical Spatial

``` r
fit7 <- bhs_fit(tr, soc ~ map + mat + clay + sand + trees,
                  coords = c("lon", "lat"),
                  nmcmc = 200L, burn = 100L,
                  phi_range = c(0.1, 5), verbose = FALSE)
pr7 <- predict(fit7, te, n_draws = 80L)
head(pr7[, c("mean", "sd")])
#>       mean       sd
#> 1 29.71762 1.936316
#> 2 33.67780 1.846140
#> 3 25.33814 2.309851
#> 4 26.48597 2.131970
#> 5 34.15971 1.619157
#> 6 31.68490 1.871767
```

## Pilar 8 – Neural operators

``` r
depth_grid <- seq(5, 120, length.out = 8L)
targets   <- t(apply(tr[, cov_cols], 1L, function(r)
  10 + 5 * r[1] + 2 * runif(length(depth_grid))))
no_fit <- no_deeponet_fit(depth_grid, targets,
                              as.matrix(tr[, cov_cols]),
                              epochs = 50L, seed = 1L)
no_pred <- predict(no_fit, as.matrix(te[, cov_cols]))
dim(no_pred)
#> [1] 15  8
```

## Pilar 9 – Diffusion models

A conditional DDPM trained on synthetic 6x6 patches;
[`dm_sample()`](https://hugomachadorodrigues.github.io/edaphos/reference/dm_sample.md)
draws 4 posterior maps.

``` r
patches <- array(rnorm(16L * 6L * 6L), dim = c(16L, 6L, 6L))
dm <- dm_fit(patches, T = 8L, epochs = 10L,
               hidden = 8L, lr = 0.05, seed = 1L)
samps <- dm_sample(dm, n_samples = 4L, seed = 1L)
dim(samps)
#> [1] 4 6 6
```

## Pilar 10 – Graph Attention Network

A k-NN co-location graph on (lon, lat) with covariates as node features,
fit via
[`gnn_fit()`](https://hugomachadorodrigues.github.io/edaphos/reference/gnn_fit.md).

``` r
g <- gnn_build_graph(dat, k = 5L, feature_cols = cov_cols)
gat <- gnn_fit(g, targets = dat$soc,
                 hidden = 8L, n_heads = 2L, n_layers = 1L,
                 epochs = 30L, lr = 0.03, seed = 1L)
gat$history[c(1, 30)]
#> [1] 0.9833333 0.8691309
```

## Cross-pillar bridges (v3.0.0)

The **bridges** compose two pillars into a single API. Here we show a
representative pair per cluster.

### P10 x P1 – GAT embeddings as causal nuisance

``` r
# Requires `bnlearn`; run when that Suggests dependency is installed.
feat_df <- dat[, c(cov_cols, "soc")]
kg <- gnn_causal_discovery(gat, feat_df, method = "hc",
                              n_emb_cols = 3L, seed = 1L)
head(kg$edges_feature_only)
```

### P7 x P5 – Thompson-sampling AL

Posterior-sampling active learning over the BHS fit.

``` r
pool_df <- dat[1:8, c(cov_cols, "lon", "lat")]
q <- al_query_bhs(fit7, pool_df, n_select = 3L, n_draws = 50L)
q
#> <edaphos_al_bhs_query>  (Pilar 7 x Pilar 5)
#>   pool size : 8
#>   n_draws   : 50   n_select: 3
#>   top candidates by avg posterior variance:
#>   pool_index posterior_var posterior_sd
#> 7          7      3.902586     1.975496
#> 3          3      3.826381     1.956114
#> 1          1      3.342914     1.828364
```

## Head-to-head: unified uncertainty scoring

All six methods producing `edaphos_posterior` objects can be scored
side-by-side through
[`uncertainty_calibrate()`](https://hugomachadorodrigues.github.io/edaphos/reference/uncertainty_calibrate.md).

``` r
crps <- c(
  P1_Causal   = uncertainty_calibrate(post_p1, te$soc)$crps,
  P6_Quantum  = uncertainty_calibrate(post_p6, te$soc)$crps
)
crps
#>  P1_Causal P6_Quantum 
#>   1.305664   9.143574
```

For the full 1 095-profile WoSIS Cerrado benchmark comparing all six
“static point regression” methods, load
`inst/extdata/benchmark_wosis_6pilar.rds` and inspect `cv_aggregate`
(v3.1.0 vignette: `case-cerrado-end-to-end.Rmd`).

## Next steps

- **Per-pillar deep dives** – 17 vignettes, one per pillar + key case
  studies, cover the full feature surface.
- **[`?edaphos`](https://hugomachadorodrigues.github.io/edaphos/reference/edaphos-package.md)**
  – package-level help page with the complete function index.
- **Cross-pillar bridges** – see `causal-discovery-trio.Rmd` for how P1,
  P5 and P7 combine to run a DAG-driven AL loop.

## Citation

Please cite edaphos as:

> Rodrigues, H. (2026). *edaphos: Disruptive algorithms for digital soil
> mapping.* R package version 3.10.0.
> <https://github.com/HugoMachadoRodrigues/edaphos>
