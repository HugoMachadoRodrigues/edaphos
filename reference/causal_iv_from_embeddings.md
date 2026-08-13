# Fit 2SLS using foundation-model (or proxy) embeddings as instruments

Convenience wrapper that:

1.  Takes a matrix of per-profile embeddings (rows = profiles, columns =
    embedding dims),

2.  Reduces them to `n_pcs` principal components,

3.  Attaches the PCs to `data` as new columns named `PC_1`, ...,

4.  Runs
    [`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)
    with the PCs as instruments.

## Usage

``` r
causal_iv_from_embeddings(
  data,
  embeddings,
  exposure,
  outcome,
  covariates = NULL,
  n_pcs = 5L
)
```

## Arguments

- data:

  Data frame with `exposure`, `outcome` and any `covariates`.

- embeddings:

  Numeric matrix with `nrow(data)` rows (one per data row) and any
  number of columns (embedding dimensions).

- exposure, outcome, covariates:

  See
  [`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md).

- n_pcs:

  Integer; number of top principal components to keep as instruments.
  Default `5L`.

## Value

`edaphos_causal_iv` object (see
[`causal_iv_fit_2sls()`](https://hugomachadorodrigues.github.io/edaphos/reference/causal_iv_fit_2sls.md)).

## Details

Using the top `n_pcs` principal components instead of raw embedding
dimensions keeps the instrument count manageable (avoiding the curse of
dimensionality) and ensures the instruments are orthogonal (which
simplifies the Sargan diagnostics). The default `n_pcs = 5L` yields a
4-over-identified model for a single-exposure query, enabling the Sargan
J-test.

## Examples

``` r
# Patch embeddings as candidate instruments. Only four of the
# twelve dimensions track the parent material; the other eight
# track canopy, which carries no geology at all.
set.seed(11)
n <- 300
mgmt      <- rnorm(n)
carbonate <- runif(n, 0, 12)
quarry_km <- runif(n, 1, 60)
ph    <- 4.6 + 0.10 * carbonate - 0.010 * quarry_km +
         0.45 * mgmt + rnorm(n, 0, 0.25)
yield <- 1.0 + 1.5 * ph + 1.3 * mgmt + rnorm(n, 0, 0.4)
soil  <- data.frame(ph, yield)

canopy <- rnorm(n)
emb <- cbind(
  matrix(canopy, n, 8)           + matrix(rnorm(n * 8, 0, 0.5), n),
  matrix(scale(carbonate), n, 2) + matrix(rnorm(n * 2, 0, 0.5), n),
  matrix(scale(quarry_km), n, 2) + matrix(rnorm(n * 2, 0, 0.5), n)
)
colnames(emb) <- paste0("emb_", 1:12)

# The trap: prcomp ranks components by variance in the EMBEDDING,
# not by relevance to the exposure. PC_1 holds 0.56 of that
# variance and is pure canopy, so on its own it is a
# non-instrument: F = 0.03 and an interval from -13.5 to +19.4.
causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 1L)
#> <edaphos_causal_iv>
#>   ph -> yield  (estimator: 2SLS, n = 300)
#>   instruments : PC_1
#>   effect      : 2.9526  (se = 8.4082, 95% CI [-13.5272, 19.4324])
#>   stage-1 F   : 0.03 (p = 0.852)  partial R^2 = 0.000
#>   [warning] Stock-Yogo threshold F < 10; instruments may be weak.

# Three PCs reach the geology directions: F = 45.6, and the
# interval [0.87, 1.75] covers the true effect of 1.5.
causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 3L)
#> <edaphos_causal_iv>
#>   ph -> yield  (estimator: 2SLS, n = 300)
#>   instruments : PC_1, PC_2, PC_3
#>   effect      : 1.3124  (se = 0.2251, 95% CI [0.8713, 1.7535])
#>   stage-1 F   : 45.55 (p = 3.12e-24)  partial R^2 = 0.316
#>   Sargan J    : chi2(2) = 0.19, p = 0.908

# More PCs is not monotonically better. The default n_pcs = 5L buys
# extra Sargan degrees of freedom but dilutes the joint first-stage
# F, which tests a growing number of restrictions: it falls from
# 45.6 at three PCs to 27.9 at five while the estimate barely
# moves. Choose n_pcs on the first stage, not on a default.
sapply(1:5, function(k)
  causal_iv_from_embeddings(soil, emb, "ph", "yield",
                            n_pcs = k)$stage1_F)
#> [1]  0.03498204  7.33208490 45.54941709 34.56315589 27.93657446

# `pca_variance_explained` documents the choice, but read it as an
# audit trail rather than a relevance ranking -- PC_1 dominates it
# and is the one component that identifies nothing.
fit <- causal_iv_from_embeddings(soil, emb, "ph", "yield", n_pcs = 3L)
round(fit$pca_variance_explained, 3)
#>   PC1   PC2   PC3 
#> 0.560 0.153 0.147 

# Constant embedding dimensions are dropped before PCA rather than
# breaking `scale. = TRUE`; `embedding_cols` records what survived.
length(causal_iv_from_embeddings(soil, cbind(emb, dead_dim = 1),
                                 "ph", "yield",
                                 n_pcs = 3L)$embedding_cols)
#> [1] 12
```
